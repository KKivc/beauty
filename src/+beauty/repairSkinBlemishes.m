function [repairedFrequency, diagnostics] = repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, smoothingStrength)
%REPAIRSKINBLEMISHES 对瑕疵位置执行受控的 Fine/Mid 局部修复。
%   普通皮肤仍由 smoothSkinTexture 处理；本函数只读取固定的瑕疵图，
%   低置信度只衰减 Fine，中高置信度才少量收敛 Mid。Base 始终不变，
%   且所有修复权重都由 structureProtectionMask 连续限制。

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
structureProtection = readMask(beautyMasks, ...
    'structureProtectionMask', imageSize);
hardProtection = readOptionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);

profile = beautySmoothingProfile(smoothingStrength);
allowed = min(skinMask, strengthMap) .* (1 - hardProtection);
nonFaceStrength = readOptionalMask(beautyMasks, ...
    'nonFaceStrengthMap', imageSize);
nonFacePixels = nonFaceStrength > .01;
if any(nonFacePixels(:))
    allowed(nonFacePixels) = profile.outsideFaceStrength .* ...
        min(skinMask(nonFacePixels), nonFaceStrength(nonFacePixels)) .* ...
        (1 - hardProtection(nonFacePixels));
end
normalRepairCurve = min(profile.blemishStrength / (.75 ^ .85), 1);
highEndRepairCurve = max(profile.blemishStrength - .75 ^ .85, 0);
% 高置信瑕疵可适度放宽一般结构门控；只有强结构边缘保留固定下限，
% 避免眼唇边界被瑕疵修复覆盖，同时不阻断普通雀斑修复。
structureGate = 1 - structureProtection .* (1 - .90 * blemishMap);
hardFeatureBand = bwdist(hardProtection >= .999) <= 3;
strongStructure = smoothStep(structureProtection, .70, .90) .* ...
    double(hardFeatureBand);
structureGate = min(structureGate, 1 - .65 * strongStructure);

% 低置信度瑕疵保留在 Fine 层；Mid 仅在连续置信度达到中高档后
% 开启，避免普通皮肤被大面积拉向一个颜色。
faceScale = readFaceScale(frequency);
noseMask = readOptionalMask(beautyMasks, 'noseMask', imageSize);
blemishDensity = imgaussfilt(double(blemishMap > .60), ...
    max(3, min(12, .04 * faceScale)), 'Padding', 'replicate');
globalHighDensity = mean(blemishMap(:) > .60);
globalBlemishMean = mean(blemishMap(:));
sparseGate = 1 - smoothStep(globalHighDensity, .05, .15) .* ...
    smoothStep(blemishDensity, .03, .20);
globalGate = smoothStep(globalBlemishMean, .005, .015);
% 鼻部只能使用与普通皮肤相同的全局和局部瑕疵证据，不能因语义位置
% 绕过全局 Gate。鼻部语义只用于 Mid 的连续保守系数，不参与 Fine 证据。
repairEvidence = min(max(blemishMap .* sparseGate .* globalGate, 0), 1);
mediumConfidence = smoothStep(repairEvidence, .60, .90);
highConfidence = smoothStep(repairEvidence, .62, .90);
if highEndRepairCurve > 0
    blobMask = smallBlemishBlobs(blemishMap > .65, faceScale);
else
    blobMask = false(imageSize);
end
% 高档额外修复必须同时满足高置信局部异常、紧凑 Blob 和全局证据；
% nose 不得替代任一 Gate。鼻部 Mid 只保留初始 0.5 系数，并按语义
% 概率连续退让，避免鼻梁和鼻翼的中频明暗结构被整片收敛。
highEndConfidence = highConfidence .* double(blobMask) .* globalGate;
noseMidGate = 1 - .50 * noseMask;
repairCurveMap = normalRepairCurve * ones(imageSize);
repairCurveMap = min(max(repairCurveMap, 0), 1);
fineWeight = repairCurveMap .* (repairEvidence + .25 * highConfidence) .* ...
    allowed .* structureGate + (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = repairCurveMap .* (.95 * mediumConfidence + ...
    .40 * highConfidence) .* allowed .* structureGate + ...
    (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = min(max(mediumWeight, 0), 1);
mediumWeight = mediumWeight .* noseMidGate;
chromaWeight = .16 * repairCurveMap .* highConfidence .* allowed .* ...
    structureGate;
fineWeight = min(max(fineWeight, 0), 1);
chromaWeight = min(max(chromaWeight, 0), 1);

radius = min(20, max(3, round(.070 * faceScale)));
kernelSize = 2 * radius + 1;
kernel = ones(kernelSize, kernelSize);

% 参考只使用非瑕疵皮肤，并降低跨越结构边缘的贡献；这样鼻梁和
% 手指的低频坡面不会被邻域平均抹平。
referenceReliability = allowed .* (1 - .86 * blemishMap) .* ...
    structureGate;
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
    'noseMask', noseMask, ...
    'noseMidGate', noseMidGate, ...
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
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap', 'structureProtectionMask'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidBlemishRepair', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    validateMask(beautyMasks.(required{index}), imageSize, required{index});
end
if isfield(beautyMasks, 'hardProtectionMask')
    validateMask(beautyMasks.hardProtectionMask, imageSize, ...
        'hardProtectionMask');
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
