function [summary, outputFolder] = smokePhase2RealImages
%SMOKEPHASE2REALIMAGES 只读真实图集并输出第二阶段回归产物。
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));

imagePaths = { ...
    'D:\桌面\人脸\人脸\14.jpg'; ...
    'D:\桌面\人脸\人脸\15.jpg'; ...
    'D:\桌面\人脸\人脸\73.jpg'; ...
    'D:\桌面\人脸\人脸\80.jpg'; ...
    'D:\桌面\人脸\人脸2\205.jpg'; ...
    'D:\桌面\人脸\人脸2\206.jpg'};
outputFolder = fullfile(tempdir, 'image_beauty_phase2_smoke_20260910');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

rowTemplate = struct('image', '', 'width', 0, 'height', 0, ...
    'faceBox', zeros(1, 4), 'usedFullFallback', false, ...
    'analysisSeconds', 0, 'sliderMilliseconds', 0, ...
    'defaultTextureRetention', NaN, 'maximumTextureRetention', NaN, ...
    'skinBrightnessIncrease', NaN, 'backgroundMaxChange', 0, ...
    'featureMaxChange', 0, 'bodyPixels', 0, ...
    'oldRoiBoundaryJump', NaN, 'visualPath', '');
rows = repmat(rowTemplate, numel(imagePaths), 1);
for index = 1:numel(imagePaths)
    imagePath = imagePaths{index};
    if ~isfile(imagePath)
        error('smokePhase2RealImages:MissingImage', ...
            'Regression image is missing: %s', imagePath);
    end
    sourceImage = imread(imagePath);
    if ~isa(sourceImage, 'uint8') || ndims(sourceImage) ~= 3 || ...
            size(sourceImage, 3) ~= 3
        error('smokePhase2RealImages:InvalidImage', ...
            'Regression image must be uint8 RGB: %s', imagePath);
    end

    previewScale = min(1, 800 / max(size(sourceImage, 1), size(sourceImage, 2)));
    if previewScale < 1
        previewImage = imresize(sourceImage, previewScale, 'bilinear');
    else
        previewImage = sourceImage;
    end
    analysisClock = tic;
    [previewFaceBox, hasFace, detectionDetails] = detectSingleFace(previewImage);
    if ~hasFace
        error('smokePhase2RealImages:NoSemanticFace', ...
            'No semantic face was found: %s', imagePath);
    end
    context = prepareBeautyContext(previewImage, previewFaceBox, ...
        detectionDetails.selectedParsing);
    analysisSeconds = toc(analysisClock);

    defaultParams = struct('smoothingStrength', 25, 'whiteningStrength', 15);
    maximumParams = struct('smoothingStrength', 100, 'whiteningStrength', 100);
    maximumSmoothingParams = struct('smoothingStrength', 100, ...
        'whiteningStrength', 0);
    sliderClock = tic;
    defaultOutput = beautifyImage(previewImage, defaultParams, ...
        previewFaceBox, context);
    sliderMilliseconds = 1000 * toc(sliderClock);
    maximumOutput = beautifyImage(previewImage, maximumParams, ...
        previewFaceBox, context);
    maximumSmoothingOutput = beautifyImage(previewImage, ...
        maximumSmoothingParams, previewFaceBox, context);

    fullFaceBox = scaleBox(previewFaceBox, 1 / previewScale, size(sourceImage));
    fullContext = resizeBeautyContext(context, size(sourceImage), fullFaceBox);
    savedOutput = beautifyImage(sourceImage, defaultParams, ...
        fullFaceBox, fullContext);
    if ~isequal(size(savedOutput), size(sourceImage))
        error('smokePhase2RealImages:SaveSizeMismatch', ...
            'Full-size result changed image dimensions: %s', imagePath);
    end

    % 纹理门槛以脸部皮肤为准，身体用于覆盖与保护核验。
    evaluationMask = imerode(context.faceSkinMask > .50, ...
        strel('disk', 2, 0)) & context.featureProtectionMask < .20;
    inputEnergy = textureEnergy(previewImage, evaluationMask, ...
        min(previewFaceBox(3:4)));
    defaultEnergy = textureEnergy(defaultOutput, evaluationMask, ...
        min(previewFaceBox(3:4)));
    maximumEnergy = textureEnergy(maximumSmoothingOutput, evaluationMask, ...
        min(previewFaceBox(3:4)));
    if inputEnergy > eps
        defaultRetention = defaultEnergy / inputEnergy;
        maximumRetention = maximumEnergy / inputEnergy;
    else
        defaultRetention = NaN;
        maximumRetention = NaN;
    end

    inputYCbCr = rgb2ycbcr(im2double(previewImage));
    outputYCbCr = rgb2ycbcr(im2double(defaultOutput));
    inputY = inputYCbCr(:, :, 1);
    outputY = outputYCbCr(:, :, 1);
    if any(evaluationMask(:))
        skinBrightnessIncrease = median(outputY(evaluationMask) - ...
            inputY(evaluationMask));
    else
        skinBrightnessIncrease = NaN;
    end
    difference = max(abs(double(defaultOutput) - double(previewImage)), [], 3);
    background = context.skinMask < .01;
    backgroundMaxChange = max(difference(background), [], 'all');
    if isfield(context, 'hardProtectionMask') && any(context.hardProtectionMask(:) >= .999)
        featureMaxChange = max(difference(context.hardProtectionMask >= .999), [], 'all');
    else
        featureMaxChange = 0;
    end

    [~, baseName] = fileparts(imagePath);
    visualPath = fullfile(outputFolder, [baseName, '_phase2.jpg']);
    annotated = annotateFaceDetection(previewImage, previewFaceBox);
    maskVisual = repmat(uint8(round(255 * context.skinMask)), [1, 1, 3]);
    imwrite([annotated, defaultOutput, maximumOutput, maskVisual], visualPath, ...
        'Quality', 94);

    rows(index).image = imagePath;
    rows(index).width = size(sourceImage, 2);
    rows(index).height = size(sourceImage, 1);
    rows(index).faceBox = previewFaceBox;
    rows(index).usedFullFallback = detectionDetails.usedFullImageParsing;
    rows(index).analysisSeconds = analysisSeconds;
    rows(index).sliderMilliseconds = sliderMilliseconds;
    rows(index).defaultTextureRetention = defaultRetention;
    rows(index).maximumTextureRetention = maximumRetention;
    rows(index).skinBrightnessIncrease = skinBrightnessIncrease;
    rows(index).backgroundMaxChange = backgroundMaxChange;
    rows(index).featureMaxChange = featureMaxChange;
    rows(index).bodyPixels = nnz(context.bodySkinMask > .35);
    if strcmp(baseName, '15')
        rows(index).oldRoiBoundaryJump = boundaryJump(difference, ...
            scaleBox([12, 114, 231, 361], previewScale, size(previewImage)));
    end
    rows(index).visualPath = visualPath;
