function tests = testBeautyV3
%TESTBEAUTYV3 v3 Mask package 和频率 tracer 测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testPackagesResolveWithSourcePathOnly(testCase)
verifyNotEmpty(testCase, which('masks.buildBeautyMasks'));
verifyNotEmpty(testCase, which('masks.buildTextureProtectionMask'));
verifyNotEmpty(testCase, which('beauty.decomposeSkinFrequency'));
verifyNotEmpty(testCase, which('beauty.smoothSkinTexture'));
verifyNotEmpty(testCase, which('beauty.composeBeautyResult'));
end

function testBeautyMasksReturnPurposeSpecificContinuousMaps(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
legacy = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
context = normalizeBeautyContext(image, faceBox, legacy);

[beautyMasks, diagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
requiredFields = {'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'hardProtectionMask'};
verifyTrue(testCase, all(isfield(beautyMasks, requiredFields)));
for index = 1:numel(requiredFields)
    verifySize(testCase, beautyMasks.(requiredFields{index}), [120, 160]);
end
verifyTrue(testCase, isfield(diagnostics, 'structure'));
verifyTrue(testCase, isfield(diagnostics.structure, 'orientationCoherence'));
verifyGreaterThan(testCase, ...
    mean(beautyMasks.textureProtectionMask(parsing.regions.leftEye > .5)), .5);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.toneProtectionMask(parsing.regions.upperLip > .5)), .5);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.structureProtectionMask(parsing.regions.nose > .5)), 0);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.structureProtectionMask(parsing.regions.neck > .5)), 0);
verifyEqual(testCase, max(beautyMasks.strengthMap( ...
    context.skinMask <= .01)), 0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.faceStrengthMap(parsing.regions.skin > .5)), ...
    mean(beautyMasks.nonFaceStrengthMap(parsing.regions.neck > .5)));

[texture, structure, tone, strength] = masks.buildBeautyMasks( ...
    image, context, faceBox);
verifyEqual(testCase, texture, beautyMasks.textureProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, structure, beautyMasks.structureProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, tone, beautyMasks.toneProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, strength, beautyMasks.strengthMap, ...
    'AbsTol', 1e-12);
end

function testFrequencyDecompositionReconstructsAndKeepsScalesFixed(testCase)
[image, faceBox, parsing] = fixtureImage(96, 128);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([96, 128])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, decomposition] = beauty.decomposeSkinFrequency(image, faceBox);
verifyLessThanOrEqual(testCase, decomposition.reconstructionError, 1e-12);
verifyEqual(testCase, frequency.base + frequency.mid + frequency.fine, ...
    frequency.sourceLuminance, 'AbsTol', 1e-12);

strengths = [0, 25, 50, 75, 100];
retentions = zeros(size(strengths));
fineEnergies = zeros(size(strengths));
for index = 1:numel(strengths)
    [smoothed, details] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strengths(index));
    retentions(index) = details.fineRetention;
    fineEnergies(index) = details.fineEnergyAfter;
    verifyEqual(testCase, smoothed.base, frequency.base, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, smoothed.mid, frequency.mid, ...
        'AbsTol', 1e-12);
end
verifyEqual(testCase, retentions(1), 1, 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(retentions) < 0));
verifyTrue(testCase, all(diff(fineEnergies) <= 1e-12));
verifyGreaterThan(testCase, retentions(end), 0);
end

function testV3PipelineUsesOneAlphaAndPreservesProtectedPixels(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
legacy = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
context = normalizeBeautyContext(image, faceBox, legacy);
params = struct('smoothingStrength', 100, ...
    'whiteningStrength', 50, 'pipeline', 'v3');
output = beautifyImage(image, params, faceBox, context);
verifyClass(testCase, output, 'uint8');
verifySize(testCase, output, size(image));
verifyEqual(testCase, output(repmat(context.hardProtectionMask >= .999, ...
    [1, 1, 3])), image(repmat(context.hardProtectionMask >= .999, ...
    [1, 1, 3])));
verifyEqual(testCase, output(repmat(context.skinMask <= .01, ...
    [1, 1, 3])), image(repmat(context.skinMask <= .01, ...
    [1, 1, 3])));

[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[smoothed, ~] = beauty.smoothSkinTexture(frequency, beautyMasks, 100);
[~, diagnostics] = beauty.composeBeautyResult( ...
    image, frequency, smoothed, beautyMasks, 50);
verifyEqual(testCase, diagnostics.alphaMap, ...
    max(smoothed.alphaMap, diagnostics.whiteningSupport), ...
    'AbsTol', 1e-12);
end

function [image, faceBox, parsing] = fixtureImage(height, width)
image = uint8(ones(height, width, 3) * 145);
[xGrid, yGrid] = meshgrid(1:width, 1:height);
skin = ((xGrid - width * .50) / (width * .33)) .^ 2 + ...
    ((yGrid - height * .43) / (height * .40)) .^ 2 <= 1;
neck = xGrid >= width * .40 & xGrid <= width * .60 & ...
    yGrid >= height * .73 & yGrid <= height * .94;
skin = skin | neck;
for channel = 1:3
    channelImage = image(:, :, channel);
    channelImage(skin) = uint8(168 + 7 * sin(2 * pi * xGrid(skin) / 17));
    image(:, :, channel) = channelImage;
end
nose = ((xGrid - width * .50) / (width * .10)) .^ 2 + ...
    ((yGrid - height * .45) / (height * .20)) .^ 2 <= 1;
image(:, :, 1) = image(:, :, 1) + uint8(12 * nose);
image(:, :, 2) = image(:, :, 2) + uint8(7 * nose);
image(:, :, 3) = image(:, :, 3) + uint8(4 * nose);
image(ceil(height * .45):ceil(height * .55), ...
    ceil(width * .43):ceil(width * .46), :) = uint8(95);
eye = false(height, width);
eye(ceil(height * .30):ceil(height * .33), ...
    ceil(width * .38):ceil(width * .46)) = true;
lip = false(height, width);
lip(ceil(height * .62):ceil(height * .66), ...
    ceil(width * .43):ceil(width * .57)) = true;
faceBox = [round(width * .17), round(height * .08), ...
    round(width * .66), round(height * .67)];
parsing = emptyFaceParsing([height, width]);
parsing.regions.skin = double(skin);
parsing.regionConfidence.skin = double(skin);
parsing.regions.neck = double(neck);
parsing.regionConfidence.neck = double(neck);
parsing.regions.nose = double(nose);
parsing.regionConfidence.nose = double(nose);
parsing.regions.leftEye = double(eye);
parsing.regionConfidence.leftEye = double(eye);
parsing.regions.upperLip = double(lip);
parsing.regionConfidence.upperLip = double(lip);
parsing.regions.lowerLip = double(lip);
parsing.regionConfidence.lowerLip = double(lip);
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
