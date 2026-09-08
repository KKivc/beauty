function [faceBox, isSingleFace] = detectSingleFace(inputImage)
%DETECTSINGLEFACE 检测并返回最显著的前景人脸框。

% 只接收三通道 RGB 图像，灰度图或带 alpha 通道的图像不进入检测流程。
if ~isnumeric(inputImage) || ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('detectSingleFace:InvalidImage', ...
        'inputImage must be a three-channel RGB image.');
end

if exist('vision.CascadeObjectDetector', 'class') == 0 || ...
        exist('imrotate', 'file') == 0
    error('detectSingleFace:MissingToolbox', ...
        'Computer Vision Toolbox and Image Processing Toolbox are required for face detection.');
end

% 主脸可能倾斜，使用多角度和正面/侧面模型收集候选框。
angles = [-30, -20, -10, 0, 10, 20, 30];
models = {'FrontalFaceCART', 'FrontalFaceLBP', 'ProfileFace'};
imageHeight = size(inputImage, 1);
imageWidth = size(inputImage, 2);
candidateBoxes = zeros(0, 4);

for modelIndex = 1:numel(models)
    detector = vision.CascadeObjectDetector(models{modelIndex}, ...
        'MergeThreshold', 3);
    for angle = angles
        rotatedImage = imrotate(inputImage, angle, 'bilinear', 'crop');
        detectedBoxes = step(detector, rotatedImage);
        mappedBoxes = mapRotatedBoxesToImage(detectedBoxes, angle, ...
            imageWidth, imageHeight);
        candidateBoxes = [candidateBoxes; mappedBoxes]; %#ok<AGROW>
    end
end

if isempty(candidateBoxes)
    faceBox = zeros(0, 4);
    isSingleFace = false;
    return;
end

% 选择最大且相对居中的候选框，忽略较小的背景人脸和眼部误检。
minimumFaceSize = max(24, 0.06 * min(imageWidth, imageHeight));
validBoxes = candidateBoxes(:, 3) >= minimumFaceSize & ...
    candidateBoxes(:, 4) >= minimumFaceSize;
 candidateBoxes = candidateBoxes(validBoxes, :);
if isempty(candidateBoxes)
    faceBox = zeros(0, 4);
    isSingleFace = false;
    return;
end
imageCenter = [imageWidth, imageHeight] / 2;
boxCenters = candidateBoxes(:, 1:2) + candidateBoxes(:, 3:4) / 2;
centerDistance = hypot((boxCenters(:, 1) - imageCenter(1)) / imageWidth, ...
    (boxCenters(:, 2) - imageCenter(2)) / imageHeight);
boxArea = candidateBoxes(:, 3) .* candidateBoxes(:, 4);
score = boxArea .* max(0.65, 1 - 0.35 * centerDistance);
[~, bestIndex] = max(score);
faceBox = expandFaceBox(candidateBoxes(bestIndex, :), imageWidth, imageHeight);
isSingleFace = true;
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

function expandedBox = expandFaceBox(faceBox, imageWidth, imageHeight)
% 检测框通常偏向五官区域，向四周扩展以覆盖额头、脸颊和下巴。
expansion = [0.10, 0.15, 1.20, 1.50] .* faceBox([3, 4, 3, 4]);
expandedBox = [faceBox(1) - expansion(1), faceBox(2) - expansion(2), ...
    expansion(3), expansion(4)];
x1 = max(1, expandedBox(1));
y1 = max(1, expandedBox(2));
x2 = min(imageWidth, expandedBox(1) + expandedBox(3));
y2 = min(imageHeight, expandedBox(2) + expandedBox(4));
expandedBox = [x1, y1, max(1, x2 - x1), max(1, y2 - y1)];
end
