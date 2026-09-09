function tests = testPortraitBeautyHelpers
%TESTPORTRAITBEAUTYHELPERS Unit tests for portrait beauty helpers.

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testBeautifyRejectsUnsupportedImageTypes(testCase)
sourceImage = uint8(zeros(32, 32, 3));
faceBox = [8, 8, 16, 16];

verifyError(testCase, @() beautifyImage(uint16(sourceImage), ...
    defaultParams(), faceBox), 'beautifyImage:InvalidImage');
verifyError(testCase, @() beautifyImage(sourceImage(:, :, 1), ...
    defaultParams(), faceBox), 'beautifyImage:InvalidImage');
verifyError(testCase, @() recommendBeautyParams(uint16(sourceImage), faceBox), ...
    'recommendBeautyParams:InvalidImage');
end

function testBeautifyRejectsMissingArguments(testCase)
sourceImage = uint8(zeros(32, 32, 3));

verifyError(testCase, @() beautifyImage(sourceImage), ...
    'beautifyImage:InvalidParams');
verifyError(testCase, @() beautifyImage(sourceImage, defaultParams()), ...
    'beautifyImage:InvalidFaceBox');
verifyError(testCase, @() recommendBeautyParams(sourceImage), ...
    'recommendBeautyParams:InvalidFaceBox');
end

function testBeautifyRejectsInvalidParams(testCase)
sourceImage = uint8(zeros(32, 32, 3));
faceBox = [8, 8, 16, 16];

invalidParams = { ...
    struct('smoothingStrength', 10), ...
    struct('whiteningStrength', 10), ...
    struct('smoothingStrength', '10', 'whiteningStrength', 10), ...
    struct('smoothingStrength', [10, 20], 'whiteningStrength', 10), ...
    struct('smoothingStrength', 10 + 1i, 'whiteningStrength', 10), ...
    struct('smoothingStrength', NaN, 'whiteningStrength', 10), ...
    struct('smoothingStrength', Inf, 'whiteningStrength', 10), ...
    struct('smoothingStrength', -1, 'whiteningStrength', 10), ...
    struct('smoothingStrength', 10, 'whiteningStrength', 101)};
for index = 1:numel(invalidParams)
    verifyError(testCase, @() beautifyImage(sourceImage, ...
        invalidParams{index}, faceBox), 'beautifyImage:InvalidParams');
end
end

function testBeautyRejectsInvalidFaceBox(testCase)
sourceImage = uint8(zeros(32, 32, 3));
params = defaultParams();
invalidFaceBoxes = {[], [1, 1, 2], [0, 1, 10, 10], ...
    [1, 1, 0, 10], [1, 1, 40, 10], [1, 1, 10, NaN], ...
    [1, 1, 10, Inf], [1 + 1i, 1, 10, 10]};
for index = 1:numel(invalidFaceBoxes)
    verifyError(testCase, @() beautifyImage(sourceImage, params, ...
        invalidFaceBoxes{index}), 'beautifyImage:InvalidFaceBox');
    verifyError(testCase, @() recommendBeautyParams(sourceImage, ...
        invalidFaceBoxes{index}), 'recommendBeautyParams:InvalidFaceBox');
end
end

function testZeroStrengthReturnsInputExactly(testCase)
sourceImage = reshape(uint8(0:95), [4, 8, 3]);
faceBox = [1, 1, 8, 4];
invalidContext = struct('notAContext', true);
outputImage = beautifyImage(sourceImage, ...
    struct('smoothingStrength', 0, 'whiteningStrength', 0), ...
    faceBox, invalidContext);
verifyClass(testCase, outputImage, 'uint8');
verifyEqual(testCase, outputImage, sourceImage);
end

function testBeautyContextValidationAndReuse(testCase)
[sourceImage, faceBox, ~, ~] = syntheticPortrait(240, 320);
context = prepareBeautyContext(sourceImage, faceBox);
verifyEqual(testCase, fieldnames(context), ...
    {'skinMask'; 'faceSkinMask'; 'featureProtectionMask'; ...
    'imageSize'; 'faceBox'});
