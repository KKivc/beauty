function [faceBox, isSingleFace, details] = detectSingleFace(inputImage, options)
%DETECTSINGLEFACE Cascade 快检后用 BiSeNet 校验并定位单张语义人脸。

% 只接收三通道 RGB 图像，灰度图或带 alpha 通道的图像不进入检测流程。
if ~isnumeric(inputImage) || ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('detectSingleFace:InvalidImage', ...
        'inputImage must be a three-channel RGB image.');
end

if nargin < 2 || isempty(options)
    options = struct();
elseif ~isstruct(options)
    error('detectSingleFace:InvalidOptions', 'options must be a struct.');
end

imageHeight = size(inputImage, 1);
imageWidth = size(inputImage, 2);
parsingImage = im2uint8(inputImage);
minimumFaceSize = max(24, 0.06 * min(imageWidth, imageHeight));
details = struct('candidateAssessment', [], 'usedFullImageParsing', false, ...
    'fullParsingCount', 0, 'selectedCandidateBox', zeros(0, 4), ...
    'selectedParsing', [], 'orientationDegrees', 0, ...
    'orientationScores', [], 'orientationParsingCount', 0);

if isfield(options, 'candidateBoxes')
    candidateBoxes = options.candidateBoxes;
    if ~isnumeric(candidateBoxes) || size(candidateBoxes, 2) ~= 4
        error('detectSingleFace:InvalidCandidateBoxes', ...
            'candidateBoxes must be an Nx4 numeric matrix.');
    end
    candidateBoxes = filterCandidateBoxes(candidateBoxes, minimumFaceSize, ...
        imageWidth, imageHeight);
else
    if exist('vision.CascadeObjectDetector', 'class') == 0 || ...
            exist('imrotate', 'file') == 0
        error('detectSingleFace:MissingToolbox', ...
            ['Computer Vision Toolbox and Image Processing Toolbox are ' ...
            'required for face detection.']);
    end
    scale = min(1, 1280 / max(imageWidth, imageHeight));
    if scale < 1
        detectionImage = imresize(inputImage, scale, 'bilinear');
    else
        detectionImage = inputImage;
    end

    % 先尝试未旋转正脸，只有失败时才增加角度和 profile 扫描。
    candidateBoxes = detectCandidates(detectionImage, scale, ...
        {'FrontalFaceCART', 'FrontalFaceLBP'}, 0);
    candidateBoxes = filterCandidateBoxes(candidateBoxes, minimumFaceSize, imageWidth, imageHeight);
    if isempty(candidateBoxes)
        candidateBoxes = detectCandidates(detectionImage, scale, ...
            {'FrontalFaceCART', 'FrontalFaceLBP'}, [-20, -10, 10, 20]);
        candidateBoxes = filterCandidateBoxes(candidateBoxes, minimumFaceSize, imageWidth, imageHeight);
    end
    if isempty(candidateBoxes)
        candidateBoxes = detectCandidates(detectionImage, scale, {'ProfileFace'}, ...
            [-20, 0, 20]);
        candidateBoxes = filterCandidateBoxes(candidateBoxes, minimumFaceSize, imageWidth, imageHeight);
    end
    if isempty(candidateBoxes)
        % 极端姿态才启用 ±30° 全模型兜底，避免拖慢常见正脸路径。
        candidateBoxes = detectCandidates(detectionImage, scale, ...
            {'FrontalFaceCART', 'FrontalFaceLBP', 'ProfileFace'}, [-30, 30]);
        candidateBoxes = filterCandidateBoxes(candidateBoxes, minimumFaceSize, imageWidth, imageHeight);
    end
end

if isempty(candidateBoxes)
    [faceBox, isSingleFace, details] = fullImageFallback( ...
        parsingImage, options, details);
    [faceBox, isSingleFace, details] = applyOrientationFallback( ...
        parsingImage, options, faceBox, isSingleFace, details);
    return;
end

% 选择最大且相对居中的候选框，忽略较小的背景人脸和眼部误检。
imageCenter = [imageWidth, imageHeight] / 2;
boxCenters = candidateBoxes(:, 1:2) + candidateBoxes(:, 3:4) / 2;
centerDistance = hypot((boxCenters(:, 1) - imageCenter(1)) / imageWidth, ...
    (boxCenters(:, 2) - imageCenter(2)) / imageHeight);
