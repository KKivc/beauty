function migratedContext = migrateBeautyContext(inputImage, faceBox, context, targetSchema)
%MIGRATEBEAUTYCONTEXT 显式迁移 Beauty Context。
%   T08 起默认生产输出为 V4 分层 Context（beautyPipelineContract）；
%   本入口用于把历史 v3.0/v3.1 Context 显式迁移到指定目标：默认目标
%   仍为 v3.1（既有行为不变），显式传入 targetSchema='4.0'（或 'v4'）
%   时迁移到 V4 canonical 分层结构。支持的调用形式：
%     migrateBeautyContext(context)
%     migrateBeautyContext(context, targetSchema)
%     migrateBeautyContext(inputImage, faceBox, context)
%     migrateBeautyContext(context, inputImage, faceBox)
%     migrateBeautyContext(inputImage, faceBox, context, targetSchema)
%     migrateBeautyContext(context, inputImage, faceBox, targetSchema)
%   仅有 Context 时可迁移字段和 alias；若 Context 携带原图缓存，则
%   自动使用该原图重新生成运行时产物。提供原图时始终重建缓存，
%   不会把历史 3.0 派生产物仅补上 alias 后标记为当前算法产物。
%   V4 输入迁移到 V4 为幂等操作：只做 reader 校验与规范化，不重建
%   缓存（缓存兼容由 artifactVersion 把握，见 beautifyImage）。

if nargin == 1
    migratedContext = migrateContextOnly(inputImage, 'v3.1');
    return;
end
if nargin == 2
    migratedContext = migrateContextOnly(inputImage, ...
        normalizeTargetSchema(faceBox));
    return;
end
if nargin > 4
    error('migrateBeautyContext:InvalidArguments', ...
        '迁移最多接受 inputImage、faceBox、Context 和 targetSchema 四个参数。');
end
if nargin == 4
    target = normalizeTargetSchema(targetSchema);
else
    target = 'v3.1';
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
migratedContext = migrateWithImage(sourceImage, sourceFaceBox, ...
    sourceContext, target);
end

function migratedContext = migrateContextOnly(sourceContext, target)
validateContext(sourceContext, target);
if strcmp(target, '4.0') && isV4Version(sourceContext.schemaVersion)
    % V4 输入迁移到 V4 保持幂等：有缓存原图时走 reader 做一致性校验
    % 与规范化，否则只做与图像无关的结构校验后原样返回。
    if hasCachedInput(sourceContext)
        migratedContext = normalizeBeautyContext( ...
            sourceContext.runtimeCache.inputImage, sourceContext.faceBox, ...
            sourceContext);
    else
        migratedContext = normalizeBeautyContextV4(sourceContext, ...
            maskReferenceSize(sourceContext), ...
            validFaceBoxOrNull(sourceContext));
    end
    return;
end
sourceSchemaVersion = schemaVersionText(sourceContext.schemaVersion);
if strcmp(target, '4.0')
    if hasCachedInput(sourceContext)
        sourceImage = sourceContext.runtimeCache.inputImage;
        migrated = migrateWithImage(sourceImage, sourceContext.faceBox, ...
            sourceContext, 'v3.1');
        imageSize = size(sourceImage);
    else
        migrated = migrateWithoutImage(sourceContext);
        imageSize = size(sourceContext.skinMask);
    end
    migratedContext = toV4Canonical(migrated, sourceSchemaVersion, ...
        imageSize);
    return;
end
% 既有 v3.1 迁移路径（保持不变）。
if hasCachedInput(sourceContext)
    migratedContext = migrateWithImage( ...
        sourceContext.runtimeCache.inputImage, sourceContext.faceBox, ...
        sourceContext, 'v3.1');
else
    migratedContext = migrateWithoutImage(sourceContext);
end
end

function migratedContext = migrateWithImage(inputImage, faceBox, context, target)
validateContext(context, target);
sourceSchemaVersion = schemaVersionText(context.schemaVersion);
if strcmp(target, '4.0') && isV4Version(context.schemaVersion)
    % V4 Context 已是 canonical：按当前输入做 reader 校验/规范化（幂等），
    % 不重建缓存。
    migratedContext = normalizeBeautyContext(inputImage, faceBox, context);
    return;
