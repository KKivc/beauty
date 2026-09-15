function metrics = measureBeautyRegression(inputImage, outputImage, ...
        beautyContext, faceBox)
%MEASUREBEAUTYREGRESSION 使用固定口径测量美颜回归指标。
%   鼻部与脸外皮肤结构共用 YCbCr、按人脸尺度计算的低通尺度、
%   语义 ROI 和分位数统计公式，避免测试各自实现近似指标。

if ~isValidRgbImage(inputImage) || ~isValidRgbImage(outputImage)
    error('measureBeautyRegression:InvalidImage', ...
        '输入图像和结果图像必须是 uint8 三通道 RGB 图像。');
end
if ~isequal(size(inputImage), size(outputImage))
    error('measureBeautyRegression:InvalidOutput', ...
        '输入图像和结果图像的尺寸必须一致。');
end
beautyContext = normalizeBeautyContext(inputImage, faceBox, beautyContext);

config = metricConfig(faceBox);
inputY = rgb2ycbcr(im2double(inputImage));
outputY = rgb2ycbcr(im2double(outputImage));
inputY = inputY(:, :, 1);
outputY = outputY(:, :, 1);
inputLow = imgaussfilt(inputY, config.lowPassSigma, 'Padding', 'replicate');
outputLow = imgaussfilt(outputY, config.lowPassSigma, 'Padding', 'replicate');
inputDetail = inputY - inputLow;
outputDetail = outputY - outputLow;

skinMask = beautyContext.skinMask >= config.skinThreshold;
processableSkin = skinMask & ...
    beautyContext.featureProtectionMask < config.protectionThreshold;
if ~any(processableSkin(:))
    processableSkin = skinMask;
end
noseProbability = beautyContext.regions.nose;
noseRoi = skinMask & noseProbability >= config.semanticThreshold;
outsideRoi = beautyContext.nonFaceSkinMask >= config.skinThreshold;
if ~any(noseRoi(:))
    noseRoi = fallbackNoseRoi(faceBox, size(inputImage));
end
if ~any(outsideRoi(:))
    outsideRoi = fallbackOutsideRoi(faceBox, size(inputImage));
end

metrics = struct();
metrics.textureEnergy = mean(abs(outputDetail(processableSkin)));
metrics.blemishEnergy = mean(max(abs(outputDetail(processableSkin)) - ...
    config.blemishFloor, 0));
metrics.meanLuminance = mean(outputY(skinMask));
metrics.noseStructure = structureStatistic(outputLow, noseRoi, config);
metrics.outsideStructure = structureStatistic(outputLow, outsideRoi, config);
metrics.noseStructureInput = structureStatistic(inputLow, noseRoi, config);
metrics.outsideStructureInput = structureStatistic(inputLow, outsideRoi, config);
metrics.backgroundMaxChange = maxChange(inputImage, outputImage, ~skinMask);
metrics.hardProtectionMaxChange = maxChange(inputImage, outputImage, ...
    beautyContext.hardProtectionMask >= .999);
metrics.outputSize = size(outputImage);
metrics.outputClass = class(outputImage);
metrics.sameSize = isequal(size(inputImage), size(outputImage));
metrics.sameChannels = ndims(outputImage) == 3 && size(outputImage, 3) == 3;
metrics.config = config;
end

function config = metricConfig(faceBox)
faceScale = min(faceBox(3:4));
config = struct( ...
    'colorSpace', 'YCbCr', ...
    'luminanceChannel', 1, ...
    'skinThreshold', .35, ...
    'semanticThreshold', .35, ...
    'protectionThreshold', .35, ...
    'lowPassSigma', min(8, max(1.25, .018 * faceScale)), ...
    'structurePercentile', .90, ...
    'blemishFloor', .008);
end

function value = structureStatistic(luminance, roi, config)
[gradientX, gradientY] = gradient(luminance);
gradientMagnitude = hypot(gradientX, gradientY);
values = gradientMagnitude(roi);
if isempty(values)
    value = 0;
    return;
end
value = percentileValue(values, config.structurePercentile);
end

function value = maxChange(inputImage, outputImage, mask)
if ~any(mask(:))
    value = 0;
    return;
end
difference = abs(double(outputImage) - double(inputImage));
difference = max(difference, [], 3);
value = max(difference(mask));
end

function roi = fallbackNoseRoi(faceBox, imageSize)
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
centerX = faceBox(1) + .50 * faceBox(3);
centerY = faceBox(2) + .53 * faceBox(4);
roi = ((xGrid - centerX) / max(1, .16 * faceBox(3))) .^ 2 + ...
    ((yGrid - centerY) / max(1, .30 * faceBox(4))) .^ 2 <= 1;
end

function roi = fallbackOutsideRoi(faceBox, imageSize)
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
faceRegion = xGrid >= faceBox(1) & ...
    xGrid <= faceBox(1) + faceBox(3) - 1 & ...
    yGrid >= faceBox(2) & ...
    yGrid <= faceBox(2) + faceBox(4) - 1;
roi = ~faceRegion & yGrid >= faceBox(2) + .55 * faceBox(4);
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

function valid = isValidRgbImage(image)
valid = isa(image, 'uint8') && isreal(image) && ndims(image) == 3 && ...
    size(image, 3) == 3;
end

