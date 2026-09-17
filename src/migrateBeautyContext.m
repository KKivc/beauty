function migratedContext = migrateBeautyContext(inputImage, faceBox, context)
%MIGRATEBEAUTYCONTEXT 显式将 Beauty Context 升级为 v3.1。
%   仅有 Context 时可迁移字段和 alias；若 Context 携带原图缓存，则
%   自动使用该原图重新生成 v3.1 运行时产物。提供原图时始终重建缓存，
%   不会把历史 3.0 派生产物仅补上 alias 后标记为当前算法产物。

if nargin == 1
    sourceContext = inputImage;
    validateContext(sourceContext);
    if hasCachedInput(sourceContext)
        migratedContext = migrateWithImage( ...
            sourceContext.runtimeCache.inputImage, sourceContext.faceBox, ...
            sourceContext);
    else
        migratedContext = migrateWithoutImage(sourceContext);
    end
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
migratedContext = migrateWithImage(sourceImage, sourceFaceBox, sourceContext);
end

function migratedContext = migrateWithImage(inputImage, faceBox, context)
validateContext(context);
sourceSchemaVersion = schemaVersionText(context.schemaVersion);
% normalizeBeautyContext 负责旧 alias 与基础字段规范化；这里随后用
% 当前输入重新生成完整缓存，确保缓存产物拥有独立的 v3.1 版本信息。
migratedContext = normalizeBeautyContext(inputImage, faceBox, context);
[runtimeMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
    inputImage, migratedContext, double(faceBox));
migration = struct( ...
    'status', 'regenerated', ...
    'sourceSchemaVersion', sourceSchemaVersion, ...
    'message', '已按当前输入重新生成 v3.1 运行时派生产物。');
migratedContext.runtimeCache = buildBeautyRuntimeCache( ...
    inputImage, double(faceBox), runtimeMasks, maskDiagnostics, migration);
migratedContext.migrationDiagnostics = migration;
end

function migratedContext = migrateWithoutImage(context)
sourceSchemaVersion = schemaVersionText(context.schemaVersion);
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
    error('migrateBeautyContext:MissingChromaProtectionMask', ...
        '无原图时，旧 Context 必须包含 toneProtectionMask 或 chromaProtectionMask。');
end

migratedContext = context;
migratedContext.chromaProtectionMask = chromaProtectionMask;
migratedContext.toneProtectionMask = chromaProtectionMask;
if ~isfield(migratedContext, 'whiteningProtectionMask')
    migratedContext.whiteningProtectionMask = zeros(imageSize);
end
migratedContext.schemaVersion = '3.1';
if isfield(migratedContext, 'faceBox') && ...
        isnumeric(migratedContext.faceBox) && ...
        isequal(size(migratedContext.faceBox), [1, 4]) && ...
        all(isfinite(migratedContext.faceBox(3:4))) && ...
        all(migratedContext.faceBox(3:4) > 0)
    migratedContext.faceScale = min(double(migratedContext.faceBox(3:4)));
end
if isfield(migratedContext, 'protectionMasks') && ...
        isstruct(migratedContext.protectionMasks) && ...
        isscalar(migratedContext.protectionMasks)
    migratedContext.protectionMasks.chroma = chromaProtectionMask;
    migratedContext.protectionMasks.tone = chromaProtectionMask;
    migratedContext.protectionMasks.whitening = ...
        migratedContext.whiteningProtectionMask;
end
migration = struct( ...
    'status', 'aliasMigrated', ...
    'sourceSchemaVersion', sourceSchemaVersion, ...
    'message', '已迁移色度保护字段；无原图时未宣称缓存产物已重建。');
migratedContext.migrationDiagnostics = migration;
if isfield(migratedContext, 'runtimeCache')
    migratedContext.runtimeCache = markCacheForRegeneration( ...
        migratedContext.runtimeCache, sourceSchemaVersion);
end
end

function cache = markCacheForRegeneration(cache, sourceSchemaVersion)
if ~isstruct(cache) || ~isscalar(cache)
    return;
end
cache.migration = struct( ...
    'status', 'requiresRegeneration', ...
    'sourceSchemaVersion', sourceSchemaVersion, ...
    'message', '无原图可用，历史运行时缓存必须在处理入口重新生成。');
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
if ~isV3Version(context.schemaVersion)
    error('migrateBeautyContext:UnsupportedVersion', ...
        '只接受 Beauty Context 版本 3.0 或 3.1。');
end
end

function valid = isV3Version(value)
if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
    valid = value == 3 || value == 3.1;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && ...
    any(strcmp(value, {'3.0', '3.1'}));
end

function value = schemaVersionText(version)
if isnumeric(version) && isscalar(version) && version == 3
    value = '3.0';
elseif isnumeric(version) && isscalar(version) && version == 3.1
    value = '3.1';
elseif isstring(version) && isscalar(version)
    value = char(version);
elseif ischar(version) && size(version, 1) == 1
    value = version;
else
    value = 'unknown';
end
end

function valid = isValidRgbImage(value)
valid = isa(value, 'uint8') && isreal(value) && ndims(value) == 3 && ...
    size(value, 3) == 3;
end