end
if strcmp(target, '4.0')
    v31Context = migrateWithImage(inputImage, faceBox, context, 'v3.1');
    migratedContext = toV4Canonical(v31Context, sourceSchemaVersion, ...
        size(inputImage));
    return;
end
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

function v4Context = toV4Canonical(context, sourceSchemaVersion, imageSize)
%TOV4CANONICAL 把完整 v3.x Context 包装为 V4 canonical 分层结构。
%   T08 起 canonical 层发布不止 semantic：源 Context 已携带的
%   processability（T05 分层）、evidence（T06 分层）与 protection
%   （T07 分层）原样带入 canonical 层，semantic 分组字段与
%   diagnostics.policyEvidence 元数据不得再丢；pre-T05 旧 Context
%   缺这些层时保持 partial V4（reader 允许缺失层），semantic 层退回
%   由 v3 语义字段构造 regions/confidence。legacy general masks 只
%   作为顶层 compat alias 原样保留，绝不写入 canonical 层。
v4Context = context;
v4Context.schemaVersion = '4.0';
if isfield(context, 'semantic') && isstruct(context.semantic) && ...
        isscalar(context.semantic) && ...
        (isfield(context.semantic, 'regions') || ...
        isfield(context.semantic, 'confidence'))
    % T05 起生产 Context 自带分组语义字段（faceSkin/bodySkin 等），
    % 迁移时原样保留，不从扁平 regions 重造。
    v4Context.semantic = context.semantic;
else
    canonicalRegions = canonicalSemanticRegions(context);
    v4Context.semantic = struct( ...
        'regions', canonicalRegions, ...
        'confidence', canonicalSemanticConfidence(context, canonicalRegions));
end
canonicalLayers = {'semantic'};
deferredLayers = {};
carryLayerNames = {'processability', 'evidence', 'protection'};
for index = 1:numel(carryLayerNames)
    name = carryLayerNames{index};
    if isfield(context, name) && isstruct(context.(name)) && ...
            isscalar(context.(name))
        v4Context.(name) = context.(name);
        canonicalLayers{end + 1} = name;
    else
        deferredLayers{end + 1} = name;
    end
end
canonicalLayers{end + 1} = 'diagnostics';
diagnostics = struct( ...
    'schemaVersion', '4.0', ...
    'sourceSchemaVersion', sourceSchemaVersion, ...
    'canonicalLayers', {canonicalLayers}, ...
    'deferredLayers', {deferredLayers}, ...
    'compatAliases', {{'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'regions', ...
    'regionConfidence', 'semanticProbabilities', ...
    'semanticConfidence'}});
if isfield(context, 'diagnostics') && isstruct(context.diagnostics) && ...
        isscalar(context.diagnostics) && ...
        isfield(context.diagnostics, 'policyEvidence')
    % T06 遗留补齐：policyEvidence 来源/版本元数据随迁移保留。
    diagnostics.policyEvidence = context.diagnostics.policyEvidence;
end
v4Context.diagnostics = diagnostics;
v4Context = normalizeBeautyContextV4(v4Context, imageSize, ...
    validFaceBoxOrNull(context));
end

function regions = canonicalSemanticRegions(context)
names = faceParsingClassNames();
if isfield(context, 'regions') && isstruct(context.regions) && ...
        isscalar(context.regions)
    regions = struct();
    for index = 1:numel(names)
        name = names{index};
        if ~isfield(context.regions, name)
            error('migrateBeautyContext:InvalidContext', ...
                '字段 regions 缺少类别 %s，无法迁移到 V4 semantic 层。', ...
                name);
        end
        regions.(name) = double(context.regions.(name));
    end
elseif isfield(context, 'semanticProbabilities') && ...
        isnumeric(context.semanticProbabilities) && ...
        isreal(context.semanticProbabilities) && ...
        ndims(context.semanticProbabilities) == 3 && ...
        size(context.semanticProbabilities, 3) == numel(names)
    regions = struct();
    for index = 1:numel(names)
        regions.(names{index}) = double( ...
            context.semanticProbabilities(:, :, index));
    end
