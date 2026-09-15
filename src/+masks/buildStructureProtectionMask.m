function [structureProtectionMask, diagnostics] = ...
        buildStructureProtectionMask(inputImage, beautyContext, faceBox)
%BUILDSTRUCTUREPROTECTIONMASK 依据低频梯度和方向连续性保护皮肤结构。
%   鼻部与脸外皮肤使用同一低通、梯度和方向一致性计算，不依赖
%   当前模型不存在的手、肩或关节独立语义。

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
if isfield(beautyContext, 'nonFaceSkinMask')
    nonFace = min(skin, readMask(beautyContext, ...
        'nonFaceSkinMask', imageSize));
else
    nonFace = max(skin - min(skin, face), 0);
end
regions = semanticRegions(beautyContext, imageSize);
confidence = semanticConfidence(beautyContext, imageSize);
faceScale = min(faceBox(3:4));
lowPassSigma = min(8, max(1.25, .018 * faceScale));

ycbcr = rgb2ycbcr(im2double(inputImage));
luminance = ycbcr(:, :, 1);
lowFrequency = imgaussfilt(luminance, lowPassSigma, ...
    'Padding', 'replicate');
[gradientX, gradientY] = gradient(lowFrequency);
gradientMagnitude = hypot(gradientX, gradientY);
coherenceSigma = max(1.5, lowPassSigma / 2);
tensorXX = imgaussfilt(gradientX .^ 2, coherenceSigma, ...
    'Padding', 'replicate');
tensorYY = imgaussfilt(gradientY .^ 2, coherenceSigma, ...
    'Padding', 'replicate');
tensorXY = imgaussfilt(gradientX .* gradientY, coherenceSigma, ...
    'Padding', 'replicate');
orientationCoherence = sqrt((tensorXX - tensorYY) .^ 2 + ...
    4 * tensorXY .^ 2) ./ (tensorXX + tensorYY + eps);

skinSupport = skin > .05;
gradientValues = gradientMagnitude(skinSupport);
if isempty(gradientValues)
    gradientEvidence = zeros(imageSize);
else
    low = percentileValue(gradientValues, .55);
    high = max(percentileValue(gradientValues, .95), low + 1e-6);
    gradientEvidence = smoothStep(gradientMagnitude, low, high);
end
continuity = smoothStep(orientationCoherence, .35, .85);
continuousEvidence = gradientEvidence .* (.35 + .65 * continuity);

noseEvidence = semanticUnion(regions, confidence, {'nose'});
noseSupport = min(face, noseEvidence);
% 鼻区保留一个与瑕疵无关的结构下限，防止鼻梁/鼻翼在高强度时消失。
noseStructure = noseSupport .* max(.22, continuousEvidence);

outsideSupport = min(nonFace, skin);
outsideStructure = outsideSupport .* continuousEvidence;
outsideStructure = outsideStructure .* ...
    min(1, imgaussfilt(double(outsideSupport > .05), ...
    max(1, coherenceSigma), 'Padding', 'replicate') + .25);

faceStructure = min(face, skin) .* continuousEvidence;
faceRadius = min(8, max(2, round(.012 * faceScale)));
faceBoundary = face > .05 & ...
    bwdist(face <= .35) <= faceRadius;
faceBoundary = double(faceBoundary) .* ...
    (.25 + .75 * gradientEvidence);
structureProtectionMask = max(cat(3, noseStructure, ...
    outsideStructure, faceStructure, faceBoundary), [], 3);
structureProtectionMask = structureProtectionMask .* min(max(skin, 0), 1);
structureProtectionMask = min(max(double(structureProtectionMask), 0), 1);

diagnostics = struct( ...
    'lowFrequency', lowFrequency, ...
    'lowPassSigma', lowPassSigma, ...
    'gradientX', gradientX, ...
    'gradientY', gradientY, ...
    'gradientMagnitude', gradientMagnitude, ...
    'orientationCoherence', orientationCoherence, ...
    'continuousEvidence', continuousEvidence, ...
    'noseSupport', noseSupport, ...
    'noseStructure', noseStructure, ...
    'outsideSupport', outsideSupport, ...
    'outsideStructure', outsideStructure, ...
    'faceBoundary', faceBoundary, ...
    'faceScale', faceScale);
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
