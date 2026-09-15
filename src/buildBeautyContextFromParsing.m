function context = buildBeautyContextFromParsing(inputImage, faceBox, parsing)
%BUILDBEAUTYCONTEXTFROMPARSING 将解析结果转换为可消费 context。
if ~isstruct(parsing) || ~isfield(parsing, 'regions') || ~isfield(parsing, 'regionConfidence')
    error('buildBeautyContextFromParsing:InvalidParsing', 'Missing regions or confidence.');
end
[height, width, channels] = size(inputImage);
if channels ~= 3, error('buildBeautyContextFromParsing:InvalidImage', 'Expected RGB image.'); end
names = faceParsingClassNames(); regions = struct(); confidence = struct();
for index = 1:numel(names)
    name = names{index};
    if ~isfield(parsing.regions, name) || ~isfield(parsing.regionConfidence, name)
        error('buildBeautyContextFromParsing:InvalidParsing', 'All 19 classes are required.');
    end
    regions.(name) = validateMask(parsing.regions.(name), height, width, name);
    confidence.(name) = validateMask(parsing.regionConfidence.(name), height, width, name);
end
% 以模型 soft probability 合成脸、耳和颈部，避免 hard label 造成漏皮。
skinNames = {'skin', 'nose', 'leftEar', 'rightEar', 'neck'};
skinProbability = softUnion(regions, confidence, skinNames);
faceProbability = softUnion(regions, confidence, skinNames(1:4));
neckProbability = softUnion(regions, confidence, {'neck'});

% 眼眉和遮挡物保持硬保护；鼻、嘴使用各自的精细软边界。
[featureProtection, hard, featureDiagnostics] = ...
    buildFeatureProtectionMasks(inputImage, regions, confidence, ...
    min(faceBox(3:4)));
skinExclusion = min(featureDiagnostics.skinExclusionEvidence, 1);
skinProbability = skinProbability .* (1 - skinExclusion);
faceProbability = faceProbability .* (1 - skinExclusion);
neckProbability = neckProbability .* (1 - skinExclusion);

face = probabilityMask(faceProbability, min(faceBox(3:4)));
neck = probabilityMask(neckProbability, min(faceBox(3:4)));
skin = probabilityMask(skinProbability, min(faceBox(3:4)));
context = struct('skinMask', skin, ...
    'faceSkinMask', face, 'featureProtectionMask', featureProtection, ...
    'schemaVersion', '2.0', 'regions', regions, 'regionConfidence', confidence, ...
    'bodySkinMask', double(neck), 'hardProtectionMask', double(hard), ...
    'geometry', makeGeometry(face), 'imageSize', size(inputImage), 'faceBox', double(faceBox));
end

function mask = validateMask(value, height, width, name)
if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), [height width]) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('buildBeautyContextFromParsing:InvalidMask', 'Invalid mask: %s.', name);
end
mask = double(value);
end

function probability = softUnion(regions, confidence, names)
evidence = zeros(size(regions.(names{1})));
for index = 1:numel(names)
    evidence = max(evidence, min(regions.(names{index}), confidence.(names{index})));
end
probability = min(max(evidence, 0), 1);
end

function soft = probabilityMask(probability, faceScale)
% 先在概率域闭合最多 1--3 像素的小解析孔洞，再统一做平滑阈值映射。
lowThreshold = .20;
highThreshold = .65;
radius = min(3, max(2, round(.004 * faceScale)));
closedProbability = imclose(probability, strel('disk', radius, 0));
t = min(max((closedProbability - lowThreshold) / ...
    (highThreshold - lowThreshold), 0), 1);
soft = t .^ 2 .* (3 - 2 * t);
end

function geometry = makeGeometry(face)
geometry = struct('contours', struct('face', zeros(0,2), 'eyes', zeros(0,2), 'nose', zeros(0,2), 'mouth', zeros(0,2)), 'landmarks', zeros(0,2));
if exist('bwboundaries', 'file') ~= 0 && any(face(:))
    boundaries = bwboundaries(face, 'noholes'); if ~isempty(boundaries), geometry.contours.face = boundaries{1}; end
end
end