else
    error('migrateBeautyContext:InvalidContext', ...
        '缺少 regions 或 semanticProbabilities，无法迁移到 V4 semantic 层。');
end
end

function confidence = canonicalSemanticConfidence(context, regions)
names = faceParsingClassNames();
imageSize = size(regions.(names{1}));
if isfield(context, 'regionConfidence') && ...
        isstruct(context.regionConfidence) && ...
        isscalar(context.regionConfidence)
    confidence = struct();
    for index = 1:numel(names)
        name = names{index};
        if isfield(context.regionConfidence, name)
            confidence.(name) = double(context.regionConfidence.(name));
        else
            confidence.(name) = zeros(imageSize);
        end
    end
elseif isfield(context, 'semanticConfidence') && ...
        isnumeric(context.semanticConfidence) && ...
        isreal(context.semanticConfidence) && ...
        ndims(context.semanticConfidence) == 3 && ...
        size(context.semanticConfidence, 3) == numel(names)
    confidence = struct();
    for index = 1:numel(names)
        confidence.(names{index}) = double( ...
            context.semanticConfidence(:, :, index));
    end
else
    % v3 语义约定：置信度缺失时与语义区域一致。
    confidence = regions;
end
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

function validateContext(context, target)
if ~isstruct(context) || ~isscalar(context) || ...
        ~isfield(context, 'schemaVersion')
    error('migrateBeautyContext:InvalidContext', ...
        'Beauty Context 必须是包含 schemaVersion 的标量结构体。');
end
if strcmp(target, '4.0')
    if ~isV3Version(context.schemaVersion) && ...
            ~isV4Version(context.schemaVersion)
        error('migrateBeautyContext:UnsupportedVersion', ...
            '迁移到 V4 只接受 Beauty Context 版本 3.0、3.1 或 4.0。');
    end
    return;
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

function valid = isV4Version(value)
if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
    valid = value == 4;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = ischar(value) && size(value, 1) == 1 && strcmp(value, '4.0');
end

function target = normalizeTargetSchema(value)
if isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value)
    if value == 3.1
        value = 'v3.1';
    elseif value == 4
        value = '4.0';
    end
end
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~(ischar(value) && size(value, 1) == 1)
    error('migrateBeautyContext:UnsupportedTarget', ...
        'targetSchema 必须是 v3.1 或 4.0（V4 canonical）。');
end
switch value
    case {'3.1', 'v3.1'}
        target = 'v3.1';
    case {'4.0', 'v4'}
        target = '4.0';
    otherwise
        error('migrateBeautyContext:UnsupportedTarget', ...
            'targetSchema 只支持 v3.1 或 4.0（V4 canonical），收到：%s。', ...
            value);
end
end

function value = schemaVersionText(version)
if isnumeric(version) && isscalar(version) && version == 3
    value = '3.0';
elseif isnumeric(version) && isscalar(version) && version == 3.1
    value = '3.1';
elseif isnumeric(version) && isscalar(version) && version == 4
    value = '4.0';
elseif isstring(version) && isscalar(version)
    value = char(version);
elseif ischar(version) && size(version, 1) == 1
    value = version;
else
    value = 'unknown';
end
end

function imageSize = maskReferenceSize(context)
imageSize = [];
if isfield(context, 'skinMask') && isnumeric(context.skinMask) && ...
        isreal(context.skinMask) && ~isempty(context.skinMask)
    imageSize = size(context.skinMask);
end
end

function faceBox = validFaceBoxOrNull(context)
faceBox = [];
if isfield(context, 'faceBox') && isnumeric(context.faceBox) && ...
        isreal(context.faceBox) && isequal(size(context.faceBox), [1, 4]) && ...
        all(isfinite(context.faceBox)) && all(context.faceBox(3:4) > 0)
    faceBox = double(context.faceBox);
end
end

function valid = isValidRgbImage(value)
valid = isa(value, 'uint8') && isreal(value) && ndims(value) == 3 && ...
    size(value, 3) == 3;
end