verifySize(testCase, context.skinMask, size(sourceImage, [1, 2]));
verifyGreaterThan(testCase, nnz(context.faceSkinMask), 0);
params = struct('smoothingStrength', 50, 'whiteningStrength', 50);
verifyEqual(testCase, beautifyImage(sourceImage, params, faceBox, context), ...
    beautifyImage(sourceImage, params, faceBox));
verifyEqual(testCase, recommendBeautyParams(sourceImage, faceBox, context), ...
    recommendBeautyParams(sourceImage, faceBox));

badContext = context;
badContext.faceBox(1) = badContext.faceBox(1) + 1;
verifyError(testCase, @() beautifyImage(sourceImage, params, faceBox, badContext), ...
    'beautifyImage:InvalidContext');
verifyError(testCase, @() recommendBeautyParams( ...
    sourceImage, faceBox, badContext), 'recommendBeautyParams:InvalidContext');
end

function testNonzeroBeautyPreservesShapeAndChannels(testCase)
sourceImage = uint8(zeros(40, 60, 3));
sourceImage(:, :, 1) = 100;
sourceImage(:, :, 2) = 80;
sourceImage(:, :, 3) = 70;
outputImage = beautifyImage(sourceImage, ...
    struct('smoothingStrength', 100, 'whiteningStrength', 100), ...
    [10, 8, 30, 24]);
verifyClass(testCase, outputImage, 'uint8');
verifySize(testCase, outputImage, size(sourceImage));
verifyTrue(testCase, nnz(outputImage ~= sourceImage) > 0, ...
    'Non-zero beauty strengths should change pixels in the face region.');
end

function testBeautyPreservesDimensionsForDifferentShapes(testCase)
imageSizes = [7, 5; 11, 17; 32, 19];
for index = 1:size(imageSizes, 1)
    imageHeight = imageSizes(index, 1);
    imageWidth = imageSizes(index, 2);
    sourceImage = reshape(uint8(0:(imageHeight * imageWidth * 3 - 1)), ...
        [imageHeight, imageWidth, 3]);
    outputImage = beautifyImage(sourceImage, ...
        struct('smoothingStrength', 0, 'whiteningStrength', 50), ...
        [1, 1, imageWidth, imageHeight]);
    verifyClass(testCase, outputImage, 'uint8');
    verifyEqual(testCase, size(outputImage), [imageHeight, imageWidth, 3]);
end
end

function testRecommendationIsBoundedAndAdaptive(testCase)
darkTextured = uint8(80 * ones(48, 48, 3));
darkTextured(12:2:36, 12:2:36, :) = 180;
brightSmooth = uint8(220 * ones(48, 48, 3));
faceBox = [1, 1, 48, 48];

darkParams = recommendBeautyParams(darkTextured, faceBox);
brightParams = recommendBeautyParams(brightSmooth, faceBox);
verifyTrue(testCase, all(struct2array(darkParams) >= 0));
verifyTrue(testCase, all(struct2array(darkParams) <= 100));
verifyTrue(testCase, all(struct2array(brightParams) >= 0));
verifyTrue(testCase, all(struct2array(brightParams) <= 100));
verifyEqual(testCase, fieldnames(darkParams), ...
    {'smoothingStrength'; 'whiteningStrength'});
verifyTrue(testCase, all(isfinite(struct2array(darkParams))));
verifyNotEqual(testCase, darkParams.whiteningStrength, ...
    brightParams.whiteningStrength);
verifyGreaterThan(testCase, darkParams.whiteningStrength, 55, ...
    'Adaptive whitening must not be capped at 55.');
verifyGreaterThan(testCase, darkParams.smoothingStrength, ...
    brightParams.smoothingStrength);
end

function testWhiteningBrightnessIncreasesMonotonically(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(480, 640);
strengths = [0, 25, 50, 75, 100];
meanBrightness = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', 0, ...
        'whiteningStrength', strengths(index)), faceBox);
    grayImage = im2double(rgb2gray(outputImage));
    meanBrightness(index) = mean(grayImage(skinRegion));
