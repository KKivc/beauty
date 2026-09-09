function beautyContext = prepareBeautyContext(inputImage, faceBox)
%PREPAREBEAUTYCONTEXT 一次分析裸露皮肤与需要保护的五官。

if nargin < 1 || ~isValidRgbImage(inputImage)
    error('prepareBeautyContext:InvalidImage', ...
        'inputImage must be a uint8 three-channel RGB image.');
end
if nargin < 2
    error('prepareBeautyContext:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
ensureRequiredFunctions();

inputDouble = im2double(inputImage);
ycbcrImage = rgb2ycbcr(inputDouble);
luminance = ycbcrImage(:, :, 1);
cb = ycbcrImage(:, :, 2);
cr = ycbcrImage(:, :, 3);
[imageHeight, imageWidth, ~] = size(inputImage);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
relativeX = (xGrid - faceBox(1)) / max(faceBox(3) - 1, 1);
relativeY = (yGrid - faceBox(2)) / max(faceBox(4) - 1, 1);
insideFace = relativeX >= 0 & relativeX <= 1 & ...
    relativeY >= 0 & relativeY <= 1;

% 额头、双颊和鼻侧提供稳健肤色样本，避开眼口中心。
sampleRegion = insideFace & relativeY >= 0.30 & relativeY <= 0.78 & ...
    (((relativeX >= 0.24 & relativeX <= 0.38) | ...
    (relativeX >= 0.62 & relativeX <= 0.76)) | ...
    (relativeX >= 0.44 & relativeX <= 0.56 & relativeY <= 0.66)) & ...
    luminance > 0.06 & luminance < 0.98;
if nnz(sampleRegion) < 32
    sampleRegion = insideFace & relativeX >= 0.28 & relativeX <= 0.72 & ...
        relativeY >= 0.30 & relativeY <= 0.78 & ...
        luminance > 0.04 & luminance < 0.99;
end

sampleCb = cb(sampleRegion);
sampleCr = cr(sampleRegion);
sampleY = luminance(sampleRegion);
if ~isempty(sampleY)
    reliableBrightness = sampleY >= prctile(sampleY, 65);
    sampleCb = sampleCb(reliableBrightness);
    sampleCr = sampleCr(reliableBrightness);
    sampleY = sampleY(reliableBrightness);
end
reference = [median(sampleCb), median(sampleCr), median(sampleY)];
spread = max([robustSpread(sampleCb, reference(1)), ...
    robustSpread(sampleCr, reference(2)), ...
    robustSpread(sampleY, reference(3))], [0.018, 0.018, 0.045]);

chromaDistance = sqrt(((cb - reference(1)) / (3.0 * spread(1))) .^ 2 + ...
    ((cr - reference(2)) / (3.0 * spread(2))) .^ 2);
localLuminance = imgaussfilt(luminance, ...
    min(18, max(2, 0.018 * min(faceBox(3:4)))), 'Padding', 'replicate');
luminanceCompatible = luminance > 0.22 & luminance < 0.985 & ...
    luminance >= 0.62 * localLuminance & ...
    luminance >= max([0.035, reference(3) - 0.30, ...
    0.50 * reference(3)]);
referenceColorfulness = hypot(reference(1) - 0.5, reference(2) - 0.5);
chromaCompatible = hypot(cb - 0.5, cr - 0.5) <= ...
    max(0.10, referenceColorfulness + 0.07);
globalCandidate = chromaDistance <= 1.45 & luminanceCompatible & ...
    chromaCompatible;
faceCandidate = insideFace & chromaDistance <= 1.55 & ...
    luminanceCompatible & chromaCompatible & ...
    luminance >= max(0.035, reference(3) - 0.28);

faceSeed = faceCandidate & relativeX >= 0.23 & relativeX <= 0.77 & ...
    relativeY >= 0.18 & relativeY <= 0.80;
if any(faceSeed(:))
    faceSkin = imreconstruct(faceSeed, faceCandidate);
else
    faceSkin = faceCandidate;
end
faceScale = min(faceBox(3:4));
faceSkin = repairSmallGaps(faceSkin, faceBox(3) * faceBox(4), faceScale);
faceSkin = faceSkin & insideFace;

% 全图候选按连通域筛选，允许严格匹配的断开手部或手臂。
globalCandidate = globalCandidate | faceSkin;
globalCandidate = imclose(globalCandidate, ...
    strel('disk', max(1, round(0.004 * faceScale)), 0));
components = bwconncomp(globalCandidate, 8);
stats = regionprops(components, 'Area', 'BoundingBox', 'Centroid', 'Solidity');
skinBinary = false(imageHeight, imageWidth);
minimumBodyArea = max(24, round(0.0012 * imageHeight * imageWidth));
maximumIndependentArea = 0.20 * imageHeight * imageWidth;
faceCore = insideFace & relativeX >= 0.15 & relativeX <= 0.85 & ...
    relativeY >= 0.12 & relativeY <= 0.92;
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    overlapsFace = any(faceCore(pixels));
    meanDistance = mean(chromaDistance(pixels));
    box = stats(index).BoundingBox;
    touchesLeftRight = box(1) <= 1.5 && ...
        box(1) + box(3) >= imageWidth - 0.5;
    touchesTopBottom = box(2) <= 1.5 && ...
        box(2) + box(4) >= imageHeight - 0.5;
    independentSkin = stats(index).Area >= minimumBodyArea && ...
        stats(index).Area <= maximumIndependentArea && ...
        stats(index).Solidity >= 0.38 && meanDistance <= 0.78 && ...
        ~(touchesLeftRight || touchesTopBottom) && ...
        stats(index).Centroid(2) >= faceBox(2) + 0.28 * faceBox(4);
    if overlapsFace || independentSkin
        skinBinary(pixels) = true;
    end
end
skinBinary = skinBinary | faceSkin;
skinBinary = repairSmallGaps(skinBinary, imageHeight * imageWidth, faceScale);
% 形态学只能修复候选内部的小斑点，不能越过颜色边界。
faceSkin = faceSkin & faceCandidate;
skinBinary = skinBinary & (globalCandidate | faceSkin);
erosionRadius = min(4, max(1, round(0.012 * faceScale)));
skinBinary = imerode(skinBinary, strel('disk', erosionRadius, 0));
faceSkin = imerode(faceSkin, strel('disk', erosionRadius, 0));

skinMask = inwardSoftMask(skinBinary, faceScale);
faceSkinMask = inwardSoftMask(faceSkin, faceScale);
featureProtectionMask = createFeatureProtection( ...
    inputImage, luminance, cb, cr, faceBox, insideFace, relativeX, relativeY);
featureProtectionMask = min(featureProtectionMask, double(insideFace));

beautyContext = struct( ...
    'skinMask', skinMask, ...
    'faceSkinMask', faceSkinMask, ...
    'featureProtectionMask', featureProtectionMask, ...
    'imageSize', size(inputImage), ...
    'faceBox', double(faceBox));
end

function repaired = repairSmallGaps(binaryMask, referenceArea, faceScale)
closeRadius = max(1, round(0.004 * faceScale));
repaired = imclose(binaryMask, strel('disk', closeRadius, 0));
holes = imfill(repaired, 'holes') & ~repaired;
maximumHoleArea = max(6, round(0.0010 * referenceArea));
largeHoles = bwareaopen(holes, maximumHoleArea + 1);
repaired = repaired | (holes & ~largeHoles);
repaired = bwareaopen(repaired, max(4, round(0.00004 * referenceArea)));
end

function softMask = inwardSoftMask(binaryMask, faceScale)
featherRadius = min(8, max(2, 0.012 * faceScale));
distance = double(bwdist(~binaryMask));
position = min(distance / featherRadius, 1);
softMask = position .^ 2 .* (3 - 2 * position);
softMask(~binaryMask) = 0;
end

function protection = createFeatureProtection(inputImage, luminance, cb, cr, ...
        faceBox, insideFace, relativeX, relativeY)
faceScale = min(faceBox(3:4));
smoothed = imgaussfilt(luminance, min(6, max(2, 0.025 * faceScale)), ...
    'Padding', 'replicate');
[horizontalGradient, verticalGradient] = gradient(smoothed);
gradientMagnitude = hypot(horizontalGradient, verticalGradient);
faceGradient = gradientMagnitude(insideFace);
gradientLimit = max(median(faceGradient) + ...
    2.4 * robustSpread(faceGradient, median(faceGradient)), 0.025);
strongStructure = min(max((gradientMagnitude - 0.55 * gradientLimit) / ...
    max(gradientLimit, eps), 0), 1);

eyeZone = insideFace & relativeY >= 0.20 & relativeY <= 0.44 & ...
    ((relativeX >= 0.08 & relativeX <= 0.41) | ...
    (relativeX >= 0.59 & relativeX <= 0.92));
mouthZone = insideFace & relativeY >= 0.64 & relativeY <= 0.88 & ...
    relativeX >= 0.24 & relativeX <= 0.76;
noseZone = insideFace & relativeY >= 0.38 & relativeY <= 0.76 & ...
    relativeX >= 0.34 & relativeX <= 0.66;
faceY = luminance(insideFace);
faceCr = cr(insideFace);
darkLimit = median(faceY) - max(0.025, 0.7 * robustSpread(faceY, median(faceY)));
redLimit = median(faceCr) + max(0.012, 0.55 * robustSpread(faceCr, median(faceCr)));
fallback = strongStructure .* double(eyeZone | noseZone | mouthZone);
fallback = max(fallback, double(eyeZone & luminance < darkLimit));
fallback = max(fallback, double(mouthZone & cr > redLimit & ...
    cr > cb + 0.025));

cascade = detectCascadeProtection(inputImage, faceBox, gradientMagnitude);
protection = max(fallback, cascade);
protection = imgaussfilt(protection, min(2.2, max(0.8, 0.004 * faceScale)), ...
    'Padding', 'replicate');
protection = min(max(protection, 0), 1);
end

function bestProtection = detectCascadeProtection(inputImage, faceBox, gradientMagnitude)
bestProtection = zeros(size(gradientMagnitude));
if exist('vision.CascadeObjectDetector', 'class') == 0
    return;
end

xStart = max(1, floor(faceBox(1)));
yStart = max(1, floor(faceBox(2)));
xEnd = min(size(inputImage, 2), ceil(faceBox(1) + faceBox(3) - 1));
yEnd = min(size(inputImage, 1), ceil(faceBox(2) + faceBox(4) - 1));
roi = inputImage(yStart:yEnd, xStart:xEnd, :);
roiGradient = gradientMagnitude(yStart:yEnd, xStart:xEnd);
bestScore = 0;
for angle = [-15, 0, 15]
    rotated = imrotate(roi, angle, 'bilinear', 'crop');
    try
        eyeBoxes = runCascade(rotated, 'EyePairBig');
        noseBoxes = runCascade(rotated, 'Nose');
        mouthBoxes = runCascade(rotated, 'Mouth');
    catch
        continue;
    end
    [candidate, score] = buildAnatomicalProtection( ...
        size(rotated), eyeBoxes, noseBoxes, mouthBoxes, ...
        imrotate(roiGradient, angle, 'bilinear', 'crop'));
    if score > bestScore
        restored = imrotate(candidate, -angle, 'bilinear', 'crop');
        bestProtection(:) = 0;
        bestProtection(yStart:yEnd, xStart:xEnd) = restored;
        bestScore = score;
    end
end
end

function boxes = runCascade(imageData, modelName)
detector = vision.CascadeObjectDetector(modelName);
boxes = detector(imageData);
release(detector);
end

function [protection, score] = buildAnatomicalProtection( ...
        imageSize, eyeBoxes, noseBoxes, mouthBoxes, roiGradient)
height = imageSize(1);
width = imageSize(2);
protection = zeros(height, width);
score = 0;
eyeBox = largestValidBox(eyeBoxes, width, height, [0.10, 0.08, 0.90, 0.58]);
noseBox = largestValidBox(noseBoxes, width, height, [0.22, 0.28, 0.78, 0.82]);
mouthBox = largestValidBox(mouthBoxes, width, height, [0.16, 0.52, 0.84, 0.96]);

if ~isempty(eyeBox)
    eyeCenter = centerOfBox(eyeBox);
else
    eyeCenter = [NaN, NaN];
end
if ~isempty(noseBox)
    noseCenter = centerOfBox(noseBox);
else
    noseCenter = [NaN, NaN];
end
if ~isempty(mouthBox)
    mouthCenter = centerOfBox(mouthBox);
else
    mouthCenter = [NaN, NaN];
end

hasEye = ~isempty(eyeBox) && eyeCenter(2) < 0.60 * height;
hasNose = ~isempty(noseBox) && noseCenter(2) > 0.32 * height && ...
    (~hasEye || noseCenter(2) > eyeCenter(2)) && ...
    abs(noseCenter(1) - width / 2) < 0.25 * width;
hasMouth = ~isempty(mouthBox) && mouthCenter(2) > 0.55 * height && ...
    (~hasNose || mouthCenter(2) > noseCenter(2)) && ...
    abs(mouthCenter(1) - width / 2) < 0.28 * width;
validEye = hasEye && hasNose && hasMouth;
validNose = validEye;
validMouth = validEye;

if validEye
    expandedEye = expandBox(eyeBox, [0.18, 0.60], width, height);
    protection = max(protection, softRectangle(height, width, expandedEye));
    score = score + 2;
end
if validMouth
    expandedMouth = expandBox(mouthBox, [0.15, 0.18], width, height);
    protection = max(protection, softRectangle(height, width, expandedMouth));
    score = score + 2;
end
if validNose
    noseMask = softRectangle(height, width, noseBox);
    gradientScale = max(prctile(roiGradient(noseMask > 0.2), 80), 0.02);
    protection = max(protection, noseMask .* ...
        min(roiGradient / gradientScale, 1));
    score = score + 1;
end
end

function box = largestValidBox(boxes, width, height, limits)
box = [];
if isempty(boxes)
    return;
end
centers = [boxes(:, 1) + boxes(:, 3) / 2, ...
    boxes(:, 2) + boxes(:, 4) / 2];
valid = centers(:, 1) >= limits(1) * width & ...
    centers(:, 2) >= limits(2) * height & ...
    centers(:, 1) <= limits(3) * width & ...
    centers(:, 2) <= limits(4) * height;
boxes = boxes(valid, :);
if isempty(boxes)
    return;
end
[~, index] = max(boxes(:, 3) .* boxes(:, 4));
box = boxes(index, :);
end

function center = centerOfBox(box)
center = [box(1) + box(3) / 2, box(2) + box(4) / 2];
end

function expanded = expandBox(box, fractions, width, height)
horizontal = fractions(1) * box(3);
vertical = fractions(2) * box(4);
expanded = [max(1, box(1) - horizontal), max(1, box(2) - vertical), ...
    min(width, box(1) + box(3) + horizontal) - max(1, box(1) - horizontal), ...
    min(height, box(2) + box(4) + vertical) - max(1, box(2) - vertical)];
end

function mask = softRectangle(height, width, box)
mask = zeros(height, width);
xStart = max(1, floor(box(1)));
yStart = max(1, floor(box(2)));
xEnd = min(width, ceil(box(1) + box(3) - 1));
yEnd = min(height, ceil(box(2) + box(4) - 1));
mask(yStart:yEnd, xStart:xEnd) = 1;
mask = imgaussfilt(mask, max(0.8, 0.03 * min(box(3:4))), ...
    'Padding', 'replicate');
mask = min(mask, 1);
end

function value = robustSpread(samples, center)
if isempty(samples)
    value = 0;
else
    value = 1.4826 * median(abs(samples - center));
end
end

function isValid = isValidRgbImage(inputImage)
isValid = isa(inputImage, 'uint8') && isreal(inputImage) && ...
    ndims(inputImage) == 3 && size(inputImage, 3) == 3;
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('prepareBeautyContext:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
end

function ensureRequiredFunctions
requiredFunctions = {'rgb2ycbcr', 'imgaussfilt', 'imreconstruct', ...
    'imclose', 'imfill', 'bwareaopen', 'bwdist', 'bwconncomp', ...
    'regionprops', 'imrotate', 'imerode', 'strel'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('prepareBeautyContext:MissingToolbox', ...
        'Image Processing Toolbox is required for beauty analysis.');
end
end
