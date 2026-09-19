function context = normalizeBeautyContextV4(context, imageSize, faceBox)
%NORMALIZEBEAUTYCONTEXTV4 校验并规范化 V4 分层 Context 的 canonical 字段。
%   V4 canonical 结构（expand 阶段，schemaVersion='4.0'）：
%     semantic.regions / semantic.confidence — 语义区域，键名限定为
%       faceParsingClassNames 的 19 类词表；
%     processability / evidence / protection — 分层容器，允许先以空
%       结构体出现，由 T05/T06/T07 的 builder 逐步填充；
%     diagnostics — schema 与迁移元数据，必须是标量结构体。
%   任一 canonical 层存在即为合法（partial V4）；缺失的层保持缺失。
%   本函数是 normalizeBeautyContext 与 migrateBeautyContext 共用的
%   V4 reader 核心：只做结构校验与规范化（logical → double、补齐
%   imageSize/faceBox/faceScale 身份字段），不重建派生 Mask，也不
%   改写顶层 compat alias。v3.0/v3.1 输入仍走 normalizeBeautyContext
%   的既有路径，生产者当前继续输出 v3.1。
%
%   输入参数：
%     context   — schemaVersion 为 '4.0'（或数值 4）的标量结构体。
%     imageSize — 参考尺寸 [H W 3] 或 [H W]；为空时跳过尺寸相关校验，
%                 也不补齐 context.imageSize。
%     faceBox   — 参考人脸框 [1 4]；为空时跳过 faceBox/faceScale 校验。

if ~isstruct(context) || ~isscalar(context)
    error('normalizeBeautyContextV4:InvalidStructure', ...
        'V4 Beauty Context 必须是标量结构体。');
end

canonicalLayers = {'semantic', 'processability', 'evidence', 'protection'};
present = isfield(context, canonicalLayers);
if ~any(present)
    error('normalizeBeautyContextV4:InvalidStructure', ...
        'V4 Context 缺少 canonical 分层字段（semantic/processability/evidence/protection）。');
end
for index = 1:numel(canonicalLayers)
    if present(index) && (~isstruct(context.(canonicalLayers{index})) || ...
            ~isscalar(context.(canonicalLayers{index})))
        error('normalizeBeautyContextV4:InvalidStructure', ...
            'V4 canonical 层 %s 必须是标量结构体。', canonicalLayers{index});
    end
end

if present(1)
    context.semantic = normalizeSemanticLayer(context.semantic, imageSize);
end
for index = 2:numel(canonicalLayers)
    if present(index)
        context.(canonicalLayers{index}) = normalizeMaskLayer( ...
            context.(canonicalLayers{index}), imageSize, ...
            canonicalLayers{index});
    end
end
if isfield(context, 'diagnostics') && (~isstruct(context.diagnostics) || ...
        ~isscalar(context.diagnostics))
    error('normalizeBeautyContextV4:InvalidStructure', ...
        'V4 canonical 层 diagnostics 必须是标量结构体。');
end

context = normalizeIdentityFields(context, imageSize, faceBox);
context.schemaVersion = '4.0';
end

function semantic = normalizeSemanticLayer(semantic, imageSize)
if ~isfield(semantic, 'regions') && ~isfield(semantic, 'confidence')
    error('normalizeBeautyContextV4:InvalidStructure', ...
        'V4 semantic 层缺少 regions/confidence 字段。');
end
names = faceParsingClassNames();
if isfield(semantic, 'regions')
    semantic.regions = normalizeNamedMasks(semantic.regions, imageSize, ...
        names, 'semantic.regions');
end
if isfield(semantic, 'confidence')
    semantic.confidence = normalizeNamedMasks(semantic.confidence, ...
        imageSize, names, 'semantic.confidence');
end
end

function values = normalizeNamedMasks(value, imageSize, names, fieldName)
if ~isstruct(value) || ~isscalar(value) || isempty(fieldnames(value))
    error('normalizeBeautyContextV4:InvalidSemantic', ...
        '字段 %s 必须是非空语义结构体。', fieldName);
end
fields = fieldnames(value);
for index = 1:numel(fields)
    name = fields{index};
    if ~any(strcmp(name, names))
        error('normalizeBeautyContextV4:InvalidSemantic', ...
            '字段 %s 含未知语义类别 %s。', fieldName, name);
    end
    value.(name) = validateMaskValue(value.(name), imageSize, ...
        sprintf('%s.%s', fieldName, name));
end
values = value;
end

function layer = normalizeMaskLayer(layer, imageSize, layerName)
fields = fieldnames(layer);
for index = 1:numel(fields)
    layer.(fields{index}) = validateMaskValue(layer.(fields{index}), ...
        imageSize, sprintf('%s.%s', layerName, fields{index}));
end
end

function value = validateMaskValue(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('normalizeBeautyContextV4:InvalidMask', ...
        '字段 %s 的类型或取值范围无效。', name);
end
if ~isempty(imageSize) && ~isequal(size(value), imageSize(1:2))
    error('normalizeBeautyContextV4:InvalidMask', ...
        '字段 %s 的尺寸与输入图像不匹配。', name);
end
value = double(value);
end

function context = normalizeIdentityFields(context, imageSize, faceBox)
if ~isempty(imageSize)
    if isfield(context, 'imageSize')
        if ~isnumeric(context.imageSize) || ~isreal(context.imageSize) || ...
                ~isequal(size(context.imageSize), [1, 3]) || ...
                any(~isfinite(context.imageSize)) || ...
                ~isequal(double(context.imageSize(1:2)), ...
                double(imageSize(1:2))) || ...
                (numel(imageSize) > 2 && ...
                double(context.imageSize(3)) ~= double(imageSize(3)))
            error('normalizeBeautyContextV4:SizeMismatch', ...
                'V4 Context 的 imageSize 与输入图像不匹配。');
        end
    elseif numel(imageSize) == 3
        context.imageSize = imageSize;
    end
end
if ~isempty(faceBox)
    if isfield(context, 'faceBox')
        if ~isnumeric(context.faceBox) || ~isreal(context.faceBox) || ...
                ~isequal(size(context.faceBox), [1, 4]) || ...
                any(~isfinite(context.faceBox)) || ...
                any(abs(double(context.faceBox) - double(faceBox)) > 1e-9)
            error('normalizeBeautyContextV4:SizeMismatch', ...
                'V4 Context 的 faceBox 与当前人脸框不匹配。');
        end
    else
        context.faceBox = double(faceBox);
    end
    context.faceScale = min(double(faceBox(3:4)));
end
end
