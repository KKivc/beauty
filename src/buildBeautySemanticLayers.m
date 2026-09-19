function [semantic, processability] = buildBeautySemanticLayers( ...
        regions, regionConfidence, skinMask, bodySkinMask)
%BUILDBEAUTYSEMANTICLAYERS 构建 V4 semantic 与 processability 分层。
%   semantic 层回答"这里是什么区域"，processability 层回答"这里是否
%   允许进入皮肤算法"；两者都与 protection 解耦：输入只有解析语义和
%   当前皮肤域，不读取任何 protection/strength 字段，因此
%   processability.skin 不等于 1-protection。
%
%   semantic 层结构：
%     regions / confidence — Face Parsing 19 类（faceParsingClassNames
%       词表）的原始语义概率与置信度，键名与取值满足
%       normalizeBeautyContextV4 的 semantic 校验规则；
%     分组语义字段（策略层消费的稳定视图，值为 HxW double、[0,1]）：
%       faceSkin — {'skin','nose','leftEar','rightEar'}（与生产
%         faceProbability 同一来源映射）；
%       nose     — {'nose'}；
%       ear      — {'leftEar','rightEar'}；
%       eye      — {'leftEye','rightEye'}；
%       brow     — {'leftBrow','rightBrow'}；
%       lip      — {'mouth','upperLip','lowerLip'}；
%       hair     — {'hair'}；
%       neck     — {'neck'}；
%       bodySkin — SCHP 身体皮肤（调用方传入 buildBodySkinMaskFromSchp
%         合并后的结果；Face Parsing 19 类没有躯干/四肢类别，SCHP
%         合并前传 []，本函数输出全零，不伪造 body 语义）。
%     分组字段的置信度与 union 规则与 buildBeautyContextFromParsing
%     的 semanticUnion 相同：逐类别 min(region, confidence)，再跨类别
%     取 max；bodySkin 的置信度已由 SCHP 侧颜色/连通性校验折算。
%
%   processability 层结构：
%     skin — 允许进入皮肤算法的最终皮肤域，即合并脸/颈皮肤与 SCHP
%       身体皮肤后的 skinMask。它只由解析语义与皮肤域决定，不读取
%       protection 字段；兼容阶段与 compat 字段 skinMask bit-exact，
%       后续 Region Policy Ticket 才允许在语义层内重新划定。
%
%   刷新纪律：prepareBeautyContext 在合并 SCHP 身体皮肤并规范化后
%   必须用最终 regions/regionConfidence/skinMask/bodySkinMask 重新
%   调用本函数，覆盖 build 阶段的初版分层；resize 路径的分层刷新
%   契约由后续 Ticket 处理。
%
%   输入参数：
%     regions / regionConfidence — 含 faceParsingClassNames 全部类别
%       的 HxW 概率/置信度结构体；
%     skinMask    — 当前皮肤域 HxW，值域 [0,1]；
%     bodySkinMask — SCHP 身体皮肤 HxW 或 []（未合并时），值域 [0,1]。

names = faceParsingClassNames();
[regions, regionConfidence, imageSize] = validateSemantics( ...
    regions, regionConfidence, names);
skinMask = validateLayerMask(skinMask, imageSize, 'skinMask', true);
if isempty(bodySkinMask)
    bodySkin = zeros(imageSize);
else
    bodySkin = validateLayerMask(bodySkinMask, imageSize, ...
        'bodySkinMask', true);
end

semantic = struct( ...
    'regions', regions, ...
    'confidence', regionConfidence);
groupedSources = struct( ...
    'faceSkin', {{'skin', 'nose', 'leftEar', 'rightEar'}}, ...
    'nose', {{'nose'}}, ...
    'ear', {{'leftEar', 'rightEar'}}, ...
    'eye', {{'leftEye', 'rightEye'}}, ...
    'brow', {{'leftBrow', 'rightBrow'}}, ...
    'lip', {{'mouth', 'upperLip', 'lowerLip'}}, ...
    'hair', {{'hair'}}, ...
    'neck', {{'neck'}});
groupedNames = fieldnames(groupedSources);
for index = 1:numel(groupedNames)
    name = groupedNames{index};
    semantic.(name) = semanticUnion(regions, regionConfidence, ...
        groupedSources.(name));
end
semantic.bodySkin = bodySkin;

processability = struct('skin', skinMask);
end

function [regions, regionConfidence, imageSize] = validateSemantics( ...
        regions, regionConfidence, names)
if ~isstruct(regions) || ~isscalar(regions) || ...
        ~isstruct(regionConfidence) || ~isscalar(regionConfidence)
    error('buildBeautySemanticLayers:InvalidSemantics', ...
        'regions 与 regionConfidence 必须是标量结构体。');
end
missing = names(~isfield(regions, names) | ~isfield(regionConfidence, names));
if ~isempty(missing)
    error('buildBeautySemanticLayers:InvalidSemantics', ...
        '解析语义缺少类别：%s。', strjoin(missing, '、'));
end
imageSize = size(regions.(names{1}));
regions = copyValidatedSemantics(regions, names, 'regions', imageSize);
regionConfidence = copyValidatedSemantics(regionConfidence, names, ...
    'regionConfidence', imageSize);
end

function values = copyValidatedSemantics(source, names, fieldName, imageSize)
values = struct();
for index = 1:numel(names)
    name = names{index};
    values.(name) = validateLayerMask(source.(name), imageSize, ...
        sprintf('%s.%s', fieldName, name), true);
end
values = orderfields(values, names);
end

function value = validateLayerMask(value, imageSize, name, requireSize)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('buildBeautySemanticLayers:InvalidMask', ...
        '字段 %s 的类型或取值范围无效。', name);
end
if requireSize && ~isequal(size(value), imageSize)
    error('buildBeautySemanticLayers:InvalidMask', ...
        '字段 %s 的尺寸与解析语义不匹配。', name);
end
value = double(value);
end

function probability = semanticUnion(regions, confidence, names)
probability = zeros(size(regions.(names{1})));
for index = 1:numel(names)
    probability = max(probability, min(regions.(names{index}), ...
        confidence.(names{index})));
end
probability = min(max(double(probability), 0), 1);
end
