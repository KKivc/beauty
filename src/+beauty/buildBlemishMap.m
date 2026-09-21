function [blemishMap, diagnostics] = buildBlemishMap( ...
        inputImage, frequency, beautyMasks, stageProtection)
%BUILDBLEMISHMAP 根据固定频率和色度残差生成瑕疵置信度图。
%   瑕疵图不读取任何美颜强度，因此同一输入在不同滑块档位下保持
%   同一分类结果。Fine、Mid 和色度证据先分别归一化，再合成为一张
%   连续的 [0, 1] 置信度图；结构保护只在后续修复时限制修改量。
%
%   运行期 evidence 定位（T11）：本函数是 blemish 运行期 evidence 的
%   唯一生产者，输入仍是 BeautyMasks 与频率分解，数值逻辑（阈值、
%   权重、平滑）冻结不变。产物由 beautifyImage 组装进局部
%   runtimeEvidence 结构供 stage 消费；不写入持久化 policy-time
%   Context（不进 V4 分层、不进缓存兼容判定），与
%   masks.buildBeautyPolicyEvidence 的 policy-time evidence 层无
%   依赖关系。后续 Repair/Tone consumer 应从 runtimeEvidence 读取
%   本图，而不是假设它存在于静态 Context。
%
%   第 4 参数 stageProtection 只用于构建独立的 denseBlemishField：高置信
%   种子的局部密度可以形成大片连续包络，但包络最终仍逐像素经过
%   processability、hard、region band、五官/耳部软保护和结构保护裁剪。
%   该证据不回写任何 protection，也不进入现有 compact blob Repair。

if nargin < 4
    stageProtection = [];
end
validateInput(inputImage, frequency, beautyMasks);
imageSize = size(inputImage, 1:2);
fine = double(frequency.fine);
mid = double(frequency.mid);
ycbcr = rgb2ycbcr(im2double(inputImage));
cb = ycbcr(:, :, 2);
cr = ycbcr(:, :, 3);

skinMask = readMask(beautyMasks, 'skinMask', imageSize);
hardProtection = readOptionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);
skinCandidate = skinMask .* (1 - hardProtection);
skinSupport = skinCandidate > .05;
if ~any(skinSupport(:))
    blemishMap = zeros(imageSize);
    denseBlemishField = zeros(imageSize);
    diagnostics = emptyDiagnostics(imageSize, skinCandidate, ...
        denseBlemishField);
    return;
end

faceScale = readFaceScale(frequency, beautyMasks);
chromaSigma = min(12, max(2.5, .025 * faceScale));
localCb = imgaussfilt(cb, chromaSigma, 'Padding', 'replicate');
localCr = imgaussfilt(cr, chromaSigma, 'Padding', 'replicate');

fineMagnitude = abs(fine);
midMagnitude = abs(mid);
chromaMagnitude = max(abs(cb - localCb), abs(cr - localCr));

[fineEvidence, fineThresholds] = residualEvidence( ...
    fineMagnitude, skinSupport, .50, .88, .35, .95, .0035);
[midEvidence, midThresholds] = residualEvidence( ...
    midMagnitude, skinSupport, .50, .88, .40, 1.05, .0060);
[chromaEvidence, chromaThresholds] = residualEvidence( ...
    chromaMagnitude, skinSupport, .50, .88, .40, 1.05, .0100);

% 一个单独的证据只构成低置信度；多种证据同时出现时才逐步进入
% 中高置信度，避免把正常毛孔或鼻梁梯度整片判为瑕疵。
combinedEvidence = .30 * fineEvidence + .38 * midEvidence + ...
    .32 * chromaEvidence;
synergy = max(cat(3, fineEvidence .* midEvidence, ...
    fineEvidence .* chromaEvidence, midEvidence .* chromaEvidence), [], 3);
combinedEvidence = min(1, combinedEvidence + .22 * sqrt(synergy));

evidenceSigma = max(.65, min(2.5, .0025 * faceScale));
smoothedEvidence = imgaussfilt(combinedEvidence, evidenceSigma, ...
    'Padding', 'replicate');
confidence = .78 * combinedEvidence + .22 * smoothedEvidence;
confidence = min(max(confidence, 0), 1) .* double(skinCandidate > .01);

