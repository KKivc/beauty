function beautifiedImage = beautifyImage(inputImage, params, faceBox)
%BEAUTIFYIMAGE 对单人脸 RGB 图像执行磨皮和美白。

if nargin < 1 || ~isValidRgbImage(inputImage)
    error('beautifyImage:InvalidImage', ...
        'inputImage must be a uint8 three-channel RGB image.');
end

if nargin < 2 || ~isstruct(params) || ~isscalar(params) || ...
        ~isfield(params, 'smoothingStrength') || ...
        ~isfield(params, 'whiteningStrength')
    error('beautifyImage:InvalidParams', ...
        'params must contain smoothingStrength and whiteningStrength.');
end
smoothingStrength = params.smoothingStrength;
whiteningStrength = params.whiteningStrength;
if ~isValidStrength(smoothingStrength) || ~isValidStrength(whiteningStrength)
    error('beautifyImage:InvalidParams', ...
        'Beauty strengths must be finite numeric scalars in the range 0 to 100.');
end

if nargin < 3
    error('beautifyImage:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));

% 零强度时直接返回原图，保证逐元素完全一致。
if smoothingStrength == 0 && whiteningStrength == 0
    beautifiedImage = inputImage;
    return;
end
ensureImageProcessingToolbox();

inputDouble = im2double(inputImage);
ycbcrImage = rgb2ycbcr(inputDouble);
luminance = ycbcrImage(:, :, 1);
originalLuminance = luminance;
beautyMask = createBeautyMask(inputDouble, faceBox);

% 固定保护图由原始亮度计算，保证各档强度只改变效果幅度。
[horizontalGradient, verticalGradient] = gradient(originalLuminance);
edgeMagnitude = hypot(horizontalGradient, verticalGradient);
edgeProtection = 1 ./ (1 + (edgeMagnitude / 0.055) .^ 4);

if smoothingStrength > 0
    % 滤波尺度随人脸大小变化，避免高分辨率图仍使用固定小窗口。
    faceScale = min(faceBox(3), faceBox(4));
    detailSigma = min(18, max(1.5, 0.018 * faceScale));
    filterSize = 2 * ceil(3 * detailSigma) + 1;
    baseLuminance = imgaussfilt(originalLuminance, detailSigma, ...
        'FilterSize', filterSize, 'Padding', 'replicate');
    detailLayer = originalLuminance - baseLuminance;

    % 小纹理充分衰减，强细节和五官边缘通过两级权重保留。
    detailProtection = 1 ./ (1 + (abs(detailLayer) / 0.075) .^ 4);
    smoothingRatio = smoothingStrength / 100;
    smoothingEffect = 1 - (1 - smoothingRatio) ^ 1.4;
    smoothingMask = beautyMask .* edgeProtection .* detailProtection;
    luminance = originalLuminance - smoothingEffect .* ...
        smoothingMask .* detailLayer;
end

if whiteningStrength > 0
    % 非线性强度映射提升低档可见度，同时在高档平滑饱和。
    whiteningRatio = whiteningStrength / 100;
    whiteningEffect = (1 - exp(-2.5 * whiteningRatio)) / ...
        (1 - exp(-2.5));
    highlightProtection = min(max((0.96 - luminance) / 0.24, 0), 1);
    whiteningEdgeProtection = 0.45 + 0.55 * edgeProtection;
    luminanceIncrease = 0.30 * whiteningEffect .* beautyMask .* ...
        whiteningEdgeProtection .* highlightProtection .* (1 - luminance);
    luminance = luminance + min(luminanceIncrease, max(0, 0.97 - luminance));
end

ycbcrImage(:, :, 1) = min(max(luminance, 0), 1);
outputDouble = ycbcr2rgb(ycbcrImage);
outputDouble = min(max(outputDouble, 0), 1);
beautifiedImage = uint8(round(outputDouble * 255));

% 再次确认算法分支没有泄漏临时尺寸或通道变化。
if ~isequal(size(beautifiedImage), size(inputImage))
    error('beautifyImage:InvalidOutput', ...
        'The beautified image must preserve the input dimensions.');
end
end

function isValid = isValidRgbImage(inputImage)
isValid = isa(inputImage, 'uint8') && isreal(inputImage) && ...
    ndims(inputImage) == 3 && size(inputImage, 3) == 3;
end

function isValid = isValidStrength(strength)
isValid = isnumeric(strength) && isreal(strength) && isscalar(strength) && ...
    isfinite(strength) && strength >= 0 && strength <= 100;
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('beautifyImage:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
end

function ensureImageProcessingToolbox
requiredFunctions = {'rgb2ycbcr', 'ycbcr2rgb', 'imgaussfilt'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('beautifyImage:MissingToolbox', ...
        'Image Processing Toolbox is required for beauty processing.');
end
end
