function [beautifiedImage, diagnostics] = beautifyImage( ...
        inputImage, params, faceBox, beautyContext)
%BEAUTIFYIMAGE 通过 v3 package 编排结构感知的磨皮和美白。
%   运行时缓存校验同时理解 v3.1 compat 与 V4 layered 两种 Context
%   形态：缓存兼容由 artifactVersion/algorithmVersion 决定，缺字段、
%   尺寸不匹配或版本不兼容一律触发安全重建，不静默复用。
%
%   运行期 evidence（T11）：frequency decomposition 与 blemish map 在
%   本函数内组装为局部 runtimeEvidence 结构，供各 stage 消费。它只在
%   单次调用内存活，不写入持久化 policy-time Context（不进 V4
%   分层、不进缓存兼容判定），与 masks.buildBeautyPolicyEvidence 的
%   policy-time evidence 层无依赖关系；详见 makeRuntimeEvidence。

if nargin < 2
    params = [];
end
if nargin < 3
    faceBox = [];
end
validateInput(inputImage, params, faceBox);
smoothingStrength = params.smoothingStrength;
whiteningStrength = params.whiteningStrength;

% 零强度严格返回原图，同时保留轻量诊断，避免无意义地触发模型推理。
if smoothingStrength == 0 && whiteningStrength == 0
    beautifiedImage = inputImage;
    diagnostics = struct('pipeline', 'v3', 'identity', true, ...
        'imageSize', size(inputImage));
    return;
end

ensureImageProcessingToolbox();
runtimeCache = [];
if nargin < 4 || isempty(beautyContext)
    beautyContext = normalizeBeautyContext(inputImage, faceBox);
else
    if isfield(beautyContext, 'runtimeCache')
        runtimeCache = beautyContext.runtimeCache;
        beautyContext = rmfield(beautyContext, 'runtimeCache');
    end
    try
        beautyContext = normalizeBeautyContext(inputImage, faceBox, ...
            beautyContext);
    catch exception
        % normalizeBeautyContext:*（v3 旧形态）与
        % normalizeBeautyContextV4:*（T08 起 producer 主路径）两个错误
        % 族都表示 Context 无效，统一包装为 beautifyImage:InvalidContext；
        % 其余错误（如图像/工具箱问题）保持原样重抛。
        if startsWith(exception.identifier, 'normalizeBeautyContext:') || ...
                startsWith(exception.identifier, 'normalizeBeautyContextV4:')
            error('beautifyImage:InvalidContext', ...
                'Beauty Context 无效：%s', exception.message);
        end
        rethrow(exception);
    end
end

[beautifiedImage, diagnostics] = runV3Beauty(inputImage, beautyContext, ...
    faceBox, smoothingStrength, whiteningStrength, runtimeCache);
if ~isa(beautifiedImage, 'uint8') || ...
        ~isequal(size(beautifiedImage), size(inputImage))
    error('beautifyImage:InvalidOutput', ...
        '美颜结果必须保持输入图像的尺寸和数据类型。');
end
end

