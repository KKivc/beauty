function [repairedFrequency, diagnostics] = repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, smoothingStrength, ...
        repairContract)
%REPAIRSKINBLEMISHES 对瑕疵位置执行受控的 Fine/Mid 局部修复。
%   普通皮肤仍由 smoothSkinTexture 处理；本函数只读取固定的瑕疵图，
%   低置信度只衰减 Fine，中高置信度才少量收敛 Mid。Base 始终不变。
%
%   T14/T15/T31：第 5 参数 repairContract 是 Repair（Fine/Mid）的 stage
%   contract（组装点 +beauty/repairStageContract，生产组装层 beautifyImage
%   传入）。执行层是**纯执行器**：只消费 contract 的规范门与 strength 层，
%   不读取任何 semantic / evidence / general protection mask。
%
%   Blemish ≠ Should Repair（上位契约第 3.2 节，T31 重点）：
%     repairTargetWeight  = blemishEvidence × processability × strength
%                           × (1 - targetProtection)
%     repairSupportWeight = validSkinReference × (1 - supportProtection)
%   瑕疵证据（repairEvidence/highConfidence）只回答"像不像瑕疵"，**不**单独
%   决定修复强度；"该不该修"由 (1 - targetProtection) 独立决定。结构保护
%   **不**反向塞进 blemish 检测（证据链只消费 blemishMap 与全局/局部密度），
%   blemish 证据也**不**绕过 target 门。
%
%   读取集合（上位契约第 1 节）：
%     beautyMasks.skinMask / strengthMap / nonFaceStrengthMap
%       —— processability 与 strength 层（不参与保护判定）；
%     repairContract.hard                —— hard identity，组合 (1-hard) 乘子；
%     repairContract.support.repairMid   —— 结构保护（1 - 该值 = 生产
%       structureGate，含 runtime blemish 放宽与强结构上限；截断在它与
%       纹理/鼻部门之间，故必须独立发布；同一门也用于邻域参考池）；
%     repairContract.target.repairFine   —— 截断后作用的纹理退让保护；
%     repairContract.target.repairMid    —— 截断后作用的 Mid 鼻部退让保护；
%     repairContract.support.repairFine  —— 邻域参考池纹理保护；
%     repairContract.textureBandGate     —— T30 纯 policy 带门，只乘逐像素
%       权重，不进邻域参考统计；
%     blemishMap                        —— 运行期证据。
%
%   生产顺序（与 legacy 逐位等价的关键）：结构门在 [0,1] 截断之前作用于
%   权重；纹理门作用于 Fine/Mid/chroma，鼻部门只作用于 Mid，二者均在截断
%   之后、textureBandGate 之前，且鼻部门先于纹理门（legacy 乘法结合序）。
%
%   生产链在结构门与纹理/鼻部门之间对权重做 [0,1] 截断（
%   min(max(w·structureGate,0),1) 之后才乘纹理/鼻部门），把纹理或鼻部折叠
%   进前置门会在截断饱和区改变结果（T14 实测偏差 ~0.1 量级，T31 真实图
%   实测 fineWeight 7594px、mediumWeight 3429px 偏离）；因此 target 门按生产
%   原位拆成"前置结构 + 截断后纹理/鼻"两段，消费侧按同一顺序重建。
%
%   邻域参考统计（referenceReliability/referenceWeight）只用
%   support.repairFine / support.repairMid 与 blemish 证据，**不**乘 target
%   门与 textureBandGate：把 target 门并进参考池会让带内变化经 imfilter
%   （radius = min(20, max(3, round(.070*faceScale)))）扩散到带外，产生
%   >1 灰度级泄漏。全局参考统计因此与 target 门解耦。
%
%   兼容入口（未提供第 5 参的旧调用方）：T31 起不再自行解释 general
%   texture/structure/hard/nose masks，而是向 policy 层索取零带
%   stageProtection 后经同一组装点得到 contract。
%
%   缺字段或取值无效一律 fail-fast，不在函数内部重新拼装 protection，也不
%   静默回退。

