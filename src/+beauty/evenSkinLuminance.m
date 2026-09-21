function [luminanceResult, diagnostics] = evenSkinLuminance( ...
        frequency, beautyMasks, smoothingStrength, baseLuminanceContract, ...
        runtimeBlemish)
%EVENSKINLUMINANCE 对皮肤 Base 亮度执行局部均匀化。
%   本模块只读取 frequency.base。可靠皮肤的归一化加权局部参考用于
%   生成目标 Base；输出 baseDelta 已经包含全部作用权重，合成阶段不再
%   重复乘权，也不在此处渲染 RGB。
%
%   T16/T32：可选第 4 参数 baseLuminanceContract 是 Base Luminance 的
%   stage contract，由生产端唯一组装点（+beauty/baseLuminanceStageContract）
%   从 V4 stage protection 的规范门拼装传入。执行层是**纯执行器**：
%   只消费 contract 的规范门与 strength/processability 层，
%   不读取任何 semantic / evidence / legacy general protection mask。
%
%   读取集合（上位契约第 1 节）：
%     frequency.base —— 输入图像的低频分解结果；
%     beautyMasks.skinMask / strengthMap / faceSkinMask
%       —— processability 与 strength 层（非保护判定）；faceSkinMask
%          只用于亮度基线归一化取样域；
%     beautyMasks.faceBox —— 非保护类几何字段（参考尺度）；
%     baseLuminanceContract.target.baseLuminance
%       —— 逐像素修改门（该像素允不允许做低频亮度均衡）；
%     baseLuminanceContract.support.baseLuminance
%       —— 参考池门（该像素允不允许进入低频参考统计）；
%     baseLuminanceContract.hard —— 独立 hard identity（生产原位 (1-hard) 乘子）；
%     baseLuminanceContract.regionBandGate —— T30 纯 policy 带门，只乘
%       逐像素 supportMap，不进全局参考统计。
%
%   统一权重函数（上位契约第 2 节）：
%     targetWeight  = strength × processabilitySkin × (1 - targetProtection)
%                     → supportMap = baseWeightCurve .* regionalSkinWeight
%                       .* (1 - target.baseLuminance) .* (1 - hard)
%                       .* regionBandGate .* referenceCoverage
%     supportWeight = validSkinReference × (1 - supportProtection)
%                     → referenceReliability = skinMask .* strengthMap
%                       .* (1 - support.baseLuminance)
%   其中 baseWeightCurve 是阶段强度侧标量曲线，regionalSkinWeight =
%   min(skinMask, strengthMap) 为 processability×strength 的既有逐像素形式。
%
%   target / support 分离（上位契约第 3.3、5.6 节）：进入全局参考统计的
%   门只来自 support.*，逐像素修改门只来自 target.*，两者互不污染。把
%   target 门并进参考池会让带内变化经 imgaussfilt 参考卷积
%   （referenceSigma）扩散到带外：实测带外 2226px/0.94% 出现 ≤2 灰度级
%   泄漏。regionBandGate 同样只作用于逐像素 supportMap，不进
%   referenceReliability。
%
%   兼容入口（未提供第 4 参的旧调用方）：T32 起不再自行解释 general
%   texture/chroma/structure/hard masks，而是向 policy 层索取零带
%   stageProtection（masks.buildStageProtectionMasks(beautyMasks)），
%   经唯一组装点得到零带 contract，与生产路径共用同一份
%   Single Protection Authority。缺字段 fail-fast，不在函数内部重新拼装。
%
%   零带（compat / 无 evidence）下 target/support 门的补码逐位还原 T30
%   之前的 legacy 门控积（补码往返误差 ≤2^-54，见 policy 层说明），
%   带外泄漏维持 T30 之前的 ≤1 灰度级量级。

if nargin < 5
    runtimeBlemish = [];
end

if nargin < 3
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base 亮度均匀化需要频率、Beauty Masks 和磨皮强度。');
end
validateFrequency(frequency);
imageSize = size(frequency.base);
validateMasks(beautyMasks, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', ...
        '磨皮强度必须是 0 到 100 的数值标量。');
end

% 仅从 frequency.base 读取低频亮度；不依赖 sourceLuminance、Mid 或
% Fine，避免把已有模块的残差再次带入 Base 校正。
base = double(frequency.base);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
faceSkinMask = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);