% 保留原始证据的空间位置，平滑项只负责让修复权重连续，不扩大皮肤
% 候选区域，也不削弱结构保护本身。
blemishMap = min(max(confidence, 0), 1);
denseBlemishField = buildDenseBlemishField(blemishMap, beautyMasks, ...
    stageProtection, faceScale);
structureProtection = readOptionalMask(beautyMasks, ...
    'structureProtectionMask', imageSize);
[chromaProtection, hasChromaProtection] = resolveChromaProtectionMask( ...
    beautyMasks, imageSize, 'beauty:InvalidBlemishInput', ...
    'beauty:ChromaProtectionConflict');
if ~hasChromaProtection
    chromaProtection = zeros(imageSize);
end
faceMask = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);
faceMask = min(faceMask, skinMask);
nonFaceMask = readOptionalMask(beautyMasks, ...
    'nonFaceSkinMask', imageSize);
nonFaceMask = min(nonFaceMask, skinMask);

diagnostics = struct( ...
    'blemishMap', blemishMap, ...
    'map', blemishMap, ...
    'confidence', blemishMap, ...
    'denseBlemishField', denseBlemishField, ...
    'fineEvidence', fineEvidence, ...
    'midEvidence', midEvidence, ...
    'chromaEvidence', chromaEvidence, ...
    'fineMagnitude', fineMagnitude, ...
    'midMagnitude', midMagnitude, ...
    'chromaMagnitude', chromaMagnitude, ...
    'localCb', localCb, ...
    'localCr', localCr, ...
    'skinCandidate', skinCandidate, ...
    'faceCandidate', min(faceMask, skinCandidate), ...
    'nonFaceCandidate', min(nonFaceMask, skinCandidate), ...
    'structureProtectionMask', structureProtection, ...
    'chromaProtectionMask', chromaProtection, ...
    'toneProtectionMask', chromaProtection, ...
    'hardProtectionMask', hardProtection, ...
    'faceScale', faceScale, ...
    'imageSize', [imageSize, 3], ...
    'fineThresholds', fineThresholds, ...
    'midThresholds', midThresholds, ...
    'chromaThresholds', chromaThresholds);
end

function denseBlemishField = buildDenseBlemishField( ...
        blemishMap, beautyMasks, stageProtection, faceScale)
%BUILDDENSEBLEMISHFIELD 从高置信证据密度构建连续瑕疵包络。
%   这里不使用连通域面积、跨度或 fillRatio；这些约束属于现有
%   compact blob Repair，必须继续由 repairSkinBlemishes 独立执行。
%   先生成高置信种子，再以 faceScale 归一的局部密度形成包络，最后
%   逐像素应用不可放宽的保护门。任何 blemish 证据都不能扩大这些门。
imageSize = size(blemishMap);
[ordinarySkin] = denseOrdinarySkin(beautyMasks, stageProtection, imageSize);
% 高置信种子用于确认密集瑕疵，中置信种子用于补足“每个雀斑都不够
% 高”的连续场。两者都必须先落在同一安全域内；它们只改变 dense
% evidence 的覆盖，不会改变任何保护门。
highSeed = ordinarySkin & blemishMap >= .72;
mediumSeed = ordinarySkin & blemishMap >= .50;
if ~any(highSeed(:)) && ~any(mediumSeed(:))
    denseBlemishField = zeros(imageSize);
    return;
end

densitySigma = min(14, max(3, .022 * double(faceScale)));
localHighDensity = imgaussfilt(double(highSeed), densitySigma, ...
    'Padding', 'replicate');
localMediumDensity = imgaussfilt(double(mediumSeed), densitySigma, ...
    'Padding', 'replicate');
% 面积较大的雀斑场不一定有足够多的 .72 高置信像素。局部平均
% blemish evidence 只作为低权重底座，允许连续色斑进入曲面先验，
% 但不会单独开启 compact Repair。
localEvidence = imgaussfilt(blemishMap .* double(ordinarySkin), ...
    densitySigma, 'Padding', 'replicate');
% 大尺度密度用于连续雀斑场：整片皮肤存在许多中高置信种子时，
% 种子之间的安全皮肤也需要进入独立 dense 分支；这不改变 compact
% blob 的面积/跨度限制，也不放宽任何结构保护。
broadSigma = min(28, max(densitySigma + 2, .055 * double(faceScale)));
broadHighDensity = imgaussfilt(double(highSeed), broadSigma, ...
    'Padding', 'replicate');
