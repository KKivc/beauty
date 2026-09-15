function tests = testBeautyContextV3
%TESTBEAUTYCONTEXTV3 Beauty Context v3 规范化和原尺寸派生 Mask 测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testNormalizeConvertsV2AndKeepsLegacyFields(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
legacy = prepareBeautyContext(image, faceBox, parsing, emptyBodyParsing([40, 60]));
normalized = normalizeBeautyContext(image, faceBox, legacy);

verifyEqual(testCase, normalized.schemaVersion, '3.0');
verifyTrue(testCase, isfield(normalized, 'nonFaceSkinMask'));
verifyTrue(testCase, isfield(normalized, 'textureProtectionMask'));
verifyTrue(testCase, isfield(normalized, 'structureProtectionMask'));
verifyTrue(testCase, isfield(normalized, 'toneProtectionMask'));
verifyTrue(testCase, isfield(normalized, 'semanticProbabilities'));
verifyEqual(testCase, size(normalized.semanticProbabilities), [40, 60, 19]);
verifyEqual(testCase, size(normalized.nonFaceSkinMask), [40, 60]);
verifyEqual(testCase, normalized.featureProtectionMask, ...
    double(legacy.featureProtectionMask), 'AbsTol', 1e-12);
verifyEqual(testCase, normalized.hardProtectionMask, ...
    double(legacy.hardProtectionMask), 'AbsTol', 1e-12);

params = struct('smoothingStrength', 25, 'whiteningStrength', 15);
verifySize(testCase, beautifyImage(image, params, faceBox, legacy), [40, 60, 3]);
recommended = recommendBeautyParams(image, faceBox, legacy);
verifyTrue(testCase, isfield(recommended, 'smoothingStrength'));
end

function testNormalizeRejectsUnsupportedVersionAndSize(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
legacy = prepareBeautyContext(image, faceBox, parsing, emptyBodyParsing([40, 60]));
normalized = normalizeBeautyContext(image, faceBox, legacy);

unsupported = normalized;
unsupported.schemaVersion = '9.0';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, unsupported), ...
    'normalizeBeautyContext:UnsupportedVersion');

wrongSize = normalized;
wrongSize.imageSize = [39, 60, 3];
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSize), ...
    'normalizeBeautyContext:SizeMismatch');

wrongSemantic = normalized;
wrongSemantic.semanticProbabilities = zeros(40, 60, 18, 'single');
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSemantic), ...
    'normalizeBeautyContext:InvalidSemantic');
end

function testOriginalSizeRebuildsDerivedProtectionMasks(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
legacy = prepareBeautyContext(image, faceBox, parsing, emptyBodyParsing([40, 60]));
previewContext = normalizeBeautyContext(image, faceBox, legacy);
targetImage = imresize(image, [80, 120], 'bilinear');
targetFaceBox = [20, 16, 60, 48];
savedContext = resizeBeautyContext(previewContext, ...
    [80, 120, 3], targetFaceBox, targetImage);

verifyEqual(testCase, savedContext.schemaVersion, '3.0');
verifyEqual(testCase, savedContext.imageSize, [80, 120, 3]);
verifyEqual(testCase, savedContext.faceBox, targetFaceBox);
verifyEqual(testCase, size(savedContext.semanticProbabilities), [80, 120, 19]);
verifyEqual(testCase, size(savedContext.textureProtectionMask), [80, 120]);
verifyEqual(testCase, size(savedContext.structureProtectionMask), [80, 120]);
verifyEqual(testCase, size(savedContext.toneProtectionMask), [80, 120]);
verifyTrue(testCase, any(savedContext.structureProtectionMask(:) > 0));

params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
previewOutput = beautifyImage(image, params, faceBox, previewContext);
savedOutput = beautifyImage(targetImage, params, targetFaceBox, savedContext);
verifySize(testCase, previewOutput, [40, 60, 3]);
verifySize(testCase, savedOutput, [80, 120, 3]);
verifyClass(testCase, savedOutput, 'uint8');
end

function [image, faceBox, parsing] = fixtureContext(height, width)
image = uint8(ones(height, width, 3) * 145);
image(17:24, 28:32, :) = 105;
faceBox = [10, 8, 30, 24];
parsing = emptyFaceParsing([height, width]);
parsing.regions.skin(10:30, 15:45) = 1;
parsing.regionConfidence.skin(10:30, 15:45) = 1;
parsing.regions.nose(16:28, 27:33) = .8;
parsing.regionConfidence.nose(16:28, 27:33) = .8;
parsing.regions.leftEye(18:20, 22:27) = 1;
parsing.regionConfidence.leftEye(18:20, 22:27) = 1;
end

function parsing = emptyFaceParsing(imageSize)
names = faceParsingClassNames();
parsing = struct('regions', struct(), 'regionConfidence', struct());
for index = 1:numel(names)
    parsing.regions.(names{index}) = zeros(imageSize);
    parsing.regionConfidence.(names{index}) = zeros(imageSize);
end
end

function options = emptyBodyParsing(imageSize)
options = struct('probabilities', zeros([imageSize, 20], 'single'));
end

