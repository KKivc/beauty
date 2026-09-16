function [toneResult, diagnostics] = normalizeSkinTone( ...
        inputImage, frequency, beautyMasks, blemishMap, smoothingStrength)
%NORMALIZESKINTONE 用一套全皮肤候选结果修正低频色度异常。
%   频率结构只用于校验尺寸；脸部和脸外始终共享同一个候选色度，
%   区域差异仅来自 masks.buildBeautyStrengthMap 的连续强度图。

if nargin < 5
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一需要输入图像、频率、Beauty Masks、瑕疵图和磨皮强度。');
end
validateImage(inputImage);
imageSize = size(inputImage, 1:2);
if ~isempty(frequency)
    validateFrequency(frequency, imageSize);
end
validateMasks(beautyMasks, imageSize);
blemishMap = readBlemishMap(blemishMap, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

ycbcr = rgb2ycbcr(im2double(inputImage));
luminance = ycbcr(:, :, 1);
cb = ycbcr(:, :, 2);
cr = ycbcr(:, :, 3);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
structureProtection = readMask(beautyMasks, ...
    'structureProtectionMask', imageSize);
[chromaProtection, hasChromaProtection] = resolveChromaProtectionMask( ...
    beautyMasks, imageSize, 'beauty:InvalidSkinToneInput', ...
    'beauty:ChromaProtectionConflict');
if ~hasChromaProtection
    chromaProtection = zeros(imageSize);
end
hardProtection = readOptionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);

baseCandidate = skinMask > .05 & strengthMap > .01 & ...
    hardProtection < .999 & chromaProtection < .70;
candidate = selectToneCandidate(luminance, baseCandidate);
if ~any(candidate(:))
    candidate = skinMask > .05 & strengthMap > .01 & ...
        hardProtection < .999;
end
faceScale = readFaceScale(beautyMasks, frequency, imageSize);
chromaSigma = min(12, max(2.5, .025 * faceScale));
localCb = imgaussfilt(cb, chromaSigma, 'Padding', 'replicate');
localCr = imgaussfilt(cr, chromaSigma, 'Padding', 'replicate');
if any(candidate(:))
    candidateCb = median(localCb(candidate));
    candidateCr = median(localCr(candidate));
    hasCandidate = true;
else
    candidateCb = .5;
    candidateCr = .5;
    hasCandidate = false;
end

chromaResidual = max(abs(localCb - candidateCb), ...
    abs(localCr - candidateCr));
chromaEvidence = smoothStep(chromaResidual, .018, .060);
localChromaResidual = max(abs(cb - localCb), abs(cr - localCr));
localChromaEvidence = smoothStep(localChromaResidual, .010, .045);
blemishEvidence = smoothStep(blemishMap, .32, .72);

% 统一候选只做小幅连续校正。局部色度异常优先向邻域色度收敛，
% 正常皮肤的基础权重很低；不对亮度通道做任何补偿。
profile = beautySmoothingProfile(smoothingStrength);
ratio = double(smoothingStrength) / 100;
toneCurve = profile.toneStrength;
fullToneCurve = ratio ^ .85;
toneCurveMap = toneCurve + (fullToneCurve - toneCurve) .* ...
    smoothStep(chromaEvidence, .25, .65);
toneCurveMap = max(toneCurveMap, ...
    fullToneCurve .* localChromaEvidence);
structureGate = 1 - structureProtection;
featureGate = 1 - .78 * chromaProtection;
allowed = min(skinMask, strengthMap) .* (1 - hardProtection);
if ratio > .50
    uniformToneCurve = .36 * fullToneCurve .* ...
        smoothStep(ratio, .50, .75);
    uniformToneSupport = allowed .* structureGate .* ...
        (1 - chromaProtection);
else
    uniformToneCurve = 0;
    uniformToneSupport = zeros(imageSize);
end
weightMap = toneCurveMap .* allowed .* structureGate .* featureGate .* ...
    (.08 + .35 * chromaEvidence + .35 * localChromaEvidence + ...
    .20 * blemishEvidence);
weightMap = weightMap + uniformToneCurve .* uniformToneSupport;
weightMap = min(max(weightMap, 0), .55);
if ~hasCandidate
    weightMap = zeros(imageSize);
end

candidateDeltaCb = candidateCb - localCb;
candidateDeltaCr = candidateCr - localCr;
localDeltaCb = localCb - cb;
localDeltaCr = localCr - cr;
if uniformToneCurve > eps
    localBlend = max(localChromaEvidence, double( ...
        uniformToneSupport > eps));
else
    localBlend = localChromaEvidence;
end
deltaCb = weightMap .* ((1 - localBlend) .* candidateDeltaCb + ...
    localBlend .* localDeltaCb);
deltaCr = weightMap .* ((1 - localBlend) .* candidateDeltaCr + ...
    localBlend .* localDeltaCr);
