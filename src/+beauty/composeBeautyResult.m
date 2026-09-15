function [beautifiedImage, diagnostics] = composeBeautyResult( ...
        inputImage, frequency, smoothedFrequency, beautyMasks, whiteningStrength)
%COMPOSEBEAUTYRESULT 使用一个连续 Alpha Map 合成 v3 结果。
%   保护区域不通过脸部/脸外结果拼接，而是在同一张全图 Alpha 上
%   完成一次主合成。

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
strengthMap = readMask(beautyMasks.strengthMap, imageSize, 'strengthMap');
hardProtection = readMask(beautyMasks.hardProtectionMask, ...
    imageSize, 'hardProtectionMask');
smoothingAlpha = readMask(smoothedFrequency.alphaMap, ...
    imageSize, 'alphaMap');
sourceLuminance = double(frequency.sourceLuminance);
smoothingDelta = double(smoothedFrequency.outputLuminance) - ...
    sourceLuminance;

whiteningSupport = zeros(imageSize);
whiteningDelta = zeros(imageSize);
if whiteningStrength > 0
    ratio = double(whiteningStrength) / 100;
    skinPixels = strengthMap > .35 & hardProtection < .999;
    if any(skinPixels(:))
        medianLuminance = median(sourceLuminance(skinPixels));
    else
        medianLuminance = .78;
    end
    whiteningNeed = min(max((.78 - medianLuminance) / .35, .25), 1);
    upperLuminance = percentileValue(sourceLuminance(skinPixels), .85);
    highlightHeadroom = min(max((.97 - upperLuminance) / .20, 0), 1);
    toneStrength = .27 * (1 - exp(-6 * ratio)) / ...
        (1 - exp(-6)) + .16 * ratio;
    whiteningSupport = ratio .* strengthMap .* ...
        (1 - hardProtection);
    % 以分区常量作为提亮量，避免源亮度逐像素参与映射而压缩鼻梁、
    % 手指等低频结构；高光余量仍由当前皮肤分区整体限制。
    whiteningDelta = .23 * toneStrength .* whiteningNeed .* ...
        highlightHeadroom .* whiteningSupport;
end

% smoothingDelta 和 whiteningDelta 都是相对于原图的增量，先合成增量，
% 再只用一张 Alpha Map 将目标值与原图组合。
alphaMap = min(1, max(smoothingAlpha, whiteningSupport));
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
    'smoothingDelta', smoothingDelta, ...
    'whiteningDelta', whiteningDelta, ...
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

function value = percentileValue(values, fraction)
values = sort(values(:));
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
