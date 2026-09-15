function params = recommendBeautyParams(inputImage, faceBox, beautyContext)
%RECOMMENDBEAUTYPARAMS 根据有效皮肤区域的局部瑕疵推荐强度。

if nargin < 1 || ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('recommendBeautyParams:InvalidImage', ...
        'inputImage must be a uint8 three-channel RGB image.');
end
if nargin < 2
    error('recommendBeautyParams:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
if nargin < 3
    beautyContext = prepareBeautyContext(inputImage, faceBox);
else
    validateBeautyContext(beautyContext, size(inputImage), faceBox);
end

ycbcrImage = rgb2ycbcr(im2double(inputImage));
luminance = ycbcrImage(:, :, 1);
skinMask = min(max(beautyContext.skinMask, 0), 1);
faceSkinMask = min(max(beautyContext.faceSkinMask, 0), 1);
protectionMask = min(max(beautyContext.featureProtectionMask, 0), 1);

% 只在有效皮肤中统计，五官和保护带不能把推荐强度推高。
usablePixels = skinMask > 0.35 & protectionMask < 0.35;
facePixels = usablePixels & faceSkinMask > 0.35;
bodyPixels = usablePixels & ~facePixels;
if nnz(facePixels) < 16
    facePixels = usablePixels;
    bodyPixels = false(size(usablePixels));
end

faceScale = min(faceBox(3:4));
anomalyMap = localAnomalyMap(ycbcrImage, usablePixels, faceScale);
faceSeverity = summarizeAnomaly(anomalyMap, facePixels);
if any(bodyPixels(:))
    bodySeverity = summarizeAnomaly(anomalyMap, bodyPixels);
else
    bodySeverity = faceSeverity;
end

% 脸部瑕疵是主要依据，身体皮肤只作较小补充，避免大面积手臂改变脸部档位。
% 将高密度异常映射到商业精修区间，但仍保留 45 档的自然下限。
anomalySeverity = saturate((.78 * faceSeverity + .22 * bodySeverity) / .75);
smoothingStrength = 45 + 30 * anomalySeverity;

% 美白以脸部中间调为主，避免暗背景或较暗手臂把亮度适中的脸部推到高档。
if nnz(facePixels) >= 16
    tonePixels = facePixels;
elseif nnz(usablePixels) >= 16
    tonePixels = usablePixels;
else
    tonePixels = false(size(usablePixels));
end
if any(tonePixels(:))
    toneValues = luminance(tonePixels);
    medianLuminance = median(toneValues);
    upperLuminance = percentileValue(toneValues, .85);
    brightnessDeficit = min(max((.72 - medianLuminance) / .32, 0), 1);
    highlightHeadroom = min(max((.92 - upperLuminance) / .18, 0), 1);
    whiteningNeed = brightnessDeficit .* (.60 + .40 * highlightHeadroom);
else
    whiteningNeed = 0;
end
whiteningStrength = 5 + 20 * min(max(whiteningNeed, 0), 1);

params = struct( ...
    'smoothingStrength', min(max(smoothingStrength, 45), 75), ...
    'whiteningStrength', min(max(whiteningStrength, 5), 25));
end

function anomalyMap = localAnomalyMap(ycbcrImage, usablePixels, faceScale)
%LOCALANOMALYMAP 合并局部亮度和色度异常，避免依赖全局纹理中位数。
anomalyMap = zeros(size(usablePixels));
if nnz(usablePixels) < 16
    return;
end

sigma = min(4.5, max(1.1, .012 * faceScale));
luminance = ycbcrImage(:, :, 1);
blueChroma = ycbcrImage(:, :, 2);
redChroma = ycbcrImage(:, :, 3);
localLuminance = imgaussfilt(luminance, sigma, 'Padding', 'replicate');
localBlueChroma = imgaussfilt(blueChroma, 1.15 * sigma, ...
    'Padding', 'replicate');
localRedChroma = imgaussfilt(redChroma, 1.15 * sigma, ...
    'Padding', 'replicate');

% 固定的最低阈值避免正常量化噪声进入瑕疵统计；超过阈值后按强度连续增加。
luminanceResidual = abs(luminance - localLuminance);
chromaResidual = max(abs(blueChroma - localBlueChroma), ...
    abs(redChroma - localRedChroma));
luminanceScore = saturate((luminanceResidual - .008) / .042);
chromaScore = saturate((chromaResidual - .006) / .030);
anomalyMap = saturate(.62 * luminanceScore + .38 * chromaScore);
anomalyMap(~usablePixels) = 0;
end

function severity = summarizeAnomaly(anomalyMap, selectedPixels)
%SUMMARIZEANOMALY 同时使用异常面积和异常强度。
values = anomalyMap(selectedPixels);
if isempty(values)
    severity = 0;
    return;
end

area = mean(values >= .20);
meanIntensity = mean(values);
highArea = mean(values >= .45);
areaTerm = saturate((area - .010) / .18);
intensityTerm = saturate((meanIntensity - .020) / .18);
highAreaTerm = saturate(highArea / .15);
severity = saturate(.45 * areaTerm + .35 * intensityTerm + ...
    .20 * highAreaTerm);
end

function value = saturate(value)
value = min(max(value, 0), 1);
end

function value = percentileValue(values, fraction)
%PERCENTILEVALUE 线性插值计算分位数，避免引入额外工具箱依赖。
values = sort(values(:));
if isempty(values)
    value = 0;
    return;
end
fraction = min(max(fraction, 0), 1);
position = 1 + (numel(values) - 1) * fraction;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = values(lowerIndex);
else
    weight = position - lowerIndex;
    value = (1 - weight) * values(lowerIndex) + ...
        weight * values(upperIndex);
end
end

function validateBeautyContext(context, imageSize, faceBox)
requiredFields = {'skinMask', 'faceSkinMask', 'featureProtectionMask', ...
    'imageSize', 'faceBox'};
isValid = isstruct(context) && isscalar(context) && ...
    all(isfield(context, requiredFields));
if isValid
    masks = {context.skinMask, context.faceSkinMask, ...
        context.featureProtectionMask};
    for index = 1:numel(masks)
        mask = masks{index};
        isValid = isValid && isa(mask, 'double') && isreal(mask) && ...
            isequal(size(mask), imageSize(1:2)) && all(isfinite(mask(:))) && ...
            all(mask(:) >= 0) && all(mask(:) <= 1);
    end
    isValid = isValid && isequal(double(context.imageSize), double(imageSize)) && ...
        isnumeric(context.faceBox) && isequal(size(context.faceBox), [1, 4]) && ...
        all(abs(double(context.faceBox) - double(faceBox)) <= 1e-9);
end
if ~isValid
    error('recommendBeautyParams:InvalidContext', ...
        'beautyContext does not match the input image and faceBox.');
end
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('recommendBeautyParams:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
end
