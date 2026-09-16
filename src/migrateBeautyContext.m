function migratedContext = migrateBeautyContext(inputImage, faceBox, context)
%MIGRATEBEAUTYCONTEXT 显式将 Beauty Context 升级为 v3.1。
%   migrateBeautyContext(context) 只迁移已存在的色度保护 Mask。
%   migrateBeautyContext(inputImage, faceBox, context) 会通过完整规范化
%   校验并补齐当前图像所需的派生字段。

if nargin == 1
    context = inputImage;
    migratedContext = migrateWithoutImage(context);
    return;
end
if nargin ~= 3
    error('migrateBeautyContext:InvalidArguments', ...
        '迁移需要一个 Context，或按 inputImage、faceBox、Context 提供三个参数。');
end

% 同时接受 context、inputImage、faceBox 的直观排列，便于旧调用方显式迁移。
if isstruct(inputImage) && isValidRgbImage(faceBox)
    sourceContext = inputImage;
    sourceImage = faceBox;
    sourceFaceBox = context;
else
    sourceImage = inputImage;
    sourceFaceBox = faceBox;
    sourceContext = context;
end
migratedContext = normalizeBeautyContext( ...
    sourceImage, sourceFaceBox, sourceContext);
migratedContext = migrateRuntimeCache(migratedContext, ...
    size(sourceImage, 1:2), migratedContext.chromaProtectionMask);
end

function migratedContext = migrateWithoutImage(context)
validateContext(context);
if ~isV3Version(context.schemaVersion)
    error('migrateBeautyContext:UnsupportedVersion', ...
        '只接受 Beauty Context 版本 3.0 或 3.1。');
end

if ~isfield(context, 'skinMask') || ~isnumeric(context.skinMask) || ...
        ~isreal(context.skinMask) || ~ismatrix(context.skinMask)
    error('migrateBeautyContext:InvalidContext', ...
        'Context 必须包含二维 skinMask，才能在无原图时迁移。');
end
imageSize = size(context.skinMask);
[chromaProtectionMask, hasChromaProtectionMask] = ...
    resolveChromaProtectionMask(context, imageSize, ...
    'migrateBeautyContext:InvalidContext', ...
    'migrateBeautyContext:ChromaProtectionConflict');
if ~hasChromaProtectionMask
    if hasCachedInput(context)
        migratedContext = normalizeBeautyContext( ...
            context.runtimeCache.inputImage, context.faceBox, context);
        return;
    end
    error('migrateBeautyContext:MissingChromaProtectionMask', ...
        '无原图时，旧 Context 必须包含 toneProtectionMask 或 chromaProtectionMask。');
end

migratedContext = context;
migratedContext.chromaProtectionMask = chromaProtectionMask;
migratedContext.toneProtectionMask = chromaProtectionMask;
migratedContext.schemaVersion = '3.1';
if isfield(migratedContext, 'protectionMasks') && ...
        isstruct(migratedContext.protectionMasks) && ...
        isscalar(migratedContext.protectionMasks)
    migratedContext.protectionMasks.chroma = chromaProtectionMask;
    migratedContext.protectionMasks.tone = chromaProtectionMask;
end
migratedContext = migrateRuntimeCache(migratedContext, imageSize, ...
    chromaProtectionMask);
end

function context = migrateRuntimeCache(context, imageSize, fallbackMask)
if ~isfield(context, 'runtimeCache') || ...
        ~isstruct(context.runtimeCache) || ~isscalar(context.runtimeCache)
    return;
end
cache = context.runtimeCache;
if ~isfield(cache, 'beautyMasks') || ...
        ~isstruct(cache.beautyMasks) || ~isscalar(cache.beautyMasks)
    return;
end
[cacheMask, hasCacheMask] = resolveChromaProtectionMask( ...
    cache.beautyMasks, imageSize, ...
    'migrateBeautyContext:InvalidContext', ...
    'migrateBeautyContext:ChromaProtectionConflict');
if ~hasCacheMask
    cacheMask = fallbackMask;
end
cache.beautyMasks.chromaProtectionMask = cacheMask;
cache.beautyMasks.toneProtectionMask = cacheMask;
cache.beautyMasks.schemaVersion = '3.1';
cache.schemaVersion = '3.1';
context.runtimeCache = cache;
end

function hasInput = hasCachedInput(context)
hasInput = isfield(context, 'runtimeCache') && ...
    isstruct(context.runtimeCache) && isscalar(context.runtimeCache) && ...
    isfield(context.runtimeCache, 'inputImage') && ...
    isValidRgbImage(context.runtimeCache.inputImage) && ...
    isfield(context, 'faceBox') && isnumeric(context.faceBox) && ...
    isreal(context.faceBox) && isequal(size(context.faceBox), [1, 4]);
end

function validateContext(context)
if ~isstruct(context) || ~isscalar(context) || ...
        ~isfield(context, 'schemaVersion')
    error('migrateBeautyContext:InvalidContext', ...
        'Beauty Context 必须是包含 schemaVersion 的标量结构体。');
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

function valid = isValidRgbImage(value)
valid = isa(value, 'uint8') && isreal(value) && ndims(value) == 3 && ...
    size(value, 3) == 3;
end
