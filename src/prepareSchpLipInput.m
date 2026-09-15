function [networkInput, transform] = prepareSchpLipInput(inputImage)
%PREPARESCHPLIPINPUT 按官方整图中心/方形 scale 生成 473x473 BGR 输入。
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('prepareSchpLipInput:InvalidImage', ...
        'inputImage must be a real uint8 RGB image.');
end
[height, width, ~] = size(inputImage);
if height < 2 || width < 2
    error('prepareSchpLipInput:InvalidImage', ...
        'SCHP input height and width must both be at least 2 pixels.');
end

% 官方 LIP loader 使用 [0, 0, width-1, height-1] 求 center/scale。
inputSize = [473, 473];
center = single([(width - 1) / 2, (height - 1) / 2]);
side = single(max(width - 1, height - 1));
supportScale = single([side, side]);
zoom = single((inputSize(2) - 1) / side);
offset = single([(inputSize(2) - 1) / 2, ...
    (inputSize(1) - 1) / 2]) - zoom .* center;
forwardAffine = single([zoom, 0, offset(1); 0, zoom, offset(2)]);
inverseAffine = single([1 / zoom, 0, -offset(1) / zoom; ...
    0, 1 / zoom, -offset(2) / zoom]);

[outputX, outputY] = meshgrid(single(0:inputSize(2) - 1), ...
    single(0:inputSize(1) - 1));
sourceX = inverseAffine(1, 1) .* outputX + inverseAffine(1, 3) + 1;
sourceY = inverseAffine(2, 2) .* outputY + inverseAffine(2, 3) + 1;
warpedBgr = zeros(inputSize(1), inputSize(2), 3, 'single');
channelOrder = [3, 2, 1];
for channel = 1:3
    source = single(inputImage(:, :, channelOrder(channel))) / 255;
    warpedBgr(:, :, channel) = interp2(source, sourceX, sourceY, ...
        'linear', single(0));
end

meanValue = reshape(single([.406, .456, .485]), 1, 1, 3);
stdValue = reshape(single([.225, .224, .229]), 1, 1, 3);
normalized = (warpedBgr - meanValue) ./ stdValue;
networkInput = permute(normalized, [3, 1, 2]);
transform = struct('inputSize', inputSize, 'outputSize', [119, 119], ...
    'imageSize', [height, width], 'center', center, ...
    'scale', supportScale, 'forwardAffine', forwardAffine, ...
    'inverseAffine', inverseAffine);
end
