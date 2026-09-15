function tests = testBeautyMigration
%TESTBEAUTYMIGRATION 验证瑕疵、统一肤色和结构感知美白模块。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testBlemishMapIsFixedAndContinuous(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, diagnostics] = beauty.buildBlemishMap( ...
    image, frequency, beautyMasks);
[secondMap, secondDiagnostics] = beauty.buildBlemishMap( ...
    image, frequency, beautyMasks);

verifySize(testCase, blemishMap, [120, 160]);
verifyGreaterThanOrEqual(testCase, min(blemishMap(:)), 0);
verifyLessThanOrEqual(testCase, max(blemishMap(:)), 1);
verifyEqual(testCase, secondMap, blemishMap, 'AbsTol', 1e-12);
verifyEqual(testCase, secondDiagnostics.fineEvidence, ...
    diagnostics.fineEvidence, 'AbsTol', 1e-12);
verifyTrue(testCase, all(isfield(diagnostics, ...
    {'fineEvidence', 'midEvidence', 'chromaEvidence', ...
    'structureProtectionMask', 'skinCandidate'})));
end

function testBlemishRepairKeepsBaseAndSeparatesWeights(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);
strengths = [0, 25, 50, 75, 100];
fineEnergy = zeros(size(strengths));
blemishEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    [repaired, details] = beauty.repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, strengths(index));
    verifyEqual(testCase, repaired.base, frequency.base, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, repaired.mid, ...
        frequency.mid + details.mediumCorrection, 'AbsTol', 1e-12);
    fineEnergy(index) = details.fineEnergyAfter;
    blemishEnergy(index) = details.blemishEnergyAfter;
end
verifyEqual(testCase, fineEnergy(1), fineEnergy(1), 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(fineEnergy) <= 1e-10));
verifyTrue(testCase, all(diff(blemishEnergy) <= 1e-10));
verifyTrue(testCase, any(blemishMap(:) > 0));
end

function testToneUsesOneCandidateAndZeroIsIdentity(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);
[tone, diagnostics] = beauty.normalizeSkinTone(image, frequency, ...
    beautyMasks, blemishMap, 50);
[zeroTone, ~] = beauty.normalizeSkinTone(image, beautyMasks, blemishMap, 0);

verifyEqual(testCase, tone.candidateCb, diagnostics.candidateCb, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, tone.candidateCr, diagnostics.candidateCr, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, size(tone.outputImage), size(image));
verifyEqual(testCase, zeroTone.outputImage, image);
verifyEqual(testCase, max(abs(diagnostics.deltaCb(:))) <= .55, true);
verifyEqual(testCase, max(abs(diagnostics.deltaCr(:))) <= .55, true);
end

function testWhiteningIsIndependentAndProtected(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[white, diagnostics] = beauty.applySkinWhitening( ...
    image, frequency, beautyMasks, 50);
[zeroWhite, ~] = beauty.applySkinWhitening(image, frequency, beautyMasks, 0);

verifyEqual(testCase, white.fineAfter, frequency.fine, 'AbsTol', 1e-12);
verifyEqual(testCase, white.midAfter, frequency.mid, 'AbsTol', 1e-12);
verifyTrue(testCase, diagnostics.whiteningCurve > 0);
verifyGreaterThanOrEqual(testCase, diagnostics.whiteningCurve, 0);
verifyLessThanOrEqual(testCase, diagnostics.whiteningCurve, 1);
verifyEqual(testCase, zeroWhite.outputImage, image);
verifyEqual(testCase, white.outputLuminance, ...
    frequency.sourceLuminance + diagnostics.delta, 'AbsTol', 1e-12);
verifyEqual(testCase, max(white.whiteningSupport( ...
    beautyMasks.hardProtectionMask >= .999)), 0, 'AbsTol', 1e-12);
end

function testV3DiagnosticsExposeMigrationResults(testCase)
[image, faceBox, parsing] = fixtureImage(96, 128);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([96, 128])));
[output, diagnostics] = beautifyImage(image, struct( ...
    'smoothingStrength', 75, 'whiteningStrength', 25, ...
    'pipeline', 'v3'), faceBox, context);

verifySize(testCase, output, size(image));
verifyTrue(testCase, isfield(diagnostics, 'blemishMap'));
verifyTrue(testCase, isfield(diagnostics, 'repairResult'));
verifyTrue(testCase, isfield(diagnostics, 'skinToneResult'));
verifyTrue(testCase, isfield(diagnostics, 'whiteningResult'));
verifyEqual(testCase, diagnostics.compose.alphaMap, ...
    max(cat(3, diagnostics.compose.smoothingAlpha, ...
    diagnostics.compose.whiteningSupport, diagnostics.compose.toneSupport), ...
    [], 3), 'AbsTol', 1e-12);
verifyEqual(testCase, output(repmat(context.hardProtectionMask >= .999, ...
    [1, 1, 3])), image(repmat(context.hardProtectionMask >= .999, ...
    [1, 1, 3])));
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
