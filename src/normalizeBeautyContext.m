function beautyContext = normalizeBeautyContext(inputImage, faceBox, context)
%NORMALIZEBEAUTYCONTEXT 统一验证并转换可消费的 Beauty Context。
%   无版本 Context 和 2.0 Context 按兼容规则转换为 3.0；3.0 Context
%   必须显式提供 v3 字段。转换结果保留旧字段，供尚未迁移的消费者使用。

% 同时接受 normalizeBeautyContext(context, imageSizeOrImage, faceBox)，
% 方便旧的验证调用方迁移到统一入口。
if isstruct(inputImage) && nargin >= 3 && isnumeric(context) && ...
        isreal(context) && isequal(size(context), [1, 4])
    legacyContext = inputImage;
    targetFaceBox = context;
    if isa(faceBox, 'uint8')
        inputImage = faceBox;
    elseif isnumeric(faceBox) && isreal(faceBox) && numel(faceBox) >= 2 && ...
            all(isfinite(faceBox(1:2))) && all(faceBox(1:2) >= 1) && ...
            all(faceBox(1:2) == round(faceBox(1:2)))
        inputImage = zeros([faceBox(1:2), 3], 'uint8');
    else
        error('normalizeBeautyContext:InvalidImage', ...
            '第二个参数必须是输入图像或图像尺寸。');
    end
    faceBox = targetFaceBox;
    context = legacyContext;
end

if nargin < 1 || ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('normalizeBeautyContext:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
if nargin < 2
    error('normalizeBeautyContext:InvalidFaceBox', ...
        '必须提供位于图像范围内的 [x y width height] 人脸框。');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));

if nargin < 3 || isempty(context)
    context = prepareBeautyContext(inputImage, faceBox);
end
if ~isstruct(context) || ~isscalar(context)
    error('normalizeBeautyContext:InvalidContext', ...
        'Beauty Context 必须是标量结构体。');
end

imageSize = size(inputImage);
version = readSchemaVersion(context);
switch version
    case 2
        beautyContext = convertLegacyContext(context, inputImage, faceBox);
    case 3
        validateV3Context(context, imageSize, faceBox);
        beautyContext = context;
    otherwise
        error('normalizeBeautyContext:UnsupportedVersion', ...
            '不支持 Beauty Context 版本 "%s"，只接受 2.0 或 3.0。', ...
            versionLabel(context));
end

beautyContext = finalizeContext(beautyContext, inputImage, faceBox);
end

function label = versionLabel(context)
value = context.schemaVersion;
if isstring(value) && isscalar(value)
    label = char(value);
elseif ischar(value) && size(value, 1) == 1
    label = value;
elseif isnumeric(value)
    label = mat2str(value);
else
    label = class(value);
end
end

function version = readSchemaVersion(context)
if ~isfield(context, 'schemaVersion') || isempty(context.schemaVersion)
    version = 2;
    return;
end

value = context.schemaVersion;
if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
    if value >= 3 && value < 4
        version = 3;
    elseif value >= 2 && value < 3
        version = 2;
    else
        version = value;
    end
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || size(value, 1) ~= 1
    version = NaN;
    return;
end
if startsWith(value, '3')
    version = 3;
elseif startsWith(value, '2')
    version = 2;
else
    version = value;
end
end

function context = convertLegacyContext(context, inputImage, faceBox)
validateBaseContext(context, size(inputImage), faceBox);

context.skinMask = double(context.skinMask);
context.faceSkinMask = double(context.faceSkinMask);
context.featureProtectionMask = double(context.featureProtectionMask);
if isfield(context, 'hardProtectionMask')
    validateMask(context.hardProtectionMask, size(inputImage), ...
        'hardProtectionMask');
    context.hardProtectionMask = double(context.hardProtectionMask);
else
    context.hardProtectionMask = double(context.featureProtectionMask >= .999);
end

[regions, confidence] = readLegacySemantics(context, size(inputImage));
context.regions = regions;
context.regionConfidence = confidence;
context.semanticProbabilities = stackSemantics(regions);
context.semanticConfidence = stackSemantics(confidence);
context.nonFaceSkinMask = min(max(context.skinMask - ...
    min(context.skinMask, context.faceSkinMask), 0), 1);
if isfield(context, 'bodySkinMask')
    validateMask(context.bodySkinMask, size(inputImage), 'bodySkinMask');
    context.bodySkinMask = double(context.bodySkinMask);
else
    context.bodySkinMask = context.nonFaceSkinMask;
end

[textureProtection, structureProtection, toneProtection] = ...
    deriveProtectionMasks(context, inputImage, faceBox);
context.textureProtectionMask = textureProtection;
context.structureProtectionMask = structureProtection;
context.toneProtectionMask = toneProtection;
context.schemaVersion = '3.0';
end