end

% 各档应稳定增强，默认档在典型中等肤色上已有肉眼可见提升。
verifyTrue(testCase, all(diff(meanBrightness) > 0.005));
verifyGreaterThan(testCase, ...
    255 * (meanBrightness(2) - meanBrightness(1)), 12);
verifyLessThan(testCase, meanBrightness(end), 0.95);
end

function testSmoothingTextureEnergyDecreasesMonotonically(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(480, 640);
strengths = [0, 25, 50, 75, 100];
textureEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), ...
        'whiteningStrength', 0), faceBox);
    grayImage = im2double(rgb2gray(outputImage));
    localBase = imgaussfilt(grayImage, 3, 'Padding', 'replicate');
    textureResidual = abs(grayImage - localBase);
    textureEnergy(index) = mean(textureResidual(skinRegion));
end

verifyTrue(testCase, all(diff(textureEnergy) < -1e-4));
verifyLessThan(testCase, textureEnergy(end), 0.25 * textureEnergy(1));
end

function testSmoothingRemainsEffectiveAcrossFaceScales(testCase)
configs = [360, 640, 70; 720, 1280, 220; 1080, 1920, 520];
strengths = [0, 25, 50, 75, 100];
for configIndex = 1:size(configs, 1)
    [sourceImage, faceBox, skinRegion, ~] = syntheticPortrait( ...
        configs(configIndex, 1), configs(configIndex, 2), ...
        configs(configIndex, 3));
    textureEnergy = zeros(size(strengths));
    for strengthIndex = 1:numel(strengths)
        outputImage = beautifyImage(sourceImage, struct( ...
            'smoothingStrength', strengths(strengthIndex), ...
            'whiteningStrength', 0), faceBox);
        textureEnergy(strengthIndex) = measureTextureEnergy( ...
            outputImage, skinRegion, min(faceBox(3:4)));
    end
    defaultOutput = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', 35, 'whiteningStrength', 0), faceBox);
    defaultEnergy = measureTextureEnergy( ...
        defaultOutput, skinRegion, min(faceBox(3:4)));

    verifyTrue(testCase, all(diff(textureEnergy) < 0));
    verifyLessThan(testCase, defaultEnergy, 0.90 * textureEnergy(1), ...
        'Default smoothing should visibly reduce texture at every face scale.');
    verifyLessThan(testCase, textureEnergy(end), 0.75 * textureEnergy(1));
end
end

function testBeautyProtectsHairHighlightsAndChroma(testCase)
[sourceImage, faceBox, skinRegion, backgroundRegion, ...
    hairRegion, highlightRegion] = protectedPortrait();
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox);
difference = abs(double(outputImage) - double(sourceImage));

hairDifference = difference(repmat(hairRegion, [1, 1, 3]));
backgroundDifference = difference(repmat(backgroundRegion, [1, 1, 3]));
highlightDifference = difference(repmat(highlightRegion, [1, 1, 3]));
verifyLessThanOrEqual(testCase, max(hairDifference), 1, ...
    'Deep hair inside faceBox must not be treated as skin during fallback.');
verifyLessThanOrEqual(testCase, max(backgroundDifference), 1);
verifyLessThan(testCase, mean(highlightDifference), 10);
verifyLessThan(testCase, ...
    max(outputImage(repmat(highlightRegion, [1, 1, 3]))), uint8(255));

inputYCbCr = rgb2ycbcr(sourceImage);
outputYCbCr = rgb2ycbcr(outputImage);
chromaDifference = abs(double(outputYCbCr(:, :, 2:3)) - ...
    double(inputYCbCr(:, :, 2:3)));
verifyLessThanOrEqual(testCase, ...
    max(chromaDifference(repmat(skinRegion, [1, 1, 2]))), 8);
end

function testLowReliabilityFallbackProtectsHairAndPeripheralBackground(testCase)
[sourceImage, faceBox, skinRegion, hairRegion, backgroundRegion] = ...
    fallbackPortrait();
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox);
difference = abs(double(outputImage) - double(sourceImage));
skinDifference = difference(repmat(skinRegion, [1, 1, 3]));
hairDifference = difference(repmat(hairRegion, [1, 1, 3]));
backgroundDifference = difference(repmat(backgroundRegion, [1, 1, 3]));

