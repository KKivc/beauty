function params = recommendBeautyParams(inputImage, faceBox, beautyContext)
%RECOMMENDBEAUTYPARAMS 根据脸部皮肤亮度和纹理推荐强度。

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
selectedPixels = beautyContext.faceSkinMask > 0.35 & ...
    beautyContext.featureProtectionMask < 0.35;
if nnz(selectedPixels) < 16
    selectedPixels = beautyContext.faceSkinMask > 0;
end
if nnz(selectedPixels) < 16
    xStart = max(1, floor(faceBox(1)));
    yStart = max(1, floor(faceBox(2)));
    xEnd = min(size(inputImage, 2), ceil(faceBox(1) + faceBox(3) - 1));
    yEnd = min(size(inputImage, 1), ceil(faceBox(2) + faceBox(4) - 1));
    selectedPixels(yStart:yEnd, xStart:xEnd) = true;
end

faceLuminance = luminance(selectedPixels);
medianLuminance = median(faceLuminance);
brightnessDeficit = min(max((0.68 - medianLuminance) / 0.48, 0), 1);
whiteningStrength = 100 * brightnessDeficit ^ 0.72;

faceScale = min(faceBox(3:4));
textureSigma = min(8, max(1.1, 0.009 * faceScale));
baseLuminance = imgaussfilt(luminance, textureSigma, 'Padding', 'replicate');
texture = abs(luminance - baseLuminance);
selectedTexture = texture(selectedPixels);
textureLevel = median(selectedTexture) + 0.45 * mean(selectedTexture);
textureRatio = min(max(textureLevel / 0.050, 0), 1);
smoothingStrength = 100 * textureRatio ^ 0.68;

params = struct( ...
    'smoothingStrength', min(max(smoothingStrength, 0), 100), ...
    'whiteningStrength', min(max(whiteningStrength, 0), 100));
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