broadMediumDensity = imgaussfilt(double(mediumSeed), broadSigma, ...
    'Padding', 'replicate');
broadEvidence = imgaussfilt(blemishMap .* double(ordinarySkin), ...
    broadSigma, 'Padding', 'replicate');

% 小尺度保留局部斑点，大尺度识别整片密集瑕疵场。高置信路径仍是
% 主证据；中置信路径只作为连续场的低权重底座，避免稀疏自然纹理被
% 一颗误检种子升级为大面积修复。
highEnvelope = max( ...
    smoothStep(localHighDensity, .035, .12), ...
    .75 * smoothStep(broadHighDensity, .012, .050));
mediumEnvelope = max( ...
    smoothStep(localMediumDensity, .075, .22), ...
    .60 * smoothStep(broadMediumDensity, .025, .095));
evidenceEnvelope = max( ...
    smoothStep(localEvidence, .105, .24), ...
    .65 * smoothStep(broadEvidence, .080, .18));
densityEnvelope = max(highEnvelope, .55 * mediumEnvelope);
densityEnvelope = max(densityEnvelope, .70 * evidenceEnvelope);

% 沿真实 safe skin 的内侧羽化，避免 semantic skin 边界产生新的圆圈或
% 硬切线。bwdist 只用于形成边界距离，不扩大 ordinarySkin 的语义域。
edgeWidth = max(2, round(.012 * double(faceScale)));
skinDistance = bwdist(~ordinarySkin);
edgeFade = smoothStep(skinDistance, 0, edgeWidth);
denseBlemishField = densityEnvelope .* edgeFade .* double(ordinarySkin);
denseBlemishField(denseBlemishField < .05) = 0;
denseBlemishField = min(max(denseBlemishField, 0), 1);
end

function ordinarySkin = denseOrdinarySkin( ...
        beautyMasks, stageProtection, imageSize)
%DENSEORDINARYSKIN 返回 dense field 允许使用的普通可处理皮肤。
%   语义细节的稳定来源是 stageProtection 的 regionBand 与规范
%   target/support 门；缺少 stageProtection 的直接兼容调用则使用现有
%   Beauty Masks 的纹理/结构/hard/protection 字段，不伪造语义区域。
skinMask = readOptionalMask(beautyMasks, 'skinMask', imageSize);
% 生产路径提供 faceSkinMask 时，dense 场只允许在脸部安全皮肤内建立。
% 兼容/单元 fixture 未提供该字段时回退到 skinMask，避免伪造语义区域。
faceSkinMask = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);
if any(faceSkinMask(:) > .05)
    skinMask = min(skinMask, faceSkinMask);
end
hard = readOptionalMask(beautyMasks, 'hardProtectionMask', imageSize);
texture = readOptionalMask(beautyMasks, ...
    'textureProtectionMask', imageSize);
structure = readOptionalMask(beautyMasks, ...
    'structureProtectionMask', imageSize);
regionBand = zeros(imageSize);

if isstruct(stageProtection) && isscalar(stageProtection)
    hard = max(hard, readStageMask(stageProtection, 'hard', imageSize));
    if isfield(stageProtection, 'support') && ...
            isstruct(stageProtection.support)
        texture = max(texture, readStageMask(stageProtection.support, ...
            'repairFine', imageSize));
        structure = max(structure, readStageMask(stageProtection.support, ...
            'repairMid', imageSize));
    end
    if isfield(stageProtection, 'target') && ...
            isstruct(stageProtection.target)
        texture = max(texture, readStageMask(stageProtection.target, ...
            'repairFine', imageSize));
        structure = max(structure, readStageMask(stageProtection.target, ...
            'repairMid', imageSize));
    end
    regionNames = {'regionBandFine', 'regionBandMid', 'regionBandBase', ...
        'regionBandTone', 'regionBandWhitening'};
    for index = 1:numel(regionNames)
        regionBand = max(regionBand, readStageMask(stageProtection, ...
            regionNames{index}, imageSize));
    end
end

if isfield(beautyMasks, 'protectionMask')
    legacyProtection = readOptionalMask(beautyMasks, ...
        'protectionMask', imageSize);
    texture = max(texture, legacyProtection);
    structure = max(structure, legacyProtection);
end

