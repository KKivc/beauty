function [beautifiedImage, diagnostics] = composeBeautyResult( ...
        inputImage, frequency, smoothedFrequency, beautyMasks, ...
        whiteningStrength, processing)
%COMPOSEBEAUTYRESULT 使用一个连续 Alpha Map 合成 v3 结果。
%   保护区域不通过脸部/脸外结果拼接，而是在同一张全图 Alpha 上
%   完成一次主合成。可选的 processing 参数承载瑕疵、统一肤色和
%   美白模块的诊断/结果；省略时仍由本函数调用独立美白模块。

if nargin < 4 || ~isValidRgbImage(inputImage) || ...
        ~isstruct(frequency) || ~isstruct(smoothedFrequency) || ...
        ~isstruct(beautyMasks)
    error('beauty:InvalidComposeInput', ...
        '合成需要输入图像、频率结构和 v3 Beauty Masks。');
end
if nargin < 5 || isempty(whiteningStrength)
    whiteningStrength = 0;
end
if ~isValidStrength(whiteningStrength)
    error('beauty:InvalidStrength', '美白强度必须是 0 到 100 的数值标量。');
end
if nargin < 6 || isempty(processing)
    processing = struct();
elseif ~isstruct(processing) || ~isscalar(processing)
    error('beauty:InvalidComposeInput', '处理结果必须是标量结构体。');
end
imageSize = size(inputImage, 1:2);
if ~isfield(frequency, 'sourceLuminance') || ...
        ~isequal(size(frequency.sourceLuminance), imageSize) || ...
        ~isfield(smoothedFrequency, 'outputLuminance') || ...
        ~isequal(size(smoothedFrequency.outputLuminance), imageSize) || ...
        ~isfield(smoothedFrequency, 'alphaMap') || ...
        ~isequal(size(smoothedFrequency.alphaMap), imageSize)
    error('beauty:InvalidComposeInput', '频率结构的尺寸不匹配。');
end
requiredMasks = {'strengthMap', 'hardProtectionMask'};
if ~all(isfield(beautyMasks, requiredMasks))
    error('beauty:InvalidMasks', 'v3 Beauty Masks 缺少合成字段。');
end
readMask(beautyMasks.strengthMap, imageSize, 'strengthMap');
hardProtection = readMask(beautyMasks.hardProtectionMask, ...
    imageSize, 'hardProtectionMask');
smoothingAlpha = readMask(smoothedFrequency.alphaMap, ...
    imageSize, 'alphaMap');
sourceLuminance = double(frequency.sourceLuminance);
smoothingDelta = double(smoothedFrequency.outputLuminance) - ...
    sourceLuminance;

if isfield(processing, 'whitening')
    whiteningResult = processing.whitening;
    validateWhiteningResult(whiteningResult, imageSize);
else
    [whiteningResult, ~] = beauty.applySkinWhitening(inputImage, ...
        frequency, beautyMasks, whiteningStrength);
end
whiteningSupport = readMask(whiteningResult.supportMap, imageSize, ...
    'whiteningSupport');
whiteningDelta = readMask(whiteningResult.delta, imageSize, ...
    'whiteningDelta');

toneSupport = zeros(imageSize);
toneDeltaCb = zeros(imageSize);
toneDeltaCr = zeros(imageSize);
if isfield(processing, 'skinTone')
    toneResult = processing.skinTone;
    validateToneResult(toneResult, imageSize);
    toneSupport = readMask(toneResult.toneSupport, imageSize, ...
        'toneSupport');
    sourceYcbcr = rgb2ycbcr(im2double(inputImage));
    toneDeltaCb = double(toneResult.outputCb) - sourceYcbcr(:, :, 2);
    toneDeltaCr = double(toneResult.outputCr) - sourceYcbcr(:, :, 3);
end

% smoothingDelta 和 whiteningDelta 都是相对于原图的增量，先合成增量，
% 再只用一张 Alpha Map 将目标值与原图组合。
alphaMap = min(1, max(cat(3, smoothingAlpha, whiteningSupport, ...
    toneSupport), [], 3));
delta = smoothingDelta + whiteningDelta;
targetLuminance = sourceLuminance;
active = alphaMap > eps;
targetLuminance(active) = sourceLuminance(active) + ...
    delta(active) ./ alphaMap(active);
