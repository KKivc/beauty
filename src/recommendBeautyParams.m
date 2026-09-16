function params = recommendBeautyParams(inputImage, faceBox, beautyContext)
%RECOMMENDBEAUTYPARAMS 根据 v3 的可处理皮肤指标推荐两项强度。

validateImage(inputImage);
if nargin < 2
    error('recommendBeautyParams:InvalidFaceBox', ...
        '必须提供位于图像范围内的 [x y width height] 人脸框。');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
if nargin < 3 || isempty(beautyContext)
    beautyContext = normalizeBeautyContext(inputImage, faceBox);
else
    try
        beautyContext = normalizeBeautyContext(inputImage, faceBox, ...
            beautyContext);
    catch exception
        if startsWith(exception.identifier, 'normalizeBeautyContext:')
            error('recommendBeautyParams:InvalidContext', ...
                'Beauty Context 无效：%s', exception.message);
        end
        rethrow(exception);
    end
end

[beautyMasks, ~] = masks.buildBeautyMasks(inputImage, ...
    beautyContext, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(inputImage, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(inputImage, ...
    frequency, beautyMasks);

ycbcrImage = rgb2ycbcr(im2double(inputImage));
luminance = ycbcrImage(:, :, 1);
skinMask = min(max(beautyMasks.skinMask, 0), 1);
faceSkinMask = min(max(beautyMasks.faceSkinMask, 0), 1);
nonFaceSkinMask = min(max(beautyMasks.nonFaceSkinMask, 0), 1);
processableMask = min(max(1 - beautyMasks.protectionMask, 0), 1);
processableMask = min(processableMask, 1 - beautyMasks.hardProtectionMask);
usablePixels = skinMask > .35 & processableMask > .35;

facePixels = usablePixels & faceSkinMask > .35;
bodyPixels = usablePixels & nonFaceSkinMask > .35;
if nnz(facePixels) < 16
    facePixels = usablePixels;
    bodyPixels = false(size(usablePixels));
end

faceSeverity = summarizeAnomaly(blemishMap, facePixels);
if any(bodyPixels(:))
    bodySeverity = summarizeAnomaly(blemishMap, bodyPixels);
else
    bodySeverity = faceSeverity;
end
% 脸部是主要依据，脸外皮肤只作小比例补充，推荐值保持在自然范围。
anomalySeverity = saturate((.78 * faceSeverity + ...
    .22 * bodySeverity) / .75);
smoothingStrength = 45 + 30 * anomalySeverity;

% 美白只读取可处理脸部的中间调和高光余量，背景与身体不会推高档位。
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
    brightnessDeficit = saturate((.72 - medianLuminance) / .32);
    highlightHeadroom = saturate((.92 - upperLuminance) / .18);
    whiteningNeed = brightnessDeficit .* ...
        (.60 + .40 * highlightHeadroom);
else
    whiteningNeed = 0;
end
whiteningStrength = 5 + 20 * saturate(whiteningNeed);

params = struct( ...
    'smoothingStrength', min(max(smoothingStrength, 45), 75), ...
    'whiteningStrength', min(max(whiteningStrength, 5), 25));
end

function severity = summarizeAnomaly(anomalyMap, selectedPixels)
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

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('recommendBeautyParams:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('recommendBeautyParams:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end
