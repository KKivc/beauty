function [isWrongBox, isTruncated, details] = assessSemanticFaceCandidate( ...
        parsing, candidateBox, imageSize)
%ASSESSSEMANTICFACECANDIDATE 用语义证据判断候选框是否错误或截断。
validateInputs(parsing, candidateBox, imageSize);
imageHeight = imageSize(1);
imageWidth = imageSize(2);
[rows, cols] = clippedBoxIndices(candidateBox, imageHeight, imageWidth);

featureNames = {'nose', 'leftEar', 'rightEar', 'leftEye', 'rightEye', ...
    'leftBrow', 'rightBrow', 'mouth', 'upperLip', 'lowerLip'};
featureCount = 0;
for index = 1:numel(featureNames)
    evidence = classEvidence(parsing, featureNames{index}, 0.5);
    featureCount = featureCount + any(evidence(rows, cols), 'all');
end

skinAlpha = regionAlpha(parsing, 'skin');
skinCoverage = mean(skinAlpha(rows, cols) > 0.35, 'all');
% 两个条件必须同时成立；等于阈值不判错。
isWrongBox = featureCount < 3 && skinCoverage < 0.05;

if isfield(parsing, 'roiBox')
    roiBox = parsing.roiBox;
else
    roiBox = candidateBox;
end
edgeMeans = interiorEdgeMeans(skinAlpha, roiBox, imageHeight, imageWidth);
isTruncated = any(edgeMeans > 0.10);
details = struct('featureCount', featureCount, ...
    'skinCoverage', skinCoverage, 'edgeSkinMeans', edgeMeans, ...
    'isSuspicious', isWrongBox || isTruncated);
end

function validateInputs(parsing, candidateBox, imageSize)
if ~isstruct(parsing) || ~isfield(parsing, 'regions')
    error('assessSemanticFaceCandidate:InvalidParsing', ...
        'Parsing must contain regions.');
end
if ~isnumeric(candidateBox) || ~isequal(size(candidateBox), [1, 4]) || ...
        any(~isfinite(candidateBox)) || any(candidateBox(3:4) <= 0)
    error('assessSemanticFaceCandidate:InvalidFaceBox', ...
        'Candidate box must be a finite positive rectangle.');
end
if numel(imageSize) < 2 || any(imageSize(1:2) < 1)
    error('assessSemanticFaceCandidate:InvalidImageSize', ...
        'Image size must contain positive height and width.');
end
end

function [rows, cols] = clippedBoxIndices(box, imageHeight, imageWidth)
x1 = max(1, floor(box(1)));
y1 = max(1, floor(box(2)));
x2 = min(imageWidth, ceil(box(1) + box(3) - 1));
y2 = min(imageHeight, ceil(box(2) + box(4) - 1));
if x2 < x1 || y2 < y1
    error('assessSemanticFaceCandidate:InvalidFaceBox', ...
        'Candidate box does not intersect the image.');
end
rows = y1:y2;
cols = x1:x2;
end

function mask = classEvidence(parsing, name, threshold)
names = faceParsingClassNames();
classIndex = find(strcmp(names, name), 1);
if isfield(parsing, 'hardLabels') && ~isempty(parsing.hardLabels)
    mask = parsing.hardLabels == classIndex;
else
    mask = regionAlpha(parsing, name) > threshold;
end
end

function alpha = regionAlpha(parsing, name)
if isfield(parsing, 'regionConfidence') && ...
        isfield(parsing.regionConfidence, name)
    alpha = parsing.regionConfidence.(name);
elseif isfield(parsing.regions, name)
    alpha = parsing.regions.(name);
else
    fields = fieldnames(parsing.regions);
    reference = parsing.regions.(fields{1});
    alpha = zeros(size(reference));
end
end

function edgeMeans = interiorEdgeMeans(skinAlpha, roiBox, imageHeight, imageWidth)
x1 = max(1, floor(roiBox(1)));
y1 = max(1, floor(roiBox(2)));
x2 = min(imageWidth, ceil(roiBox(1) + roiBox(3) - 1));
y2 = min(imageHeight, ceil(roiBox(2) + roiBox(4) - 1));
edgeMeans = zeros(1, 4);
if x2 < x1 || y2 < y1
    return;
end
if x1 > 1
    edgeMeans(1) = mean(skinAlpha(y1:y2, x1:min(x1 + 1, x2)), 'all');
end
if x2 < imageWidth
    edgeMeans(2) = mean(skinAlpha(y1:y2, max(x1, x2 - 1):x2), 'all');
end
if y1 > 1
    edgeMeans(3) = mean(skinAlpha(y1:min(y1 + 1, y2), x1:x2), 'all');
end
if y2 < imageHeight
    edgeMeans(4) = mean(skinAlpha(max(y1, y2 - 1):y2, x1:x2), 'all');
end
end