function validateInput(inputImage, params, faceBox)
if nargin < 1 || ~isValidRgbImage(inputImage)
    error('beautifyImage:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
if nargin < 2 || ~isstruct(params) || ~isscalar(params) || ...
        ~all(isfield(params, {'smoothingStrength', 'whiteningStrength'}))
    error('beautifyImage:InvalidParams', ...
        '参数必须包含 smoothingStrength 和 whiteningStrength。');
end
if isfield(params, 'pipeline')
    error('beautifyImage:InvalidParams', ...
        'pipeline 选择已移除，beautifyImage 统一使用 v3。');
end
if ~isValidStrength(params.smoothingStrength) || ...
        ~isValidStrength(params.whiteningStrength)
    error('beautifyImage:InvalidParams', ...
        '美颜强度必须是范围 0 到 100 内的有限数值标量。');
end
if nargin < 3
    error('beautifyImage:InvalidFaceBox', ...
        '必须提供位于图像范围内的 [x y width height] 人脸框。');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
end

function [beautifiedImage, diagnostics] = runV3Beauty( ...
        inputImage, beautyContext, faceBox, ...
        smoothingStrength, whiteningStrength, runtimeCache)
[hasRuntimeCache, beautyMasks, maskDiagnostics, frequency, ...
    decompositionDiagnostics, blemishMap, blemishDiagnostics, ...
    cacheDiagnostics] = readRuntimeCache(inputImage, runtimeCache, faceBox, ...
    beautyContext);
if ~hasRuntimeCache
    [beautyMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
        inputImage, beautyContext, faceBox);
    maskDiagnostics.reusedRuntimeCache = false;
    maskDiagnostics.runtimeCache = cacheDiagnostics;
    [frequency, decompositionDiagnostics] = beauty.decomposeSkinFrequency( ...
        inputImage, faceBox);
    [blemishMap, blemishDiagnostics] = beauty.buildBlemishMap(inputImage, ...
        frequency, beautyMasks);
else
    maskDiagnostics.reusedRuntimeCache = true;
    maskDiagnostics.runtimeCache = cacheDiagnostics;
end
% T11：frequency/blemish 统一以运行期 evidence 的身份进入消费路径。
%   组装时序：uncached 路径由 decomposeSkinFrequency/buildBlemishMap
%   刚刚生成；cached 路径的产物来自已通过 validateRuntimeCache 校验的
%   缓存记录。两条路径在此汇合成同一个 runtimeEvidence，后续 stage 与
%   诊断只从这里读取，不再区分产物来源。
runtimeEvidence = makeRuntimeEvidence(frequency, ...
    decompositionDiagnostics, blemishMap, blemishDiagnostics);
% T12：Fine smoothing 只消费 V4 stage contract 的 protection 分层。
%   从本次调用实际使用的 beautyMasks 产物推导（T07 头注约定：与生产
%   门控共用同一份 mask 产物），uncached 与 cached 两条路径同源；
%   其余 stage（Mid/Repair/Tone/...）迁移前继续走各自现有兼容逻辑。
stageProtection = masks.buildStageProtectionMasks(beautyMasks);
[smoothedFrequency, smoothingDiagnostics] = beauty.smoothSkinTexture( ...
    runtimeEvidence.frequency, beautyMasks, smoothingStrength, ...
    runtimeEvidence.blemishMap, stageProtection);
% T14：Fine repair 只消费生产端拼装的 stage contract（T07 零瑕疵快照
%   repairFine/hard + runtime blemish 放宽后的未折叠门控字段），与
%   smoothing 的 stage contract 同源（同一份 beautyMasks 产物推导）；
%   Mid 权重与共享 referenceReliability 在 repairSkinBlemishes 内部
%   继续走 legacy 兼容逻辑，直至 T15 迁移。
repairFineContract = makeRepairFineStageContract(beautyMasks, ...
    stageProtection, runtimeEvidence.blemishMap);
[repairedFrequency, repairDiagnostics] = beauty.repairSkinBlemishes( ...
    smoothedFrequency, beautyMasks, runtimeEvidence.blemishMap, ...
    smoothingStrength, repairFineContract);
[baseLuminance, baseLuminanceDiagnostics] = beauty.evenSkinLuminance( ...
    runtimeEvidence.frequency, beautyMasks, smoothingStrength);
[skinTone, skinToneDiagnostics] = beauty.normalizeSkinTone(inputImage, ...
    runtimeEvidence.frequency, beautyMasks, ...
    runtimeEvidence.blemishMap, smoothingStrength);
[whitening, whiteningDiagnostics] = beauty.applySkinWhitening(inputImage, ...
    runtimeEvidence.frequency, beautyMasks, whiteningStrength);
processing = struct( ...
    'blemishMap', runtimeEvidence.blemishMap, ...
    'blemish', runtimeEvidence.blemishDiagnostics, ...
    'repair', repairDiagnostics, ...
    'skinTone', skinTone, ...
    'skinToneDiagnostics', skinToneDiagnostics, ...
    'whitening', whitening, ...
    'whiteningDiagnostics', whiteningDiagnostics, ...
    'baseLuminance', baseLuminance, ...
    'evenSkinLuminance', baseLuminance, ...
    'maskDiagnostics', maskDiagnostics, ...
    'decompositionDiagnostics', ...
    runtimeEvidence.frequencyDiagnostics, ...
    'smoothingDiagnostics', smoothingDiagnostics);
[beautifiedImage, composeDiagnostics] = beauty.composeBeautyResult( ...
    inputImage, runtimeEvidence.frequency, repairedFrequency, ...
    beautyMasks, whiteningStrength, processing);
diagnostics = struct( ...
    'pipeline', 'v3', ...
    'identity', false, ...
    'reusedRuntimeCache', hasRuntimeCache, ...
    'beautyMasks', beautyMasks, ...
    'mask', maskDiagnostics, ...
    'frequency', runtimeEvidence.frequencyDiagnostics, ...
    'blemishMap', runtimeEvidence.blemishMap, ...
    'blemish', runtimeEvidence.blemishDiagnostics, ...
    'runtimeCache', cacheDiagnostics, ...
    'cache', cacheDiagnostics, ...
    'cacheMigration', cacheDiagnostics, ...
    'repairResult', repairedFrequency, ...
    'repair', repairDiagnostics, ...
    'smoothingResult', smoothedFrequency, ...
    'smoothing', smoothingDiagnostics, ...
    'baseLuminanceResult', baseLuminance, ...
    'baseLuminance', baseLuminanceDiagnostics, ...
    'evenSkinLuminanceResult', baseLuminance, ...
    'evenSkinLuminance', baseLuminanceDiagnostics, ...
    'skinToneResult', skinTone, ...
    'skinTone', skinToneDiagnostics, ...
    'whiteningResult', whitening, ...
    'whitening', whiteningDiagnostics, ...
    'compose', composeDiagnostics);
end

function evidence = makeRuntimeEvidence(frequency, frequencyDiagnostics, ...
    blemishMap, blemishDiagnostics)
%MAKERUNTIMEEVIDENCE 把 frequency/blemish 运行期产物组装为局部 evidence。
%   runtimeEvidence 是单次 beautifyImage 调用内的局部结构，字段语义：
%     frequency           — decomposeSkinFrequency 的完整频率分解
%                           （base/mid/fine/sourceLuminance/scales）；
%     frequencyDiagnostics— 分解诊断（含重建误差与各频带快照）；
%     blemishMap          — buildBlemishMap 的 [0,1] 瑕疵置信度图；
%     blemishDiagnostics  — 瑕疵检测诊断（fine/mid/chroma 证据与阈值）。
%   边界纪律（T11）：
%     * 不写入持久化 policy-time Context：normalizeBeautyContext(V4)
%       的 semantic/processability/evidence/protection 分层不携带本
%       结构的任何字段，后续 Repair/Tone consumer 应把 blemish 当作
%       运行期观测从本结构读取，而不是假设它存在于静态 Context。
%     * 不参与缓存兼容判定：缓存命中与否由 artifactVersion 与输入/
%       人脸框/Context 指纹决定（validateRuntimeCache）；命中后仍从
%       缓存产物组装同一结构，消费路径不感知来源差异。
%     * 无 Semantic → Evidence → Policy 反向依赖：policy-time
%       evidence 见 masks.buildBeautyPolicyEvidence（显式不含
%       blemish/frequency）；本结构只被 stage consumer 读取。
evidence = struct( ...
    'frequency', frequency, ...
    'frequencyDiagnostics', frequencyDiagnostics, ...
    'blemishMap', blemishMap, ...
    'blemishDiagnostics', blemishDiagnostics);
end

function contract = makeRepairFineStageContract(beautyMasks, ...
    stageProtection, blemishMap)
%MAKEREPAIRFINESTAGECONTRACT 组装 Fine repair 的 stage contract（T14）。
%   快照与 hard 取自 T07 protection 分层（与生产门控共用同一份
%   beautyMasks 产物推导）；三个未折叠 runtime 门控字段按
%   repairSkinBlemishes 的生产原式从同一份产物 + 本次调用的 runtime
%   blemishMap 计算，保证消费侧重建与 legacy 路径逐位等价：
%     blemishRelaxedGate — 零瑕疵参考门 + runtime 放宽量
%                          1 - structure·(1 - .90·blemish)
%                          （structureGate0 = 1 - structure 恒成立）；
%     strongStructureCap — 1 - .65·strongStructure（强结构固定下限）；
%     textureGate        — 1 - texture（v3.2 线性纹理门）。
%   textureGate 单独发布的原因：生产链在结构门与纹理门之间对权重做
%   [0,1] 截断，折叠进门控积会在截断饱和区改变结果；repairFine 的
%   1-x 补码往返亦有舍入，因此快照不参与输出算术，只作为零瑕疵参考
%   由消费侧诊断与测试消费。runtime 耦合字段不进入 policy-time
%   protection 分层（T07 边界），只在本次调用的 call site 组装，不写
%   入 runtimeEvidence（后者只承载 producer 产物，见
%   makeRuntimeEvidence）；cached/uncached 路径共用同一份 beautyMasks
%   产物，组装结果一致。
hard = stageProtection.hard;
hardFeatureBand = bwdist(hard >= .999) <= 3;
strongStructure = smoothStep(beautyMasks.structureProtectionMask, ...
    .70, .90) .* double(hardFeatureBand);
contract = struct( ...
    'repairFine', stageProtection.repairFine, ...
    'hard', hard, ...
    'blemishRelaxedGate', 1 - beautyMasks.structureProtectionMask .* ...
    (1 - .90 * blemishMap), ...
    'strongStructureCap', 1 - .65 * strongStructure, ...
    'textureGate', 1 - beautyMasks.textureProtectionMask);
end

function value = smoothStep(inputValue, low, high)
%SMOOTHSTEP 复现生产 smoothstep 曲线（t^2*(3-2t)），与
%   buildStageProtectionMasks/repairSkinBlemishes 同式。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function [isUsable, beautyMasks, maskDiagnostics, frequency, ...
        decompositionDiagnostics, blemishMap, blemishDiagnostics, ...
        cacheDiagnostics] = readRuntimeCache( ...
        inputImage, runtimeCache, faceBox, beautyContext)
isUsable = false;
beautyMasks = [];
maskDiagnostics = struct();
frequency = [];
decompositionDiagnostics = struct();
blemishMap = [];
blemishDiagnostics = struct();
cacheDiagnostics = makeCacheDiagnostics('generated', ...
    '未提供运行时缓存。', []);
if isempty(runtimeCache)
    return;
end
if ~isstruct(runtimeCache) || ~isscalar(runtimeCache)
    cacheDiagnostics = makeCacheDiagnostics('regenerated', ...
        '运行时缓存格式无效，需要重新生成。', runtimeCache);
    return;
end
cache = runtimeCache;
[isValid, reason] = validateRuntimeCache(cache, inputImage, faceBox, ...
    beautyContext);
cacheDiagnostics = makeCacheDiagnostics('regenerated', reason, cache);
if ~isValid
    return;
end
beautyMasks = cache.beautyMasks;
maskDiagnostics = cache.maskDiagnostics;
frequency = cache.frequency;
decompositionDiagnostics = cache.decompositionDiagnostics;
blemishMap = cache.blemishMap;
blemishDiagnostics = cache.blemishDiagnostics;
isUsable = true;
cacheDiagnostics.status = 'reused';
cacheDiagnostics.reused = true;
cacheDiagnostics.reason = '缓存契约、输入和全部算法产物均匹配。';
end

function diagnostics = makeCacheDiagnostics(status, reason, cache)
contract = beautyPipelineContract();
sourceSchemaVersion = '';
sourceAlgorithmVersion = '';
if isstruct(cache) && isscalar(cache)
    if isfield(cache, 'schemaVersion')
        sourceSchemaVersion = versionText(cache.schemaVersion);
    end
    if isfield(cache, 'algorithmVersion')
        sourceAlgorithmVersion = versionText(cache.algorithmVersion);
    end
end
diagnostics = struct( ...
    'status', status, ...
    'reused', strcmp(status, 'reused'), ...
    'reason', reason, ...
    'schemaVersion', contract.schemaVersion, ...
    'algorithmVersion', contract.algorithmVersion, ...
    'sourceSchemaVersion', sourceSchemaVersion, ...
    'sourceAlgorithmVersion', sourceAlgorithmVersion);
end

function [valid, reason] = validateRuntimeCache( ...
        cache, inputImage, faceBox, beautyContext)
valid = false;
required = {'schemaVersion', 'algorithmVersion', 'artifactVersion', ...
    'artifactInfo', 'artifacts', 'imageSize', 'inputImage', 'faceBox', ...
    'beautyMasks', 'maskDiagnostics', 'frequency', ...
    'decompositionDiagnostics', 'blemishMap', 'blemishDiagnostics', ...
    'migration'};
if ~all(isfield(cache, required))
    reason = '运行时缓存缺少版本或算法产物字段。';
    return;
end
contract = beautyPipelineContract();
% 三个版本号职责（见 beautyPipelineContract）：schemaVersion 描述
% Context 公共契约形态，缓存读者需同时理解 v3.1 compat 与 V4
% layered 两种合法形态，未知形态一律重建；algorithmVersion 描述
% 生产行为，artifactVersion 描述缓存兼容，两者必须与当前契约完全
% 一致，任何不匹配都触发安全重建，不静默复用。
if ~isKnownContextSchemaVersion(cache.schemaVersion)
    reason = '运行时缓存的 Context 契约版本无法识别，需要重新生成。';
    return;
end
if ~isExactVersion(cache.algorithmVersion, contract.algorithmVersion) || ...
        ~isExactVersion(cache.artifactVersion, contract.artifactVersion)
    reason = '运行时缓存的算法产物版本不匹配，需要重新生成。';
    return;
end
if ~isequal(cache.inputImage, inputImage)
    reason = '运行时缓存的输入图像不匹配，需要重新生成。';
    return;
end
if ~isnumeric(cache.faceBox) || ~isreal(cache.faceBox) || ...
        ~isequal(size(cache.faceBox), [1, 4]) || ...
        ~isequal(double(cache.faceBox), double(faceBox))
    reason = '运行时缓存的人脸框不匹配，需要重新生成。';
    return;
end
imageSize = size(inputImage, 1:2);
if ~isnumeric(cache.imageSize) || ~isreal(cache.imageSize) || ...
        ~isequal(size(cache.imageSize), [1, 3]) || ...
        ~isequal(double(cache.imageSize), [imageSize, 3])
    reason = '运行时缓存的图像尺寸不匹配，需要重新生成。';
    return;
end
if ~validateArtifactInfo(cache.artifactInfo, contract) || ...
        ~validateArtifactInfo(cache.artifacts, contract)
    reason = '运行时缓存的算法产物清单不匹配，需要重新生成。';
    return;
end
if ~isstruct(cache.migration) || ...
        ~isscalar(cache.migration)
    reason = '运行时缓存的迁移信息无效，需要重新生成。';
    return;
end
if isfield(cache.migration, 'status') && ...
        isTextEqual(cache.migration.status, 'requiresRegeneration')
    reason = '运行时缓存已标记为需要重新生成。';
    return;
end
if ~isstruct(cache.beautyMasks) || ~isscalar(cache.beautyMasks)
    reason = '运行时缓存缺少有效的 Beauty Masks 产物。';
    return;
end
if ~validateBeautyMasks(cache.beautyMasks, imageSize, faceBox, contract)
    reason = '运行时缓存的 Beauty Masks 产物无效，需要重新生成。';
    return;
end
% Context Mask 指纹比较：v3.1 compat Context 的 11 个顶层 Mask 字段
% 属于公共契约，必须全部存在且与缓存一致；V4 layered Context 的顶层
% 字段是迁移期 compat alias，缺失任一字段即无法核实缓存与当前
% Context 的对应关系（canonical 派生 Mask 由后续阶段提供），两种
% 形态下缺失或不一致都走安全重建，禁止静默复用。
isV4 = isV4LayeredContext(beautyContext);
contextNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', 'nonFaceStrengthMap'};
for index = 1:numel(contextNames)
    name = contextNames{index};
    if ~isfield(beautyContext, name)
        if isV4
            reason = sprintf( ...
                'V4 Context 缺少 compat alias %s，缓存 Mask 无法核对，需要重新生成。', ...
                name);
        else
            reason = '运行时缓存的 Mask 与当前 Context 不一致，需要重新生成。';
        end
        return;
    end
    if ~isequal(double(cache.beautyMasks.(name)), ...
            double(beautyContext.(name)))
        reason = '运行时缓存的 Mask 与当前 Context 不一致，需要重新生成。';
        return;
    end
end
if ~validateFrequency(cache.frequency, imageSize, faceBox, contract)
    reason = '运行时缓存的频率产物无效，需要重新生成。';
    return;
end
if ~validateStampedArtifact(cache.maskDiagnostics, contract) || ...
        ~validateStampedArtifact(cache.decompositionDiagnostics, contract) || ...
        ~validateStampedArtifact(cache.blemishDiagnostics, contract)
    reason = '运行时缓存的诊断产物无效，需要重新生成。';
    return;
end
if ~validateMask(cache.blemishMap, imageSize, true)
    reason = '运行时缓存的瑕疵图无效，需要重新生成。';
    return;
end
valid = true;
reason = '缓存有效。';
end

function valid = validateArtifactInfo(info, contract)
required = {'schemaVersion', 'algorithmVersion', 'artifactVersion', ...
    'beautyMasks', 'frequency', 'blemishMap'};
valid = isstruct(info) && isscalar(info) && all(isfield(info, required)) && ...
    isKnownContextSchemaVersion(info.schemaVersion) && ...
    isExactVersion(info.algorithmVersion, contract.algorithmVersion) && ...
    isExactVersion(info.artifactVersion, contract.artifactVersion);
if ~valid
    return;
end
names = {'beautyMasks', 'frequency', 'blemishMap'};
for index = 1:numel(names)
    valid = valid && isExactVersion(info.(names{index}), ...
        contract.artifactVersion);
end
end

function valid = validateBeautyMasks(beautyMasks, imageSize, faceBox, contract)
required = {'schemaVersion', 'algorithmVersion', 'artifactVersion', ...
    'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'protectionMask', ...
    'strengthMap', 'faceStrengthMap', 'nonFaceStrengthMap', ...
    'hardProtectionMask', 'noseMask', 'faceBox', 'imageSize'};
if ~all(isfield(beautyMasks, required)) || ...
        ~isKnownContextSchemaVersion(beautyMasks.schemaVersion) || ...
        ~isExactVersion(beautyMasks.algorithmVersion, ...
        contract.algorithmVersion) || ...
        ~isExactVersion(beautyMasks.artifactVersion, contract.artifactVersion)
    valid = false;
    return;
end
if ~isnumeric(beautyMasks.imageSize) || ...
        ~isequal(size(beautyMasks.imageSize), [1, 3]) || ...
        ~isequal(double(beautyMasks.imageSize), [imageSize, 3]) || ...
        ~isnumeric(beautyMasks.faceBox) || ~isreal(beautyMasks.faceBox) || ...
        ~isequal(size(beautyMasks.faceBox), [1, 4]) || ...
        ~isequal(double(beautyMasks.faceBox), double(faceBox))
    valid = false;
    return;
end
maskNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'protectionMask', ...
    'strengthMap', 'faceStrengthMap', 'nonFaceStrengthMap', ...
    'hardProtectionMask', 'noseMask'};
