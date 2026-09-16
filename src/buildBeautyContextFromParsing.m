function context = buildBeautyContextFromParsing(inputImage, faceBox, parsing)
%BUILDBEAUTYCONTEXTFROMPARSING 从 19 类解析概率构建 v3 Context。

validateImage(inputImage);
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
if ~isstruct(parsing) || ~isscalar(parsing) || ...
        ~isfield(parsing, 'regions') || ...
        ~isfield(parsing, 'regionConfidence')
    error('buildBeautyContextFromParsing:InvalidParsing', ...
        '解析结果必须包含 regions 和 regionConfidence。');
end

[regions, confidence] = normalizeSemantics(parsing, size(inputImage, 1:2));
skinProbability = semanticUnion(regions, confidence, ...
    {'skin', 'nose', 'leftEar', 'rightEar', 'neck'});
faceProbability = semanticUnion(regions, confidence, ...
    {'skin', 'nose', 'leftEar', 'rightEar'});
neckProbability = semanticUnion(regions, confidence, {'neck'});
faceScale = min(faceBox(3:4));

% 先用未排除的皮肤候选生成保护证据，再以同一证据收紧皮肤区域。
context = makeBaseContext(inputImage, faceBox, regions, confidence, ...
    probabilityMask(skinProbability, faceScale), ...
    probabilityMask(faceProbability, faceScale), ...
    probabilityMask(neckProbability, faceScale));
[~, maskDiagnostics] = masks.buildBeautyMasks(inputImage, context, faceBox);
skinExclusion = min(max(maskDiagnostics.texture.skinExclusionEvidence, 0), 1);

skinProbability = skinProbability .* (1 - skinExclusion);
faceProbability = faceProbability .* (1 - skinExclusion);
neckProbability = neckProbability .* (1 - skinExclusion);
context.skinMask = probabilityMask(skinProbability, faceScale);
context.faceSkinMask = probabilityMask(faceProbability, faceScale);
context.nonFaceSkinMask = max(context.skinMask - ...
    min(context.skinMask, context.faceSkinMask), 0);
context.bodySkinMask = context.nonFaceSkinMask;
context = attachDerivedMasks(inputImage, context, faceBox);
end

function context = makeBaseContext(inputImage, faceBox, regions, ...
        confidence, skinMask, faceSkinMask, neckMask)
names = faceParsingClassNames();
context = struct( ...
    'skinMask', double(skinMask), ...
    'faceSkinMask', double(faceSkinMask), ...
    'nonFaceSkinMask', max(double(skinMask) - ...
        min(double(skinMask), double(faceSkinMask)), 0), ...
    'schemaVersion', '3.0', ...
    'regions', regions, ...
    'regionConfidence', confidence, ...
    'semanticProbabilities', stackSemantics(regions, names), ...
    'semanticConfidence', stackSemantics(confidence, names), ...
    'geometry', makeGeometry(faceSkinMask), ...
    'imageSize', size(inputImage), ...
    'faceBox', double(faceBox));
context.bodySkinMask = double(neckMask);
end

function context = attachDerivedMasks(inputImage, context, faceBox)
[beautyMasks, ~] = masks.buildBeautyMasks(inputImage, context, faceBox);
context.textureProtectionMask = beautyMasks.textureProtectionMask;
context.structureProtectionMask = beautyMasks.structureProtectionMask;
context.toneProtectionMask = beautyMasks.toneProtectionMask;
context.strengthMap = beautyMasks.strengthMap;
context.faceStrengthMap = beautyMasks.faceStrengthMap;
context.nonFaceStrengthMap = beautyMasks.nonFaceStrengthMap;
context.protectionMasks = struct( ...
    'texture', beautyMasks.textureProtectionMask, ...
    'structure', beautyMasks.structureProtectionMask, ...
    'tone', beautyMasks.toneProtectionMask);
end

function [regions, confidence] = normalizeSemantics(parsing, imageSize)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    name = names{index};
    if ~isfield(parsing.regions, name) || ...
            ~isfield(parsing.regionConfidence, name)
        error('buildBeautyContextFromParsing:InvalidParsing', ...
            '解析结果缺少类别 %s。', name);
    end
    regions.(name) = validateMask(parsing.regions.(name), imageSize, ...
        ['regions.', name]);
    confidence.(name) = validateMask( ...
        parsing.regionConfidence.(name), imageSize, ...
        ['regionConfidence.', name]);
end
end

function probability = semanticUnion(regions, confidence, names)
probability = zeros(size(regions.(names{1})));
for index = 1:numel(names)
    probability = max(probability, min(regions.(names{index}), ...
        confidence.(names{index})));
end
probability = min(max(double(probability), 0), 1);
end

function mask = probabilityMask(probability, faceScale)
% 在概率域闭合小孔洞，再统一做平滑阈值映射。
radius = min(3, max(2, round(.004 * faceScale)));
closedProbability = imclose(probability, strel('disk', radius, 0));
t = min(max((closedProbability - .20) / .45, 0), 1);
mask = t .^ 2 .* (3 - 2 * t);
end

function values = stackSemantics(semanticStruct, names)
first = semanticStruct.(names{1});
values = zeros([size(first), numel(names)], 'single');
for index = 1:numel(names)
    values(:, :, index) = single(semanticStruct.(names{index}));
end
end

function geometry = makeGeometry(face)
geometry = struct('contours', struct('face', zeros(0, 2), ...
    'eyes', zeros(0, 2), 'nose', zeros(0, 2), 'mouth', zeros(0, 2)), ...
    'landmarks', zeros(0, 2));
if exist('bwboundaries', 'file') ~= 0 && any(face(:))
    boundaries = bwboundaries(face, 'noholes');
    if ~isempty(boundaries)
        geometry.contours.face = boundaries{1};
    end
end
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('buildBeautyContextFromParsing:InvalidMask', ...
        '字段 %s 的尺寸或取值范围无效。', name);
end
value = double(value);
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('buildBeautyContextFromParsing:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('buildBeautyContextFromParsing:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end