verifyGreaterThan(testCase, mean(skinDifference), 10, ...
    'Fallback must still process an atypical face color.');
verifyLessThanOrEqual(testCase, max(hairDifference), 1);
verifyLessThanOrEqual(testCase, mean(backgroundDifference), 2);
verifyLessThanOrEqual(testCase, max(backgroundDifference), 6);
end

function testSmoothingPreservesStrongFacialEdges(testCase)
[sourceImage, faceBox, leftRegion, rightRegion] = edgePortrait();
inputGray = im2double(rgb2gray(sourceImage));
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox);
outputGray = im2double(rgb2gray(outputImage));
inputContrast = mean(inputGray(rightRegion)) - mean(inputGray(leftRegion));
outputContrast = mean(outputGray(rightRegion)) - mean(outputGray(leftRegion));
verifyGreaterThan(testCase, outputContrast, 0.85 * inputContrast);
end

function testMaximumBeautyPreservesFacialLuminanceStructure(testCase)
% 最高档仍应保留鼻梁、眼窝和脸颊之间的低频明暗层次。
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(360, 480);
[xGrid, yGrid] = meshgrid(1:size(sourceImage, 2), 1:size(sourceImage, 1));
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
faceShape = ((xGrid - centerX) / (faceBox(3) / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceBox(4) / 2)) .^ 2;
noseLight = 22 * exp(-((xGrid - centerX) / 30) .^ 2 - ...
    ((yGrid - (centerY + 8)) / 105) .^ 2);
eyeShadow = -14 * exp(-((xGrid - (centerX - 55)) / 32) .^ 2 - ...
    ((yGrid - (centerY - 42)) / 24) .^ 2) - ...
    14 * exp(-((xGrid - (centerX + 55)) / 32) .^ 2 - ...
    ((yGrid - (centerY - 42)) / 24) .^ 2);
cheekLight = 7 * exp(-((xGrid - (centerX - 65)) / 45) .^ 2 - ...
    ((yGrid - (centerY + 42)) / 36) .^ 2) + ...
    7 * exp(-((xGrid - (centerX + 65)) / 45) .^ 2 - ...
    ((yGrid - (centerY + 42)) / 36) .^ 2);
lowFrequencyShape = noseLight + eyeShadow + cheekLight;
for channel = 1:3
    channelData = double(sourceImage(:, :, channel));
    channelData(skinRegion) = channelData(skinRegion) + ...
        lowFrequencyShape(skinRegion);
    sourceImage(:, :, channel) = uint8(min(max(round(channelData), 0), 255));
end
eyeSocket = skinRegion & faceShape < 0.35 & ...
    yGrid < centerY - 20 & abs(xGrid - centerX) > 28 & ...
    abs(xGrid - centerX) < 78;
cheek = skinRegion & faceShape < 0.35 & ...
    yGrid > centerY + 25 & abs(xGrid - centerX) > 45 & ...
    abs(xGrid - centerX) < 95;
noseRidge = skinRegion & abs(xGrid - centerX) < 16 & ...
    yGrid > centerY - 10 & yGrid < centerY + 62;
inputGray = im2double(rgb2gray(sourceImage));
for strengths = [100, 0, 100]
    if strengths == 0
        params = struct('smoothingStrength', 0, 'whiteningStrength', 100);
    else
        params = struct('smoothingStrength', strengths, 'whiteningStrength', 0);
    end
    outputGray = im2double(rgb2gray(beautifyImage(sourceImage, params, faceBox)));
    inputContrast = mean(inputGray(cheek)) - mean(inputGray(eyeSocket));
    outputContrast = mean(outputGray(cheek)) - mean(outputGray(eyeSocket));
    verifyGreaterThan(testCase, inputContrast * outputContrast, 0);
    verifyGreaterThan(testCase, abs(outputContrast), ...
        0.80 * abs(inputContrast));
    inputNoseContrast = mean(inputGray(noseRidge)) - mean(inputGray(cheek));
    outputNoseContrast = mean(outputGray(noseRidge)) - mean(outputGray(cheek));
    verifyGreaterThan(testCase, inputNoseContrast * outputNoseContrast, 0);
    verifyGreaterThan(testCase, abs(outputNoseContrast), ...
        0.80 * abs(inputNoseContrast));
