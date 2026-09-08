function metrics = evaluateImage(originalImage, outputImage, elapsedSeconds)
%EVALUATEIMAGE 计算输出图像的信息熵、总体标准差和平均梯度。

if nargin < 2 || ~isValidRgbImage(originalImage) || ...
        ~isValidRgbImage(outputImage)
    error('evaluateImage:InvalidImage', ...
        'Images must be three-channel RGB images.');
end
if size(originalImage, 1) ~= size(outputImage, 1) || ...
        size(originalImage, 2) ~= size(outputImage, 2)
    error('evaluateImage:SizeMismatch', ...
        'originalImage and outputImage must have the same pixel dimensions.');
end
if nargin < 3 || ~isnumeric(elapsedSeconds) || ~isreal(elapsedSeconds) || ...
        ~isscalar(elapsedSeconds) || ~isfinite(elapsedSeconds) || elapsedSeconds < 0
    error('evaluateImage:InvalidElapsed', ...
        'elapsedSeconds must be a finite non-negative numeric scalar.');
end
ensureImageProcessingToolbox();

% 指标统一基于输出图像的 rgb2gray 结果。
grayImage = rgb2gray(outputImage);
grayDouble = im2double(grayImage);
histogramCounts = imhist(grayImage, 256);
probabilities = histogramCounts / numel(grayImage);
probabilities = probabilities(probabilities > 0);
imageEntropy = -sum(probabilities .* log2(probabilities));
standardDeviation = std(grayDouble(:), 1);
[horizontalGradient, verticalGradient] = gradient(grayDouble);
averageGradient = mean(hypot(horizontalGradient, verticalGradient), 'all');

metrics = struct( ...
    'entropy', imageEntropy, ...
    'standardDeviation', standardDeviation, ...
    'averageGradient', averageGradient, ...
    'elapsedSeconds', elapsedSeconds);
end

function ensureImageProcessingToolbox
requiredFunctions = {'rgb2gray', 'imhist'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('evaluateImage:MissingToolbox', ...
        'Image Processing Toolbox is required for image evaluation.');
end
end

function isValid = isValidRgbImage(inputImage)
isValid = isnumeric(inputImage) && isreal(inputImage) && ...
    ndims(inputImage) == 3 && size(inputImage, 3) == 3;
end