function validateV3Context(context, imageSize, faceBox)
requiredFields = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'featureProtectionMask', 'hardProtectionMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'semanticProbabilities', 'imageSize', 'faceBox'};
if ~all(isfield(context, requiredFields))
    error('normalizeBeautyContext:InvalidContext', ...
        '3.0 Beauty Context 缺少必需字段。');
end
validateBaseContext(context, imageSize, faceBox);
validateMask(context.nonFaceSkinMask, imageSize, 'nonFaceSkinMask');
validateMask(context.hardProtectionMask, imageSize, 'hardProtectionMask');
validateMask(context.textureProtectionMask, imageSize, ...
    'textureProtectionMask');
validateMask(context.structureProtectionMask, imageSize, ...
    'structureProtectionMask');
validateMask(context.toneProtectionMask, imageSize, 'toneProtectionMask');
validateSemanticField(context.semanticProbabilities, imageSize, ...
    'semanticProbabilities');
if isfield(context, 'semanticConfidence')
    validateSemanticField(context.semanticConfidence, imageSize, ...
        'semanticConfidence');
end
end

function validateBaseContext(context, imageSize, faceBox)
requiredFields = {'skinMask', 'faceSkinMask', 'featureProtectionMask', ...
    'imageSize', 'faceBox'};
if ~all(isfield(context, requiredFields))
    error('normalizeBeautyContext:InvalidContext', ...
        'Beauty Context 缺少基础字段。');
end
expectedSize = imageSize(1:2);
validateMask(context.skinMask, imageSize, 'skinMask');
validateMask(context.faceSkinMask, imageSize, 'faceSkinMask');
validateMask(context.featureProtectionMask, imageSize, ...
    'featureProtectionMask');
if ~isnumeric(context.imageSize) || ~isreal(context.imageSize) || ...
        ~isequal(size(context.imageSize), [1, 3]) || ...
        any(~isfinite(context.imageSize)) || ...
        ~isequal(double(context.imageSize), double(imageSize))
    error('normalizeBeautyContext:SizeMismatch', ...
        'Beauty Context 的 imageSize 与输入图像不匹配。');
end
if ~isnumeric(context.faceBox) || ~isreal(context.faceBox) || ...
        ~isequal(size(context.faceBox), [1, 4]) || ...
        any(~isfinite(context.faceBox)) || ...
        any(abs(double(context.faceBox) - double(faceBox)) > 1e-9)
    error('normalizeBeautyContext:SizeMismatch', ...
        'Beauty Context 的 faceBox 与当前人脸框不匹配。');
end
if ~isequal(size(context.skinMask), expectedSize)
    error('normalizeBeautyContext:SizeMismatch', ...
        'Beauty Context 的 Mask 尺寸与输入图像不匹配。');
end
end

function validateMask(value, imageSize, name)
if ~isnumeric(value) && ~islogical(value)
    error('normalizeBeautyContext:InvalidMask', ...
        '字段 %s 必须是数值 Mask。', name);
end
if ~isreal(value) || ~isequal(size(value), imageSize(1:2)) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('normalizeBeautyContext:InvalidMask', ...
        '字段 %s 的尺寸或取值范围无效。', name);
end
end

function [regions, confidence] = readLegacySemantics(context, imageSize)
names = faceParsingClassNames();
regions = emptySemanticStruct(imageSize(1:2));
confidence = emptySemanticStruct(imageSize(1:2));
if isfield(context, 'semanticProbabilities')
    probabilities = context.semanticProbabilities;
    validateSemanticField(probabilities, imageSize, 'semanticProbabilities');
    regions = unstackSemantics(probabilities, names);
elseif isfield(context, 'regions')
    regions = normalizeSemanticStruct(context.regions, imageSize, ...
        'regions', false);
end
if isfield(context, 'semanticConfidence')
    confidenceValues = context.semanticConfidence;
    validateSemanticField(confidenceValues, imageSize, 'semanticConfidence');
    confidence = unstackSemantics(confidenceValues, names);
elseif isfield(context, 'regionConfidence')
    confidence = normalizeSemanticStruct(context.regionConfidence, ...
        imageSize, 'regionConfidence', false);
else
    confidence = regions;
end
end

function [regions, confidence] = readV3Semantics(context, imageSize)
names = faceParsingClassNames();
if isfield(context, 'semanticProbabilities')
    values = context.semanticProbabilities;
    validateSemanticField(values, imageSize, 'semanticProbabilities');
    regions = unstackSemantics(values, names);
else
    regions = normalizeSemanticStruct(context.regions, imageSize, ...
        'regions', true);
end
if isfield(context, 'semanticConfidence')
    values = context.semanticConfidence;
    validateSemanticField(values, imageSize, 'semanticConfidence');
    confidence = unstackSemantics(values, names);
elseif isfield(context, 'regionConfidence')
    confidence = normalizeSemanticStruct(context.regionConfidence, ...
        imageSize, 'regionConfidence', true);