boxArea = candidateBoxes(:, 3) .* candidateBoxes(:, 4);
score = boxArea .* max(0.65, 1 - 0.35 * centerDistance);
[~, bestIndex] = max(score);
candidateBox = candidateBoxes(bestIndex, :);
details.selectedCandidateBox = candidateBox;
localParsing = obtainParsing(parsingImage, candidateBox, options, ...
    'localParsing', 'local');
[isWrongBox, isTruncated, assessment] = assessSemanticFaceCandidate( ...
    localParsing, candidateBox, size(inputImage));
details.candidateAssessment = assessment;
if isWrongBox || isTruncated
    [faceBox, isSingleFace, details] = fullImageFallback( ...
        parsingImage, options, details);
else
    details.selectedParsing = localParsing;
    [faceBox, isSingleFace] = semanticFaceBoxFromParsing( ...
        localParsing, size(inputImage));
end
[faceBox, isSingleFace, details] = applyOrientationFallback( ...
    parsingImage, options, faceBox, isSingleFace, details);
end

function parsing = obtainParsing(inputImage, faceBox, options, fieldName, phase)
if isfield(options, fieldName) && ~isempty(options.(fieldName))
    parsing = parseFaceRegions(inputImage, faceBox, options.(fieldName));
elseif isfield(options, 'parsingRunner') && ~isempty(options.parsingRunner)
    if ~isa(options.parsingRunner, 'function_handle')
        error('detectSingleFace:InvalidParsingRunner', ...
            'parsingRunner must be a function handle.');
    end
    injected = options.parsingRunner(inputImage, faceBox, phase);
    parsing = parseFaceRegions(inputImage, faceBox, injected);
else
    parsing = parseFaceRegions(inputImage, faceBox);
end
end

function [faceBox, isSingleFace, details] = fullImageFallback( ...
        inputImage, options, details)
imageHeight = size(inputImage, 1);
imageWidth = size(inputImage, 2);
fullImageBox = [1, 1, imageWidth, imageHeight];
details.usedFullImageParsing = true;
details.fullParsingCount = details.fullParsingCount + 1;
fullParsing = obtainParsing(inputImage, fullImageBox, options, ...
    'fullParsing', 'full');
details.selectedParsing = fullParsing;
[faceBox, isSingleFace] = semanticFaceBoxFromParsing( ...
    fullParsing, size(inputImage));
end

function [faceBox, isSingleFace, details] = applyOrientationFallback( ...
        inputImage, options, faceBox, isSingleFace, details)
if isempty(details.selectedParsing)
    return;
end
bestAssessment = scoreFaceParsingOrientation(details.selectedParsing);
details.orientationScores = makeOrientationRecord(0, bestAssessment);
if ~bestAssessment.needsFallback || ~orientationFallbackEnabled(options)
    return;
end

bestAngle = 0;
bestParsing = details.selectedParsing;
bestBox = faceBox;
bestHasFace = isSingleFace;
for angle = [-90, 90, 180]
    rotatedImage = rot90(inputImage, angle / 90);
    rotatedBox = [1, 1, size(rotatedImage, 2), size(rotatedImage, 1)];
    rotatedParsing = obtainOrientationParsing( ...
        rotatedImage, rotatedBox, options, angle);
    details.orientationParsingCount = details.orientationParsingCount + 1;
    assessment = scoreFaceParsingOrientation(rotatedParsing);
    details.orientationScores(end + 1) = ...
        makeOrientationRecord(angle, assessment);
    if assessment.score > bestAssessment.score
        mappedParsing = rotateFaceParsing( ...
            rotatedParsing, -angle, size(inputImage));
        [mappedBox, hasMappedFace] = semanticFaceBoxFromParsing( ...
            mappedParsing, size(inputImage));
        if hasMappedFace
            bestAssessment = assessment;
            bestAngle = angle;
            bestParsing = mappedParsing;
            bestBox = mappedBox;
            bestHasFace = true;
        end
    end
    if assessment.isStrong
        break;
    end
end
if bestAngle ~= 0
    faceBox = bestBox;
    isSingleFace = bestHasFace;
    details.selectedParsing = bestParsing;
    details.orientationDegrees = bestAngle;
    details.usedFullImageParsing = true;
end
end

function enabled = orientationFallbackEnabled(options)
if isfield(options, 'enableOrientationFallback')
    enabled = logical(options.enableOrientationFallback);
    return;
end
hasLegacyInjection = any(isfield(options, ...
    {'localParsing', 'fullParsing', 'parsingRunner', 'candidateBoxes'}));
enabled = ~hasLegacyInjection || isfield(options, 'orientationRunner');
end

