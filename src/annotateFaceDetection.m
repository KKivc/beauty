function detectedImage = annotateFaceDetection(sourceImage, faceBox)
%ANNOTATEFACEDETECTION 在 RGB 图像上绘制检测到的人脸矩形框。

% 校验输入图像必须是三通道 RGB 数据，避免 insertShape 处理异常。
if ~isnumeric(sourceImage) || ndims(sourceImage) ~= 3 || size(sourceImage, 3) ~= 3
    error('annotateFaceDetection:InvalidImage', ...
        'sourceImage must be a three-channel RGB image.');
end

% faceBox 采用 [x y width height] 格式，只支持单个人脸框。
if ~isnumeric(faceBox) || ~isequal(size(faceBox), [1, 4])
    error('annotateFaceDetection:InvalidFaceBox', ...
        'faceBox must be one [x y width height] rectangle.');
end

% 使用绿色 Rectangle 标出检测结果，保持原图尺寸不变。
detectedImage = insertShape(sourceImage, 'Rectangle', faceBox, ...
    'Color', 'green', 'LineWidth', 3);
end
