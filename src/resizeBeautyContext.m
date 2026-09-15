function resizedContext = resizeBeautyContext(context, targetImageSize, targetFaceBox)
%RESIZEBEAUTYCONTEXT 将已解析的 mask 映射到另一个图像尺寸，不重新推理。
if ~isstruct(context) || ~isscalar(context) || ...
        ~isfield(context, 'skinMask') || ~isfield(context, 'faceSkinMask') || ...
        ~isfield(context, 'featureProtectionMask')
    error('resizeBeautyContext:InvalidContext', 'A beauty context with masks is required.');
end
if numel(targetImageSize) < 2 || any(~isfinite(targetImageSize(1:2))) || ...
        any(targetImageSize(1:2) < 1) || any(targetImageSize(1:2) ~= ...
        round(targetImageSize(1:2))) || ~isequal(size(targetFaceBox), [1, 4]) || ...
        ~isnumeric(targetFaceBox) || ~isreal(targetFaceBox) || ...
        any(~isfinite(targetFaceBox))
    error('resizeBeautyContext:InvalidTarget', 'Target image size and faceBox are invalid.');
end
height = targetImageSize(1);
width = targetImageSize(2);
if targetFaceBox(1) < 1 || targetFaceBox(2) < 1 || ...
        any(targetFaceBox(3:4) < 1) || ...
        targetFaceBox(1) + targetFaceBox(3) - 1 > width || ...
        targetFaceBox(2) + targetFaceBox(4) - 1 > height
    error('resizeBeautyContext:InvalidTarget', 'Target faceBox is outside the image.');
end
maskNames = {'skinMask', 'faceSkinMask', 'featureProtectionMask'};
if isfield(context, 'hardProtectionMask')
    maskNames{end + 1} = 'hardProtectionMask';
end
if isfield(context, 'bodySkinMask')
    maskNames{end + 1} = 'bodySkinMask';
end
resizedContext = struct();
for index = 1:numel(maskNames)
    name = maskNames{index};
    % 硬保护同样使用双线性上采样：核心内部仍保持 1，边界平滑过渡，
    % 避免 nearest 重采样在五官边界产生锯齿状的逐像素复制区。
    resizedContext.(name) = min(1, max(0, ...
        imresize(context.(name), [height, width], 'bilinear')));
end
% regions 只上采样下游实际消费的类别：beautifyImage 的暗斑层读取
% nose 概率做鼻部抑制。若全量搬运 19 类会把保存路径的内存放大一个
% 数量级；single 精度对概率图足够，消费端会自行做 double 转换。
consumedRegionNames = {'nose'};
if isfield(context, 'regions') && isfield(context, 'regionConfidence')
    resizedRegions = struct();
    resizedConfidence = struct();
    for index = 1:numel(consumedRegionNames)
        name = consumedRegionNames{index};
        if isfield(context.regions, name) && ...
                isfield(context.regionConfidence, name)
            resizedRegions.(name) = single(min(1, max(0, ...
                imresize(context.regions.(name), [height, width], ...
                'bilinear'))));
            resizedConfidence.(name) = single(min(1, max(0, ...
                imresize(context.regionConfidence.(name), ...
                [height, width], 'bilinear'))));
        end
    end
    if ~isempty(fieldnames(resizedRegions))
        resizedContext.regions = resizedRegions;
        resizedContext.regionConfidence = resizedConfidence;
    end
end
if isfield(context, 'schemaVersion')
    resizedContext.schemaVersion = context.schemaVersion;
end
resizedContext.imageSize = [height, width, 3];
resizedContext.faceBox = double(targetFaceBox);
if ~isequal(size(resizedContext.skinMask), [height, width])
    error('resizeBeautyContext:InvalidOutput', 'Context mask resize failed.');
end
end
