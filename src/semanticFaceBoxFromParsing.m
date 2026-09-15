function [faceBox, hasSemanticFace] = semanticFaceBoxFromParsing(parsing, imageSize)
%SEMANTICFACEBOXFROMPARSING 从最大人脸语义连通域生成裁剪后的边界框。
if ~isstruct(parsing) || ~isfield(parsing, 'regions') || numel(imageSize) < 2
    error('semanticFaceBoxFromParsing:InvalidInput', ...
        'Parsing regions and image size are required.');
end
imageHeight = imageSize(1);
imageWidth = imageSize(2);
regionNames = {'skin', 'nose', 'leftEar', 'rightEar', 'leftEye', ...
    'rightEye', 'leftBrow', 'rightBrow', 'mouth', 'upperLip', 'lowerLip'};
semanticMask = false(imageHeight, imageWidth);
for index = 1:numel(regionNames)
    threshold = 0.5;
    if strcmp(regionNames{index}, 'skin')
        threshold = 0.35;
    end
    semanticMask = semanticMask | classEvidence(parsing, regionNames{index}, threshold);
end

components = bwconncomp(semanticMask, 8);
if components.NumObjects == 0
    faceBox = zeros(0, 4);
    hasSemanticFace = false;
    return;
end
componentSizes = cellfun(@numel, components.PixelIdxList);
[~, largestIndex] = max(componentSizes);
[rows, cols] = ind2sub([imageHeight, imageWidth], ...
    components.PixelIdxList{largestIndex});
x1 = min(cols);
x2 = max(cols);
y1 = min(rows);
y2 = max(rows);
componentWidth = x2 - x1 + 1;
componentHeight = y2 - y1 + 1;
horizontalPadding = ceil(0.05 * componentWidth);
verticalPadding = ceil(0.10 * componentHeight);
x1 = max(1, x1 - horizontalPadding);
x2 = min(imageWidth, x2 + horizontalPadding);
y1 = max(1, y1 - verticalPadding);
y2 = min(imageHeight, y2 + verticalPadding);
faceBox = [x1, y1, x2 - x1 + 1, y2 - y1 + 1];
hasSemanticFace = true;
end

function mask = classEvidence(parsing, name, threshold)
names = faceParsingClassNames();
classIndex = find(strcmp(names, name), 1);
if isfield(parsing, 'hardLabels') && ~isempty(parsing.hardLabels)
    mask = parsing.hardLabels == classIndex;
elseif isfield(parsing, 'regionConfidence') && ...
        isfield(parsing.regionConfidence, name)
    mask = parsing.regionConfidence.(name) > threshold;
elseif isfield(parsing.regions, name)
    mask = parsing.regions.(name) > threshold;
else
    fields = fieldnames(parsing.regions);
    mask = false(size(parsing.regions.(fields{1})));
end
end