if nargin < 4
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要频率、Beauty Masks、瑕疵图和磨皮强度。');
end
validateFrequency(frequency);
imageSize = frequency.imageSize(1:2);
validateMasks(beautyMasks, imageSize);
blemishMap = readBlemishMap(blemishMap, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

base = double(frequency.base);
mid = double(frequency.mid);
fine = double(frequency.fine);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
if nargin < 5 || isempty(repairContract)
    % T31 兼容入口：向 policy 层索取零带 stageProtection 后经同一组装点
    % 得到 contract（不再读取 general masks）。
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
    repairContract = beauty.repairStageContract(stageProtection, blemishMap);
else
    repairContract = validateRepairContract(repairContract, imageSize);
end

profile = beautySmoothingProfile(smoothingStrength);
hardGate = repairContract.hard;
allowed = min(skinMask, strengthMap) .* (1 - hardGate);
nonFaceStrength = readOptionalMask(beautyMasks, ...
    'nonFaceStrengthMap', imageSize);
nonFacePixels = nonFaceStrength > .01;
if any(nonFacePixels(:))
    allowed(nonFacePixels) = profile.outsideFaceStrength .* ...
        min(skinMask(nonFacePixels), nonFaceStrength(nonFacePixels)) .* ...
        (1 - hardGate(nonFacePixels));
end
normalRepairCurve = min(profile.blemishStrength / (.75 ^ .85), 1);
highEndRepairCurve = max(profile.blemishStrength - .75 ^ .85, 0);
% 前置结构门（含 runtime blemish 放宽与强结构固定下限）由 contract 按生产
% 原式重建并发布为 support.repairMid 的补码；执行层只做补码还原，不再自行
% 组合 general masks。该门同时用于邻域参考池（见下）。
structureGate = 1 - repairContract.support.repairMid;

% 低置信度瑕疵保留在 Fine 层；Mid 仅在连续置信度达到中高档后
% 开启，避免普通皮肤被大面积拉向一个颜色。
faceScale = readFaceScale(frequency);
blemishDensity = imgaussfilt(double(blemishMap > .60), ...
    max(3, min(12, .04 * faceScale)), 'Padding', 'replicate');
globalHighDensity = mean(blemishMap(:) > .60);
globalBlemishMean = mean(blemishMap(:));
sparseGate = 1 - smoothStep(globalHighDensity, .05, .15) .* ...
    smoothStep(blemishDensity, .03, .20);
globalGate = smoothStep(globalBlemishMean, .005, .015);
% 证据链只消费 blemish 图与全局/局部密度：结构保护不得反向塞进
% blemish 检测，blemish 证据也不得绕过 target 门（见下方权重）。
repairEvidence = min(max(blemishMap .* sparseGate .* globalGate, 0), 1);
mediumConfidence = smoothStep(repairEvidence, .60, .90);
highConfidence = smoothStep(repairEvidence, .62, .90);
if highEndRepairCurve > 0
    blobMask = smallBlemishBlobs(blemishMap > .65, faceScale);
else
    blobMask = false(imageSize);
end
% 高档额外修复必须同时满足高置信局部异常、紧凑 Blob 和全局证据；
% 证据链不消费任何区域语义，鼻部同样只能靠 blemish 证据进入。
highEndConfidence = highConfidence .* double(blobMask) .* globalGate;
repairCurveMap = normalRepairCurve * ones(imageSize);
repairCurveMap = min(max(repairCurveMap, 0), 1);

% 逐像素修复强度 = blemish 证据 × processability/strength（allowed）
% × (1 - 前置结构保护)，截断后再按生产顺序乘后置门：
%   fineWeight   : × (1 - target.repairFine)          （纹理退让）
%   mediumWeight : × noseMidGate × (1 - target.repairFine)
%                  noseMidGate = (1 - target.repairMid) × midBandGate
%                                （鼻部退让 × Mid 专属 policy 带，合成后
%                                 先于纹理门相乘，与 legacy 结合序一致）
%   chromaWeight : × (1 - target.repairFine)
% blemish 证据与 target 门相互独立：改动 target 门只改变"该不该修"，不改变
% blemish 证据；鼻部门先于纹理门相乘，与 legacy 乘法结合序一致（bit-exact）。
fineWeight = repairCurveMap .* (repairEvidence + .25 * highConfidence) .* ...
    allowed .* structureGate + (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = repairCurveMap .* (.95 * mediumConfidence + ...
    .40 * highConfidence) .* allowed .* structureGate + ...
    (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = min(max(mediumWeight, 0), 1);
chromaWeight = .16 * repairCurveMap .* highConfidence .* allowed .* ...
    structureGate;
fineWeight = min(max(fineWeight, 0), 1);
chromaWeight = min(max(chromaWeight, 0), 1);

% 脸部和脸外的允许权重完成后统一应用线性纹理软保护；同一门控也
% 从邻域参考采样中排除受保护纹理，避免保护区域反向影响附近修复。
% T30/T31：纯 policy 带 textureBandGate / midBandGate 只乘逐像素权重；
% referenceReliability（下方 imfilter 邻域参考）仍用未带 support 门，
% 避免带内变化经卷积扩散到带外。零带时 textureBandGate == midBandGate == 1。
textureBandGate = repairContract.textureBandGate;
midBandGate = repairContract.midBandGate;
targetFineGate = 1 - repairContract.target.repairFine;
targetMidGate = 1 - repairContract.target.repairMid;
% Mid 逐像素门的合成顺序与 legacy 生产原式一致：
% midPixelGate = (1 - .50·nose) .* (1 - regionBandMid)，随后先于纹理门
% 乘到 mediumWeight，保证 mediumWeight 与生产路径逐位相等。
midPixelGate = targetMidGate .* midBandGate;
fineWeight = fineWeight .* targetFineGate .* textureBandGate;
mediumWeight = mediumWeight .* midPixelGate .* targetFineGate .* ...
    textureBandGate;
chromaWeight = chromaWeight .* targetFineGate .* textureBandGate;

radius = min(20, max(3, round(.070 * faceScale)));
kernelSize = 2 * radius + 1;
kernel = ones(kernelSize, kernelSize);

% 参考只使用非瑕疵皮肤，并降低跨越结构边缘的贡献；这样鼻梁和
% 手指的低频坡面不会被邻域平均抹平。参考池门来自 support.*（与 target
% 门解耦），blemish 证据按运行期独立乘入；乘法顺序与 legacy 一致
% （textureGate → blemish → structureGate），保证参考统计逐位不变。
supportTextureGate = 1 - repairContract.support.repairFine;
supportStructureGate = 1 - repairContract.support.repairMid;
referenceReliability = allowed .* supportTextureGate .* ...
    (1 - .86 * blemishMap) .* supportStructureGate;
referenceWeight = imfilter(referenceReliability, kernel, 'replicate');
fineReference = imfilter(fine .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
midReference = imfilter(mid .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
fineReference(referenceWeight <= eps) = 0;
midReference(referenceWeight <= eps) = 0;

% 参考只允许把同号残差向零收敛，避免局部邻域的反向纹理在
% 强度升高时被重新放大，从而保证 Fine 和瑕疵能量单调下降。
fineTarget = sign(fine) .* min(abs(fine), abs(fineReference));
midTarget = sign(mid) .* min(abs(mid), abs(midReference));
fineCorrection = fineWeight .* (fineTarget - fine);
mediumCorrection = mediumWeight .* (midTarget - mid);

repairedFrequency = frequency;
repairedFrequency.fine = fine + fineCorrection;
repairedFrequency.mid = mid + mediumCorrection;
repairedFrequency.reconstructedLuminance = base + ...
    repairedFrequency.mid + repairedFrequency.fine;
repairedFrequency.outputLuminance = repairedFrequency.reconstructedLuminance;
if isfield(frequency, 'alphaMap')
    alphaMap = validateMask(frequency.alphaMap, imageSize, 'alphaMap');
else
    alphaMap = zeros(imageSize);
end
repairedFrequency.alphaMap = min(1, max(alphaMap, ...
    fineWeight + mediumWeight));
repairedFrequency.blemishRepair = struct( ...
    'fineCorrection', fineCorrection, ...
    'mediumCorrection', mediumCorrection, ...
    'chromaWeight', chromaWeight);

beforeEnergy = mean(abs(fine(:)) + abs(mid(:)));
afterEnergy = mean(abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:)));
blemishBefore = mean((abs(fine(:)) + abs(mid(:))) .* blemishMap(:));
blemishAfter = mean((abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:))) .* blemishMap(:));
% T31 诊断收口：不再报告 noseMask/noseMidGate 与 general texture mask；
% 报告 target 门（逐像素修改保护）与 support 门（参考池保护）两族。
diagnostics = struct( ...
    'blemishMap', blemishMap, ...
    'sparseGate', sparseGate, ...
    'globalHighDensity', globalHighDensity, ...
    'globalBlemishMean', globalBlemishMean, ...
    'globalGate', globalGate, ...
    'normalRepairCurve', normalRepairCurve, ...
    'highEndRepairCurve', highEndRepairCurve, ...
    'repairEvidence', repairEvidence, ...
    'mediumConfidence', mediumConfidence, ...
    'highConfidence', highConfidence, ...
    'repairCurveMap', repairCurveMap, ...
    'blobMask', blobMask, ...
    'highEndConfidence', highEndConfidence, ...
    'textureGate', targetFineGate, ...
    'targetFineGate', targetFineGate, ...
    'targetMidGate', targetMidGate, ...
    'supportTextureGate', supportTextureGate, ...
    'supportStructureGate', supportStructureGate, ...
    'textureBandGate', textureBandGate, ...
    'midBandGate', midBandGate, ...
    'fineWeight', fineWeight, ...
    'mediumWeight', mediumWeight, ...
    'midWeight', mediumWeight, ...
    'chromaWeight', chromaWeight, ...
    'repairWeight', min(1, fineWeight + mediumWeight), ...
    'allowed', allowed, ...
    'structureGate', structureGate, ...
    'referenceReliability', referenceReliability, ...
    'referenceWeight', referenceWeight, ...
    'fineReference', fineReference, ...
    'midReference', midReference, ...
    'fineTarget', fineTarget, ...
    'midTarget', midTarget, ...
    'fineCorrection', fineCorrection, ...
    'mediumCorrection', mediumCorrection, ...
    'fineBefore', fine, ...
    'fineAfter', repairedFrequency.fine, ...
    'midBefore', mid, ...
    'midAfter', repairedFrequency.mid, ...
    'fineEnergyBefore', mean(abs(fine(:))), ...
    'fineEnergyAfter', mean(abs(repairedFrequency.fine(:))), ...
    'frequencyEnergyBefore', beforeEnergy, ...
    'frequencyEnergyAfter', afterEnergy, ...
    'blemishEnergyBefore', blemishBefore, ...
    'blemishEnergyAfter', blemishAfter, ...
    'baseUnchanged', isequal(repairedFrequency.base, frequency.base), ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
% 零瑕疵参考门快照（T07 target 快照的补码）保留，供诊断与测试消费；
% fineGateRuntime 为 contract 重建的前置结构门（= structureGate）。
diagnostics.fineGateRuntime = structureGate;
diagnostics.fineGateZeroBlemish = 1 - repairContract.snapshot.repairFine;
diagnostics.mediumGateZeroBlemish = 1 - repairContract.snapshot.repairMid;
end

function contract = validateRepairContract(contract, imageSize)
%VALIDATEREPAIRCONTRACT 校验 Repair（Fine/Mid）stage contract（T14/T15/T30/T31）。
%   必需字段：hard、support.repairMid（结构保护，1 - 该值 = 生产
%   structureGate，同时作用于逐像素前置截断与邻域参考池）、
%   support.repairFine（参考池纹理保护）、target.repairFine/.repairMid
%   （截断后逐像素退让保护）、textureBandGate/midBandGate（T30 纯 policy
%   带门，分别只乘 texture 通道与 Mid 通道）、snapshot.repairFine/.repairMid
%   （T07 零瑕疵参考快照）。缺字段或取值无效一律 fail-fast，不在函数内部
%   重新拼装，也不静默回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'hard', 'target', 'support', ...
        'textureBandGate', 'midBandGate', 'snapshot'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 必须是包含 hard/target/support/textureBandGate/midBandGate/snapshot 的标量结构。');
end
if ~isstruct(contract.target) || ~isscalar(contract.target) || ...
        ~all(isfield(contract.target, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 target 缺少 repairFine/repairMid。');
end
if ~isstruct(contract.support) || ~isscalar(contract.support) || ...
        ~all(isfield(contract.support, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 support 缺少 repairFine/repairMid。');
end
if ~isstruct(contract.snapshot) || ~isscalar(contract.snapshot) || ...
        ~all(isfield(contract.snapshot, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 snapshot 缺少 repairFine/repairMid。');
end
contract.hard = validateMask(contract.hard, imageSize, 'hard');
contract.target.repairFine = validateMask(contract.target.repairFine, ...
    imageSize, 'target.repairFine');
contract.target.repairMid = validateMask(contract.target.repairMid, ...
    imageSize, 'target.repairMid');
contract.support.repairFine = validateMask(contract.support.repairFine, ...
    imageSize, 'support.repairFine');
contract.support.repairMid = validateMask(contract.support.repairMid, ...
    imageSize, 'support.repairMid');
contract.textureBandGate = validateMask(contract.textureBandGate, ...
    imageSize, 'textureBandGate');
contract.midBandGate = validateMask(contract.midBandGate, ...
    imageSize, 'midBandGate');
contract.snapshot.repairFine = validateMask(contract.snapshot.repairFine, ...
    imageSize, 'snapshot.repairFine');
contract.snapshot.repairMid = validateMask(contract.snapshot.repairMid, ...
    imageSize, 'snapshot.repairMid');
end

function validateFrequency(frequency)
if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'base', 'mid', 'fine', 'imageSize'}))
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要完整的 Base/Mid/Fine 频率结构。');
end
imageSize = frequency.imageSize(1:2);
for name = {'base', 'mid', 'fine'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:)))
        error('beauty:InvalidBlemishRepair', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
end

function validateMasks(beautyMasks, imageSize)
%VALIDATEMASKS 校验 strength/processability 层输入。
%   T31 起本函数只校验 skinMask 与 strengthMap：repair 执行层不再读取
%   任何 general protection mask（texture/structure/hard/nose），保护门
%   全部来自 stage contract。
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidBlemishRepair', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    validateMask(beautyMasks.(required{index}), imageSize, required{index});
end
end

function value = readBlemishMap(value, imageSize)
if isstruct(value)
    if isfield(value, 'blemishMap')
        value = value.blemishMap;
    elseif isfield(value, 'confidence')
        value = value.confidence;
    else
        error('beauty:InvalidBlemishRepair', ...
            '瑕疵诊断结构缺少 blemishMap 或 confidence。');
    end
end
value = validateMask(value, imageSize, 'blemishMap');
end

function value = readMask(context, name, imageSize)
value = validateMask(context.(name), imageSize, name);
end

function value = readOptionalMask(context, name, imageSize)
if isfield(context, name)
    value = validateMask(context.(name), imageSize, name);
else
    value = zeros(imageSize);
end
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidBlemishRepair', 'Mask %s 无效。', name);
end
value = double(value);
end

function faceScale = readFaceScale(frequency)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
else
    if isfield(frequency, 'faceBox')
        faceScale = min(frequency.faceBox(3:4));
    else
        faceScale = min(size(frequency.base));
    end
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function blobMask = smallBlemishBlobs(candidate, faceScale)
% 只有小而紧凑的连通瑕疵才接受高档额外修复，长条纹理不进入该层。
blobMask = false(size(candidate));
if ~any(candidate(:))
    return;
end
components = bwconncomp(candidate, 8);
areaLimit = max(24, round(.006 * faceScale ^ 2));
spanLimit = max(5, round(.045 * faceScale));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    [rows, columns] = ind2sub(size(candidate), pixels);
    rowSpan = max(rows) - min(rows) + 1;
    columnSpan = max(columns) - min(columns) + 1;
    fillRatio = numel(pixels) / max(1, rowSpan * columnSpan);
    if numel(pixels) <= areaLimit && max(rowSpan, columnSpan) <= spanLimit && ...
            fillRatio >= .18
        blobMask(pixels) = true;
    end
end
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
