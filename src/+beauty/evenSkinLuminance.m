function [luminanceResult, diagnostics] = evenSkinLuminance( ...
        frequency, beautyMasks, smoothingStrength, baseLuminanceContract)
%EVENSKINLUMINANCE 对皮肤 Base 亮度执行局部均匀化。
%   本模块只读取 frequency.base。可靠皮肤的归一化加权局部参考用于
%   生成目标 Base；输出 baseDelta 已经包含全部作用权重，合成阶段不再
%   重复乘权，也不在此处渲染 RGB。
%
%   T16：可选第 4 参数 baseLuminanceContract 是 Base Luminance 的
%   stage contract，由 beautifyImage 生产端从与生产门控共用的同一份
%   beautyMasks 产物拼装传入（T12/T13 范式）。提供时 feature/
%   reference support 的保护输入只来自 contract，不再自行组合 general
%   texture/chroma/structure/hard masks；低频参考、亮度校正与输出公
%   式不变。字段语义：
%     baseLuminance — T07 发布的 stage protection 快照
%                     baseLuminance = 1 - (1 - structure) .*
%                     (1 - max(texture, chroma))；该折叠含 1-x 补码
%                     往返舍入，无法逐位还原门控积 (1 - structure) .*
%                     (1 - max(texture, chroma))，因此快照不参与输出
%                     算术，只作为 T07 参考门由诊断（baseGateSnapshot）
%                     与测试消费；
%     hard          — hard identity（T07 单独发布），按生产原位组合
%                     进 referenceReliability/supportMap 的 (1-hard)
%                     乘子；
%     structureGate — 未折叠结构门 1 - structure（reference
%                     reliability 与 supportMap 共用）；
%     featureGate   — 未折叠 feature 门 1 - max(texture, chroma)
%                     （texture 与 chroma 的组合留在生产端）；
%     regionBandGate— T30 纯 policy 带门 1 - regionBandBase（追加保护
%                     量的补），**只作用于逐像素 supportMap**，不进入
%                     referenceReliability。
%   T30 激活（region policy gate）：分级保护经 regionBandGate 注入
%   supportMap；全局参考基准（referenceReliability/referenceWeight/
%   weightedReference/referenceOffset/referenceCoverage/
%   normalizationMask）仍用未带 featureGate。分界原因：featureGate 会
%   同时进入全局参考卷积（imgaussfilt）与逐像素 support，若把 band 并
%   入 featureGate，带内变化会经参考池扩散到带外（实测带外 2226px/
%   0.94% 出现 ≤2 灰度级泄漏）。把 band 限制在 supportMap 后，带外
%   （band==0 → gate==1）逐位还原 legacy，带外输出泄漏回到 T30 之前
%   的 ≤1 灰度级量级。
%   运行期由生产端按与 legacy 完全相同的表达式、同一份 mask 产物计
%   算未折叠字段，消费侧按生产原式、原顺序重建门控，与 legacy 路径
%   逐位等价（bit-exact，零带时）。缺字段 fail-fast，不在函数内部重新
%   拼装，也不静默回退；未提供第 4 参的旧调用方走 legacy 兼容路径，
%   行为不变。processability（skinMask）与强度（strengthMap）不属于
%   protection，两条路径都继续从 beautyMasks 读取；runtime
%   reliability（referenceReliability/referenceWeight/
%   referenceCoverage）计算保留，但不再重解释 general 保护 masks 的
%   区域语义。

if nargin < 3
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base 亮度均匀化需要频率、Beauty Masks 和磨皮强度。');
end
useStageContract = nargin >= 4 && ~isempty(baseLuminanceContract);
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
% T16：保护门控来源二选一。stage 路径只消费 contract（快照不参与
% 输出算术）；legacy 路径保持原解释与数值。两条路径的三个未折叠门
% 控按同一表达式、同一份 mask 产物取得，数值逐位一致。
% T30：regionBandGate 是纯 policy 追加保护门（1 - regionBandBase），
% 只作用于 supportMap；legacy 路径无带，取恒等 1（x .* 1 逐位不变）。
if useStageContract
    baseLuminanceContract = validateBaseLuminanceContract( ...
        baseLuminanceContract, imageSize);
    structureGate = baseLuminanceContract.structureGate;
    hardProtectionGate = 1 - baseLuminanceContract.hard;
    featureGate = baseLuminanceContract.featureGate;
    regionBandGate = baseLuminanceContract.regionBandGate;
