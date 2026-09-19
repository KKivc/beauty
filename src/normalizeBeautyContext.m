function beautyContext = normalizeBeautyContext(inputImage, faceBox, context)
%NORMALIZEBEAUTYCONTEXT 验证并规范化最终 v3.1 Beauty Context。
%   处理入口只接受 v3 Context；派生保护 Mask 缺失时由 package 根据
%   当前图像和语义概率补齐，不再转换或保留 v2 字段。v3.0 的色度
%   字段会在此处补齐为 v3.1 的规范字段和兼容 alias。
%   V4 expand 阶段：schemaVersion='4.0' 的分层 Context 走只读
%   reader 分支（结构校验 + 规范化，不重建派生 Mask、不改写
%   compat alias）；v3.0/v3.1 输入路径保持不变，生产链仍输出
%   v3.1 Context。

validateImage(inputImage);
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
rejectLegacyFields(context);
if isV4Version(context)
    % V4 reader 分支：canonical 分层字段由共享入口校验并规范化，
    % 顶层 compat alias 原样保留，不在此重建派生 Mask。
    beautyContext = normalizeBeautyContextV4(context, size(inputImage), ...
        faceBox);
    return;
end
if ~isV3Version(context)
    error('normalizeBeautyContext:UnsupportedVersion', ...
        '只接受 Beauty Context 版本 3.0、3.1 或 4.0。');
end

imageSize = size(inputImage);
context = normalizeSemanticFields(context, imageSize);
validateBaseContext(context, imageSize, faceBox);

[chromaProtectionMask, hasChromaProtectionMask] = ...
    resolveChromaProtectionMask(context, imageSize(1:2), ...
    'normalizeBeautyContext:InvalidMask', ...
    'normalizeBeautyContext:ChromaProtectionConflict');
if hasChromaProtectionMask
    context.chromaProtectionMask = chromaProtectionMask;
    context.toneProtectionMask = chromaProtectionMask;
end

derivedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap'};
requiresRegeneration = hasMigrationStatus(context, ...
    {'aliasMigrated', 'requiresRegeneration'});
if ~hasChromaProtectionMask || ~all(isfield(context, derivedNames)) || ...
        requiresRegeneration
    [beautyMasks, ~] = masks.buildBeautyMasks(inputImage, context, faceBox);
    context.textureProtectionMask = beautyMasks.textureProtectionMask;
    context.structureProtectionMask = beautyMasks.structureProtectionMask;
    context.whiteningProtectionMask = beautyMasks.whiteningProtectionMask;
    context.chromaProtectionMask = beautyMasks.chromaProtectionMask;
    context.toneProtectionMask = beautyMasks.chromaProtectionMask;
    context.strengthMap = beautyMasks.strengthMap;
    context.faceStrengthMap = beautyMasks.faceStrengthMap;
    context.nonFaceStrengthMap = beautyMasks.nonFaceStrengthMap;
end
validateDerivedContext(context, imageSize);

if isfield(context, 'bodySkinMask')
    validateMask(context.bodySkinMask, imageSize, 'bodySkinMask');
    context.bodySkinMask = double(context.bodySkinMask);
end
if ~isfield(context, 'geometry')
    context.geometry = struct('contours', struct(), 'landmarks', zeros(0, 2));
end

context.skinMask = double(context.skinMask);
context.faceSkinMask = double(context.faceSkinMask);
context.nonFaceSkinMask = double(context.nonFaceSkinMask);
context.textureProtectionMask = double(context.textureProtectionMask);
context.structureProtectionMask = double(context.structureProtectionMask);
context.whiteningProtectionMask = double(context.whiteningProtectionMask);
context.chromaProtectionMask = double(context.chromaProtectionMask);
context.toneProtectionMask = double(context.toneProtectionMask);
context.strengthMap = double(context.strengthMap);
context.faceStrengthMap = double(context.faceStrengthMap);
context.nonFaceStrengthMap = double(context.nonFaceStrengthMap);
context.protectionMasks = struct( ...
    'texture', context.textureProtectionMask, ...
    'structure', context.structureProtectionMask, ...
    'whitening', context.whiteningProtectionMask, ...
    'chroma', context.chromaProtectionMask, ...
    'tone', context.chromaProtectionMask);
context.schemaVersion = '3.1';
context.imageSize = imageSize;
context.faceBox = double(faceBox);
context.faceScale = min(double(faceBox(3:4)));
beautyContext = context;
end

function rejectLegacyFields(context)
legacyFields = {'featureProtectionMask', 'hardProtectionMask'};
present = legacyFields(isfield(context, legacyFields));
if ~isempty(present)
    error('normalizeBeautyContext:LegacyFields', ...
        'Beauty Context 包含已移除的旧字段：%s。', strjoin(present, '、'));
end
end

function valid = isV3Version(context)
if ~isfield(context, 'schemaVersion') || isempty(context.schemaVersion)
    valid = false;
    return;
end
value = context.schemaVersion;
if isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value)
    valid = value == 3 || value == 3.1;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && ...
    any(strcmp(value, {'3.0', '3.1'}));
end

function valid = isV4Version(context)
if ~isfield(context, 'schemaVersion') || isempty(context.schemaVersion)
    valid = false;
    return;