valid = true;
for index = 1:numel(maskNames)
    valid = valid && validateMask(beautyMasks.(maskNames{index}), ...
        imageSize, true);
end
if ~valid
    return;
end
try
    [~, hasChroma] = resolveChromaProtectionMask(beautyMasks, imageSize, ...
        'beautifyImage:InvalidRuntimeCache', ...
        'beautifyImage:ChromaProtectionConflict');
    valid = hasChroma;
catch
    valid = false;
end
end

function valid = validateFrequency(frequency, imageSize, faceBox, contract)
required = {'schemaVersion', 'algorithmVersion', 'artifactVersion', ...
    'sourceLuminance', 'base', 'mid', 'fine', 'imageSize', 'faceBox'};
valid = isstruct(frequency) && isscalar(frequency) && ...
    all(isfield(frequency, required)) && ...
    isKnownContextSchemaVersion(frequency.schemaVersion) && ...
    isExactVersion(frequency.algorithmVersion, contract.algorithmVersion) && ...
    isExactVersion(frequency.artifactVersion, contract.artifactVersion) && ...
    isnumeric(frequency.imageSize) && isreal(frequency.imageSize) && ...
    isequal(size(frequency.imageSize), [1, 3]) && ...
    isequal(double(frequency.imageSize), [imageSize, 3]) && ...
    isnumeric(frequency.faceBox) && isreal(frequency.faceBox) && ...
    isequal(size(frequency.faceBox), [1, 4]) && ...
    isequal(double(frequency.faceBox), double(faceBox));
