function resizedContext = resizeBeautyContext(context, targetImageSize, ...
        targetFaceBox, targetImage)
%RESIZEBEAUTYCONTEXT 将 v3.0/v3.1/V4 Context 迁移到另一尺寸。
%   T09 起本入口是 V4 Context preview↔full-size 之间唯一的 resize/
%   recompute 契约点，两条路径的规则如下。
%
%   四参数路径（带目标原图，authoritative recompute，输出 '4.0'）：
%     1. semantic probabilities/confidence — 逐类双线性插值缩放并重新
%        裁剪 [0,1]，再在目标尺寸由 buildBeautyContextFromParsing 重建
%        semantic 分层（分组语义按同一 union 规则从缩放后概率重推）。
%     2. processability 与 semantic.bodySkin — 先合并缩放后的脸外/
%        SCHP 身体皮肤得到最终皮肤域，再由 buildBeautySemanticLayers
%        按"最终 regions + 最终皮肤域"刷新分层；分层不得停留在合并
%        前的旧值。源 Context 缺少 bodySkinMask 时 bodySkin 语义保持
%        全零，不把颈部解析语义伪造成 body。
%     3. soft protection（T31 起 protection 层的规范双门控
%        target.*/support.* 与过渡扁平字段）与全部 compat
%        派生字段 — 由 rebuildBeautyDerivedMasks 在目标分辨率重算，
%        不缩放预览侧数值。
%     4. protection.hard — 由目标图像的 hardProtectionMask 原样重建，
%        生成即二值；本契约禁止任何路径把缩放产生的灰边带入 compose
%        identity。
%     5. image-dependent policy evidence（periocular/nostril/
%        noseStructure/lip/edgeDetail/structureGradient/darkDetail，
%        按当前 builder 全部依赖图像内容）— 由桥接在目标分辨率重算，
%        禁止只缩放预览 evidence。
%     6. runtimeCache — 在目标尺寸全量重建，是唯一可被保存链路当作
%        full authoritative 复用的 resize 缓存。
%
%   三参数轻量路径（无目标原图，显式 compatibility path，输出 '3.1'）：
%     只用双线性插值 + 裁剪 [0,1] 缩放 v3.1 compat 字段，供旧 consumer
%     与诊断入口继续消费。V4 源的 canonical 分层在此显式丢弃——缺失
%     目标原图时不得伪造分层，也不得用缩放值冒充目标分辨率的
%     evidence/protection；不生成 runtimeCache。migrationDiagnostics.
%     status='resized' 是兼容路径标记（同时允许下游按部分语义规范
%     化），下游保存链路不得把该产物当作 full authoritative Context，
%     也不得借它复用预览缓存。
%
%   T08 起生产链输出 V4 分层 Context，源 Context 允许是 '4.0'：带目标
%   原图的分支在目标尺寸上从语义重新构建全部派生字段与 canonical 分
%   层；三参数轻量分支只缩放 compat alias 字段，输出保持 v3.1 形态。

if ~isstruct(context) || ~isscalar(context)
    error('resizeBeautyContext:InvalidContext', ...
        '必须提供标量 Beauty Context。');
end
hasTargetImage = nargin >= 4 && ~isempty(targetImage);
validateSourceContext(context, ~hasTargetImage);
sourceSize = size(context.skinMask);
validateTarget(targetImageSize, targetFaceBox);
targetSize = targetImageSize(1:2);

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
    % 前一步 buildBeautyContextFromParsing 已经基于未合并的脸外皮肤
    % 生成过派生字段；合并目标尺寸的身体皮肤后，由权威桥接清掉旧字段
    % 并按最终 skinMask 重建，避免 runtime cache 携带不一致的结构和强度图。
    rebuilt = rebuildBeautyDerivedMasks(targetImage, rebuilt, targetFaceBox);
    resizedContext = normalizeBeautyContext(targetImage, ...
        double(targetFaceBox), rebuilt);
    % T09 分层刷新契约：合并缩放皮肤后，semantic/processability 必须
    % 以最终 regions 与皮肤域重建（与 prepareBeautyContext 的刷新纪律
    % 一致），不得停留在 build 阶段基于合并前皮肤域的初版分层。源
    % Context 缺少 bodySkinMask 时 bodySkin 语义保持全零，不伪造 body。
    if isfield(context, 'bodySkinMask')
        layerBodySkin = resizedContext.bodySkinMask;
    else
        layerBodySkin = [];
    end
    [resizedContext.semantic, resizedContext.processability] = ...
        buildBeautySemanticLayers(resizedContext.regions, ...
        resizedContext.regionConfidence, resizedContext.skinMask, ...
        layerBodySkin);
    [runtimeMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
        targetImage, resizedContext, double(targetFaceBox));
    migration = struct( ...
        'status', 'resizedAndRegenerated', ...
        'sourceSchemaVersion', schemaVersionText(context.schemaVersion), ...
        'message', '原尺寸 Context 已按目标图像重建 V4 分层、派生字段与运行时缓存。');
    resizedContext.migrationDiagnostics = migration;
    resizedContext.runtimeCache = buildBeautyRuntimeCache( ...
        targetImage, double(targetFaceBox), runtimeMasks, maskDiagnostics, migration);
    return;