function parsing = obtainOrientationParsing( ...
        rotatedImage, rotatedBox, options, angle)
if isfield(options, 'orientationRunner') && ~isempty(options.orientationRunner)
    if ~isa(options.orientationRunner, 'function_handle')
        error('detectSingleFace:InvalidOrientationRunner', ...
            'orientationRunner must be a function handle.');
    end
    injected = options.orientationRunner(rotatedImage, rotatedBox, angle);
    parsing = parseFaceRegions(rotatedImage, rotatedBox, injected);
else
    parsing = parseFaceRegions(rotatedImage, rotatedBox);
end
end

function record = makeOrientationRecord(angle, assessment)
record = struct('angle', angle, 'score', assessment.score, ...
    'featureCount', assessment.featureCount, ...
    'hasNose', assessment.hasNose, ...
    'hasLipGroup', assessment.hasLipGroup, ...
    'hasEyeBrow', assessment.hasEyeBrow, ...
    'skinCoverage', assessment.skinCoverage, ...
    'isStrong', assessment.isStrong);
end

function validBoxes = filterCandidateBoxes(boxes, minimumFaceSize, imageWidth, imageHeight)
if isempty(boxes)
    validBoxes = zeros(0, 4);
    return;
end
valid = all(isfinite(boxes), 2) & boxes(:, 1) >= 1 & boxes(:, 2) >= 1 & ...
    boxes(:, 3) >= minimumFaceSize & boxes(:, 4) >= minimumFaceSize & ...
    boxes(:, 1) + boxes(:, 3) - 1 <= imageWidth & ...
    boxes(:, 2) + boxes(:, 4) - 1 <= imageHeight;
validBoxes = boxes(valid, :);
end

function mappedCandidates = detectCandidates(image, scale, modelNames, angles)
persistent frontalCart frontalLbp profile
detectors = cell(1, numel(modelNames));
for index = 1:numel(modelNames)
    switch modelNames{index}
        case 'FrontalFaceCART'
            if isempty(frontalCart), frontalCart = vision.CascadeObjectDetector( ...
                    'FrontalFaceCART', 'MergeThreshold', 3); end
            detectors{index} = frontalCart;
        case 'FrontalFaceLBP'
            if isempty(frontalLbp), frontalLbp = vision.CascadeObjectDetector( ...
                    'FrontalFaceLBP', 'MergeThreshold', 3); end
            detectors{index} = frontalLbp;
        otherwise
            if isempty(profile), profile = vision.CascadeObjectDetector( ...
                    'ProfileFace', 'MergeThreshold', 3); end
            detectors{index} = profile;
    end
end
imageHeight = size(image, 1);
imageWidth = size(image, 2);
mappedCandidates = zeros(0, 4);
for detectorIndex = 1:numel(detectors)
    for angle = angles
        if angle == 0
            rotatedImage = image;
        else
            rotatedImage = imrotate(image, angle, 'bilinear', 'crop');
        end
        detectedBoxes = step(detectors{detectorIndex}, rotatedImage);
        boxes = mapRotatedBoxesToImage(detectedBoxes, angle, imageWidth, imageHeight);
        if ~isempty(boxes)
            boxes = boxes / scale;
            mappedCandidates = [mappedCandidates; boxes]; %#ok<AGROW>
        end
    end
end
end

function mappedBoxes = mapRotatedBoxesToImage(boxes, angle, imageWidth, imageHeight)
if isempty(boxes)
    mappedBoxes = zeros(0, 4);
    return;
end

center = [(imageWidth + 1) / 2, (imageHeight + 1) / 2];
theta = angle * pi / 180;
cosTheta = cos(theta);
sinTheta = sin(theta);
mappedBoxes = zeros(size(boxes));
for index = 1:size(boxes, 1)
    box = boxes(index, :);
    corners = [box(1), box(2); box(1) + box(3), box(2); ...
        box(1), box(2) + box(4); box(1) + box(3), box(2) + box(4)];
    delta = corners - center;
    originalCorners = [cosTheta * delta(:, 1) - sinTheta * delta(:, 2), ...
        sinTheta * delta(:, 1) + cosTheta * delta(:, 2)] + center;
    x1 = max(1, min(originalCorners(:, 1)));
    y1 = max(1, min(originalCorners(:, 2)));
    x2 = min(imageWidth, max(originalCorners(:, 1)));
    y2 = min(imageHeight, max(originalCorners(:, 2)));
    mappedBoxes(index, :) = [x1, y1, max(0, x2 - x1), max(0, y2 - y1)];
end
end