if ~valid
    return;
end
for name = {'sourceLuminance', 'base', 'mid', 'fine'}
    value = frequency.(name{1});
    valid = valid && isnumeric(value) && isreal(value) && ...
        isequal(size(value), imageSize) && all(isfinite(value(:)));
end
end

function valid = validateStampedArtifact(value, contract)
valid = isstruct(value) && isscalar(value) && ...
    all(isfield(value, {'schemaVersion', 'algorithmVersion', ...
    'artifactVersion'})) && ...
    isKnownContextSchemaVersion(value.schemaVersion) && ...
    isExactVersion(value.algorithmVersion, contract.algorithmVersion) && ...
    isExactVersion(value.artifactVersion, contract.artifactVersion);
end

function valid = validateMask(value, imageSize, requireRange)
valid = (isnumeric(value) || islogical(value)) && isreal(value) && ...
    isequal(size(value), imageSize) && all(isfinite(value(:)));
if valid && requireRange
    valid = all(value(:) >= 0) && all(value(:) <= 1);
end
end

function valid = isKnownContextSchemaVersion(value)
%ISKNOWNCONTEXTSCHEMAVERSION 判断版本戳是否为缓存读者能理解的
%   Context 公共契约形态：v3.1 compat 或 V4 layered。schemaVersion
%   只描述 Context 字段布局，不承担缓存兼容职责（由 artifactVersion
%   负责），因此不要求与当前生产契约完全一致；Context schema 迁移
%   期间两种形态的缓存都可安全复用。
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && ...
    any(strcmp(value, {'3.1', '4.0'}));
end

function valid = isV4LayeredContext(beautyContext)
%ISV4LAYEREDCONTEXT 判断已规范化的 Context 是否为 V4 分层形态。
valid = isfield(beautyContext, 'schemaVersion') && ...
    isExactVersion(beautyContext.schemaVersion, '4.0');
end

function valid = isExactVersion(value, expected)
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && strcmp(value, expected);
end

function valid = isTextEqual(value, expected)
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && strcmp(value, expected);
end

function value = versionText(value)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || size(value, 1) ~= 1
    value = '';
end
end

function isValid = isValidRgbImage(inputImage)
isValid = isa(inputImage, 'uint8') && isreal(inputImage) && ...
    ndims(inputImage) == 3 && size(inputImage, 3) == 3;
end

function isValid = isValidStrength(strength)
isValid = isnumeric(strength) && isreal(strength) && isscalar(strength) && ...
    isfinite(strength) && strength >= 0 && strength <= 100;
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('beautifyImage:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end

function ensureImageProcessingToolbox
requiredFunctions = {'rgb2ycbcr', 'ycbcr2rgb', 'imgaussfilt'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('beautifyImage:MissingToolbox', ...
        '美颜处理需要 Image Processing Toolbox。');
end
end