end
bothOutput = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox);
bothGray = im2double(rgb2gray(bothOutput));
inputEyeContrast = mean(inputGray(cheek)) - mean(inputGray(eyeSocket));
outputEyeContrast = mean(bothGray(cheek)) - mean(bothGray(eyeSocket));
inputNoseContrast = mean(inputGray(noseRidge)) - mean(inputGray(cheek));
outputNoseContrast = mean(bothGray(noseRidge)) - mean(bothGray(cheek));
verifyGreaterThan(testCase, inputEyeContrast * outputEyeContrast, 0);
verifyGreaterThan(testCase, abs(outputEyeContrast), ...
    0.80 * abs(inputEyeContrast));
verifyGreaterThan(testCase, inputNoseContrast * outputNoseContrast, 0);
verifyGreaterThan(testCase, abs(outputNoseContrast), ...
    0.80 * abs(inputNoseContrast));
end

function testBeautyKeepsBackgroundChangesSmall(testCase)
[sourceImage, faceBox, ~, backgroundRegion] = syntheticPortrait(480, 640);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox);
backgroundMask = repmat(backgroundRegion, [1, 1, 3]);
backgroundDifference = abs(double(outputImage(backgroundMask)) - ...
    double(sourceImage(backgroundMask)));

verifyLessThanOrEqual(testCase, mean(backgroundDifference), 0.1);
verifyLessThanOrEqual(testCase, max(backgroundDifference), 1);
end

function testMaskFollowsNonEllipticalSkinContent(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(240, 320);
sourceImage(70:150, 150:230, :) = uint8(45);
mask = createBeautyMask(im2double(sourceImage), faceBox);
verifyGreaterThan(testCase, mean(mask(skinRegion & sourceImage(:, :, 1) > 100)), 0.25);
verifyLessThan(testCase, mean(mask(90:130, 175:205), 'all'), 0.15);
end

function testMaskBoundaryIsSoftWithoutEllipseHalo(testCase)
[sourceImage, faceBox, ~, backgroundRegion] = syntheticPortrait(240, 320);
mask = createBeautyMask(im2double(sourceImage), faceBox);
verifyEqual(testCase, max(mask(backgroundRegion), [], 'all'), 0, 'AbsTol', 1e-12);
edgeBand = mask(faceBox(2), faceBox(1):faceBox(1) + faceBox(3) - 1);
verifyLessThanOrEqual(testCase, max(abs(diff(edgeBand))), 0.5);
end

function testFrecklesAttenuateProgressivelyWithTextureRetained(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(240, 320);
[xGrid, yGrid] = meshgrid(1:size(sourceImage, 2), ...
    1:size(sourceImage, 1));
freckleCenters = [132, 105; 148, 116; 166, 102; 178, 124; 154, 138];
freckleRegion = false(size(skinRegion));
for centerIndex = 1:size(freckleCenters, 1)
    center = freckleCenters(centerIndex, :);
    freckleRegion = freckleRegion | ...
        ((xGrid - center(1)) .^ 2 + (yGrid - center(2)) .^ 2 <= 9);
end
freckleRegion = freckleRegion & skinRegion;
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(freckleRegion) = max(0, ...
        channelData(freckleRegion) - uint8(42));
    sourceImage(:, :, channel) = channelData;
end

surroundingRegion = imdilate(freckleRegion, strel('disk', 5, 0)) & ...
    skinRegion & ~freckleRegion;
strengths = [0, 25, 50, 75, 100];
freckleContrast = zeros(size(strengths));
textureEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), ...
        'whiteningStrength', 0), faceBox);
    grayImage = im2double(rgb2gray(outputImage));
    freckleContrast(index) = mean(grayImage(surroundingRegion)) - ...
        mean(grayImage(freckleRegion));
    textureEnergy(index) = measureTextureEnergy( ...
        outputImage, skinRegion, min(faceBox(3:4)));