end

% 三参数入口没有目标原图，不能重新计算依赖像素的派生结果；它仍需
% 完整携带语义、皮肤、保护和强度字段，避免下游规范化时回落到旧尺寸。
[sourceChroma, ~] = resolveChromaProtectionMask(context, sourceSize, ...
    'resizeBeautyContext:InvalidContext', ...
    'resizeBeautyContext:ChromaProtectionConflict');
resizedSkin = resizeLightweightMask(context.skinMask, targetSize);
resizedFaceSkin = resizeLightweightMask(context.faceSkinMask, targetSize);
resizedNonFaceSkin = resizeLightweightMask(context.nonFaceSkinMask, targetSize);
resizedTexture = resizeLightweightMask(context.textureProtectionMask, targetSize);
resizedStructure = resizeLightweightMask(context.structureProtectionMask, targetSize);
if isfield(context, 'whiteningProtectionMask')
    resizedWhitening = resizeLightweightMask( ...
        context.whiteningProtectionMask, targetSize);
else
    % 没有目标原图时无法按 Feature 身份重建；显式标记为待重建，
    % 由带目标图像的规范化入口重新生成独立亮度保护。
    resizedWhitening = zeros(targetSize, 'single');
end
resizedChroma = resizeLightweightMask(sourceChroma, targetSize);
resizedStrength = resizeLightweightMask(context.strengthMap, targetSize);
resizedFaceStrength = resizeLightweightMask(context.faceStrengthMap, targetSize);
resizedNonFaceStrength = resizeLightweightMask(context.nonFaceStrengthMap, targetSize);
% 轻量分支没有目标原图，无法重建/缩放 canonical 分层：V4 源的分层
% 在此显式丢弃（不得用缩放值冒充目标分辨率的 evidence/protection），
% 输出保持 v3.1 兼容形态（仅 compat alias），由旧 normalize 路径继续
% 消费；兼容路径标记见 migrationDiagnostics。
resizedContext = struct( ...
    'skinMask', resizedSkin, ...
    'faceSkinMask', resizedFaceSkin, ...
    'nonFaceSkinMask', resizedNonFaceSkin, ...
    'textureProtectionMask', resizedTexture, ...
    'structureProtectionMask', resizedStructure, ...
    'whiteningProtectionMask', resizedWhitening, ...
    'chromaProtectionMask', resizedChroma, ...
    'toneProtectionMask', resizedChroma, ...
    'strengthMap', resizedStrength, ...
    'faceStrengthMap', resizedFaceStrength, ...
    'nonFaceStrengthMap', resizedNonFaceStrength, ...
    'schemaVersion', '3.1', ...
    'imageSize', [targetSize, 3], ...
    'faceBox', double(targetFaceBox), ...
    'faceScale', min(double(targetFaceBox(3:4))), ...
    'migrationDiagnostics', struct( ...
    'status', 'resized', ...
    'sourceSchemaVersion', schemaVersionText(context.schemaVersion), ...
    'message', '轻量兼容迁移：仅缩放 v3.1 compat 派生字段，未重建 V4 分层与运行时缓存。'), ...
    'protectionMasks', struct( ...
    'texture', resizedTexture, ...
    'structure', resizedStructure, ...
    'whitening', resizedWhitening, ...
    'chroma', resizedChroma, ...
    'tone', resizedChroma));
if isfield(context, 'bodySkinMask')
    if isequal(context.bodySkinMask, context.nonFaceSkinMask)
        resizedContext.bodySkinMask = resizedNonFaceSkin;
    else
        resizedContext.bodySkinMask = resizeLightweightMask( ...
            context.bodySkinMask, targetSize);
    end
end
if isfield(context, 'regions') && isfield(context.regions, 'nose')
    % 轻量入口只保留已有的鼻部语义，完整语义仅在目标原图分支使用。
    resizedContext.regions = struct('nose', single(resizeMask( ...
        context.regions.nose, targetSize)));
elseif isfield(context, 'semanticProbabilities')
    names = faceParsingClassNames();
    noseIndex = find(strcmp(names, 'nose'), 1);
    probabilities = readSemanticStack(context, sourceSize, ...
        'semanticProbabilities');
    resizedContext.regions = struct('nose', single(resizeMask( ...
        probabilities(:, :, noseIndex), targetSize)));
end
if isfield(context, 'regionConfidence') && ...
        isfield(context.regionConfidence, 'nose')
    resizedContext.regionConfidence = struct('nose', single(resizeMask( ...
        context.regionConfidence.nose, targetSize)));
elseif isfield(context, 'semanticConfidence') || ...
        isfield(context, 'semanticProbabilities')
    names = faceParsingClassNames();
    noseIndex = find(strcmp(names, 'nose'), 1);
    confidence = readSemanticStack(context, sourceSize, ...
        'semanticConfidence');
    resizedContext.regionConfidence = struct('nose', single(resizeMask( ...
        confidence(:, :, noseIndex), targetSize)));
