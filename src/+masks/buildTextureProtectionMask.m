function [textureProtectionMask, diagnostics] = ...
        buildTextureProtectionMask(inputImage, beautyContext, faceBox)
%BUILDTEXTUREPROTECTIONMASK 生成五官和细节的纹理保护 Mask。
%   眉毛使用独立的核心与窄羽化，不与通用遮挡物集合重复计算。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    faceBox = beautyContext.faceBox;
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
skin = readMask(beautyContext, 'skinMask', imageSize);
face = readMask(beautyContext, 'faceSkinMask', imageSize);
regions = semanticRegions(beautyContext, imageSize);
confidence = semanticConfidence(beautyContext, imageSize);
faceScale = min(faceBox(3:4));

% 通用集合不包含 leftBrow/rightBrow，避免眉毛被双重保护和过度冻结。
featureNames = {'leftEye', 'rightEye', 'eyeglass', 'mouth', ...
    'upperLip', 'lowerLip', 'nose', 'earring', 'necklace'};
featureEvidence = semanticUnion(regions, confidence, featureNames);
featureProtection = smoothStep(featureEvidence, .20, .65);

browEvidence = semanticUnion(regions, confidence, ...
    {'leftBrow', 'rightBrow'});
browProtection = smoothStep(browEvidence, .35, .65);
browCore = browEvidence >= .65;
browRadius = min(4, max(1, round(.006 * faceScale)));
if any(browCore(:))
    browBand = .34 * max(0, 1 - ...
        bwdist(browCore) / (browRadius + 1));
    browBand(browCore) = 1;
    browProtection = max(browProtection, browBand);
end

eyeEvidence = semanticUnion(regions, confidence, {'leftEye', 'rightEye'});
eyeCore = eyeEvidence >= .45;
eyeBand = imdilate(eyeCore, strel('disk', ...
    min(18, max(6, round(.030 * faceScale))), 0));
grayImage = im2double(rgb2gray(inputImage));
lashCore = detectDarkEyeLines(grayImage, eyeCore, eyeBand, faceScale);
lashProtection = feather(lashCore, ...
    min(4, max(1, round(.006 * faceScale))), .98);

hardProtection = readOptionalMask(beautyContext, ...
    'hardProtectionMask', imageSize);
textureProtectionMask = max(cat(3, featureProtection, ...
    browProtection, lashProtection, hardProtection), [], 3);
textureProtectionMask = min(max(double(textureProtectionMask), 0), 1);

diagnostics = struct( ...
    'featureEvidence', featureEvidence, ...
    'featureProtection', featureProtection, ...
    'browEvidence', browEvidence, ...
    'browProtection', browProtection, ...
    'browCore', browCore, ...
    'eyeEvidence', eyeEvidence, ...
    'eyeCore', eyeCore, ...
    'lashCore', lashCore, ...
    'lashProtection', lashProtection, ...
    'hardProtectionMask', hardProtection, ...
    'faceSkinMask', face);
end

function lashCore = detectDarkEyeLines(grayImage, eyeCore, eyeBand, faceScale)
lashCore = false(size(eyeCore));
if ~any(eyeCore(:)) || ~any(eyeBand(:))
    return;
end
darkSigma = min(2.4, max(.7, .004 * faceScale));
lineImage = imgaussfilt(grayImage, darkSigma, 'Padding', 'replicate');
darkResidual = lineImage - grayImage;
values = sort(darkResidual(eyeBand & ~eyeCore));
if isempty(values)
    return;
end
darkThreshold = max(.035, percentileValue(values, .72));
candidate = eyeBand & ~eyeCore & darkResidual >= darkThreshold;
nearEye = bwdist(eyeCore) <= min(9, max(3, round(.014 * faceScale)));
candidate = candidate & nearEye;
% 用窄的连接闭合接受带间断睫毛，写入 hard 的仍是原始暗线像素。
gapLength = min(5, max(2, round(.006 * faceScale)));
lineSupport = false(size(candidate));
for angle = 0:15:165
    closed = imclose(candidate, strel('line', gapLength, angle));
    lineSupport = lineSupport | imdilate(closed, strel('disk', 1, 0));
end
lashCore = candidate & lineSupport;
end

function evidence = semanticUnion(regions, confidence, names)
evidence = zeros(size(regions.(names{1})));
for index = 1:numel(names)
    evidence = max(evidence, min(regions.(names{index}), ...
        confidence.(names{index})));
end
evidence = min(max(double(evidence), 0), 1);
end

function regions = semanticRegions(context, imageSize)
if isfield(context, 'semanticProbabilities')
    regions = unstackSemantics(context.semanticProbabilities, imageSize);
elseif isfield(context, 'regions')
    regions = context.regions;
else
    regions = emptySemantics(imageSize);
end
regions = validateSemantics(regions, imageSize);
end

function confidence = semanticConfidence(context, imageSize)
if isfield(context, 'semanticConfidence')
    confidence = unstackSemantics(context.semanticConfidence, imageSize);
elseif isfield(context, 'regionConfidence')
    confidence = context.regionConfidence;
elseif isfield(context, 'semanticProbabilities')
    confidence = unstackSemantics(context.semanticProbabilities, imageSize);
elseif isfield(context, 'regions')
    confidence = context.regions;
else
    confidence = emptySemantics(imageSize);
end
confidence = validateSemantics(confidence, imageSize);
end

function semantics = unstackSemantics(values, imageSize)
if ~isnumeric(values) || ~isreal(values) || ndims(values) ~= 3 || ...
        ~isequal(size(values), [imageSize, numel(faceParsingClassNames())]) || ...
        any(~isfinite(values(:))) || any(values(:) < 0) || any(values(:) > 1)
    error('masks:InvalidContext', '语义概率堆栈的尺寸或取值无效。');
end
names = faceParsingClassNames();
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
        semantics.(name) = zeros(imageSize);
    end
    value = semantics.(name);
    if ~isnumeric(value) || ~isreal(value) || ...
            ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
            any(value(:) < 0) || any(value(:) > 1)
        error('masks:InvalidContext', '语义类别 %s 无效。', name);
    end
    semantics.(name) = double(value);
end
end

function semantics = emptySemantics(imageSize)
names = faceParsingClassNames();
semantics = struct();
for index = 1:numel(names)
    semantics.(names{index}) = zeros(imageSize);
end
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

function value = readOptionalMask(context, name, imageSize)
if isfield(context, name)
    value = readMask(context, name, imageSize);
else
    value = zeros(imageSize);
end
end

function value = feather(core, radius, peak)
value = zeros(size(core));
if ~any(core(:))
    return;
end
value = peak * max(0, 1 - bwdist(core) / (radius + 1));
value(core) = peak;
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function value = percentileValue(values, fraction)
values = sort(values(:));
index = 1 + round(fraction * (numel(values) - 1));
value = values(index);
end

function validateImageAndFace(inputImage, faceBox)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('masks:InvalidImage', '输入图像必须是 uint8 三通道 RGB 图像。');
end
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > size(inputImage, 2) || ...
        faceBox(2) + faceBox(4) - 1 > size(inputImage, 1)
    error('masks:InvalidFaceBox', '人脸框超出图像范围。');
end
end
