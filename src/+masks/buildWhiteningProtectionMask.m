function [whiteningProtectionMask, diagnostics] = ...
        buildWhiteningProtectionMask(inputImage, beautyContext, faceBox, ...
        textureDiagnostics)
%BUILDWHITENINGPROTECTIONMASK 生成仅供亮度美白使用的五官过渡保护。
%   保护依据语义特征身份分别计算半径；过渡只写入合格皮肤，
%   多个特征重叠时取最大值，避免眉毛过渡削弱眼、唇和鼻孔边界。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    if isfield(beautyContext, 'faceBox')
        faceBox = beautyContext.faceBox;
    else
        error('masks:InvalidFaceBox', '必须提供人脸框。');
    end
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
skinMask = readMask(beautyContext, 'skinMask', imageSize);
regions = semanticRegions(beautyContext, imageSize);
confidence = semanticConfidence(beautyContext, imageSize);
faceScale = min(double(faceBox(3:4)));
qualifiedSkin = skinMask >= .5;

if nargin < 4 || ~isstruct(textureDiagnostics) || ...
        ~isscalar(textureDiagnostics)
    [~, textureDiagnostics] = masks.buildTextureProtectionMask( ...
        inputImage, beautyContext, faceBox);
end

eyeCore = semanticUnion(regions, confidence, ...
    {'leftEye', 'rightEye'}) >= .60;
lipCore = semanticUnion(regions, confidence, ...
    {'mouth', 'upperLip', 'lowerLip'}) >= .60;
browCore = semanticUnion(regions, confidence, ...
    {'leftBrow', 'rightBrow'}) >= .45;
nostrilCore = diagnosticMask(textureDiagnostics, 'nostrilCore', imageSize);
lashCore = diagnosticMask(textureDiagnostics, 'lashCore', imageSize);

radii = struct( ...
    'eye', .0125 * faceScale, ...
    'lip', .0100 * faceScale, ...
    'nostril', .0075 * faceScale, ...
    'brow', .00375 * faceScale, ...
    'lash', .00375 * faceScale);

eyeTransition = skinTransition(eyeCore, qualifiedSkin, radii.eye, .50);
lipTransition = skinTransition(lipCore, qualifiedSkin, radii.lip, .60);
nostrilTransition = skinTransition(nostrilCore, qualifiedSkin, ...
    radii.nostril, .60);
browTransition = skinTransition(browCore, qualifiedSkin, radii.brow, 2, 0);
lashTransition = skinTransition(lashCore, qualifiedSkin, radii.lash, .50);

% 取最大值合并重叠保护；这里明确不加入整个鼻部语义区域。
% 特征核心由纹理模块的硬保护负责，亮度 Mask 只写入合格皮肤过渡。
whiteningProtectionMask = max(cat(3, eyeTransition, lipTransition, ...
    nostrilTransition, browTransition, lashTransition), [], 3);
whiteningProtectionMask = min(max(double(whiteningProtectionMask), 0), 1);

diagnostics = struct( ...
    'faceScale', faceScale, ...
    'qualifiedSkin', qualifiedSkin, ...
    'radii', radii, ...
    'featureCore', eyeCore | lipCore | nostrilCore | browCore | lashCore, ...
    'eyeCore', eyeCore, ...
    'lipCore', lipCore, ...
    'nostrilCore', nostrilCore, ...
    'browCore', browCore, ...
    'lashCore', lashCore, ...
    'eyeTransition', eyeTransition, ...
    'lipTransition', lipTransition, ...
    'nostrilTransition', nostrilTransition, ...
    'browTransition', browTransition, ...
    'lashTransition', lashTransition, ...
    'noseSemanticExcluded', true, ...
    'whiteningProtectionMask', whiteningProtectionMask);
end

function transition = skinTransition(core, qualifiedSkin, radius, power, ...
        pixelPadding)
transition = zeros(size(core));
if ~any(core(:))
    return;
end
if nargin < 4
    power = 1;
end
if nargin < 5
    pixelPadding = 1;
end
distance = bwdist(core);
% 像素距离包含离散边界，额外一个像素用于保持小脸上过渡连续。
effectiveRadius = max(double(radius) + double(pixelPadding), 1);
weight = max(0, 1 - distance / effectiveRadius);
transition(qualifiedSkin) = smoothStep(weight(qualifiedSkin), 0, 1) .^ power;
end

function evidence = semanticUnion(regions, confidence, names)
evidence = zeros(size(regions.(names{1})));
for index = 1:numel(names)
    evidence = max(evidence, min(regions.(names{index}), ...
        confidence.(names{index})));
end
evidence = min(max(double(evidence), 0), 1);
end

function semantics = semanticRegions(context, imageSize)
if isfield(context, 'regions')
    semantics = context.regions;
else
    semantics = unstackSemantics(context.semanticProbabilities, imageSize);
end
semantics = validateSemantics(semantics, imageSize);
end

function semantics = semanticConfidence(context, imageSize)
if isfield(context, 'regionConfidence')
    semantics = context.regionConfidence;
elseif isfield(context, 'semanticConfidence')
    semantics = unstackSemantics(context.semanticConfidence, imageSize);
else
    semantics = semanticRegions(context, imageSize);
end
semantics = validateSemantics(semantics, imageSize);
end

function semantics = unstackSemantics(values, imageSize)
names = faceParsingClassNames();
if ~isnumeric(values) || ~isreal(values) || ndims(values) ~= 3 || ...
        ~isequal(size(values), [imageSize, numel(names)]) || ...
        any(~isfinite(values(:))) || any(values(:) < 0) || ...
        any(values(:) > 1)
    error('masks:InvalidContext', '语义概率堆栈无效。');
end
semantics = struct();
for index = 1:numel(names)
    semantics.(names{index}) = double(values(:, :, index));
end
end

function semantics = validateSemantics(semantics, imageSize)
names = faceParsingClassNames();
if ~isstruct(semantics) || ~isscalar(semantics)
    error('masks:InvalidContext', '语义概率必须是标量结构体。');
end
for index = 1:numel(names)
    name = names{index};
    if ~isfield(semantics, name)
        error('masks:InvalidContext', '语义类别 %s 缺失。', name);
    end
    value = semantics.(name);
    if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
            ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
            any(value(:) < 0) || any(value(:) > 1)
        error('masks:InvalidContext', '语义类别 %s 无效。', name);
    end
    semantics.(name) = double(value);
end
end

function value = diagnosticMask(diagnostics, name, imageSize)
if ~isfield(diagnostics, name)
    value = false(imageSize);
    return;
end
value = diagnostics.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', '纹理诊断字段 %s 无效。', name);
end
value = value >= .5;
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('masks:InvalidContext', 'Context 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 %s 无效。', name);
end
value = double(value);
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function validateImageAndFace(inputImage, faceBox)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('masks:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > size(inputImage, 2) || ...
        faceBox(2) + faceBox(4) - 1 > size(inputImage, 1)
    error('masks:InvalidFaceBox', '人脸框超出图像范围。');
end
end