% 阈值只把已有软保护转换为 dense field 的排除条件，不修改原始
% protection 数值。纹理保护覆盖眉毛、眼睑/睫毛、唇部和鼻部软带；
% 结构保护覆盖鼻翼沟、耳轮及其他结构边缘；regionBand 覆盖 V4
% policy 的语义带。skinMask 本身排除头发、衣服和背景。
ordinarySkin = skinMask > .05 & hard < .50 & ...
    texture < .20 & structure < .15 & regionBand <= eps;
end

function value = readStageMask(context, name, imageSize)
if isfield(context, name)
    value = readStandaloneMask(context.(name), imageSize, name);
else
    value = zeros(imageSize);
end
end

function value = readStandaloneMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidBlemishInput', ...
        '字段 %s 的尺寸或取值无效。', name);
end
value = double(value);
end

function [evidence, thresholds] = residualEvidence( ...
        magnitude, support, centerFraction, highFraction, ...
        spreadMultiplier, upperMultiplier, floorValue)
values = magnitude(support);
center = percentileValue(values, centerFraction);
upper = percentileValue(values, highFraction);
spread = max(upper - center, floorValue);
low = center + spreadMultiplier * spread;
high = center + upperMultiplier * spread;
if high <= low
    high = low + floorValue;
end
evidence = smoothStep(magnitude, low, high) .* double(support);
thresholds = struct('center', center, 'upper', upper, ...
    'spread', spread, 'low', low, 'high', high);
end

function value = percentileValue(values, fraction)
values = sort(double(values(:)));
if isempty(values)
    value = 0;
    return;
end
position = 1 + (numel(values) - 1) * fraction;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    weight = position - lower;
    value = (1 - weight) * values(lower) + weight * values(upper);
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function faceScale = readFaceScale(frequency, beautyMasks)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
elseif isfield(frequency, 'faceBox')
    faceScale = min(double(frequency.faceBox(3:4)));
elseif isfield(beautyMasks, 'faceBox')
    faceScale = min(double(beautyMasks.faceBox(3:4)));
else
    faceScale = min(size(frequency.sourceLuminance));
end
end

function validateInput(inputImage, frequency, beautyMasks)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('beauty:InvalidBlemishInput', ...
        '瑕疵检测输入图像必须是 uint8 三通道 RGB 图像。');
end
if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'sourceLuminance', 'fine', 'mid'}))
    error('beauty:InvalidBlemishInput', ...
        '瑕疵检测需要完整的亮度、Fine 和 Mid 频率结构。');
end
imageSize = size(inputImage, 1:2);
for name = {'sourceLuminance', 'fine', 'mid'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ...
            ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:)))
        error('beauty:InvalidBlemishInput', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidBlemishInput', ...
        '瑕疵检测需要标量 v3 Beauty Masks。');
end
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('beauty:InvalidBlemishInput', ...
        'Beauty Masks 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidBlemishInput', ...
        'Beauty Masks 字段 %s 无效。', name);
end
value = double(value);
end

function value = readOptionalMask(context, name, imageSize)
if ~isfield(context, name)
    value = zeros(imageSize);
    return;
end
value = readMask(context, name, imageSize);
end

function diagnostics = emptyDiagnostics(imageSize, skinCandidate, ...
        denseBlemishField)
empty = zeros(imageSize);
diagnostics = struct( ...
    'blemishMap', empty, ...
    'confidence', empty, ...
    'denseBlemishField', denseBlemishField, ...
    'fineEvidence', empty, ...
    'midEvidence', empty, ...
    'chromaEvidence', empty, ...
    'fineMagnitude', empty, ...
    'midMagnitude', empty, ...
    'chromaMagnitude', empty, ...
    'localCb', empty, ...
    'localCr', empty, ...
    'skinCandidate', skinCandidate, ...
    'faceCandidate', empty, ...
    'nonFaceCandidate', empty, ...
    'structureProtectionMask', empty, ...
    'chromaProtectionMask', empty, ...
    'toneProtectionMask', empty, ...
    'hardProtectionMask', empty, ...
    'faceScale', 0, ...
    'imageSize', [imageSize, 3], ...
    'fineThresholds', emptyThresholds(), ...
    'midThresholds', emptyThresholds(), ...
    'chromaThresholds', emptyThresholds());
end

function thresholds = emptyThresholds
thresholds = struct('center', 0, 'upper', 0, 'spread', 0, ...
    'low', 0, 'high', 0);
end
