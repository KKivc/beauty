function resizedContext = resizeBeautyContext(context, targetImageSize, ...
        targetFaceBox, targetImage)
%RESIZEBEAUTYCONTEXT 迁移 Context 到另一个尺寸并维护语义几何。
%   仅提供三个参数时保留旧的轻量缩放行为；提供目标原图时，先缩放
%   语义概率，再在目标尺寸上重新构建派生保护 Mask。

if ~isstruct(context) || ~isscalar(context) || ...
        ~isfield(context, 'skinMask') || ~isfield(context, 'faceSkinMask') || ...
        ~isfield(context, 'featureProtectionMask')
    error('resizeBeautyContext:InvalidContext', ...
        '必须提供包含基础 Mask 的 Beauty Context。');
end
sourceSize = size(context.skinMask);
if numel(sourceSize) ~= 2
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 的 Mask 尺寸无效。');
end
validateTarget(targetImageSize, targetFaceBox);
height = targetImageSize(1);
width = targetImageSize(2);
if nargin >= 4 && ~isempty(targetImage)
    if ~isa(targetImage, 'uint8') || ~isreal(targetImage) || ...
            ndims(targetImage) ~= 3 || size(targetImage, 3) ~= 3 || ...
            ~isequal(size(targetImage, 1:2), [height, width])
        error('resizeBeautyContext:InvalidTarget', ...
            '目标原图必须是与 targetImageSize 一致的 uint8 RGB 图像。');
    end
end

resizedContext = struct();
maskNames = {'skinMask', 'faceSkinMask', 'featureProtectionMask', ...
    'hardProtectionMask', 'bodySkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap'};
for index = 1:numel(maskNames)
    name = maskNames{index};
    if isfield(context, name)
        validateSourceMask(context.(name), sourceSize, name);
        resizedContext.(name) = resizeMask(context.(name), [height, width]);
    end
end

hasTargetImage = nargin >= 4 && ~isempty(targetImage);
[regions, confidence, hasFullSemantics] = ...
    resizeSemanticFields(context, sourceSize, [height, width], hasTargetImage);

if hasTargetImage && ~hasFullSemantics
    error('resizeBeautyContext:InvalidContext', ...
        '原尺寸重建需要完整的 19 类语义概率。');
end
if hasTargetImage && hasFullSemantics
    parsing = struct('regions', regions, 'regionConfidence', confidence);
    rebuilt = buildBeautyContextFromParsing(targetImage, ...
        double(targetFaceBox), parsing);
    if isfield(resizedContext, 'bodySkinMask')
        rebuilt.bodySkinMask = resizedContext.bodySkinMask;
        rebuilt.skinMask = max(rebuilt.skinMask, rebuilt.bodySkinMask);
    end
    resizedContext = normalizeBeautyContext(targetImage, ...
        double(targetFaceBox), rebuilt);
    return;
end

if ~isempty(fieldnames(regions))
    resizedContext.regions = regions;
    resizedContext.regionConfidence = confidence;
end
if isfield(context, 'semanticProbabilities') && ...
        ~hasTargetImage && isSchemaV3(context)
    resizedContext.semanticProbabilities = resizeSemanticStack( ...
        context.semanticProbabilities, sourceSize, [height, width]);
    if isfield(context, 'semanticConfidence')
        resizedContext.semanticConfidence = resizeSemanticStack( ...
            context.semanticConfidence, sourceSize, [height, width]);
    end
end
if isfield(context, 'schemaVersion')
    resizedContext.schemaVersion = context.schemaVersion;
end
resizedContext.imageSize = [height, width, 3];
resizedContext.faceBox = double(targetFaceBox);

if isfield(context, 'protectionMasks') && isstruct(context.protectionMasks)
    resizedContext.protectionMasks = struct();
    protectionNames = {'texture', 'structure', 'tone'};
    for index = 1:numel(protectionNames)
        name = protectionNames{index};
        if isfield(context.protectionMasks, name)
            resizedContext.protectionMasks.(name) = resizeMask( ...
                context.protectionMasks.(name), [height, width]);
        end
    end
end
if ~isequal(size(resizedContext.skinMask), [height, width])
    error('resizeBeautyContext:InvalidOutput', ...
        'Context Mask 缩放失败。');
end
end

function [regions, confidence, hasFullSemantics] = ...
        resizeSemanticFields(context, sourceSize, targetSize, fullResize)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
hasFullSemantics = false;
if isfield(context, 'semanticProbabilities')
    values = context.semanticProbabilities;
    if isValidSemanticStack(values, sourceSize)
        hasFullSemantics = true;
        if fullResize
            for index = 1:numel(names)
                regions.(names{index}) = single(resizeMask( ...
                    values(:, :, index), targetSize));
            end
        end
    end