end
verifyTrue(testCase, all(diff(freckleContrast) < 0));
verifyLessThanOrEqual(testCase, freckleContrast(end), ...
    0.30 * freckleContrast(1));
verifyGreaterThan(testCase, freckleContrast(end), ...
    0.02 * freckleContrast(1));
verifyGreaterThanOrEqual(testCase, textureEnergy(end), ...
    0.10 * textureEnergy(1));
end


function testContextIncludesDisconnectedSkinButRejectsSkinLikeBackground(testCase)
[sourceImage, faceBox, ~, ~] = syntheticPortrait(360, 480);
[xGrid, yGrid] = meshgrid(1:480, 1:360);
armRegion = xGrid >= 35 & xGrid <= 95 & yGrid >= 220 & yGrid <= 340;
backgroundRegion = xGrid >= 390 & yGrid <= 105;
skinColor = uint8([172, 128, 108]);
backgroundColor = uint8([168, 126, 108]);
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(armRegion) = skinColor(channel);
    channelData(backgroundRegion) = backgroundColor(channel);
    sourceImage(:, :, channel) = channelData;
end
context = prepareBeautyContext(sourceImage, faceBox);
verifyGreaterThan(testCase, mean(context.skinMask(armRegion)), 0.65);
verifyLessThan(testCase, mean(context.skinMask(backgroundRegion)), 0.05);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, context);
difference = mean(abs(double(outputImage) - double(sourceImage)), 3);
verifyGreaterThan(testCase, mean(difference(armRegion)), 3);
verifyLessThan(testCase, mean(difference(backgroundRegion)), 0.2);
end

function testMaximumSmoothingPreservesProtectedFeatureGradients(testCase)
[sourceImage, faceBox, ~, ~] = syntheticPortrait(360, 480);
[xGrid, yGrid] = meshgrid(1:480, 1:360);
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
eyeRegion = ((xGrid - (centerX - 48)) / 25) .^ 2 + ...
    ((yGrid - (centerY - 48)) / 11) .^ 2 <= 1 | ...
    ((xGrid - (centerX + 48)) / 25) .^ 2 + ...
    ((yGrid - (centerY - 48)) / 11) .^ 2 <= 1;
mouthRegion = ((xGrid - centerX) / 38) .^ 2 + ...
    ((yGrid - (centerY + 68)) / 10) .^ 2 <= 1;
eyeColor = uint8([35, 28, 24]);
mouthColor = uint8([145, 52, 62]);
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(eyeRegion) = eyeColor(channel);
    channelData(mouthRegion) = mouthColor(channel);
    sourceImage(:, :, channel) = channelData;
end
featureBand = imdilate(eyeRegion | mouthRegion, strel('disk', 3, 0));
context = prepareBeautyContext(sourceImage, faceBox);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, context);
inputGradient = imgradient(rgb2gray(sourceImage));
outputGradient = imgradient(rgb2gray(outputImage));
verifyGreaterThanOrEqual(testCase, mean(outputGradient(featureBand)), ...
    0.85 * mean(inputGradient(featureBand)));
end

function testChromaSpotsAttenuateMonotonically(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(300, 400);
[xGrid, yGrid] = meshgrid(1:400, 1:300);
centers = [155, 172; 245, 172; 145, 188; 255, 188];
spotRegion = false(300, 400);
for index = 1:size(centers, 1)
    spotRegion = spotRegion | ((xGrid - centers(index, 1)) .^ 2 + ...
        (yGrid - centers(index, 2)) .^ 2 <= 12);
end
spotRegion = spotRegion & skinRegion;
red = sourceImage(:, :, 1);
blue = sourceImage(:, :, 3);
red(spotRegion) = min(uint8(255), red(spotRegion) + uint8(34));
blue(spotRegion) = blue(spotRegion) - min(blue(spotRegion), uint8(14));
sourceImage(:, :, 1) = red;
sourceImage(:, :, 3) = blue;
surrounding = imdilate(spotRegion, strel('disk', 5, 0)) & ...
    skinRegion & ~spotRegion;
context = prepareBeautyContext(sourceImage, faceBox);
strengths = [0, 25, 50, 75, 100];
contrast = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), 'whiteningStrength', 0), ...
        faceBox, context);
    outputYCbCr = rgb2ycbcr(outputImage);
    cr = double(outputYCbCr(:, :, 3));
    contrast(index) = mean(cr(spotRegion)) - mean(cr(surrounding));
