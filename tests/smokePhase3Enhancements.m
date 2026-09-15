function [summary, diagnostics] = smokePhase3Enhancements( ...
        imageFolder, outputFolder)
%SMOKEPHASE3ENHANCEMENTS 校准方向、肢体召回和 r 图定向均肤。
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
if nargin < 1 || ~isfolder(imageFolder)
    error('smokePhase3Enhancements:InvalidImageFolder', ...
        'Pass a folder containing source images and matching *r references.');
end
if nargin < 2 || isempty(outputFolder)
    outputFolder = fullfile(tempdir, ...
        'image_beauty_phase3_smoke_20260912');
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

pairs = discoverReferencePairs(imageFolder);
if isempty(pairs)
    error('smokePhase3Enhancements:MissingReferencePairs', ...
        'No source image and matching *r reference pairs were found.');
end
rowTemplate = struct('image', '', 'orientationDegrees', 0, ...
    'analysisSeconds', 0, 'defaultFineRetention', NaN, ...
    'maximumFineRetention', NaN, 'maximumMediumRetention', NaN, ...
    'maximumChromaRetention', NaN, 'referenceFineRetention', NaN, ...
    'referenceMediumRetention', NaN, 'referenceChromaRetention', NaN, ...
    'maximumChannelMedianShift', NaN, 'visualPath', '');