% T32：保护门控只来自 contract。兼容入口向 policy 层索取零带 stageProtection。
if nargin < 4 || isempty(baseLuminanceContract)
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
    baseLuminanceContract = beauty.baseLuminanceStageContract(stageProtection);
end
baseLuminanceContract = validateBaseLuminanceContract( ...
    baseLuminanceContract, imageSize);
targetGate = 1 - baseLuminanceContract.target.baseLuminance;
supportGate = 1 - baseLuminanceContract.support.baseLuminance;
hardProtectionGate = 1 - baseLuminanceContract.hard;
regionBandGate = baseLuminanceContract.regionBandGate;
profile = beautySmoothingProfile(smoothingStrength);

% 参考权重与作用权重分开：前者只决定局部参考是否可信，后者决定
% 当前像素实际校正多少。这样五官和强结构不会污染邻域参考，也不会
% 通过同一张权重在最终合成时被再次衰减。
% referenceReliability 是全局参考池统计（经 imgaussfilt 卷积），只消费
% supportGate（含 (1-hard)），刻意不含 regionBandGate——band 只作用于
% 逐像素 supportMap，否则带内变化会经参考池扩散到带外。
referenceReliability = skinMask .* strengthMap .* supportGate;
% dense/blemish 参考排除只在 75 档以上启用。低中档不读取新增运行期
% 门，保持已有 Base 输出逐位不变；高档路径使用与 Repair 相同的
% denseBlemishField 与高置信候选排除，避免低频目标污染全局参考。
referenceExclusion = readRuntimeBlemishExclusion(runtimeBlemish, imageSize);
referenceReliability = referenceReliability .* ...
    (1 - profile.highEndRepairGate .* referenceExclusion);
referenceReliability = min(max(referenceReliability, 0), 1);

faceScale = readFaceScale(frequency, beautyMasks, imageSize);
referenceSigma = readReferenceSigma(frequency, faceScale);
referenceWeight = imgaussfilt(referenceReliability, referenceSigma, ...
    'Padding', 'replicate');
weightedReference = imgaussfilt(referenceReliability .* base, ...
    referenceSigma, 'Padding', 'replicate');
minimumReferenceWeight = .05;
referenceValid = referenceWeight >= minimumReferenceWeight;
localReference = base;
localReference(referenceValid) = weightedReference(referenceValid) ./ ...
    referenceWeight(referenceValid);

% 局部均值只负责消除空间不均，整体亮度基线以可靠脸部皮肤为零点
% 归一化。偏移是全图常量，不会在脸部和脸外交界制造新的梯度。
normalizationMask = referenceValid & faceSkinMask > .35 & ...
    referenceReliability > .05;
if ~any(normalizationMask(:))
    normalizationMask = referenceValid & referenceReliability > .05;
end
if any(normalizationMask(:))
    referenceOffset = median(base(normalizationMask) - ...
        localReference(normalizationMask));
else
    referenceOffset = 0;
end
localReference(referenceValid) = localReference(referenceValid) + ...
    referenceOffset;

% 参考覆盖度让非常稀疏的皮肤参考平滑退让；没有任何有效参考时为
% 零，保证该位置既没有 Base 增量，也不会被误诊为已支持校正。
referenceCoverage = min(referenceWeight / .20, 1);
referenceCoverage = smoothStep(referenceCoverage, .10, .75);
referenceCoverage(~referenceValid) = 0;

ratio = double(smoothingStrength) / 100;
% Base 是大尺度校正，采用保守的最大作用系数；原始目标差异仍先
% 按 ±.03 限幅，避免在低频结构边缘产生可见梯度。
baseCurve = ratio ^ .85;
baseAmplitudeGain = .06;
baseWeightCurve = baseAmplitudeGain .* baseCurve;
regionalSkinWeight = min(skinMask, strengthMap);
% T32：逐像素修改门只来自 target.baseLuminance，hard 与 T30 纯 policy
% 带按生产原位单独相乘（regionBandGate 只在此处注入，不进
% referenceReliability）。零带时 regionBandGate == 1，乘法恒等。
supportMap = baseWeightCurve .* regionalSkinWeight .* targetGate .* ...
    hardProtectionGate .* regionBandGate .* referenceCoverage;
supportMap = min(max(supportMap, 0), 1);