else
    confidence = regions;
end
end

function values = normalizeSemanticStruct(value, imageSize, fieldName, requireAll)
names = faceParsingClassNames();
if ~isstruct(value) || ~isscalar(value)
    error('normalizeBeautyContext:InvalidSemantic', ...
        '字段 %s 必须是语义概率结构体。', fieldName);
end
values = emptySemanticStruct(imageSize(1:2));
for index = 1:numel(names)
    name = names{index};
    if ~isfield(value, name)
        if requireAll
            error('normalizeBeautyContext:InvalidSemantic', ...
                '字段 %s 缺少类别 %s。', fieldName, name);
        end
        continue;
    end
    validateMask(value.(name), imageSize, [fieldName, '.', name]);
    values.(name) = double(value.(name));
end
end

function validateSemanticField(value, imageSize, name)
if ~isnumeric(value) || ~isreal(value) || ndims(value) ~= 3 || ...
        size(value, 1) ~= imageSize(1) || size(value, 2) ~= imageSize(2) || ...
        size(value, 3) ~= numel(faceParsingClassNames()) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('normalizeBeautyContext:InvalidSemantic', ...
        '字段 %s 必须是与输入图像同尺寸的 HxWx19 概率图。', name);
end
end

function values = stackSemantics(semanticStruct)
names = faceParsingClassNames();
first = semanticStruct.(names{1});
values = zeros([size(first), numel(names)], 'single');
for index = 1:numel(names)
    values(:, :, index) = single(semanticStruct.(names{index}));
end
end

function semanticStruct = unstackSemantics(values, names)
semanticStruct = struct();
for index = 1:numel(names)
    semanticStruct.(names{index}) = double(values(:, :, index));
end
end

function semanticStruct = emptySemanticStruct(imageSize)
names = faceParsingClassNames();
semanticStruct = struct();
for index = 1:numel(names)
    semanticStruct.(names{index}) = zeros(imageSize);
end
end

function [textureProtection, structureProtection, toneProtection] = ...
        deriveProtectionMasks(context, inputImage, faceBox)
regions = context.regions;
confidence = context.regionConfidence;
names = faceParsingClassNames();
hasAllSemantics = all(isfield(regions, names)) && ...
    all(isfield(confidence, names));
if ~hasAllSemantics
    textureProtection = double(context.featureProtectionMask);
    structureProtection = textureProtection;
    toneProtection = textureProtection;
    return;
end

[~, ~, diagnostics] = buildFeatureProtectionMasks(inputImage, ...
    regions, confidence, min(faceBox(3:4)));
textureProtection = max(cat(3, diagnostics.occluderProtection, ...
    diagnostics.browProtection, diagnostics.lipProtection, ...
    diagnostics.eyeDetailProtection), [], 3);
structureProtection = max(cat(3, diagnostics.noseStructureProtection, ...
    diagnostics.periocularProtection, diagnostics.doubleEyelidProtection), ...
    [], 3);
toneProtection = max(cat(3, diagnostics.lipProtection, ...
    diagnostics.browProtection, diagnostics.noseProtection, ...
    diagnostics.eyeDetailProtection), [], 3);
textureProtection = min(max(double(textureProtection), 0), 1);
structureProtection = min(max(double(structureProtection), 0), 1);
toneProtection = min(max(double(toneProtection), 0), 1);
end

function context = finalizeContext(context, inputImage, faceBox)
imageSize = size(inputImage);
[regions, confidence] = readV3Semantics(context, imageSize);
context.regions = regions;
context.regionConfidence = confidence;
context.semanticProbabilities = stackSemantics(regions);
context.semanticConfidence = stackSemantics(confidence);
context.skinMask = double(context.skinMask);
context.faceSkinMask = double(context.faceSkinMask);
context.nonFaceSkinMask = double(context.nonFaceSkinMask);
context.featureProtectionMask = double(context.featureProtectionMask);
context.hardProtectionMask = double(context.hardProtectionMask);
context.textureProtectionMask = double(context.textureProtectionMask);
context.structureProtectionMask = double(context.structureProtectionMask);
context.toneProtectionMask = double(context.toneProtectionMask);
if ~isfield(context, 'bodySkinMask')
    context.bodySkinMask = context.nonFaceSkinMask;
else
    context.bodySkinMask = double(context.bodySkinMask);
end
if ~isfield(context, 'geometry')
    context.geometry = struct('contours', struct(), 'landmarks', zeros(0, 2));
end
context.protectionMasks = struct( ...
    'texture', context.textureProtectionMask, ...
    'structure', context.structureProtectionMask, ...
    'tone', context.toneProtectionMask);
context.schemaVersion = '3.0';
context.imageSize = imageSize;
context.faceBox = double(faceBox);
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('normalizeBeautyContext:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end
