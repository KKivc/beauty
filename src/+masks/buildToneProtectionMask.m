function [toneProtectionMask, diagnostics] = ...
        buildToneProtectionMask(inputImage, beautyContext, faceBox)
%BUILDTONEPROTECTIONMASK 保护五官颜色和鼻孔色调，避免色度处理串色。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    faceBox = beautyContext.faceBox;
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
skin = readMask(beautyContext, 'skinMask', imageSize);
regions = semanticRegions(beautyContext, imageSize);
confidence = semanticConfidence(beautyContext, imageSize);
faceScale = min(faceBox(3:4));

toneNames = {'leftEye', 'rightEye', 'eyeglass', 'mouth', ...
    'upperLip', 'lowerLip', 'nose', 'earring', 'necklace'};
toneEvidence = semanticUnion(regions, confidence, toneNames);
toneProtection = smoothStep(toneEvidence, .18, .60);

browEvidence = semanticUnion(regions, confidence, ...
    {'leftBrow', 'rightBrow'});
browProtection = smoothStep(browEvidence, .32, .62);

noseEvidence = semanticUnion(regions, confidence, {'nose'});
noseCore = noseEvidence >= .60;
nostrilCandidate = detectNostrilCandidate(inputImage, ...
    noseEvidence, noseCore, faceScale);
nostrilProtection = feather(nostrilCandidate, ...
    min(4, max(1, round(.006 * faceScale))), 1);

hardProtection = readOptionalMask(beautyContext, ...
    'hardProtectionMask', imageSize);
toneProtectionMask = max(cat(3, toneProtection, browProtection, ...
    nostrilProtection, hardProtection), [], 3);
toneProtectionMask = min(max(double(toneProtectionMask), 0), 1);

diagnostics = struct( ...
    'toneEvidence', toneEvidence, ...
    'toneProtection', toneProtection, ...
    'browProtection', browProtection, ...
    'noseEvidence', noseEvidence, ...
    'nostrilCandidate', nostrilCandidate, ...
    'nostrilProtection', nostrilProtection, ...
    'hardProtectionMask', hardProtection);
end

function candidate = detectNostrilCandidate(inputImage, noseEvidence, noseCore, faceScale)
candidate = false(size(noseEvidence));
if ~any(noseCore(:))
    return;
end
grayImage = im2double(rgb2gray(inputImage));
lowSigma = min(8, max(1.25, .018 * faceScale));
lowFrequency = imgaussfilt(grayImage, lowSigma, 'Padding', 'replicate');
surrounding = imgaussfilt(lowFrequency, ...
    min(12, max(2.5, 2.2 * lowSigma)), 'Padding', 'replicate');
darkValley = surrounding - lowFrequency;
[gradientX, gradientY] = gradient(lowFrequency);
gradientMagnitude = hypot(gradientX, gradientY);
noseValues = gradientMagnitude(noseCore);
valleyValues = darkValley(noseCore);
if isempty(noseValues)
    return;
end
gradientThreshold = max(.012, percentileValue(noseValues, .90));
valleyThreshold = max(.018, percentileValue(valleyValues, .90));
seed = noseCore & gradientMagnitude >= gradientThreshold & ...
    darkValley >= valleyThreshold;
minimumArea = max(8, round(.0003 * faceScale ^ 2));
candidate = keepComponents(seed, minimumArea, faceScale);
end

function output = keepComponents(seed, minimumArea, faceScale)
output = false(size(seed));
if ~any(seed(:))
    return;
end
components = bwconncomp(seed, 8);
minimumSpan = max(3, round(.01 * faceScale));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    if numel(pixels) < minimumArea
        continue;
    end
    [rows, columns] = ind2sub(size(seed), pixels);
    rowSpan = max(rows) - min(rows) + 1;
    columnSpan = max(columns) - min(columns) + 1;
    fillRatio = numel(pixels) / max(1, rowSpan * columnSpan);
    if max(rowSpan, columnSpan) >= minimumSpan && fillRatio >= .18
        output(pixels) = true;
    end
end
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