% dense 区域的慢变斑驳只增加受限的 Base 支持，不改变原有参考目标。
% denseAllowedWeight 已经经过 Repair 的同皮肤参考覆盖与结构门；这里
% 重新乘 Base 自己的 target/hard/band 门，并限制总支持，保留鼻梁和
% 脸颊曲面的低频坡度。高档门显式保留，75 档及以下该分支逐位为零。
denseAllowedWeight = readRuntimeDenseAllowedWeight(runtimeBlemish, imageSize);
denseBaseReference = readRuntimeDenseBaseReference( ...
    runtimeBlemish, imageSize);
denseBaseReferenceCoverage = readRuntimeDenseBaseReferenceCoverage( ...
    runtimeBlemish, imageSize);
denseReferenceCoverage = readRuntimeDenseReferenceCoverage( ...
    runtimeBlemish, imageSize);
densePermission = denseAllowedWeight ./ max(denseReferenceCoverage, .05);
densePermission(denseAllowedWeight <= eps) = 0;
densePermission = min(max(densePermission, 0), 1);
denseBaseWeight = .68 .* profile.highEndRepairGate .* ...
    densePermission .* denseBaseReferenceCoverage .* targetGate .* ...
    hardProtectionGate .* regionBandGate;
denseBaseWeight = min(max(denseBaseWeight, 0), 1);
supportMap = min(max(supportMap + denseBaseWeight, 0), 1);

% 先限制未经计权的目标差异，再乘一次完整作用权重。该差异保留
% 符号，因此暗区可提亮、亮区可压低，二者使用同一条校正路径。
rawBaseDelta = localReference - base;
limitedBaseDelta = min(max(rawBaseDelta, -.03), .03);
baseDelta = limitedBaseDelta .* supportMap;
denseBaseDelta = min(max(denseBaseReference - base, -.03), .03) .* ...
    denseBaseWeight;
baseDelta = min(max(baseDelta + denseBaseDelta, -.03), .03);
baseAfter = base + baseDelta;

luminanceResult = struct( ...
    'base', baseAfter, ...
    'baseBefore', base, ...
    'baseAfter', baseAfter, ...
    'outputBase', baseAfter, ...
    'targetBase', localReference, ...
    'baseDelta', baseDelta, ...
    'delta', baseDelta, ...
    'luminanceDelta', baseDelta, ...
    'baseCurve', baseCurve, ...
    'baseWeightCurve', baseWeightCurve, ...
    'baseAmplitudeGain', baseAmplitudeGain, ...
    'supportMap', supportMap, ...
    'baseSupport', supportMap, ...
    'alphaMap', supportMap, ...
    'reference', localReference, ...
    'referenceWeight', referenceWeight, ...
    'referenceValid', referenceValid, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));