targetLuminance = min(max(targetLuminance, 0), 1);
outputLuminance = sourceLuminance + ...
    alphaMap .* (targetLuminance - sourceLuminance);

ycbcr = rgb2ycbcr(im2double(inputImage));
ycbcr(:, :, 1) = min(max(outputLuminance, 0), 1);
sourceCb = ycbcr(:, :, 2);
sourceCr = ycbcr(:, :, 3);
toneTargetCb = sourceCb;
toneTargetCr = sourceCr;
activeTone = alphaMap > eps;
toneTargetCb(activeTone) = sourceCb(activeTone) + ...
    toneDeltaCb(activeTone) ./ alphaMap(activeTone);
toneTargetCr(activeTone) = sourceCr(activeTone) + ...
    toneDeltaCr(activeTone) ./ alphaMap(activeTone);
toneTargetCb = min(max(toneTargetCb, 0), 1);
toneTargetCr = min(max(toneTargetCr, 0), 1);
ycbcr(:, :, 2) = sourceCb + alphaMap .* (toneTargetCb - sourceCb);
ycbcr(:, :, 3) = sourceCr + alphaMap .* (toneTargetCr - sourceCr);
outputDouble = min(max(ycbcr2rgb(ycbcr), 0), 1);
beautifiedImage = uint8(round(outputDouble * 255));
inactive = alphaMap <= eps;
for channel = 1:size(inputImage, 3)
    outputChannel = beautifiedImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(inactive) = sourceChannel(inactive);
    outputChannel(hardProtection >= .999) = sourceChannel( ...
        hardProtection >= .999);
    beautifiedImage(:, :, channel) = outputChannel;
end
if ~isequal(size(beautifiedImage), size(inputImage))
    error('beauty:InvalidOutput', 'v3 合成结果没有保持输入图像尺寸。');
end

diagnostics = struct( ...
    'alphaMap', alphaMap, ...
    'smoothingAlpha', smoothingAlpha, ...
    'whiteningSupport', whiteningSupport, ...
    'toneSupport', toneSupport, ...
    'smoothingDelta', smoothingDelta, ...
    'whiteningDelta', whiteningDelta, ...
    'toneDeltaCb', toneDeltaCb, ...
    'toneDeltaCr', toneDeltaCr, ...
    'toneTargetCb', toneTargetCb, ...
    'toneTargetCr', toneTargetCr, ...
    'targetLuminance', targetLuminance, ...
    'outputLuminance', outputLuminance, ...
    'hardProtectionMask', hardProtection, ...
    'backgroundUnchanged', maxChange(inputImage, beautifiedImage, ...
    alphaMap <= eps), ...
    'hardProtectionUnchanged', maxChange(inputImage, beautifiedImage, ...
    hardProtection >= .999));
end

function valid = isValidRgbImage(image)
valid = isa(image, 'uint8') && isreal(image) && ndims(image) == 3 && ...
    size(image, 3) == 3;
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function value = readMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidMasks', 'Mask %s 无效。', name);
end
value = double(value);
end

function value = maxChange(inputImage, outputImage, mask)
if ~any(mask(:))
    value = 0;
    return;
end
difference = max(abs(double(outputImage) - double(inputImage)), [], 3);
value = max(difference(mask));
end

function validateWhiteningResult(result, imageSize)
if ~isstruct(result) || ~isscalar(result) || ...
        ~all(isfield(result, {'supportMap', 'delta'}))
    error('beauty:InvalidComposeInput', ...
        '美白结果缺少 supportMap 或 delta。');
end
readMask(result.supportMap, imageSize, 'whiteningSupport');
readMask(result.delta, imageSize, 'whiteningDelta');
end

function validateToneResult(result, imageSize)
if ~isstruct(result) || ~isscalar(result) || ...
        ~all(isfield(result, {'toneSupport', 'outputCb', 'outputCr'}))
    error('beauty:InvalidComposeInput', ...
        '肤色结果缺少 toneSupport 或输出色度。');
end
readMask(result.toneSupport, imageSize, 'toneSupport');
readMask(result.outputCb, imageSize, 'outputCb');
readMask(result.outputCr, imageSize, 'outputCr');
end
