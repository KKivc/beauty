function tests = testBaseLuminanceEqualization
%TESTBASELUMINANCEEQUALIZATION Base-only 亮度均匀化与最终合成回归。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testBaseOnlyReferenceSupportsBothCorrectionSigns(testCase)
imageSize = [120, 160];
[xGrid, ~] = meshgrid(1:imageSize(2), 1:imageSize(1));
base = .55 + .10 * tanh((xGrid - 80) / 18);
frequency = struct( ...
    'base', base, ...
    'mid', nan(imageSize), ...
    'fine', nan(imageSize), ...
    'sourceLuminance', nan(imageSize));
masks = simpleMasks(imageSize, [1, 1, 160, 120]);

[result, diagnostics] = beauty.evenSkinLuminance( ...
    frequency, masks, 100);

verifyGreaterThan(testCase, nnz(diagnostics.positiveSupport), 0);
verifyGreaterThan(testCase, nnz(diagnostics.negativeSupport), 0);
verifyGreaterThanOrEqual(testCase, min(result.baseDelta(:)), -.03);
verifyLessThanOrEqual(testCase, max(result.baseDelta(:)), .03);
verifyEqual(testCase, result.baseDelta, ...
    diagnostics.limitedBaseDelta .* result.supportMap, 'AbsTol', 1e-12);
verifyTrue(testCase, isequaln(frequency.mid, nan(imageSize)));
verifyTrue(testCase, diagnostics.frequencyUnchanged);
end

function testZeroStrengthAndMissingReferenceAreIdentity(testCase)
imageSize = [32, 48];
base = .50 * ones(imageSize);
frequency = struct('base', base, 'mid', zeros(imageSize), ...
    'fine', zeros(imageSize));
masks = simpleMasks(imageSize, [1, 1, 48, 32]);

[zeroResult, zeroDiagnostics] = beauty.evenSkinLuminance( ...
    frequency, masks, 0);
verifyEqual(testCase, zeroResult.baseDelta, zeros(imageSize), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, zeroResult.supportMap, zeros(imageSize), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, zeroDiagnostics.baseCurve, 0, 'AbsTol', 1e-12);

masks.skinMask = zeros(imageSize);
masks.strengthMap = zeros(imageSize);
[emptyResult, emptyDiagnostics] = beauty.evenSkinLuminance( ...
    frequency, masks, 100);
verifyEqual(testCase, emptyResult.baseDelta, zeros(imageSize), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, emptyResult.supportMap, zeros(imageSize), ...
    'AbsTol', 1e-12);
verifyFalse(testCase, emptyDiagnostics.hasReliableReference);
end

function testHardProtectionZeroesBaseSupport(testCase)
imageSize = [64, 80];
[xGrid, ~] = meshgrid(1:imageSize(2), 1:imageSize(1));
frequency = struct('base', .55 + .08 * sin(xGrid / 10), ...
    'mid', zeros(imageSize), 'fine', zeros(imageSize));
masks = simpleMasks(imageSize, [1, 1, 80, 64]);
hard = false(imageSize);
hard(25:35, 32:45) = true;
masks.hardProtectionMask = double(hard);

[result, ~] = beauty.evenSkinLuminance(frequency, masks, 100);
verifyEqual(testCase, result.supportMap(hard), zeros(nnz(hard), 1), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, result.baseDelta(hard), zeros(nnz(hard), 1), ...
    'AbsTol', 1e-12);
end

function testComposeAddsWeightedBaseDeltaOnce(testCase)
imageSize = [24, 32];
image = uint8(ones([imageSize, 3]) * 128);
sourceYcbcr = rgb2ycbcr(im2double(image));
sourceLuminance = sourceYcbcr(:, :, 1);
frequency = struct('sourceLuminance', sourceLuminance, ...
    'base', sourceLuminance, 'mid', zeros(imageSize), ...
    'fine', zeros(imageSize));
masks = simpleMasks(imageSize, [1, 1, 32, 24]);
smoothed = struct('outputLuminance', sourceLuminance, ...
    'alphaMap', zeros(imageSize));
baseResult = struct('baseDelta', .02 * ones(imageSize), ...
    'supportMap', .50 * ones(imageSize));
processing = struct('baseLuminance', baseResult);

[~, diagnostics] = beauty.composeBeautyResult( ...
    image, frequency, smoothed, masks, 0, processing);

verifyEqual(testCase, diagnostics.alphaMap, .50 * ones(imageSize), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.luminanceDelta, .02 * ones(imageSize), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.outputLuminance, ...
    sourceLuminance + .02, 'AbsTol', 1e-12);
end

function masks = simpleMasks(imageSize, faceBox)
masks = struct( ...
    'skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'hardProtectionMask', zeros(imageSize), ...
    'textureProtectionMask', zeros(imageSize), ...
    'toneProtectionMask', zeros(imageSize), ...
    'chromaProtectionMask', zeros(imageSize), ...
    'faceBox', faceBox);
end