end
verifyTrue(testCase, all(diff(contrast) < 0));
verifyLessThan(testCase, contrast(end), 0.45 * contrast(1));
end

function testEvaluateImageReturnsExpectedMetrics(testCase)
values = uint8([0, 64; 128, 255]);
originalImage = uint8(zeros(2, 2, 3));
outputImage = repmat(values, [1, 1, 3]);
metrics = evaluateImage(originalImage, outputImage, 0.25);

verifyEqual(testCase, fieldnames(metrics), ...
    {'entropy'; 'standardDeviation'; 'averageGradient'; 'elapsedSeconds'});
verifyEqual(testCase, metrics.entropy, 2, 'AbsTol', 1e-12);
verifyEqual(testCase, metrics.standardDeviation, 0.3697144486609025, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, metrics.averageGradient, 0.7394392159153644, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, metrics.elapsedSeconds, 0.25);
end

function testEvaluateImageRejectsInvalidInputs(testCase)
sourceImage = uint8(zeros(12, 16, 3));
otherSize = uint8(zeros(10, 16, 3));
verifyError(testCase, @() evaluateImage(sourceImage, otherSize, 0), ...
    'evaluateImage:SizeMismatch');
invalidElapsedValues = {-1, NaN, Inf, [0, 1]};
for index = 1:numel(invalidElapsedValues)
    verifyError(testCase, @() evaluateImage(sourceImage, sourceImage, ...
        invalidElapsedValues{index}), 'evaluateImage:InvalidElapsed');
end
verifyError(testCase, @() evaluateImage(sourceImage(:, :, 1), sourceImage, 0), ...
    'evaluateImage:InvalidImage');
verifyError(testCase, @() evaluateImage(sourceImage, sourceImage(:, :, 1), 0), ...
    'evaluateImage:InvalidImage');
end

function [sourceImage, faceBox, skinRegion, backgroundRegion] = ...
        syntheticPortrait(imageHeight, imageWidth, faceWidth)
%SYNTHETICPORTRAIT 构造带细纹的中等肤色高分辨率测试图。
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
if nargin < 3
    faceWidth = round(0.46 * imageWidth);
    faceHeight = round(0.73 * imageHeight);
else
    faceHeight = round(1.25 * faceWidth);
end
faceX = round((imageWidth - faceWidth) / 2);
faceY = round(0.12 * imageHeight);
faceBox = [faceX, faceY, faceWidth, faceHeight];
centerX = faceX + faceWidth / 2;
centerY = faceY + faceHeight / 2;
radialDistance = ((xGrid - centerX) / (faceWidth / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceHeight / 2)) .^ 2;
faceRegion = radialDistance <= 0.82;
skinRegion = radialDistance <= 0.45;
backgroundRegion = radialDistance >= 1.15;
texture = 12 * sin(2 * pi * xGrid / 12) .* sin(2 * pi * yGrid / 10);
backgroundColor = [55, 65, 75];
skinColor = [172, 128, 108];
sourceImage = zeros(imageHeight, imageWidth, 3, 'uint8');
for channel = 1:3
    channelData = backgroundColor(channel) * ones(imageHeight, imageWidth);
    texturedSkin = skinColor(channel) + texture;
    channelData(faceRegion) = texturedSkin(faceRegion);
    sourceImage(:, :, channel) = uint8(min(max(round(channelData), 0), 255));
end
end