else
    structureProtection = readMask(beautyMasks, ...
        'structureProtectionMask', imageSize);
    hardProtection = readOptionalMask(beautyMasks, ...
        'hardProtectionMask', imageSize);
    textureProtection = readOptionalMask(beautyMasks, ...
        'textureProtectionMask', imageSize);
    [chromaProtection, hasChromaProtection] = resolveChromaProtectionMask( ...
        beautyMasks, imageSize, 'beauty:InvalidEvenLuminanceInput', ...
        'beauty:ChromaProtectionConflict');
    if ~hasChromaProtection
        chromaProtection = zeros(imageSize);
    end
    featureProtection = max(cat(3, textureProtection, ...
        chromaProtection), [], 3);
    structureGate = 1 - structureProtection;
    hardProtectionGate = 1 - hardProtection;
    featureGate = 1 - featureProtection;
    regionBandGate = ones(imageSize);
end

% 参考权重与作用权重分开：前者只决定局部参考是否可信，后者决定
% 当前像素实际校正多少。这样五官和强结构不会污染邻域参考，也不会
% 通过同一张权重在最终合成时被再次衰减。
% T30 分界：referenceReliability 是全局参考池统计（经 imgaussfilt 卷
% 积），刻意不含 regionBandGate——band 只作用于逐像素 supportMap，
% 否则带内变化会经参考池扩散到带外。
referenceReliability = skinMask .* strengthMap .* structureGate .* ...
    hardProtectionGate .* featureGate;
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
% T30：regionBandGate 只在此处（逐像素 support/修正量）注入，不进
% referenceReliability。零带/legacy 时 regionBandGate == 1，乘法恒
% 等，supportMap 与 legacy 逐位相等。
supportMap = baseWeightCurve .* regionalSkinWeight .* structureGate .* ...
    hardProtectionGate .* featureGate .* regionBandGate .* ...
    referenceCoverage;
supportMap = min(max(supportMap, 0), 1);

% 先限制未经计权的目标差异，再乘一次完整作用权重。该差异保留
% 符号，因此暗区可提亮、亮区可压低，二者使用同一条校正路径。
rawBaseDelta = localReference - base;
limitedBaseDelta = min(max(rawBaseDelta, -.03), .03);
baseDelta = limitedBaseDelta .* supportMap;
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
    'structureGate', structureGate, ...
    'hardProtectionGate', hardProtectionGate, ...
    'featureGate', featureGate, ...
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
    'faceScale', faceScale, ...
    'baseDeltaLimit', .03, ...
    'maxAbsBaseDelta', max(abs(baseDelta(:))), ...
    'frequencyUnchanged', true, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
if useStageContract
    % T16：stage 路径不再报告 chroma/tone 兼容 alias（保护输入由
    % contract 承载），新增 T07 baseLuminance 快照的参考门；runtime
    % 门控积 structureGate·featureGate 与 1 - 快照一致（≤1e-15，1-x
    % 补码往返舍入），由测试断言衔接 T07 语义。T30：另报告纯 policy
    % 带门 regionBandGate（只作用于 supportMap，不进全局参考）。
    diagnostics.baseGateSnapshot = 1 - baseLuminanceContract.baseLuminance;
    diagnostics.regionBandGate = regionBandGate;
else
    diagnostics.chromaProtectionMask = chromaProtection;
    diagnostics.toneProtectionMask = chromaProtection;
end
end

function contract = validateBaseLuminanceContract(contract, imageSize)
%VALIDATEBASELUMINANCECONTRACT 校验 Base Luminance stage contract（T16/T30）。
%   必需字段：baseLuminance（T07 零运行期耦合快照）、hard（hard
%   identity）、structureGate/featureGate（生产端按生产原式计算的未折
%   叠门控字段）、regionBandGate（T30 纯 policy 带门 1 - regionBandBase，
%   只作用于 supportMap）。缺字段或取值无效一律 fail-fast，不在函数内
%   部重新拼装，也不静默回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'baseLuminance', 'hard', ...
        'structureGate', 'featureGate', 'regionBandGate'}))
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base Luminance stage contract 必须是包含 baseLuminance、hard、structureGate、featureGate 和 regionBandGate 的标量结构。');
end
contract.baseLuminance = readMask(contract, 'baseLuminance', imageSize);
contract.hard = readMask(contract, 'hard', imageSize);
contract.structureGate = readMask(contract, 'structureGate', imageSize);
contract.featureGate = readMask(contract, 'featureGate', imageSize);
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
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base 亮度均匀化需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap', 'structureProtectionMask'};
for index = 1:numel(required)
    name = required{index};
    if ~isfield(beautyMasks, name)
        error('beauty:InvalidEvenLuminanceInput', ...
            'Beauty Masks 缺少字段 %s。', name);
    end
    readMask(beautyMasks, name, imageSize);
end
optional = {'hardProtectionMask', 'textureProtectionMask'};
for index = 1:numel(optional)
    if isfield(beautyMasks, optional{index})
        readMask(beautyMasks, optional{index}, imageSize);
    end
end
[~, ~] = resolveChromaProtectionMask(beautyMasks, imageSize, ...
    'beauty:InvalidEvenLuminanceInput', ...
    'beauty:ChromaProtectionConflict');
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
