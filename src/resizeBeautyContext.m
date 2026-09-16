function resizedContext = resizeBeautyContext(context, targetImageSize, ...
        targetFaceBox, targetImage)
%RESIZEBEAUTYCONTEXT 将 v3 Context 迁移到另一尺寸。
%   有目标原图时重新构建全部派生 Mask；没有目标原图时仅缩放语义、
%   皮肤和已生成的派生字段，供预览级迁移使用。

if ~isstruct(context) || ~isscalar(context)
    error('resizeBeautyContext:InvalidContext', ...
        '必须提供标量 Beauty Context。');
end
validateSourceContext(context);
sourceSize = size(context.skinMask);
validateTarget(targetImageSize, targetFaceBox);
targetSize = targetImageSize(1:2);

hasTargetImage = nargin >= 4 && ~isempty(targetImage);
if hasTargetImage
    validateTargetImage(targetImage, targetSize);
end

if hasTargetImage
    semanticProbabilities = readSemanticStack(context, sourceSize, ...
        'semanticProbabilities');
    semanticConfidence = readSemanticStack(context, sourceSize, ...
        'semanticConfidence');
    resizedProbabilities = resizeSemanticStack(semanticProbabilities, ...
        targetSize);
    resizedConfidence = resizeSemanticStack(semanticConfidence, targetSize);
    names = faceParsingClassNames();
    parsing = struct( ...
        'regions', unstackSemantics(resizedProbabilities, names), ...
        'regionConfidence', unstackSemantics(resizedConfidence, names));
    rebuilt = buildBeautyContextFromParsing(targetImage, ...
        double(targetFaceBox), parsing);
    scaledNonFace = resizeMask(context.nonFaceSkinMask, targetSize);
    rebuilt.skinMask = max(rebuilt.skinMask, scaledNonFace);
    rebuilt.nonFaceSkinMask = max(rebuilt.skinMask - ...
        min(rebuilt.skinMask, rebuilt.faceSkinMask), 0);
    if isfield(context, 'bodySkinMask')
        rebuilt.bodySkinMask = resizeMask(context.bodySkinMask, targetSize);
    end
    rebuilt = attachDerivedMasks(targetImage, rebuilt, targetFaceBox);
    resizedContext = normalizeBeautyContext(targetImage, ...
        double(targetFaceBox), rebuilt);
    return;
end

% 三参数入口是轻量迁移入口，只携带后续显示所需的 Mask 和鼻部语义；
% 原尺寸保存必须使用上面的目标原图分支，以重新生成完整 v3 Context。
resizedContext = struct( ...
    'skinMask', resizeMask(context.skinMask, targetSize), ...
    'faceSkinMask', resizeMask(context.faceSkinMask, targetSize), ...
    'nonFaceSkinMask', resizeMask(context.nonFaceSkinMask, targetSize), ...
    'textureProtectionMask', resizeMask(context.textureProtectionMask, targetSize), ...
    'structureProtectionMask', resizeMask(context.structureProtectionMask, targetSize), ...
    'toneProtectionMask', resizeMask(context.toneProtectionMask, targetSize), ...
    'schemaVersion', '3.0', ...
    'imageSize', [targetSize, 3], ...
    'faceBox', double(targetFaceBox));
if isfield(context, 'bodySkinMask')
    resizedContext.bodySkinMask = resizeMask(context.bodySkinMask, targetSize);
end
maskNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'bodySkinMask'};
for index = 1:numel(maskNames)
    name = maskNames{index};
    if isfield(context, name) && ~isfield(resizedContext, name)
        validateSourceMask(context.(name), sourceSize, name);
        resizedContext.(name) = resizeMask(context.(name), targetSize);
    end
end
if isfield(context, 'regions') && isfield(context.regions, 'nose')
    resizedContext.regions = struct('nose', resizeMask( ...
        context.regions.nose, targetSize));
end
if isfield(context, 'regionConfidence') && ...
        isfield(context.regionConfidence, 'nose')
    resizedContext.regionConfidence = struct('nose', resizeMask( ...
        context.regionConfidence.nose, targetSize));
end
end

function context = attachDerivedMasks(inputImage, context, faceBox)
[beautyMasks, ~] = masks.buildBeautyMasks(inputImage, context, faceBox);
context.textureProtectionMask = beautyMasks.textureProtectionMask;
context.structureProtectionMask = beautyMasks.structureProtectionMask;
context.toneProtectionMask = beautyMasks.toneProtectionMask;
context.strengthMap = beautyMasks.strengthMap;
context.faceStrengthMap = beautyMasks.faceStrengthMap;
context.nonFaceStrengthMap = beautyMasks.nonFaceStrengthMap;
context.protectionMasks = struct( ...
    'texture', beautyMasks.textureProtectionMask, ...
    'structure', beautyMasks.structureProtectionMask, ...
    'tone', beautyMasks.toneProtectionMask);