end
value = context.schemaVersion;
if isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value)
    valid = value == 4;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && strcmp(value, '4.0');
end

function context = normalizeSemanticFields(context, imageSize)
names = faceParsingClassNames();
if isfield(context, 'semanticProbabilities')
    validateSemanticField(context.semanticProbabilities, imageSize, ...
        'semanticProbabilities');
    regions = unstackSemantics(context.semanticProbabilities, names);
elseif isfield(context, 'regions')
    if allowsPartialSemantics(context)
        regions = normalizePartialSemanticStruct(context.regions, ...
            imageSize, 'regions');
    else
        regions = normalizeSemanticStruct(context.regions, imageSize, 'regions');
    end
else
    error('normalizeBeautyContext:InvalidSemantic', ...
        'Beauty Context 缺少语义概率。');
end

if isfield(context, 'semanticConfidence')
    validateSemanticField(context.semanticConfidence, imageSize, ...
        'semanticConfidence');
    confidence = unstackSemantics(context.semanticConfidence, names);
elseif isfield(context, 'regionConfidence')
    if allowsPartialSemantics(context)
        confidence = normalizePartialSemanticStruct( ...
            context.regionConfidence, imageSize, 'regionConfidence');
    else
        confidence = normalizeSemanticStruct(context.regionConfidence, ...
            imageSize, 'regionConfidence');
    end
else
    confidence = regions;
end

context.regions = regions;
context.regionConfidence = confidence;
context.semanticProbabilities = stackSemantics(regions, names);
context.semanticConfidence = stackSemantics(confidence, names);
end

function validateBaseContext(context, imageSize, faceBox)
requiredFields = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'imageSize', 'faceBox'};
if ~all(isfield(context, requiredFields))
    error('normalizeBeautyContext:InvalidContext', ...
        'Beauty Context 缺少基础字段。');
end
validateMask(context.skinMask, imageSize, 'skinMask');
validateMask(context.faceSkinMask, imageSize, 'faceSkinMask');
validateMask(context.nonFaceSkinMask, imageSize, 'nonFaceSkinMask');
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
end

function validateDerivedContext(context, imageSize)
names = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', ...
    'nonFaceStrengthMap'};
for index = 1:numel(names)
    validateMask(context.(names{index}), imageSize, names{index});
end
end

function valid = hasMigrationStatus(context, statuses)
valid = false;
if ~isfield(context, 'migrationDiagnostics') || ...
        ~isstruct(context.migrationDiagnostics) || ...
        ~isscalar(context.migrationDiagnostics) || ...
        ~isfield(context.migrationDiagnostics, 'status')
    return;
end
status = context.migrationDiagnostics.status;
if isstring(status) && isscalar(status)
    status = char(status);
end
valid = ischar(status) && size(status, 1) == 1 && any(strcmp(status, statuses));
end

function values = normalizeSemanticStruct(value, imageSize, fieldName)
names = faceParsingClassNames();
if ~isstruct(value) || ~isscalar(value)
    error('normalizeBeautyContext:InvalidSemantic', ...
        '字段 %s 必须是语义概率结构体。', fieldName);
end

values = struct();
for index = 1:numel(names)
    name = names{index};
    if ~isfield(value, name)
        error('normalizeBeautyContext:InvalidSemantic', ...
            '字段 %s 缺少类别 %s。', fieldName, name);
    end
    values.(name) = validateMask(value.(name), imageSize, ...
        [fieldName, '.', name]);
end
end

function values = normalizePartialSemanticStruct(value, imageSize, fieldName)
if ~isstruct(value) || ~isscalar(value)
    error('normalizeBeautyContext:InvalidSemantic', ...
        '字段 %s 必须是语义概率结构体。', fieldName);
end
names = faceParsingClassNames();
values = struct();
for index = 1:numel(names)
    name = names{index};
    if isfield(value, name)
        values.(name) = validateMask(value.(name), imageSize, ...
            [fieldName, '.', name]);
    else
        values.(name) = zeros(imageSize(1:2));
    end
end
end

function valid = allowsPartialSemantics(context)
valid = isfield(context, 'migrationDiagnostics') && ...
    isstruct(context.migrationDiagnostics) && ...
    isscalar(context.migrationDiagnostics) && ...
    isfield(context.migrationDiagnostics, 'status') && ...
    isTextEqual(context.migrationDiagnostics.status, 'resized');
end

function valid = isTextEqual(value, expected)
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && strcmp(value, expected);
end

function validateSemanticField(value, imageSize, name)
if ~isnumeric(value) || ~isreal(value) || ndims(value) ~= 3 || ...
        size(value, 1) ~= imageSize(1) || ...
        size(value, 2) ~= imageSize(2) || ...
        size(value, 3) ~= numel(faceParsingClassNames()) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('normalizeBeautyContext:InvalidSemantic', ...
        '字段 %s 必须是与输入图像同尺寸的 HxWx19 概率图。', name);
end
end

function values = stackSemantics(semanticStruct, names)
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

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize(1:2)) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('normalizeBeautyContext:InvalidMask', ...
        '字段 %s 的尺寸或取值范围无效。', name);
end
value = double(value);
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('normalizeBeautyContext:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('normalizeBeautyContext:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end