end
end

function [chromaProtectionMask, hasChromaProtectionMask] = ...
        validateSourceContext(context, requireDerived)
if ~isfield(context, 'schemaVersion') || ~isKnownSourceVersion( ...
        context.schemaVersion)
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 必须是版本 3.0、3.1 或 4.0（V4 分层）。');
end
if any(isfield(context, {'featureProtectionMask', 'hardProtectionMask'}))
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 包含已移除的旧保护字段。');
end
required = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'imageSize', 'faceBox'};
if ~all(isfield(context, required))
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 缺少 v3 字段。');
end
sourceSize = size(context.skinMask);
for index = 1:3
    validateSourceMask(context.(required{index}), sourceSize, ...
        required{index});
end
if ~isnumeric(context.imageSize) || ~isequal(size(context.imageSize), [1, 3]) || ...
        ~isequal(double(context.imageSize), [sourceSize, 3])
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 的 imageSize 无效。');
end
if ~isnumeric(context.faceBox) || ~isequal(size(context.faceBox), [1, 4]) || ...
        ~isreal(context.faceBox) || any(~isfinite(context.faceBox)) || ...
        context.faceBox(1) < 1 || context.faceBox(2) < 1 || ...
        any(context.faceBox(3:4) <= 0) || ...
        context.faceBox(1) + context.faceBox(3) - 1 > sourceSize(2) || ...
        context.faceBox(2) + context.faceBox(4) - 1 > sourceSize(1)
    error('resizeBeautyContext:InvalidContext', ...
        '源 Context 的 faceBox 无效。');
end

[chromaProtectionMask, hasChromaProtectionMask] = ...
    resolveChromaProtectionMask(context, sourceSize, ...
    'resizeBeautyContext:InvalidContext', ...
    'resizeBeautyContext:ChromaProtectionConflict');
derived = {'textureProtectionMask', 'structureProtectionMask', ...
    'strengthMap', 'faceStrengthMap', 'nonFaceStrengthMap'};
if requireDerived
    if ~hasChromaProtectionMask || ~all(isfield(context, derived))
        error('resizeBeautyContext:InvalidContext', ...
            '三参数迁移需要完整的 v3 派生字段。');
    end
end
for index = 1:numel(derived)
    name = derived{index};
    if isfield(context, name)
        validateSourceMask(context.(name), sourceSize, name);
    end
end
if isfield(context, 'whiteningProtectionMask')
    validateSourceMask(context.whiteningProtectionMask, sourceSize, ...
        'whiteningProtectionMask');
end
if isfield(context, 'bodySkinMask')
    validateSourceMask(context.bodySkinMask, sourceSize, 'bodySkinMask');
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

function valid = isKnownSourceVersion(value)
%ISKNOWNSOURCEVERSION v3.0/v3.1 compat 与 V4 layered 都是合法源形态；
%   V4 源经 compat alias 读取语义与皮肤字段（producer 始终携带）。
if isstring(value) && isscalar(value)
    value = char(value);
end
valid = isV3Version(value) || (ischar(value) && size(value, 1) == 1 && ...
    strcmp(value, '4.0'));
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

function values = readSemanticStack(context, sourceSize, name)
if isfield(context, name)
    values = context.(name);
elseif strcmp(name, 'semanticConfidence')
    if isfield(context, 'semanticProbabilities')
        values = context.semanticProbabilities;
    elseif allowsPartialSemantics(context)
        values = stackPartialSemantics(context.regions, ...
            faceParsingClassNames(), sourceSize);
    else
        error('resizeBeautyContext:InvalidContext', ...
            '源 Context 缺少字段 %s。', name);
    end
else
    names = faceParsingClassNames();
    if allowsPartialSemantics(context)
        values = stackPartialSemantics(context.regions, names, sourceSize);
    else
        values = stackSemantics(context.regions, names);
    end
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

function values = stackPartialSemantics(semanticStruct, names, imageSize)
if ~isstruct(semanticStruct) || ~isscalar(semanticStruct)
    error('resizeBeautyContext:InvalidContext', ...
        '轻量 Context 的语义字段必须是标量结构体。');
end
values = zeros([imageSize, numel(names)], 'single');
for index = 1:numel(names)
    name = names{index};
    if isfield(semanticStruct, name)
        value = semanticStruct.(name);
        if ~isnumeric(value) || ~isreal(value) || ...
                ~isequal(size(value), imageSize) || ...
                any(~isfinite(value(:))) || any(value(:) < 0) || ...
                any(value(:) > 1)
            error('resizeBeautyContext:InvalidContext', ...
                '轻量 Context 的语义类别 %s 无效。', name);
        end
        values(:, :, index) = single(value);
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

function output = resizeMask(value, targetSize)
output = min(1, max(0, imresize(double(value), targetSize, ...
    'bilinear')));
end

function output = resizeLightweightMask(value, targetSize)
output = single(resizeMask(value, targetSize));
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