% T32 诊断收口：算法侧不再持有 legacy structure/feature/chroma 语义，
% 诊断统一报告 target 门（逐像素修改保护）、support 门（参考池保护）与
% 独立 hard/band 门；不再报告 structureGate/featureGate/chromaProtectionMask。
% baseGateSnapshot 为 T07 快照衔接：1 - target.baseLuminance。
diagnostics = struct( ...
    'base', baseAfter, ...
    'baseBefore', base, ...
    'baseAfter', baseAfter, ...
    'outputBase', baseAfter, ...
    'targetBase', localReference, ...
    'rawBaseDelta', rawBaseDelta, ...
    'limitedBaseDelta', limitedBaseDelta, ...
    'baseDelta', baseDelta, ...
    'delta', baseDelta, ...
    'luminanceDelta', baseDelta, ...
    'baseCurve', baseCurve, ...
    'baseWeightCurve', baseWeightCurve, ...
    'baseAmplitudeGain', baseAmplitudeGain, ...
    'regionalSkinWeight', regionalSkinWeight, ...
    'targetGate', targetGate, ...
    'supportGate', supportGate, ...
    'hardProtectionGate', hardProtectionGate, ...
    'regionBandGate', regionBandGate, ...
    'referenceReliability', referenceReliability, ...
    'referenceWeight', referenceWeight, ...
    'referenceCoverage', referenceCoverage, ...
    'referenceOffset', referenceOffset, ...
    'minimumReferenceWeight', minimumReferenceWeight, ...
    'referenceValid', referenceValid, ...
    'hasReliableReference', any(referenceValid(:)), ...
    'positiveSupport', supportMap > 0 & baseDelta > 0, ...
    'negativeSupport', supportMap > 0 & baseDelta < 0, ...
    'supportMap', supportMap, ...
    'baseSupport', supportMap, ...
    'alphaMap', supportMap, ...
    'referenceSigma', referenceSigma, ...
    'denseAllowedWeight', denseAllowedWeight, ...
    'denseBaseWeight', denseBaseWeight, ...
    'denseBaseReference', denseBaseReference, ...
    'denseBaseReferenceCoverage', denseBaseReferenceCoverage, ...
    'denseBaseDelta', denseBaseDelta, ...
    'faceScale', faceScale, ...
    'baseDeltaLimit', .03, ...
    'maxAbsBaseDelta', max(abs(baseDelta(:))), ...
    'frequencyUnchanged', true, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
diagnostics.baseGateSnapshot = 1 - baseLuminanceContract.target.baseLuminance;
end

function contract = validateBaseLuminanceContract(contract, imageSize)
%VALIDATEBASELUMINANCECONTRACT 校验 Base Luminance stage contract（T16/T32）。
%   必需字段：hard（hard identity）、target.baseLuminance（逐像素修改
%   保护）、support.baseLuminance（参考池保护）、regionBandGate（T30 纯
%   policy 带门 1 - regionBandBase，只作用于 supportMap）。缺字段或取值
%   无效一律 fail-fast，不在函数内部重新拼装，也不静默回退到 legacy
%   general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'hard', 'target', 'support', ...
        'regionBandGate'}))
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base Luminance stage contract 必须是包含 hard/target/support/regionBandGate 的标量结构。');
end
if ~isstruct(contract.target) || ~isscalar(contract.target) || ...
        ~isfield(contract.target, 'baseLuminance')
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base Luminance stage contract 的 target 缺少 baseLuminance。');
end
if ~isstruct(contract.support) || ~isscalar(contract.support) || ...
        ~isfield(contract.support, 'baseLuminance')
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base Luminance stage contract 的 support 缺少 baseLuminance。');
end
contract.hard = readMask(contract, 'hard', imageSize);
contract.target.baseLuminance = readMask(contract.target, ...
    'baseLuminance', imageSize);
contract.support.baseLuminance = readMask(contract.support, ...
    'baseLuminance', imageSize);
contract.regionBandGate = readMask(contract, 'regionBandGate', imageSize);
end

function validateFrequency(frequency)
if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~isfield(frequency, 'base')
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base 亮度均匀化需要 frequency.base。');
end
base = frequency.base;
if ~isnumeric(base) || ~isreal(base) || ~ismatrix(base) || ...
        isempty(base) || any(~isfinite(base(:))) || ...
        any(base(:) < 0) || any(base(:) > 1)
    error('beauty:InvalidEvenLuminanceInput', ...
        'frequency.base 必须是 [0,1] 范围内的二维有限亮度图。');
end
end

function validateMasks(beautyMasks, imageSize)
% T32：只校验 strength/processability 层与非保护类几何字段；保护门一律
% 来自 stage contract，故不再要求任何 *ProtectionMask。
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base 亮度均匀化需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap'};
for index = 1:numel(required)
    name = required{index};
    if ~isfield(beautyMasks, name)
        error('beauty:InvalidEvenLuminanceInput', ...
            'Beauty Masks 缺少字段 %s。', name);
    end
    readMask(beautyMasks, name, imageSize);
end
if isfield(beautyMasks, 'faceSkinMask')
    readMask(beautyMasks, 'faceSkinMask', imageSize);
end
end

function value = readMask(context, name, imageSize)
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidEvenLuminanceInput', ...
        'Beauty Masks 字段 %s 无效。', name);
end
value = double(value);
end

function value = readOptionalMask(context, name, imageSize)
if isfield(context, name)
    value = readMask(context, name, imageSize);
else
    value = zeros(imageSize);
end
end

function exclusion = readRuntimeBlemishExclusion(value, imageSize)
%READRUNTIMEBLEMISHEXCLUSION 读取高档 Base 参考池的运行期排除域。
%   只保留一个内部排除语义：dense field 与高置信 blemish candidate
%   的并集。该字段不进入持久化 Context 或缓存校验契约。
exclusion = zeros(imageSize);
if isempty(value)
    return;
