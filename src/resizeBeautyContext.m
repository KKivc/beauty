function resizedContext = resizeBeautyContext(context, targetImageSize, ...
        targetFaceBox, targetImage)
%RESIZEBEAUTYCONTEXT 将 v3.0/v3.1/V4 Context 迁移到另一尺寸。
%   T08 起生产链输出 V4 分层 Context，源 Context 允许是 '4.0'：带目标
%   原图的分支在目标尺寸上从语义重新构建全部派生字段与 canonical 分
%   层；三参数轻量分支只缩放 compat alias 字段，输出保持 v3.1 形态
%   （分层刷新契约由后续 Ticket 处理，缺失目标原图时不得伪造分层）。

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
    [runtimeMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
        targetImage, resizedContext, double(targetFaceBox));
    migration = struct( ...
        'status', 'resizedAndRegenerated', ...
        'sourceSchemaVersion', schemaVersionText(context.schemaVersion), ...
        'message', '原尺寸 Context 已按目标图像重新生成运行时派生产物。');
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
% 轻量分支没有目标原图，无法重建/缩放 canonical 分层，输出保持
% v3.1 形态（仅 compat alias），由旧 normalize 路径继续消费。
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
    'message', '已按目标尺寸缩放 v3.1 Context 派生字段。'), ...
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