end
summary = struct2table(rows);
if any(summary.defaultTextureRetention < .80) || ...
        any(summary.maximumTextureRetention < .55) || ...
        any(summary.maximumTextureRetention > .80)
    error('smokePhase2RealImages:TextureRetention', ...
        '真实图纹理保留率未达标：默认档=%s，最大档=%s。', ...
        mat2str(summary.defaultTextureRetention', 4), ...
        mat2str(summary.maximumTextureRetention', 4));
end
if any(summary.backgroundMaxChange > 1) || any(summary.featureMaxChange > 0)
    error('smokePhase2RealImages:ProtectionChanged', ...
        'Background or hard-protected facial features changed unexpectedly.');
end
if any(summary.analysisSeconds(2:end) > 5) || ...
        any(summary.sliderMilliseconds > 500)
    error('smokePhase2RealImages:Performance', ...
        'Warm parsing or slider performance exceeded the smoke-test budget.');
end
firstBox = summary.faceBox(1, :);
if ~summary.usedFullFallback(1) || ...
        firstBox(1) + firstBox(3) / 2 > .70 * summary.width(1)
    error('smokePhase2RealImages:Image14Recovery', ...
        '14.jpg did not recover from the right-hair false detection.');
end
if summary.oldRoiBoundaryJump(2) > 1
    error('smokePhase2RealImages:Image15Boundary', ...
        '15.jpg still shows a measurable old-ROI rectangular boundary.');
end
if any(summary.bodyPixels(3:end) == 0)
    error('smokePhase2RealImages:BodySkinMissing', ...
        'A full-body regression image has no confirmed body skin.');
end
end

function energy = textureEnergy(imageData, mask, faceScale)
if nnz(mask) < 16
    energy = NaN;
    return;
end
gray = im2double(rgb2gray(imageData));
base = imgaussfilt(gray, max(1, .008 * faceScale), 'Padding', 'replicate');
residual = abs(gray - base);
energy = mean(residual(mask));
end

function box = scaleBox(box, scale, imageSize)
box = round(double(box) * scale);
box(1) = max(1, min(box(1), imageSize(2)));
box(2) = max(1, min(box(2), imageSize(1)));
x2 = min(imageSize(2), box(1) + box(3) - 1);
y2 = min(imageSize(1), box(2) + box(4) - 1);
box(3:4) = max(1, [x2 - box(1) + 1, y2 - box(2) + 1]);
end

function jump = boundaryJump(difference, box)
height = size(difference, 1);
width = size(difference, 2);
x1 = max(3, min(width - 2, round(box(1))));
y1 = max(3, min(height - 2, round(box(2))));
x2 = max(3, min(width - 2, round(box(1) + box(3) - 1)));
y2 = max(3, min(height - 2, round(box(2) + box(4) - 1)));
jumps = [ ...
    abs(mean(difference(y1:y2, x1:x1 + 1), 'all') - ...
        mean(difference(y1:y2, x1 - 2:x1 - 1), 'all')), ...
    abs(mean(difference(y1:y2, x2 - 1:x2), 'all') - ...
        mean(difference(y1:y2, x2 + 1:x2 + 2), 'all')), ...
    abs(mean(difference(y1:y1 + 1, x1:x2), 'all') - ...
        mean(difference(y1 - 2:y1 - 1, x1:x2), 'all')), ...
    abs(mean(difference(y2 - 1:y2, x1:x2), 'all') - ...
        mean(difference(y2 + 1:y2 + 2, x1:x2), 'all'))];
jump = max(jumps);
end