end
if isstruct(value)
    if isfield(value, 'blemishMap')
        blemishMap = readStandaloneMask(value.blemishMap, imageSize, ...
            'blemishMap');
    elseif isfield(value, 'confidence')
        blemishMap = readStandaloneMask(value.confidence, imageSize, ...
            'confidence');
    else
        error('beauty:InvalidEvenLuminanceInput', ...
            '运行期瑕疵诊断缺少 blemishMap 或 confidence。');
    end
    if isfield(value, 'denseBlemishField')
        denseField = readStandaloneMask(value.denseBlemishField, ...
            imageSize, 'denseBlemishField');
    else
        denseField = zeros(imageSize);
    end
else
    blemishMap = readStandaloneMask(value, imageSize, 'blemishMap');
    denseField = zeros(imageSize);
end
exclusion = max(denseField, double(blemishMap > .60));
end

function denseAllowedWeight = readRuntimeDenseAllowedWeight(value, imageSize)
%READRUNTIMEDENSEALLOWEDWEIGHT 读取 Repair 发布的 dense 作用门。
denseAllowedWeight = zeros(imageSize);
if isempty(value) || ~isstruct(value) || ...
        ~isfield(value, 'denseAllowedWeight')
    return;
end
denseAllowedWeight = readStandaloneMask(value.denseAllowedWeight, ...
    imageSize, 'denseAllowedWeight');
end

function denseReference = readRuntimeDenseBaseReference(value, imageSize)
denseReference = zeros(imageSize);
if isempty(value) || ~isstruct(value) || ...
        ~isfield(value, 'denseBaseReference')
    return;
end
denseReference = readStandaloneMask(value.denseBaseReference, imageSize, ...
    'denseBaseReference');
end

function coverage = readRuntimeDenseBaseReferenceCoverage(value, imageSize)
coverage = zeros(imageSize);
if isempty(value) || ~isstruct(value) || ...
        ~isfield(value, 'denseBaseReferenceCoverage')
    return;
end
coverage = readStandaloneMask(value.denseBaseReferenceCoverage, imageSize, ...
    'denseBaseReferenceCoverage');
end

function coverage = readRuntimeDenseReferenceCoverage(value, imageSize)
coverage = zeros(imageSize);
if isempty(value) || ~isstruct(value) || ...
        ~isfield(value, 'denseReferenceCoverageForTarget')
    return;
end
coverage = readStandaloneMask(value.denseReferenceCoverageForTarget, ...
    imageSize, 'denseReferenceCoverageForTarget');
end

function value = readStandaloneMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidEvenLuminanceInput', ...
        '运行期瑕疵字段 %s 无效。', name);
end
value = double(value);
end

function faceScale = readFaceScale(frequency, beautyMasks, imageSize)
if isfield(beautyMasks, 'faceBox') && isnumeric(beautyMasks.faceBox) && ...
        isreal(beautyMasks.faceBox) && numel(beautyMasks.faceBox) == 4 && ...
        all(isfinite(beautyMasks.faceBox(:))) && ...
        all(double(beautyMasks.faceBox(3:4)) > 0)
    faceScale = min(double(beautyMasks.faceBox(3:4)));
elseif isfield(frequency, 'faceScale') && ...
        isnumeric(frequency.faceScale) && isreal(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
elseif isfield(frequency, 'faceBox') && ...
        isnumeric(frequency.faceBox) && numel(frequency.faceBox) == 4 && ...
        all(isfinite(frequency.faceBox(:))) && ...
        all(double(frequency.faceBox(3:4)) > 0)
    faceScale = min(double(frequency.faceBox(3:4)));
else
    faceScale = min(imageSize);
end
end

function referenceSigma = readReferenceSigma(frequency, faceScale)
% 优先复用分解阶段记录的 Base 尺度，保证同一输入使用同一尺度口径。
if isfield(frequency, 'scales') && isstruct(frequency.scales) && ...
        isscalar(frequency.scales) && ...
        isfield(frequency.scales, 'mediumSigma') && ...
        isnumeric(frequency.scales.mediumSigma) && ...
        isreal(frequency.scales.mediumSigma) && ...
        isscalar(frequency.scales.mediumSigma) && ...
        isfinite(frequency.scales.mediumSigma) && ...
        frequency.scales.mediumSigma > 0
    mediumSigma = double(frequency.scales.mediumSigma);
else
    mediumSigma = min(32, max(5, .045 * faceScale));
end
referenceSigma = min(48, max(5 * mediumSigma, .25 * faceScale));
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
