function params = recommendBeautyParams(inputImage, faceBox)
%RECOMMENDBEAUTYPARAMS 根据人脸亮度和局部纹理推荐美颜强度。

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
ensureImageProcessingToolbox();

inputDouble = im2double(inputImage);
ycbcrImage = rgb2ycbcr(inputDouble);
luminance = ycbcrImage(:, :, 1);
beautyMask = createBeautyMask(inputDouble, faceBox);
selectedPixels = beautyMask > 0.35;
if nnz(selectedPixels) < 16
    selectedPixels = beautyMask > 0;
end
if nnz(selectedPixels) == 0
    % 极小人脸框可能没有椭圆内部像素，退回到框内像素保证统计稳定。
    xStart = max(1, floor(faceBox(1)));
    yStart = max(1, floor(faceBox(2)));
    xEnd = min(size(inputImage, 2), ceil(faceBox(1) + faceBox(3) - 1));
    yEnd = min(size(inputImage, 1), ceil(faceBox(2) + faceBox(4) - 1));
    selectedPixels(yStart:yEnd, xStart:xEnd) = true;
end

% 新美白曲线低档更明显，因此推荐值按稳健亮度缺口连续映射。
faceLuminance = luminance(selectedPixels);
medianLuminance = median(faceLuminance);
brightnessDeficit = min(max((0.67 - medianLuminance) / 0.55, 0), 1);
whiteningStrength = 100 * (1 - exp(-1.8 * brightnessDeficit)) / ...
    (1 - exp(-1.8));

% 纹理统计尺度随人脸大小变化，与磨皮的基础层尺度保持一致方向。
faceScale = min(faceBox(3), faceBox(4));
textureSigma = min(10, max(1.2, 0.012 * faceScale));
baseLuminance = imgaussfilt(luminance, textureSigma, ...
    'Padding', 'replicate');
highFrequency = abs(luminance - baseLuminance);
selectedTexture = highFrequency(selectedPixels);
textureLevel = median(selectedTexture) + 0.35 * mean(selectedTexture);
textureRatio = min(max(textureLevel / 0.055, 0), 1);
smoothingStrength = 100 * (1 - exp(-2.0 * textureRatio)) / ...
    (1 - exp(-2.0));

params = struct( ...
    'smoothingStrength', min(max(smoothingStrength, 0), 100), ...
    'whiteningStrength', min(max(whiteningStrength, 0), 100));
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

function ensureImageProcessingToolbox
requiredFunctions = {'rgb2ycbcr', 'imgaussfilt'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('recommendBeautyParams:MissingToolbox', ...
        'Image Processing Toolbox is required for beauty recommendations.');
end
end
