function [strengthMap, diagnostics] = buildBeautyStrengthMap( ...
        inputImage, beautyContext, faceBox)
%BUILDBEAUTYSTRENGTHMAP 生成区分脸部与脸外皮肤的连续强度图。
%   首版不猜测手、肩或关节语义，只使用 Context 已确认的皮肤区域。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    if isfield(beautyContext, 'faceBox')
        faceBox = beautyContext.faceBox;
    else
        error('masks:InvalidFaceBox', '必须提供人脸框。');
    end
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
skin = readMask(beautyContext, 'skinMask', imageSize);
face = readMask(beautyContext, 'faceSkinMask', imageSize);
faceRegion = min(skin, face);
if isfield(beautyContext, 'nonFaceSkinMask')
    nonFaceRegion = min(skin, readMask(beautyContext, ...
        'nonFaceSkinMask', imageSize));
else
    nonFaceRegion = max(skin - faceRegion, 0);
end

% 皮肤 Mask 本身已经是概率域平滑结果，只做有界映射，不重新二值化。
faceStrength = min(max(faceRegion, 0), 1);
nonFaceStrength = .45 * min(max(nonFaceRegion, 0), 1);
strengthMap = max(faceStrength, nonFaceStrength);
strengthMap(~(skin > .01)) = 0;

% 使用图像尺度记录本次强度图的几何口径，供 tracer 和诊断复用。
faceScale = min(faceBox(3:4));
diagnostics = struct( ...
    'faceStrengthMap', faceStrength, ...
    'nonFaceStrengthMap', nonFaceStrength, ...
    'skinMask', skin, ...
    'faceSkinMask', face, ...
    'nonFaceSkinMask', nonFaceRegion, ...
    'faceScale', faceScale, ...
    'imageSize', [imageSize, 3]);
end

function validateImageAndFace(inputImage, faceBox)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('masks:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
imageHeight = size(inputImage, 1);
imageWidth = size(inputImage, 2);
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('masks:InvalidFaceBox', '人脸框超出图像范围。');
end
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('masks:InvalidContext', 'Context 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 %s 无效。', name);
end
value = double(value);
end