end

function validateSourceContext(context)
if ~isfield(context, 'schemaVersion') || ~isV3Version(context.schemaVersion)
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 必须是版本 3.0。');
end
if any(isfield(context, {'featureProtectionMask', 'hardProtectionMask'}))
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 包含已移除的旧保护字段。');
end
required = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'imageSize', 'faceBox'};
if ~all(isfield(context, required))
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 缺少 v3 字段。');
end
sourceSize = size(context.skinMask);
for index = 1:numel(required(1:9))
    validateSourceMask(context.(required{index}), sourceSize, ...
        required{index});
end
if ~isnumeric(context.imageSize) || ~isequal(size(context.imageSize), [1, 3]) || ...
        ~isequal(double(context.imageSize), [sourceSize, 3])
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 的 imageSize 无效。');
end
if ~isnumeric(context.faceBox) || ~isequal(size(context.faceBox), [1, 4]) || ...
        any(~isfinite(context.faceBox))
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 的 faceBox 无效。');
end
end

function valid = isV3Version(value)
if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
    valid = value >= 3 && value < 4;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && startsWith(value, '3');
end

function values = readSemanticStack(context, sourceSize, name)
if isfield(context, name)
    values = context.(name);
elseif strcmp(name, 'semanticConfidence')
    values = context.semanticProbabilities;
else
    names = faceParsingClassNames();
    values = stackSemantics(context.regions, names);
end
if ~isnumeric(values) || ~isreal(values) || ndims(values) ~= 3 || ...
        ~isequal(size(values, 1:2), sourceSize) || ...
        size(values, 3) ~= numel(faceParsingClassNames()) || ...
        any(~isfinite(values(:))) || any(values(:) < 0) || ...
        any(values(:) > 1)
    error('resizeBeautyContext:InvalidContext', ...
        '字段 %s 的尺寸或取值范围无效。', name);
end
values = single(values);
end

function output = resizeSemanticStack(values, targetSize)
output = zeros([targetSize, size(values, 3)], 'single');
for index = 1:size(values, 3)
    output(:, :, index) = single(resizeMask(values(:, :, index), ...
        targetSize));
end
end

function semanticStruct = unstackSemantics(values, names)
semanticStruct = struct();
for index = 1:numel(names)
    semanticStruct.(names{index}) = double(values(:, :, index));
end
end

function values = stackSemantics(semanticStruct, names)
first = semanticStruct.(names{1});
values = zeros([size(first), numel(names)], 'single');
for index = 1:numel(names)
    values(:, :, index) = single(semanticStruct.(names{index}));
end
end

function output = resizeMask(value, targetSize)
output = min(1, max(0, imresize(double(value), targetSize, ...
    'bilinear')));
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
if ~isnumeric(targetImageSize) || numel(targetImageSize) < 2 || ...
        any(~isfinite(targetImageSize(1:2))) || ...
        any(targetImageSize(1:2) < 1) || ...
        any(targetImageSize(1:2) ~= round(targetImageSize(1:2))) || ...
        ~isnumeric(targetFaceBox) || ~isreal(targetFaceBox) || ...
        ~isequal(size(targetFaceBox), [1, 4]) || ...
        any(~isfinite(targetFaceBox))
    error('resizeBeautyContext:InvalidTarget', ...
        '目标图像尺寸和人脸框无效。');
end
height = targetImageSize(1);
width = targetImageSize(2);
if targetFaceBox(1) < 1 || targetFaceBox(2) < 1 || ...
        any(targetFaceBox(3:4) <= 0) || ...
        targetFaceBox(1) + targetFaceBox(3) - 1 > width || ...
        targetFaceBox(2) + targetFaceBox(4) - 1 > height
    error('resizeBeautyContext:InvalidTarget', ...
        '目标人脸框超出图像范围。');
end
end

function validateTargetImage(targetImage, targetSize)
if ~isa(targetImage, 'uint8') || ~isreal(targetImage) || ...
        ndims(targetImage) ~= 3 || size(targetImage, 3) ~= 3 || ...
        ~isequal(size(targetImage, 1:2), targetSize)
    error('resizeBeautyContext:InvalidTarget', ...
        '目标原图必须是与 targetImageSize 一致的 uint8 RGB 图像。');
end
end
