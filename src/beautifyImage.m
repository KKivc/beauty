function beautifiedImage = beautifyImage(inputImage, params, faceBox, beautyContext)
%BEAUTIFYIMAGE 对裸露皮肤执行结构保留的磨皮和美白。

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

% 零强度在 context 构建或验证前直接返回。
if smoothingStrength == 0 && whiteningStrength == 0
    beautifiedImage = inputImage;
    return;
end
ensureImageProcessingToolbox();
if nargin < 4
    beautyContext = prepareBeautyContext(inputImage, faceBox);
else
    validateBeautyContext(beautyContext, size(inputImage), faceBox);
end

inputDouble = im2double(inputImage);
ycbcrImage = rgb2ycbcr(inputDouble);
originalY = ycbcrImage(:, :, 1);
originalCb = ycbcrImage(:, :, 2);
originalCr = ycbcrImage(:, :, 3);
effectMask = beautyContext.skinMask .* ...
    (1 - beautyContext.featureProtectionMask);
highlightDetailProtection = min(max((originalY - 0.72) / 0.16, 0), 1);
effectMask = effectMask .* (1 - 0.95 * highlightDetailProtection);
faceScale = min(faceBox(3:4));

% 大尺度基底承载脸部立体结构，只衰减中尺度色斑和高频纹理。
fineSigma = min(4.5, max(0.9, 0.006 * faceScale));
mediumSigma = min(24, max(5, 0.045 * faceScale));
fineBase = imgaussfilt(originalY, fineSigma, 'Padding', 'replicate');
lowFrequency = imgaussfilt(originalY, mediumSigma, 'Padding', 'replicate');
fineDetail = originalY - fineBase;
mediumDetail = fineBase - lowFrequency;

% 低频梯度只保护真正的面部形状，不把孤立雀斑误判为结构。
[horizontalGradient, verticalGradient] = gradient(lowFrequency);
structureGradient = hypot(horizontalGradient, verticalGradient);
structureProtection = min(max((structureGradient - 0.004) / 0.035, 0), 1);
processingMask = effectMask .* (1 - 0.98 * structureProtection);

if smoothingStrength > 0
    ratio = smoothingStrength / 100;
    fineRetention = 1 - 0.80 * ratio ^ 0.85;
    mediumRetention = 1 - 0.98 * ratio ^ 1.15;
    smoothedY = lowFrequency + mediumRetention * mediumDetail + ...
        fineRetention * fineDetail;
    outputY = originalY + processingMask .* (smoothedY - originalY);

    % 色度异常同步衰减，避免亮度磨平后仍残留橙红色斑。
    chromaSigma = min(12, max(2.5, 0.025 * faceScale));
    localCb = imgaussfilt(originalCb, chromaSigma, 'Padding', 'replicate');
    localCr = imgaussfilt(originalCr, chromaSigma, 'Padding', 'replicate');
    chromaEffect = 0.92 * ratio ^ 1.05;
    outputCb = originalCb + processingMask .* chromaEffect .* ...
        (localCb - originalCb);
    outputCr = originalCr + processingMask .* chromaEffect .* ...
        (localCr - originalCr);
else
    outputY = originalY;
    outputCb = originalCb;
    outputCr = originalCr;
end

if whiteningStrength > 0
    ratio = whiteningStrength / 100;
    % 有界单调中间调曲线，最大档仍保留亮度排序和高光层次。
    toneStrength = 0.18 * (1 - exp(-6 * ratio)) / ...
        (1 - exp(-6)) + 0.10 * ratio;
    highlightProtection = min(max((0.97 - outputY) / 0.20, 0), 1);
    increase = toneStrength .* effectMask .* highlightProtection .^ 2 .* ...
        outputY .* (1 - outputY);
    outputY = outputY + min(increase, max(0, 0.975 - outputY));
end

ycbcrImage(:, :, 1) = min(max(outputY, 0), 1);
ycbcrImage(:, :, 2) = min(max(outputCb, 0), 1);
ycbcrImage(:, :, 3) = min(max(outputCr, 0), 1);
outputDouble = min(max(ycbcr2rgb(ycbcrImage), 0), 1);
beautifiedImage = uint8(round(outputDouble * 255));
if ~isequal(size(beautifiedImage), size(inputImage))
    error('beautifyImage:InvalidOutput', ...
        'The beautified image must preserve the input dimensions.');
end
end

function validateBeautyContext(context, imageSize, faceBox)
requiredFields = {'skinMask', 'faceSkinMask', 'featureProtectionMask', ...
    'imageSize', 'faceBox'};
isValid = isstruct(context) && isscalar(context) && ...
    all(isfield(context, requiredFields));
if isValid
    expectedMaskSize = imageSize(1:2);
    masks = {context.skinMask, context.faceSkinMask, ...
        context.featureProtectionMask};
    for index = 1:numel(masks)
        mask = masks{index};
        isValid = isValid && isa(mask, 'double') && isreal(mask) && ...
            isequal(size(mask), expectedMaskSize) && all(isfinite(mask(:))) && ...
            all(mask(:) >= 0) && all(mask(:) <= 1);
    end
    isValid = isValid && isequal(double(context.imageSize), double(imageSize)) && ...
        isnumeric(context.faceBox) && isequal(size(context.faceBox), [1, 4]) && ...
        all(abs(double(context.faceBox) - double(faceBox)) <= 1e-9);
end
if ~isValid
    error('beautifyImage:InvalidContext', ...
        'beautyContext does not match the input image and faceBox.');
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