elseif isfield(context, 'regions')
    hasFullSemantics = hasAllSemanticFields(context.regions, names, sourceSize);
    if fullResize && hasFullSemantics
        for index = 1:numel(names)
            name = names{index};
            regions.(name) = single(resizeMask( ...
                context.regions.(name), targetSize));
        end
    end
end

if ~hasFullSemantics || ~fullResize
    % 三参数旧入口只保留 beautifyImage 当前消费的鼻部概率，避免原尺寸
    % 保存前的预览 Context 被无谓复制成多份大数组。
    if isfield(context, 'regions') && isfield(context.regions, 'nose') && ...
            isequal(size(context.regions.nose), sourceSize)
        regions.nose = single(resizeMask(context.regions.nose, targetSize));
    end
    if isfield(context, 'regionConfidence') && ...
            isfield(context.regionConfidence, 'nose') && ...
            isequal(size(context.regionConfidence.nose), sourceSize)
        confidence.nose = single(resizeMask( ...
            context.regionConfidence.nose, targetSize));
    end
    if ~fullResize
        return;
    end
    return;
end

if isfield(context, 'semanticConfidence')
    values = context.semanticConfidence;
    if ~isValidSemanticStack(values, sourceSize)
        error('resizeBeautyContext:InvalidContext', ...
            'semanticConfidence 的尺寸或类别数无效。');
    end
    if fullResize
        for index = 1:numel(names)
            confidence.(names{index}) = single(resizeMask( ...
                values(:, :, index), targetSize));
        end
    end
elseif isfield(context, 'regionConfidence') && ...
        hasAllSemanticFields(context.regionConfidence, names, sourceSize)
    if fullResize
        for index = 1:numel(names)
            name = names{index};
            confidence.(name) = single(resizeMask( ...
                context.regionConfidence.(name), targetSize));
        end
    end
else
    confidence = regions;
end
end

function output = resizeSemanticStack(values, sourceSize, targetSize)
if ~isValidSemanticStack(values, sourceSize)
    error('resizeBeautyContext:InvalidContext', ...
        '语义概率堆栈的尺寸或类别数无效。');
end
output = zeros([targetSize, size(values, 3)], 'single');
for index = 1:size(values, 3)
    output(:, :, index) = single(resizeMask(values(:, :, index), targetSize));
end
end

function valid = isValidSemanticStack(value, sourceSize)
valid = isnumeric(value) && isreal(value) && ndims(value) == 3 && ...
    isequal(size(value, 1:2), sourceSize) && ...
    size(value, 3) == numel(faceParsingClassNames()) && ...
    all(isfinite(value(:))) && all(value(:) >= 0) && all(value(:) <= 1);
end

function valid = hasAllSemanticFields(value, names, sourceSize)
valid = isstruct(value) && isscalar(value);
if ~valid
    return;
end
for index = 1:numel(names)
    name = names{index};
    valid = valid && isfield(value, name) && ...
        isnumeric(value.(name)) && isreal(value.(name)) && ...
        isequal(size(value.(name)), sourceSize) && ...
        all(isfinite(value.(name)), 'all') && ...
        all(value.(name) >= 0, 'all') && all(value.(name) <= 1, 'all');
end
end

function output = resizeMask(value, targetSize)
output = min(1, max(0, imresize(double(value), targetSize, 'bilinear')));
end

function validateSourceMask(value, sourceSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), sourceSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('resizeBeautyContext:InvalidContext', ...
        '字段 %s 的源 Mask 无效。', name);
end
end

function validateTarget(targetImageSize, targetFaceBox)
if numel(targetImageSize) < 2 || ...
        any(~isfinite(targetImageSize(1:2))) || ...
        any(targetImageSize(1:2) < 1) || ...
        any(targetImageSize(1:2) ~= round(targetImageSize(1:2))) || ...
        ~isequal(size(targetFaceBox), [1, 4]) || ...
        ~isnumeric(targetFaceBox) || ~isreal(targetFaceBox) || ...
        any(~isfinite(targetFaceBox))
    error('resizeBeautyContext:InvalidTarget', ...
        '目标图像尺寸和人脸框无效。');
end
height = targetImageSize(1);
width = targetImageSize(2);
if targetFaceBox(1) < 1 || targetFaceBox(2) < 1 || ...
        any(targetFaceBox(3:4) < 1) || ...
        targetFaceBox(1) + targetFaceBox(3) - 1 > width || ...
        targetFaceBox(2) + targetFaceBox(4) - 1 > height
    error('resizeBeautyContext:InvalidTarget', ...
        '目标人脸框超出图像范围。');
end
end

function valid = isSchemaV3(context)
valid = isfield(context, 'schemaVersion') && ...
    ((ischar(context.schemaVersion) && startsWith(context.schemaVersion, '3')) || ...
    (isstring(context.schemaVersion) && startsWith(context.schemaVersion, '3')));
end
