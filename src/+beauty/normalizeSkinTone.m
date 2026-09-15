function [toneResult, diagnostics] = normalizeSkinTone(inputImage, varargin)
%NORMALIZESKINTONE 用一套全皮肤候选结果修正低频色度异常。
%   主调用形式为
%       normalizeSkinTone(inputImage, beautyMasks, blemishMap, strength)
%   也接受带频率结构的形式
%       normalizeSkinTone(inputImage, frequency, beautyMasks, ...)
%   频率结构只用于校验尺寸；脸部和脸外始终共享同一个候选色度，
%   区域差异仅来自 masks.buildBeautyStrengthMap 的连续强度图。

[frequency, beautyMasks, blemishMap, smoothingStrength] = ...
    parseInputs(inputImage, varargin{:});
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
toneProtection = readOptionalMask(beautyMasks, ...
    'toneProtectionMask', imageSize);
hardProtection = readOptionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);

baseCandidate = skinMask > .05 & strengthMap > .01 & ...
    hardProtection < .999 & toneProtection < .70;
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
blemishEvidence = smoothStep(blemishMap, .32, .72);

% 统一候选只做小幅连续校正。正常皮肤的基础权重很低，明显色度
% 异常或瑕疵残余才逐步增加；不对亮度通道做任何补偿。
ratio = double(smoothingStrength) / 100;
toneCurve = ratio ^ .85;
structureGate = 1 - structureProtection;
featureGate = 1 - .78 * toneProtection;
allowed = min(skinMask, strengthMap) .* (1 - hardProtection);
weightMap = toneCurve .* allowed .* structureGate .* featureGate .* ...
    (.08 + .35 * chromaEvidence + .20 * blemishEvidence);
weightMap = min(max(weightMap, 0), .55);
if ~hasCandidate
    weightMap = zeros(imageSize);
end

deltaCb = weightMap .* (candidateCb - localCb);
deltaCr = weightMap .* (candidateCr - localCr);
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
    'chromaEvidence', chromaEvidence, ...
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
    'blemishEvidence', blemishEvidence, ...
    'weightMap', weightMap, ...
    'alphaMap', weightMap, ...
    'toneSupport', weightMap, ...
    'deltaCb', deltaCb, ...
    'deltaCr', deltaCr, ...
    'faceWeight', weightMap .* double(faceMask > .01), ...
    'nonFaceWeight', weightMap .* double(nonFaceMask > .01), ...
    'structureProtectionMask', structureProtection, ...
    'toneProtectionMask', toneProtection, ...
    'hardProtectionMask', hardProtection, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
end

function [frequency, beautyMasks, blemishMap, smoothingStrength] = ...
        parseInputs(inputImage, varargin)
frequency = [];
count = numel(varargin);
if count == 4 && isFrequency(varargin{1})
    frequency = varargin{1};
    beautyMasks = varargin{2};
    if isnumeric(varargin{3}) && isscalar(varargin{3}) && ...
            ~isscalar(varargin{4})
        smoothingStrength = varargin{3};
        blemishMap = varargin{4};
    else
        blemishMap = varargin{3};
        smoothingStrength = varargin{4};
    end
elseif count == 3 && isFrequency(varargin{1})
    frequency = varargin{1};
    beautyMasks = varargin{2};
    blemishMap = zeros(size(inputImage, 1:2));
    smoothingStrength = varargin{3};
elseif count == 3
    beautyMasks = varargin{1};
    if isnumeric(varargin{2}) && isscalar(varargin{2}) && ...
            ~isscalar(varargin{3})
        smoothingStrength = varargin{2};
        blemishMap = varargin{3};
    else
        blemishMap = varargin{2};
        smoothingStrength = varargin{3};
    end
elseif count == 2 && isFrequency(varargin{1})
    frequency = varargin{1};
    beautyMasks = varargin{2};
    blemishMap = zeros(size(inputImage, 1:2));
    smoothingStrength = 100;
elseif count == 2 && isnumeric(varargin{2})
    beautyMasks = varargin{1};
    blemishMap = zeros(size(inputImage, 1:2));
    smoothingStrength = varargin{2};
else
    error('beauty:InvalidSkinToneInput', ...
        ['肤色统一需要 (inputImage, Beauty Masks, blemishMap, strength)，', ...
        '或带 frequency 的等价形式。']);
end
end

function valid = isFrequency(value)
valid = isstruct(value) && isscalar(value) && ...
    all(isfield(value, {'base', 'mid', 'fine', 'imageSize'}));
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
