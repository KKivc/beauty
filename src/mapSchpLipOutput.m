function [probabilities, confidence, hardLabels] = mapSchpLipOutput(logits, transform, imageSize)
%MAPSCHPLIPOUTPUT 放大 fusion logits，并按预处理 affine 双线性回映原图。
if ~isnumeric(logits) || ~isreal(logits) || ndims(logits) ~= 3 || ...
        size(logits, 3) ~= 20 || any(~isfinite(logits(:)))
    error('mapSchpLipOutput:InvalidLogits', 'Expected finite HxWx20 logits.');
end
required = {'inputSize', 'forwardAffine'};
if ~isstruct(transform) || ~all(isfield(transform, required)) || ...
        numel(imageSize) < 2 || any(~isfinite(imageSize(1:2))) || ...
        any(imageSize(1:2) < 1) || any(imageSize(1:2) ~= round(imageSize(1:2)))
    error('mapSchpLipOutput:InvalidTransform', ...
        'A valid SCHP affine transform and image size are required.');
end

logits = single(logits);
modelLogits = resizeAlignCorners(logits, transform.inputSize);
height = imageSize(1);
width = imageSize(2);
[originalX, originalY] = meshgrid(single(0:width - 1), single(0:height - 1));
affine = single(transform.forwardAffine);
sampleX = affine(1, 1) .* originalX + affine(1, 2) .* originalY + ...
    affine(1, 3) + 1;
sampleY = affine(2, 1) .* originalX + affine(2, 2) .* originalY + ...
    affine(2, 3) + 1;
mappedLogits = zeros(height, width, 20, 'single');
for classIndex = 1:20
    mappedLogits(:, :, classIndex) = interp2(modelLogits(:, :, classIndex), ...
        sampleX, sampleY, 'linear', single(0));
end

shifted = mappedLogits - max(mappedLogits, [], 3);
probabilities = exp(shifted);
probabilities = probabilities ./ max(sum(probabilities, 3), eps('single'));
[confidence, labels] = max(probabilities, [], 3);
hardLabels = uint8(labels);
end

function resized = resizeAlignCorners(values, targetSize)
% 与 torch interpolate(..., align_corners=True) 使用相同采样坐标。
sourceHeight = size(values, 1);
sourceWidth = size(values, 2);
targetHeight = targetSize(1);
targetWidth = targetSize(2);
[queryX, queryY] = meshgrid(single(linspace(1, sourceWidth, targetWidth)), ...
    single(linspace(1, sourceHeight, targetHeight)));
resized = zeros(targetHeight, targetWidth, size(values, 3), 'single');
for channel = 1:size(values, 3)
    resized(:, :, channel) = interp2(values(:, :, channel), ...
        queryX, queryY, 'linear');
end
end