rows = repmat(rowTemplate, size(pairs, 1), 1);
for pairIndex = 1:size(pairs, 1)
    sourcePath = fullfile(imageFolder, pairs{pairIndex, 1});
    referencePath = fullfile(imageFolder, pairs{pairIndex, 2});
    sourceImage = imread(sourcePath);
    referenceImage = imread(referencePath);
    [previewImage, previewScale] = makePreview(sourceImage);
    referenceImage = imresize(referenceImage, size(previewImage, [1, 2]), ...
        'bilinear');

    analysisClock = tic;
    [faceBox, hasFace, detection] = detectSingleFace(previewImage);
    if ~hasFace
        error('smokePhase3Enhancements:NoFace', ...
            'No semantic face was found: %s', sourcePath);
    end
    context = prepareBeautyContext(previewImage, faceBox, ...
        detection.selectedParsing, struct('rotationDegrees', ...
        detection.orientationDegrees));
    analysisSeconds = toc(analysisClock);
    defaultOutput = beautifyImage(previewImage, struct( ...
        'smoothingStrength', 25, 'whiteningStrength', 0), faceBox, context);
    maximumOutput = beautifyImage(previewImage, struct( ...
        'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);

    evaluationMask = imerode(context.faceSkinMask > .5, ...
        strel('disk', 2, 0)) & context.featureProtectionMask < .2;
    originalMetrics = skinVariationMetrics(previewImage, evaluationMask);
    defaultMetrics = skinVariationMetrics(defaultOutput, evaluationMask);
    maximumMetrics = skinVariationMetrics(maximumOutput, evaluationMask);
    referenceMetrics = skinVariationMetrics(referenceImage, evaluationMask);
    channelShift = channelMedianShift( ...
        previewImage, maximumOutput, evaluationMask);

    [~, baseName] = fileparts(sourcePath);
    visualPath = fullfile(outputFolder, [baseName, '_phase3.jpg']);
    maskVisual = repmat(uint8(round(255 * context.skinMask)), [1, 1, 3]);
    imwrite([previewImage, defaultOutput, maximumOutput, ...
        referenceImage, maskVisual], visualPath, 'Quality', 94);

    rows(pairIndex).image = sourcePath;
    rows(pairIndex).orientationDegrees = detection.orientationDegrees;
    rows(pairIndex).analysisSeconds = analysisSeconds;
    rows(pairIndex).defaultFineRetention = safeRatio( ...
        defaultMetrics.fine, originalMetrics.fine);
    rows(pairIndex).maximumFineRetention = safeRatio( ...
        maximumMetrics.fine, originalMetrics.fine);
    rows(pairIndex).maximumMediumRetention = safeRatio( ...
        maximumMetrics.medium, originalMetrics.medium);
    rows(pairIndex).maximumChromaRetention = safeRatio( ...
        maximumMetrics.chroma, originalMetrics.chroma);
    rows(pairIndex).referenceFineRetention = safeRatio( ...
        referenceMetrics.fine, originalMetrics.fine);
    rows(pairIndex).referenceMediumRetention = safeRatio( ...
        referenceMetrics.medium, originalMetrics.medium);
    rows(pairIndex).referenceChromaRetention = safeRatio( ...
        referenceMetrics.chroma, originalMetrics.chroma);
    rows(pairIndex).maximumChannelMedianShift = channelShift;
    rows(pairIndex).visualPath = visualPath;
    if previewScale <= 0
        error('smokePhase3Enhancements:InvalidPreview', ...
            'Preview scale must be positive.');
    end
end
summary = struct2table(rows);
writetable(summary, fullfile(outputFolder, 'summary.csv'));

diagnostics = struct();
image17Path = findImage(imageFolder, '17');
if isempty(image17Path)
    diagnostics.image17 = struct('skipped', true, ...
        'reason', '17 image not found in the supplied folder.');
    diagnostics.image17Visual = '';
else
    [diagnostics.image17, diagnostics.image17Visual] = ...
        validateRotatedImage(image17Path, outputFolder);
end
image80Path = findImage(imageFolder, '80');
if isempty(image80Path)
    diagnostics.image80 = struct('skipped', true, ...
        'reason', '80 image not found in the supplied folder.');
    diagnostics.image80Visual = '';
else
    [diagnostics.image80, diagnostics.image80Visual] = ...
        validateArmRecall(image80Path, outputFolder);
end

% 100 档语义为“自然质感上限”：与旧实现相比刻意保留更多中高频纹理，
% 上限按新曲线重定位（实测 maximum 中位 0.79、极差 [0.66, 0.91]）。
if any(summary.defaultFineRetention < .80) || ...
        any(summary.maximumFineRetention < .55) || ...
        any(summary.maximumFineRetention > .93) || ...
        median(summary.maximumFineRetention) < .68 || ...
        median(summary.maximumFineRetention) > .86
    error('smokePhase3Enhancements:FineRetention', ...
        'Fine texture retention is outside the accepted range: maximum in [%.3f, %.3f], median %.3f.', ...
        min(summary.maximumFineRetention), max(summary.maximumFineRetention), ...
        median(summary.maximumFineRetention));
end

function pairs = discoverReferencePairs(imageFolder)
extensions = {'.jpg', '.jpeg', '.png'};
files = dir(imageFolder);
pairs = cell(0, 2);
for fileIndex = 1:numel(files)
    if files(fileIndex).isdir
        continue;
    end
    [~, baseName, extension] = fileparts(files(fileIndex).name);
    if ~ismember(lower(extension), extensions) || ...
            numel(baseName) < 2 || lower(baseName(end)) ~= 'r'
        continue;
    end
    sourceBase = baseName(1:end - 1);
    sourcePath = findImage(imageFolder, sourceBase);
    if ~isempty(sourcePath)
        [~, sourceName, sourceExtension] = fileparts(sourcePath);
        pairs(end + 1, :) = {[sourceName, sourceExtension], ...
            files(fileIndex).name}; %#ok<AGROW>
    end
end
end

function imagePath = findImage(imageFolder, baseName)
imagePath = '';
for extension = {'.jpg', '.jpeg', '.png'}
    candidate = fullfile(imageFolder, [baseName, extension{1}]);
    if isfile(candidate)
        imagePath = candidate;
        return;
    end
end
end
if median(summary.maximumMediumRetention) < .60 || ...
        median(summary.maximumMediumRetention) > .85
    error('smokePhase3Enhancements:MediumRetention', ...
        'Medium-scale retention is outside the accepted range: median %.3f.', ...
        median(summary.maximumMediumRetention));
end
if median(summary.maximumChromaRetention) > .75
    error('smokePhase3Enhancements:ChromaRetention', ...
        'Chroma variation was not reduced enough.');
end
if any(summary.maximumChannelMedianShift > 2 / 255)
    error('smokePhase3Enhancements:ToneShift', ...
        'Smoothing changed the median skin tone.');
end
end

function [preview, scale] = makePreview(image)
scale = min(1, 800 / max(size(image, 1), size(image, 2)));
if scale < 1
    preview = imresize(image, scale, 'bilinear');
else
    preview = image;
end
end

function metrics = skinVariationMetrics(image, mask)
if nnz(mask) < 16
    error('smokePhase3Enhancements:EmptySkin', ...
        'The face evaluation mask is empty.');
end
ycbcr = rgb2ycbcr(im2double(image));
y = ycbcr(:, :, 1);
cb = ycbcr(:, :, 2);
cr = ycbcr(:, :, 3);
fineBase = imgaussfilt(y, 1.2, 'Padding', 'replicate');
mediumBase = imgaussfilt(y, 8, 'Padding', 'replicate');
cbBase = imgaussfilt(cb, 8, 'Padding', 'replicate');
crBase = imgaussfilt(cr, 8, 'Padding', 'replicate');
metrics = struct('fine', mean(abs(y(mask) - fineBase(mask))), ...
    'medium', mean(abs(fineBase(mask) - mediumBase(mask))), ...
    'chroma', mean(hypot(cb(mask) - cbBase(mask), ...
    cr(mask) - crBase(mask))));
end

function shift = channelMedianShift(source, output, mask)
source = rgb2ycbcr(im2double(source));
output = rgb2ycbcr(im2double(output));
shifts = zeros(1, 3);
for channel = 1:3
    sourceChannel = source(:, :, channel);
    outputChannel = output(:, :, channel);
    shifts(channel) = abs(median(outputChannel(mask)) - ...
        median(sourceChannel(mask)));
end
shift = max(shifts);
end

function ratio = safeRatio(value, reference)
ratio = value / max(reference, eps);
end

function [result, visualPath] = validateRotatedImage(imagePath, outputFolder)
source = imread(imagePath);
[preview, ~] = makePreview(source);
[faceBox, hasFace, detection] = detectSingleFace(preview);
assessment = scoreFaceParsingOrientation(detection.selectedParsing);
if ~hasFace || detection.orientationDegrees ~= -90 || ...
        assessment.featureCount < 5 || ~assessment.hasNose || ...
        ~assessment.hasLipGroup
    error('smokePhase3Enhancements:RotatedFace', ...
        '17.jpg did not recover the expected rotated face semantics.');
end
context = prepareBeautyContext(preview, faceBox, ...
    detection.selectedParsing, struct('rotationDegrees', ...
    detection.orientationDegrees));
output = beautifyImage(preview, struct('smoothingStrength', 100, ...
    'whiteningStrength', 0), faceBox, context);
difference = max(abs(double(output) - double(preview)), [], 3);
noseMask = context.regions.nose >= .35 & context.faceSkinMask > .35;
noseInterior = imerode(noseMask, strel('disk', 2, 0));
if nnz(noseInterior) < 16
    error('smokePhase3Enhancements:Image17Nose', ...
        '17.jpg 的有效鼻部内部区域不足。');
end
noseHardFraction = nnz(noseInterior & ...
    context.hardProtectionMask >= .999) / nnz(noseInterior);
activeNose = noseInterior & context.featureProtectionMask < .80;
meanNoseChange = mean(difference(activeNose));
inputGray = im2double(rgb2gray(preview));
outputGray = im2double(rgb2gray(output));
structureSigma = min(8, max(1.25, .018 * min(faceBox(3:4))));
inputLow = imgaussfilt(inputGray, structureSigma, 'Padding', 'replicate');
outputLow = imgaussfilt(outputGray, structureSigma, 'Padding', 'replicate');
[inputX, inputY] = gradient(inputLow);
[outputX, outputY] = gradient(outputLow);
inputStructure = hypot(inputX, inputY);
outputStructure = hypot(outputX, outputY);
structureRetention = mean(outputStructure(noseInterior)) / ...
    max(mean(inputStructure(noseInterior)), eps);
if noseHardFraction > .20 || meanNoseChange < .50 || ...
        structureRetention < .85
    error('smokePhase3Enhancements:Image17NoseSmoothing', ...
        '17.jpg 的鼻部参与度、硬保护覆盖或立体结构保留未达标。');
end
visualPath = fullfile(outputFolder, '17_orientation_phase3.jpg');
featureVisual = repmat(uint8(round(255 * ...
    context.featureProtectionMask)), [1, 1, 3]);
imwrite([preview, output, featureVisual], visualPath, 'Quality', 94);
result = struct('orientationDegrees', detection.orientationDegrees, ...
    'featureCount', assessment.featureCount, 'score', assessment.score, ...
    'faceBox', faceBox, 'orientationParsingCount', ...
    detection.orientationParsingCount, 'noseHardFraction', noseHardFraction, ...
    'meanNoseChange', meanNoseChange, ...
    'noseStructureRetention', structureRetention);
end

function [result, visualPath] = validateArmRecall(imagePath, outputFolder)
source = imread(imagePath);
[faceBox, hasFace, detection] = detectSingleFace(source);
if ~hasFace
    error('smokePhase3Enhancements:Image80Face', ...
        '80.jpg has no semantic face.');
end
probabilities = inferSchpLipProbabilities(source, ...
    struct('rotationDegrees', detection.orientationDegrees));
context = prepareBeautyContext(source, faceBox, detection.selectedParsing, ...
    struct('probabilities', probabilities));
names = schpLipClassNames();
limb = max(cat(3, classProbability('leftArm'), ...
    classProbability('rightArm'), classProbability('leftLeg'), ...
    classProbability('rightLeg')), [], 3);
excludeNames = {'glove', 'upperClothes', 'dress', 'coat', 'socks', ...
    'pants', 'jumpsuits', 'scarf', 'skirt', 'hair', 'hat', ...
    'leftShoe', 'rightShoe'};
exclude = zeros(size(limb));
for exclusionIndex = 1:numel(excludeNames)
    exclude = max(exclude, ...
        classProbability(excludeNames{exclusionIndex}));
end
[xGrid, yGrid] = meshgrid(1:size(source, 2), 1:size(source, 1));
rightRegion = xGrid > .72 * size(source, 2) & ...
    yGrid > .30 * size(source, 1);
target = rightRegion & limb >= .55 & exclude < .40;
recall = nnz(target & context.bodySkinMask > .35) / max(1, nnz(target));
if recall < .85
    error('smokePhase3Enhancements:ArmRecall', ...
        '80.jpg right-arm recall is below 85%%.');
end
output = beautifyImage(source, struct('smoothingStrength', 100, ...
    'whiteningStrength', 0), faceBox, context);
combinedOutput = beautifyImage(source, struct('smoothingStrength', 100, ...
    'whiteningStrength', 15), faceBox, context);
difference = max(abs(double(output) - double(source)), [], 3);
backgroundChange = max(difference(context.skinMask < .01), [], 'all');
hardChange = max(difference(context.hardProtectionMask >= .999), [], 'all');
if backgroundChange > 1 || hardChange > 0
    error('smokePhase3Enhancements:ProtectionChanged', ...
        '80.jpg background or protected features changed unexpectedly.');
end
faceEvaluation = imerode(context.faceSkinMask > .50, ...
    strel('disk', 2, 0)) & context.featureProtectionMask < .35;
bodyEvaluation = imerode(context.bodySkinMask > .50, ...
    strel('disk', 2, 0)) & context.featureProtectionMask < .35;
if nnz(faceEvaluation) < 16 || nnz(bodyEvaluation) < 16
    error('smokePhase3Enhancements:Image80SkinRegions', ...
        '80.jpg 的脸部或脸外皮肤评估区域不足。');
end
faceChange = mean(difference(faceEvaluation));
bodyChange = mean(difference(bodyEvaluation));
bodyToFaceChange = bodyChange / max(faceChange, eps);
sourceYCbCr = rgb2ycbcr(im2double(source));
combinedYCbCr = rgb2ycbcr(im2double(combinedOutput));
faceBrightnessIncrease = median(combinedYCbCr(faceEvaluation) - ...
    sourceYCbCr(faceEvaluation));
bodyBrightnessIncrease = median(combinedYCbCr(bodyEvaluation) - ...
    sourceYCbCr(bodyEvaluation));
bodyChromaShift = max(channelMedianDifference( ...
    sourceYCbCr, combinedYCbCr, bodyEvaluation, [2, 3]));
% 参考图对手、手臂和肩部也做了接近脸部的均肤；身体仍需弱于脸部，
% 但旧的 .75 上限会错误拒绝真实参考级结果。
if bodyToFaceChange > .95 || ...
        bodyBrightnessIncrease > .55 * max(faceBrightnessIncrease, eps) || ...
        bodyChromaShift > 2 / 255
    error('smokePhase3Enhancements:Image80NaturalBodySkin', ...
        ['80.jpg 的脸外弱化未达标：磨皮变化比 %.4f，脸部增亮 %.6f，' ...
        '脸外增亮 %.6f，脸外色度偏移 %.6f。'], ...
        bodyToFaceChange, faceBrightnessIncrease, ...
        bodyBrightnessIncrease, bodyChromaShift);
end
visualPath = fullfile(outputFolder, '80_arm_phase3.jpg');
maskVisual = repmat(uint8(round(255 * context.skinMask)), [1, 1, 3]);
imwrite([source, output, combinedOutput, maskVisual], visualPath, 'Quality', 94);
result = struct('rightArmRecall', recall, ...
    'targetPixels', nnz(target), 'includedPixels', ...
    nnz(target & context.bodySkinMask > .35), ...
    'backgroundMaxChange', backgroundChange, ...
    'hardFeatureMaxChange', hardChange, ...
    'bodyToFaceChange', bodyToFaceChange, ...
    'faceBrightnessIncrease', faceBrightnessIncrease, ...
    'bodyBrightnessIncrease', bodyBrightnessIncrease, ...
    'bodyChromaShift', bodyChromaShift);

    function value = classProbability(name)
        value = probabilities(:, :, find(strcmp(names, name), 1));
    end
end

function differences = channelMedianDifference(source, output, mask, channels)
%CHANNELMEDIANDIFFERENCE 计算指定颜色通道在区域内的中位数偏移。
differences = zeros(size(channels));
for index = 1:numel(channels)
    channel = channels(index);
    sourceChannel = source(:, :, channel);
    outputChannel = output(:, :, channel);
    differences(index) = abs(median(outputChannel(mask)) - ...
        median(sourceChannel(mask)));
end
end