function textureEnergy = measureTextureEnergy(imageData, region, faceScale)
grayImage = im2double(rgb2gray(imageData));
measurementSigma = max(1, 0.008 * faceScale);
localBase = imgaussfilt(grayImage, measurementSigma, ...
    'Padding', 'replicate');
textureResidual = abs(grayImage - localBase);
textureEnergy = mean(textureResidual(region));
end

function [sourceImage, faceBox, skinRegion, backgroundRegion, ...
        hairRegion, highlightRegion] = protectedPortrait
[sourceImage, faceBox, skinRegion, backgroundRegion] = ...
    syntheticPortrait(480, 640);
[xGrid, yGrid] = meshgrid(1:size(sourceImage, 2), 1:size(sourceImage, 1));
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
radialDistance = ((xGrid - centerX) / (faceBox(3) / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceBox(4) / 2)) .^ 2;
hairRegion = radialDistance <= 0.70 & ...
    yGrid < centerY - 0.25 * faceBox(4);
highlightRegion = radialDistance <= 0.18 & ...
    xGrid > centerX + 0.08 * faceBox(3);
hairColor = [48, 31, 24];
highlightColor = [246, 224, 210];
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(hairRegion) = hairColor(channel);
    channelData(highlightRegion) = highlightColor(channel);
    sourceImage(:, :, channel) = channelData;
end
skinRegion = skinRegion & ~hairRegion & ~highlightRegion;
end

function [sourceImage, faceBox, skinRegion, hairRegion, ...
        backgroundRegion] = fallbackPortrait
imageHeight = 480;
imageWidth = 640;
faceBox = [170, 60, 300, 360];
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
radialDistance = sqrt(((xGrid - centerX) / (faceBox(3) / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceBox(4) / 2)) .^ 2);
faceRegion = radialDistance <= 0.88;
skinRegion = radialDistance <= 0.40 & ...
    yGrid > centerY - 0.15 * faceBox(4);
hairRegion = radialDistance <= 0.68 & ...
    yGrid < centerY - 0.27 * faceBox(4);
backgroundRegion = radialDistance >= 0.78 & radialDistance <= 0.88 & ...
    xGrid > centerX;
sourceImage = zeros(imageHeight, imageWidth, 3, 'uint8');
baseColor = [42, 60, 78];
atypicalSkinColor = [80, 160, 180];
hairColor = [48, 31, 24];
backgroundColor = [55, 115, 205];
for channel = 1:3
    channelData = baseColor(channel) * ones(imageHeight, imageWidth);
    channelData(faceRegion) = atypicalSkinColor(channel);
    channelData(hairRegion) = hairColor(channel);
    channelData(backgroundRegion) = backgroundColor(channel);
    sourceImage(:, :, channel) = uint8(channelData);
end
end

function [sourceImage, faceBox, leftRegion, rightRegion] = edgePortrait
imageHeight = 400;
imageWidth = 500;
faceBox = [100, 50, 300, 300];
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
insideFace = ((xGrid - 250) / 145) .^ 2 + ...
    ((yGrid - 200) / 145) .^ 2 <= 1;
leftRegion = insideFace & xGrid >= 225 & xGrid <= 244 & ...
    yGrid >= 130 & yGrid <= 270;
rightRegion = insideFace & xGrid >= 256 & xGrid <= 275 & ...
    yGrid >= 130 & yGrid <= 270;
texture = 8 * sin(2 * pi * xGrid / 9) .* sin(2 * pi * yGrid / 11);
sourceImage = uint8(70 * ones(imageHeight, imageWidth, 3));
for channel = 1:3
    channelData = double(sourceImage(:, :, channel));
    leftData = 120 + texture;
    rightData = 205 + texture;
    leftFace = insideFace & xGrid < 250;
    rightFace = insideFace & xGrid >= 250;
    channelData(leftFace) = leftData(leftFace);
    channelData(rightFace) = rightData(rightFace);
    sourceImage(:, :, channel) = uint8(round(channelData));
end
end

function params = defaultParams
params = struct('smoothingStrength', 10, 'whiteningStrength', 10);
end
