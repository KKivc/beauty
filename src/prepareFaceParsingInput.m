function [networkInput, transform] = prepareFaceParsingInput(inputImage, faceBox)
%PREPAREFACEPARSINGINPUT 将扩展人脸 ROI 等比例 letterbox 到 512x512。
if ~isa(inputImage, 'uint8') || ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('prepareFaceParsingInput:InvalidImage', 'Expected uint8 RGB image.');
end
if ~isnumeric(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || any(faceBox(3:4) <= 0)
    error('prepareFaceParsingInput:InvalidFaceBox', 'Invalid face rectangle.');
end
[height, width, ~] = size(inputImage);
x1 = max(1, floor(faceBox(1) - 0.20 * faceBox(3)));
y1 = max(1, floor(faceBox(2) - 0.30 * faceBox(4)));
x2 = min(width, ceil(faceBox(1) + 1.20 * faceBox(3) - 1));
y2 = min(height, ceil(faceBox(2) + 1.45 * faceBox(4) - 1));
if x2 < x1 || y2 < y1
    error('prepareFaceParsingInput:InvalidFaceBox', 'Face rectangle is outside image.');
end
roi = inputImage(y1:y2, x1:x2, :);
scale = min(512 / size(roi, 2), 512 / size(roi, 1));
resized = imresize(roi, scale, 'bilinear');
resizedSize = size(resized, [1, 2]);
top = floor((512 - size(resized, 1)) / 2);
left = floor((512 - size(resized, 2)) / 2);
letterboxed = zeros(512, 512, 3, 'uint8');
letterboxed(1 + top:top + size(resized, 1), ...
    1 + left:left + size(resized, 2), :) = resized;
normalized = im2single(letterboxed);
meanValue = reshape(single([0.485, 0.456, 0.406]), 1, 1, 3);
stdValue = reshape(single([0.229, 0.224, 0.225]), 1, 1, 3);
networkInput = (normalized - meanValue) ./ stdValue;
transform = struct('roiBox', [x1, y1, x2 - x1 + 1, y2 - y1 + 1], ...
    'scale', scale, 'padTop', top, 'padLeft', left, ...
    'resizedSize', resizedSize, 'inputSize', [512, 512]);
end
