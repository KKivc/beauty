function [faceBox, isSingleFace] = detectSingleFace(inputImage)
%DETECTSINGLEFACE 在 RGB 图像中检测是否恰好存在一张人脸。

% 只接收三通道 RGB 图像，灰度图或带 alpha 通道的图像不进入检测流程。
if ~isnumeric(inputImage) || ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('detectSingleFace:InvalidImage', ...
        'inputImage must be a three-channel RGB image.');
end

% 使用 Computer Vision Toolbox 的 CascadeObjectDetector 获取候选 faceBox。
detector = vision.CascadeObjectDetector();
faceBoxes = step(detector, inputImage);

% GUI 只允许单人脸图像；多人脸或未检测到人脸都返回空 faceBox。
isSingleFace = size(faceBoxes, 1) == 1;
if isSingleFace
    faceBox = faceBoxes(1, :);
else
    faceBox = zeros(0, 4);
end
end