outputCb = min(max(cb + deltaCb, 0), 1);
outputCr = min(max(cr + deltaCr, 0), 1);

toneResult = struct( ...
    'candidateChroma', struct('cb', candidateCb, 'cr', candidateCr), ...
    'candidateCb', candidateCb, ...
    'candidateCr', candidateCr, ...
    'localCb', localCb, ...
    'localCr', localCr, ...
    'outputCb', outputCb, ...
    'outputCr', outputCr, ...
    'outputLuminance', luminance, ...
    'deltaCb', deltaCb, ...
    'deltaCr', deltaCr, ...
    'weightMap', weightMap, ...
    'alphaMap', weightMap, ...
    'toneSupport', weightMap, ...
    'uniformToneCurve', uniformToneCurve, ...
    'localBlend', localBlend, ...
    'chromaEvidence', chromaEvidence, ...
    'localChromaResidual', localChromaResidual, ...
    'localChromaEvidence', localChromaEvidence, ...
    'blemishEvidence', blemishEvidence, ...
    'candidateMask', double(candidate), ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
toneResult.outputImage = renderToneImage(inputImage, toneResult);

faceMask = min(skinMask, readOptionalMask(beautyMasks, ...
    'faceSkinMask', imageSize));
nonFaceMask = min(skinMask, readOptionalMask(beautyMasks, ...
    'nonFaceSkinMask', imageSize));
diagnostics = struct( ...
    'candidateMask', double(candidate), ...
    'candidateChroma', toneResult.candidateChroma, ...
    'candidateCb', candidateCb, ...
    'candidateCr', candidateCr, ...
    'localCb', localCb, ...
    'localCr', localCr, ...
    'chromaResidual', chromaResidual, ...
    'chromaEvidence', chromaEvidence, ...
    'localChromaResidual', localChromaResidual, ...
    'localChromaEvidence', localChromaEvidence, ...
    'blemishEvidence', blemishEvidence, ...
    'weightMap', weightMap, ...
    'alphaMap', weightMap, ...
    'toneSupport', weightMap, ...
    'uniformToneCurve', uniformToneCurve, ...
    'localBlend', localBlend, ...
    'deltaCb', deltaCb, ...
    'deltaCr', deltaCr, ...
    'faceWeight', weightMap .* double(faceMask > .01), ...
    'nonFaceWeight', weightMap .* double(nonFaceMask > .01), ...
    'structureProtectionMask', structureProtection, ...
    'chromaProtectionMask', chromaProtection, ...
    'toneProtectionMask', chromaProtection, ...
    'hardProtectionMask', hardProtection, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
end

function candidate = selectToneCandidate(luminance, baseCandidate)
candidate = baseCandidate;
values = luminance(baseCandidate);
if isempty(values)
    return;
end
low = percentileValue(values, .10);
high = percentileValue(values, .90);
candidate = baseCandidate & luminance >= low & luminance <= high;
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFrequency(frequency, imageSize)
for name = {'base', 'mid', 'fine'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:)))
        error('beauty:InvalidSkinToneInput', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
end

function validateMasks(beautyMasks, imageSize)
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap', 'structureProtectionMask'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidSkinToneInput', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    readMask(beautyMasks, required{index}, imageSize);
end
[~, ~] = resolveChromaProtectionMask(beautyMasks, imageSize, ...
    'beauty:InvalidSkinToneInput', 'beauty:ChromaProtectionConflict');
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('beauty:InvalidSkinToneInput', ...
        'Beauty Masks 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidSkinToneInput', ...
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

function value = readBlemishMap(value, imageSize)
if isempty(value)
    value = zeros(imageSize);
elseif isstruct(value)
    if isfield(value, 'blemishMap')
        value = value.blemishMap;
    elseif isfield(value, 'confidence')
        value = value.confidence;
    else
        error('beauty:InvalidSkinToneInput', ...
            '瑕疵诊断结构缺少 blemishMap 或 confidence。');
    end
end
value = readStandaloneMask(value, imageSize, 'blemishMap');
end

function value = readStandaloneMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidSkinToneInput', '字段 %s 无效。', name);
end
value = double(value);
end

function faceScale = readFaceScale(beautyMasks, frequency, imageSize)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
elseif isfield(beautyMasks, 'faceBox')
    faceScale = min(double(beautyMasks.faceBox(3:4)));
else
    faceScale = min(imageSize);
end
end

function outputImage = renderToneImage(inputImage, toneResult)
ycbcr = rgb2ycbcr(im2double(inputImage));
ycbcr(:, :, 2) = toneResult.outputCb;
ycbcr(:, :, 3) = toneResult.outputCr;
outputImage = uint8(round(min(max(ycbcr2rgb(ycbcr), 0), 1) * 255));
inactive = toneResult.weightMap <= eps;
for channel = 1:size(inputImage, 3)
    outputChannel = outputImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(inactive) = sourceChannel(inactive);
    outputImage(:, :, channel) = outputChannel;
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
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

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
