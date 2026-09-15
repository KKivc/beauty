function [softMasks, confidence, hardLabels] = mapFaceParsingOutput(logits, transform, imageSize)
%MAPFACEPARSINGOUTPUT 回映 19 类 logits，并返回置信度与 hard label。
if ~isnumeric(logits) || ndims(logits) ~= 3 || size(logits, 3) ~= 19
    error('mapFaceParsingOutput:InvalidLogits', 'Expected HxWx19 logits.');
end
if numel(imageSize) < 2 || ~isfield(transform, 'roiBox') || ...
        ~isfield(transform, 'scale') || ~isfield(transform, 'padTop') || ...
        ~isfield(transform, 'padLeft')
    error('mapFaceParsingOutput:InvalidTransform', 'Invalid letterbox transform.');
end
% ONNX 主输出通常为 64x64x19；先恢复模型输入尺寸，再去除 letterbox。
logits = imresize(logits, transform.inputSize, 'bilinear');
probabilities = softmax(logits, 3);
[confidence, labels] = max(probabilities, [], 3);
rowStart = transform.padTop + 1;
colStart = transform.padLeft + 1;
if isfield(transform, 'resizedSize')
    resizedSize = transform.resizedSize;
else
    resizedSize = round(transform.roiBox([4, 3]) * transform.scale);
end
rowEnd = min(transform.inputSize(1), rowStart + resizedSize(1) - 1);
colEnd = min(transform.inputSize(2), colStart + resizedSize(2) - 1);
crop = probabilities(rowStart:rowEnd, colStart:colEnd, :);
cropConfidence = confidence(rowStart:rowEnd, colStart:colEnd);
cropLabels = labels(rowStart:rowEnd, colStart:colEnd);
height = imageSize(1);
width = imageSize(2);
softMasks = zeros(height, width, 19);
roiBox = transform.roiBox;
roiRows = roiBox(2):min(height, roiBox(2) + roiBox(4) - 1);
roiCols = roiBox(1):min(width, roiBox(1) + roiBox(3) - 1);
for classIndex = 1:19
    resizedMask = imresize(crop(:, :, classIndex), [numel(roiRows), numel(roiCols)], 'bilinear');
    softMasks(roiRows, roiCols, classIndex) = resizedMask;
end
confidence = zeros(height, width);
hardLabels = zeros(height, width, 'uint8');
confidence(roiRows, roiCols) = imresize(cropConfidence, [numel(roiRows), numel(roiCols)], 'bilinear');
hardLabels(roiRows, roiCols) = uint8(round(imresize(cropLabels, ...
    [numel(roiRows), numel(roiCols)], 'nearest')));
end

function probabilities = softmax(logits, dimension)
shifted = logits - max(logits, [], dimension);
exponent = exp(shifted);
probabilities = exponent ./ max(sum(exponent, dimension), eps('single'));
end
