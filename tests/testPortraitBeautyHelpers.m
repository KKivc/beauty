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
context = contextForTestImage(sourceImage, faceBox);
required = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'semanticProbabilities', ...
    'schemaVersion', 'regions', 'regionConfidence', 'bodySkinMask', ...
    'geometry', 'imageSize', 'faceBox'};
verifyTrue(testCase, all(isfield(context, required)));
verifyFalse(testCase, any(isfield(context, ...
    {'featureProtectionMask', 'hardProtectionMask'})));
verifySize(testCase, context.skinMask, size(sourceImage, [1, 2]));
verifyGreaterThan(testCase, nnz(context.faceSkinMask), 0);
params = struct('smoothingStrength', 50, 'whiteningStrength', 50);
verifyEqual(testCase, beautifyImage(sourceImage, params, faceBox, context), ...
    beautifyImage(sourceImage, params, faceBox, context));
verifyEqual(testCase, recommendBeautyParams(sourceImage, faceBox, context), ...
    recommendBeautyParams(sourceImage, faceBox, context));

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
faceBox = [10, 8, 30, 24];
context = contextForTestImage(sourceImage, faceBox);
outputImage = beautifyImage(sourceImage, ...
    struct('smoothingStrength', 100, 'whiteningStrength', 100), ...
    faceBox, context);
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
    faceBox = [1, 1, imageWidth, imageHeight];
    context = contextForTestImage(sourceImage, faceBox);
    outputImage = beautifyImage(sourceImage, ...
        struct('smoothingStrength', 0, 'whiteningStrength', 50), ...
        faceBox, context);
    verifyClass(testCase, outputImage, 'uint8');
    verifyEqual(testCase, size(outputImage), [imageHeight, imageWidth, 3]);
end
end

function testRecommendationIsBoundedAndAdaptive(testCase)
darkTextured = uint8(80 * ones(48, 48, 3));
darkTextured(12:2:36, 12:2:36, :) = 180;
brightSmooth = uint8(220 * ones(48, 48, 3));
faceBox = [1, 1, 48, 48];
darkContext = contextForTestImage(darkTextured, faceBox);
brightContext = contextForTestImage(brightSmooth, faceBox);

darkParams = recommendBeautyParams(darkTextured, faceBox, darkContext);
brightParams = recommendBeautyParams(brightSmooth, faceBox, brightContext);
verifyTrue(testCase, all(struct2array(darkParams) >= 0));
verifyTrue(testCase, all(struct2array(darkParams) <= 100));
verifyTrue(testCase, all(struct2array(brightParams) >= 0));
verifyTrue(testCase, all(struct2array(brightParams) <= 100));
verifyEqual(testCase, fieldnames(darkParams), ...
    {'smoothingStrength'; 'whiteningStrength'});
verifyTrue(testCase, all(isfinite(struct2array(darkParams))));
verifyNotEqual(testCase, darkParams.whiteningStrength, ...
    brightParams.whiteningStrength);
verifyLessThanOrEqual(testCase, darkParams.whiteningStrength, 30, ...
    'Adaptive whitening must remain conservative.');
verifyGreaterThan(testCase, darkParams.smoothingStrength, ...
    brightParams.smoothingStrength);
end

function testWhiteningBrightnessIncreasesMonotonically(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(480, 640);
context = contextForTestImage(sourceImage, faceBox, skinRegion);
strengths = [0, 25, 50, 75, 100];
meanBrightness = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', 0, ...
        'whiteningStrength', strengths(index)), faceBox, context);
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
context = contextForTestImage(sourceImage, faceBox, skinRegion);
strengths = [0, 25, 50, 75, 100];
textureEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), ...
        'whiteningStrength', 0), faceBox, context);
    grayImage = im2double(rgb2gray(outputImage));
    localBase = imgaussfilt(grayImage, 3, 'Padding', 'replicate');
    textureResidual = abs(grayImage - localBase);
    textureEnergy(index) = mean(textureResidual(skinRegion));
end

verifyTrue(testCase, all(diff(textureEnergy) <= 1e-6));
verifyLessThan(testCase, textureEnergy(end), 0.95 * textureEnergy(1));
verifyLessThan(testCase, textureEnergy(end), ...
    textureEnergy(end - 1) - 1e-12, ...
    '75--100 档仍应继续降低普通皮肤纹理能量。');
verifyGreaterThan(testCase, textureEnergy(end), 0, ...
    '高档磨皮仍应保留非零纹理。');
end

function testSmoothingRemainsEffectiveAcrossFaceScales(testCase)
configs = [360, 640, 70; 720, 1280, 220; 1080, 1920, 520];
strengths = [0, 25, 50, 75, 100];
for configIndex = 1:size(configs, 1)
    [sourceImage, faceBox, skinRegion, ~] = syntheticPortrait( ...
        configs(configIndex, 1), configs(configIndex, 2), ...
        configs(configIndex, 3));
    context = contextForTestImage(sourceImage, faceBox, skinRegion);
    textureEnergy = zeros(size(strengths));
    for strengthIndex = 1:numel(strengths)
        outputImage = beautifyImage(sourceImage, struct( ...
            'smoothingStrength', strengths(strengthIndex), ...
            'whiteningStrength', 0), faceBox, context);
        textureEnergy(strengthIndex) = measureTextureEnergy( ...
            outputImage, skinRegion, min(faceBox(3:4)));
    end
    defaultOutput = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', 35, 'whiteningStrength', 0), faceBox, context);
    defaultEnergy = measureTextureEnergy( ...
        defaultOutput, skinRegion, min(faceBox(3:4)));

    verifyTrue(testCase, all(diff(textureEnergy) <= 1e-8));
    verifyLessThan(testCase, defaultEnergy, 0.99 * textureEnergy(1), ...
        'Default smoothing should visibly reduce texture at every face scale.');
    verifyLessThan(testCase, textureEnergy(end), 0.98 * textureEnergy(1));
end
end

function testBeautyProtectsHairHighlightsAndChroma(testCase)
[sourceImage, faceBox, skinRegion, backgroundRegion, ...
    hairRegion, highlightRegion] = protectedPortrait();
context = contextForTestImage(sourceImage, faceBox, skinRegion, hairRegion);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, context);
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
context = contextForTestImage(sourceImage, faceBox, skinRegion, hairRegion);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, context);
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
skinRegion = sourceImage(:, :, 1) > 80;
context = contextForTestImage(sourceImage, faceBox, skinRegion);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
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
context = contextForTestImage(sourceImage, faceBox, skinRegion);
for strengths = [100, 0, 100]
    if strengths == 0
        params = struct('smoothingStrength', 0, 'whiteningStrength', 100);
    else
        params = struct('smoothingStrength', strengths, 'whiteningStrength', 0);
    end
    outputGray = im2double(rgb2gray(beautifyImage( ...
        sourceImage, params, faceBox, context)));
    inputContrast = mean(inputGray(cheek)) - mean(inputGray(eyeSocket));
    outputContrast = mean(outputGray(cheek)) - mean(outputGray(eyeSocket));
    verifyGreaterThan(testCase, inputContrast * outputContrast, 0);
    verifyGreaterThan(testCase, abs(outputContrast), ...
        0.85 * abs(inputContrast));
    inputNoseContrast = mean(inputGray(noseRidge)) - mean(inputGray(cheek));
    outputNoseContrast = mean(outputGray(noseRidge)) - mean(outputGray(cheek));
    verifyGreaterThan(testCase, inputNoseContrast * outputNoseContrast, 0);
    verifyGreaterThan(testCase, abs(outputNoseContrast), ...
        0.85 * abs(inputNoseContrast));
end
bothOutput = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, context);
bothGray = im2double(rgb2gray(bothOutput));
inputEyeContrast = mean(inputGray(cheek)) - mean(inputGray(eyeSocket));
outputEyeContrast = mean(bothGray(cheek)) - mean(bothGray(eyeSocket));
inputNoseContrast = mean(inputGray(noseRidge)) - mean(inputGray(cheek));
outputNoseContrast = mean(bothGray(noseRidge)) - mean(bothGray(cheek));
verifyGreaterThan(testCase, inputEyeContrast * outputEyeContrast, 0);
verifyGreaterThan(testCase, abs(outputEyeContrast), ...
    0.85 * abs(inputEyeContrast));
verifyGreaterThan(testCase, inputNoseContrast * outputNoseContrast, 0);
verifyGreaterThan(testCase, abs(outputNoseContrast), ...
    0.85 * abs(inputNoseContrast));
end

function testBeautyKeepsBackgroundChangesSmall(testCase)
[sourceImage, faceBox, skinRegion, backgroundRegion] = syntheticPortrait(480, 640);
context = contextForTestImage(sourceImage, faceBox, skinRegion);
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, context);
backgroundMask = repmat(backgroundRegion, [1, 1, 3]);
backgroundDifference = abs(double(outputImage(backgroundMask)) - ...
    double(sourceImage(backgroundMask)));

verifyLessThanOrEqual(testCase, mean(backgroundDifference), 0.1);
verifyLessThanOrEqual(testCase, max(backgroundDifference), 1);
end

function testMaskFollowsNonEllipticalSkinContent(testCase)
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(240, 320);
sourceImage(70:150, 150:230, :) = uint8(45);
semanticSkin = skinRegion;
semanticSkin(70:150, 150:230) = false;
context = contextForTestImage(sourceImage, faceBox, semanticSkin);
mask = context.faceSkinMask;
verifyGreaterThan(testCase, mean(mask(skinRegion & sourceImage(:, :, 1) > 100)), 0.25);
verifyLessThan(testCase, mean(mask(90:130, 175:205), 'all'), 0.15);
end

function testMaskBoundaryIsSoftWithoutEllipseHalo(testCase)
[sourceImage, faceBox, skinRegion, backgroundRegion] = syntheticPortrait(240, 320);
context = contextForTestImage(sourceImage, faceBox, skinRegion);
mask = context.faceSkinMask;
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
textureRegion = skinRegion & ...
    ~imdilate(freckleRegion, strel('disk', 7, 0));
context = contextForTestImage(sourceImage, faceBox, skinRegion);
strengths = [0, 25, 50, 75, 100];
freckleContrast = zeros(size(strengths));
textureEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), ...
        'whiteningStrength', 0), faceBox, context);
    grayImage = im2double(rgb2gray(outputImage));
    freckleContrast(index) = mean(grayImage(surroundingRegion)) - ...
        mean(grayImage(freckleRegion));
    textureEnergy(index) = measureTextureEnergy( ...
        outputImage, textureRegion, min(faceBox(3:4)));
end
verifyTrue(testCase, all(diff(freckleContrast) < 0));
verifyLessThanOrEqual(testCase, freckleContrast(end), ...
    0.25 * freckleContrast(1));
verifyGreaterThan(testCase, freckleContrast(end), ...
    0.02 * freckleContrast(1));
verifyGreaterThanOrEqual(testCase, textureEnergy(end), ...
    0.50 * textureEnergy(1));
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
neckRegion = false(size(armRegion));
neckRows = round(faceBox(2) + 0.72 * faceBox(4)): ...
    round(faceBox(2) + 0.88 * faceBox(4));
neckColumns = round(faceBox(1) + 0.40 * faceBox(3)): ...
    round(faceBox(1) + 0.60 * faceBox(3));
neckRegion(neckRows, neckColumns) = true;
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(neckRegion) = skinColor(channel);
    sourceImage(:, :, channel) = channelData;
end
context = contextForTestImage(sourceImage, faceBox, [], [], neckRegion);
verifyLessThanOrEqual(testCase, mean(context.skinMask(armRegion)), 0.05);
verifyLessThan(testCase, mean(context.skinMask(backgroundRegion)), 0.05);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, context);
difference = mean(abs(double(outputImage) - double(sourceImage)), 3);
verifyLessThanOrEqual(testCase, mean(difference(armRegion)), 0.2);
verifyLessThan(testCase, mean(difference(backgroundRegion)), 0.2);
verifyGreaterThan(testCase, mean(difference(neckRegion)), 0.1);
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
context = contextForTestImage(sourceImage, faceBox, [], eyeRegion | mouthRegion);
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
context = contextForTestImage(sourceImage, faceBox, skinRegion);
strengths = [0, 25, 50, 75, 100];
contrast = zeros(size(strengths));
outputAtMaximum = sourceImage;
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), 'whiteningStrength', 0), ...
        faceBox, context);
    outputYCbCr = rgb2ycbcr(outputImage);
    cr = double(outputYCbCr(:, :, 3));
    contrast(index) = mean(cr(spotRegion)) - mean(cr(surrounding));
    if strengths(index) == 100
        outputAtMaximum = outputImage;
    end
end
verifyTrue(testCase, all(diff(contrast(1:4)) < 0));
verifyTrue(testCase, contrast(end) <= contrast(end - 1), ...
    '75--100 档允许色斑继续减弱，但不得回升。');
verifyLessThanOrEqual(testCase, contrast(end), 0.85 * contrast(1));
% 高档应优先去除明显色斑，仍保留可测的正向色差。
verifyGreaterThanOrEqual(testCase, contrast(end), 0.05 * contrast(1));
inputYCbCr = rgb2ycbcr(sourceImage);
outputYCbCr = rgb2ycbcr(outputAtMaximum);
chromaChange = abs(double(outputYCbCr(:, :, 3)) - double(inputYCbCr(:, :, 3)));
spotChange = mean(chromaChange(spotRegion));
surroundingChange = mean(chromaChange(surrounding));
verifyLessThan(testCase, surroundingChange, .75 * spotChange);
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

function testPolicyEvidencePublishesValidContinuousFields(testCase)
%TESTPOLICYEVIDENCEPUBLISHESVALIDCONTINUOUSFIELDS policy evidence 层必须
%   逐字段满足 V4 evidence 规范：HxW double、实数、有限、[0,1]，
%   且来源/版本元数据挂在 diagnostics 层而非 evidence 层内部。
[sourceImage, faceBox, parsing] = evidencePortraitFixture();
context = prepareBeautyContext(sourceImage, faceBox, parsing, ...
    emptyBodyParsing(size(sourceImage, [1 2])));
verifyTrue(testCase, isfield(context, 'evidence'));
evidence = context.evidence;
verifyTrue(testCase, isstruct(evidence) && isscalar(evidence));
expectedFields = {'periocular'; 'nostril'; 'noseStructure'; 'lip'; ...
    'edgeDetail'; 'structureGradient'; 'darkDetail'; 'earStructure'};
verifyEqual(testCase, fieldnames(evidence), expectedFields);
imageSize = size(sourceImage, [1, 2]);
for index = 1:numel(expectedFields)
    value = evidence.(expectedFields{index});
    verifyTrue(testCase, isnumeric(value) && ~islogical(value), ...
        'evidence 字段必须是连续强度的数值矩阵。');
    verifySize(testCase, value, imageSize);
    verifyTrue(testCase, all(isfinite(value(:))));
    verifyGreaterThanOrEqual(testCase, min(value(:)), 0);
    verifyLessThanOrEqual(testCase, max(value(:)), 1);
end
% 注入的语义区域必须产生非零 evidence，确认字段不是恒空占位。
verifyGreaterThan(testCase, max(evidence.periocular(:)), 0);
verifyGreaterThan(testCase, max(evidence.noseStructure(:)), 0);
verifyGreaterThan(testCase, max(evidence.lip(:)), 0);
verifyGreaterThan(testCase, max(evidence.edgeDetail(:)), 0);
verifyGreaterThan(testCase, max(evidence.structureGradient(:)), 0);
verifyGreaterThan(testCase, max(evidence.darkDetail(:)), 0);

verifyTrue(testCase, isfield(context, 'diagnostics') && ...
    isfield(context.diagnostics, 'policyEvidence'));
metadata = context.diagnostics.policyEvidence;
verifyTrue(testCase, all(isfield(metadata, ...
    {'builder', 'evidenceVersion', 'algorithmVersion', 'sources'})));
verifyEqual(testCase, metadata.algorithmVersion, ...
    beautyPipelineContract().algorithmVersion);
verifyTrue(testCase, all(isfield(metadata.sources, expectedFields)));
end

function testPolicyEvidenceIsDeterministicWithoutRuntimeArtifacts(testCase)
%TESTPOLICYEVIDENCEISDETERMINISTICWITHOUTRUNTIMEARTIFACTS 无循环依赖：
%   evidence 只由图像、语义和静态诊断决定，构建它不要求先运行
%   blemish/frequency；桥接重建与直接构建都复现同一 evidence。
[sourceImage, faceBox, parsing] = evidencePortraitFixture();
prepared = prepareBeautyContext(sourceImage, faceBox, parsing, ...
    emptyBodyParsing(size(sourceImage, [1 2])));

stripped = rmfield(prepared, 'runtimeCache');
stripped = rmfield(stripped, 'evidence');
stripped = rmfield(stripped, 'diagnostics');
rebuilt = rebuildBeautyDerivedMasks(sourceImage, stripped, faceBox);
verifyEqual(testCase, rebuilt.evidence, prepared.evidence, 'AbsTol', 0);
verifyEqual(testCase, rebuilt.diagnostics.policyEvidence, ...
    prepared.diagnostics.policyEvidence);

[~, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    stripped, faceBox);
[directEvidence, directMetadata] = masks.buildBeautyPolicyEvidence( ...
    sourceImage, stripped, faceBox, maskDiagnostics);
verifyEqual(testCase, directEvidence, prepared.evidence, 'AbsTol', 0);
verifyEqual(testCase, directMetadata, ...
    prepared.diagnostics.policyEvidence);
repeatEvidence = masks.buildBeautyPolicyEvidence(sourceImage, ...
    stripped, faceBox, maskDiagnostics);
verifyEqual(testCase, repeatEvidence, directEvidence, 'AbsTol', 0);

% 诊断缺失时必须显式报错，不允许静默退化为不完整 evidence。
verifyError(testCase, @() masks.buildBeautyPolicyEvidence(sourceImage, ...
    stripped, faceBox, struct()), 'masks:InvalidDiagnostics');

% 运行期处理（内部生成 blemish/frequency 产物）不改变 context 上的
% policy evidence，也不改变其可重建性。
params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
beautifyImage(sourceImage, params, faceBox, prepared);
verifyEqual(testCase, prepared.evidence, rebuilt.evidence, 'AbsTol', 0);
end

function testPolicyEvidenceFeedsOnlyStageProtection(testCase)
%TESTPOLICYEVIDENCEFEEDSONLYSTAGEPROTECTION evidence 层的只读边界与
%   policy 消费边界：篡改任何 evidence 字段都不得改变 buildBeautyMasks
%   的 v3.1 产物（evidence 不回写保护 mask）；V4 stage protection 的
%   消费字段随 Ticket 递增——T20 起 periocular/lip、T21 起 nostril/
%   noseStructure、T22 起 earStructure（见
%   masks.buildStageProtectionMasks 的 readEyeLipEvidence/
%   readNoseBands/readEarBands）——篡改这些字段时输出经 policy 通道
%   变化（正控制），篡改其余字段（edgeDetail/structureGradient/
%   darkDetail）时端到端输出逐位不变（T06 边界保持）；且各情形下 hard
%   identity 区域 RGB 都与源图逐位相等（hard 来自未被篡改的
%   beautyMasks 产物）。
[sourceImage, faceBox, parsing] = evidencePortraitFixture();
prepared = prepareBeautyContext(sourceImage, faceBox, parsing, ...
    emptyBodyParsing(size(sourceImage, [1 2])));
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);
cleanBareContext = rmfield(prepared, 'runtimeCache');
cleanOutput = beautifyImage(sourceImage, params, faceBox, ...
    cleanBareContext);

regeneratedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'runtimeCache'};
tampered = prepared;
evidenceNames = fieldnames(tampered.evidence);
for index = 1:numel(evidenceNames)
    tampered.evidence.(evidenceNames{index}) = ...
        ones(size(sourceImage, [1, 2]));
end
cleanMasksInput = rmfield(prepared, ...
    regeneratedNames(isfield(prepared, regeneratedNames)));
tamperedMasksInput = rmfield(tampered, ...
    regeneratedNames(isfield(tampered, regeneratedNames)));
cleanMasks = masks.buildBeautyMasks(sourceImage, cleanMasksInput, faceBox);
tamperedMasks = masks.buildBeautyMasks(sourceImage, tamperedMasksInput, ...
    faceBox);
maskNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'hardProtectionMask', 'protectionMask'};
for index = 1:numel(maskNames)
    verifyEqual(testCase, tamperedMasks.(maskNames{index}), ...
        cleanMasks.(maskNames{index}), 'AbsTol', 0);
end

% 只篡改 stage protection 不消费的三个 evidence 字段：输出逐位不变。
%   T21 起 nostril/noseStructure 已被 policyTexture（Fine 侧 .95）与
%   smoothingMid/repairMid（.90/.85）、baseLuminance（.80）、whitening
%   （.85）消费；T22 起 earStructure 已被 policyTexture 与
%   smoothingMid/repairMid/baseLuminance 消费——三者均不得再列入本
%   清单（篡改它们必然改变输出，旧清单因此过期）。
%   剩余字段 edgeDetail/structureGradient/darkDetail 未被任何 consumer
%   读取：全仓 grep 显示它们只由 masks.buildBeautyPolicyEvidence 生产，
%   仅在**构建期**作为 earStructure 的输入被使用，构建完成后作为
%   evidence 字段不再进入任何 stage（buildStageProtectionMasks 只读
%   periocular/lip/nostril/noseStructure/earStructure）。本断言通过即
%   为实测确认。
nonConsumedNames = {'edgeDetail', 'structureGradient', 'darkDetail'};
nonConsumedTampered = prepared;
for index = 1:numel(nonConsumedNames)
    nonConsumedTampered.evidence.(nonConsumedNames{index}) = ...
        ones(size(sourceImage, [1, 2]));
end
nonConsumedBare = rmfield(nonConsumedTampered, ...
    regeneratedNames(isfield(nonConsumedTampered, regeneratedNames)));
nonConsumedOutput = beautifyImage(sourceImage, params, faceBox, ...
    nonConsumedBare);
verifyEqual(testCase, nonConsumedOutput, cleanOutput, ...
    'stage protection 不消费的 evidence 字段不得影响输出。');

% 篡改 periocular/lip（T20 policy 消费字段）：输出经 policy 通道变化，
% hard identity 区域仍与源图逐位相等。
tamperedOutput = beautifyImage(sourceImage, params, faceBox, ...
    rmfield(tampered, 'runtimeCache'));
verifyNotEqual(testCase, tamperedOutput, cleanOutput, ...
    'T20 stage protection 必须消费 periocular/lip evidence。');
[~, cleanDiagnostics] = beautifyImage(sourceImage, params, faceBox, ...
    cleanBareContext);
hard = cleanDiagnostics.beautyMasks.hardProtectionMask >= .999;
hardRgb = repmat(hard, [1, 1, 3]);
verifyTrue(testCase, nnz(hard) > 0, 'fixture 必须产生非空 hard 区域。');
verifyEqual(testCase, tamperedOutput(hardRgb), sourceImage(hardRgb), ...
    'hard identity 区域 RGB 不得因 evidence 篡改而改变。');
end

function testEyeLipPolicyBandsFollowEvidenceContract(testCase)
%TESTEYLIPPOLICYBANDSFOLLOWEVIDENCECONTRACT T20 eye/lip 三带分级保护的
%   受控 contract 断言（直接调用 buildStageProtectionMasks，屏蔽几何
%   噪声）：
%     identity core —— hard 字段与输入 hardProtectionMask 逐位相等，
%       不新增任何 hard 像素；
%     soft detail band —— evidence=1 的非 hard 像素抬升到固定档位
%       smoothingFine/repairFine/baseLuminance=.95、smoothingMid=.90、
%       whitening=.85、tone=.90（仅唇侧；.95 取检测细节保护区间
%       .92--.99 中点，.90/.85 与检测细节档位对齐，见 builder 头注）；
%     skin transition band —— 仅封顶 texture 通道：
%       smoothingFine <= 1-.55*transitionBand（legacy texture=1 的满
%       保护环带在 evidence=.30 处重新打开到 .5776 的处理量）；
%     证据零带（partial V4 / 缺省输入）时与 T07 legacy 折叠逐位相等；
%     非法 evidence（尺寸/取值/类型）fail-fast。
    [fixture, evidence, hardIdentity] = eyeLipPolicyUnitFixture();
    legacyZero = masks.buildStageProtectionMasks(fixture.masksZero);
    policyZero = masks.buildStageProtectionMasks(fixture.masksZero, evidence);
    legacyFull = masks.buildStageProtectionMasks(fixture.masksFull);
    policyFull = masks.buildStageProtectionMasks(fixture.masksFull, evidence);

    % identity core：hard 原样拷贝，不新增任何 hard 像素。
    verifyEqual(testCase, policyZero.hard, hardIdentity, 'AbsTol', 0);
    verifyEqual(testCase, policyFull.hard, legacyFull.hard, 'AbsTol', 0);
    detailBand = max(smoothStep(evidence.periocular, .50, .78), ...
        smoothStep(evidence.lip, .55, .85));
    softDetailBand = detailBand > .5 & hardIdentity == 0;
    verifyTrue(testCase, nnz(softDetailBand) > 0 && nnz(hardIdentity) > 0, ...
        'fixture 必须同时包含非 hard 的 detail band 与 hard identity。');

    % soft detail band：非 hard 的 evidence=1 像素抬升到固定档位。
    eyePoint = fixture.eyeDetailPoint;
    verifyEqual(testCase, policyZero.smoothingFine(eyePoint(1), eyePoint(2)), ...
        .95, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.smoothingMid(eyePoint(1), eyePoint(2)), ...
        .90, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.repairFine(eyePoint(1), eyePoint(2)), ...
        .95, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.repairMid(eyePoint(1), eyePoint(2)), ...
        .95, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.baseLuminance(eyePoint(1), eyePoint(2)), ...
        .95, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.whitening(eyePoint(1), eyePoint(2)), ...
        .85, 'AbsTol', 1e-12);
    verifyEqual(testCase, policyZero.tone(eyePoint(1), eyePoint(2)), 0, ...
        'AbsTol', 1e-12, '眼周色度无 identity 语义，tone 不得被眼带抬升。');
    lipPoint = fixture.lipDetailPoint;
    verifyEqual(testCase, policyZero.tone(lipPoint(1), lipPoint(2)), .90, ...
        'AbsTol', 1e-12, '唇色是 identity 色度，唇 detail band 必须进入 tone 保护。');

    % skin transition band：只封顶 texture 通道，打开满保护环带。
    transitionPoint = fixture.transitionPoint;
    t = min(max((.30 - .08) / (.40 - .08), 0), 1);
    expectedCap = 1 - .55 * (t .^ 2 * (3 - 2 * t));
    verifyEqual(testCase, ...
        policyFull.smoothingFine(transitionPoint(1), transitionPoint(2)), ...
        expectedCap, 'AbsTol', 1e-12);
    verifyEqual(testCase, ...
        legacyFull.smoothingFine(transitionPoint(1), transitionPoint(2)), 1, ...
        'AbsTol', 1e-12, 'fixture 须以 texture=1 复现 legacy 满保护环带。');
    transitionBand = max(smoothStep(evidence.periocular, .08, .40), ...
        smoothStep(evidence.lip, .12, .50)) .* (1 - detailBand);
    activeTransition = transitionBand > 0;
    verifyTrue(testCase, ...
        all(policyFull.smoothingFine(activeTransition) <= ...
        1 - .55 * transitionBand(activeTransition) + 1e-12), ...
        'transition band 内 Fine 保护不得超过 1-.55*transitionBand 封顶。');

    % 证据零带：与 T07 legacy 折叠逐位相等（两组 mask 产物都验证）。
    zeroEvidence = struct('periocular', zeros(fixture.imageSize), ...
        'lip', zeros(fixture.imageSize));
    fieldNames = fieldnames(legacyZero);
    for fieldIndex = 1:numel(fieldNames)
        fieldName = fieldNames{fieldIndex};
        zeroPolicyZero = masks.buildStageProtectionMasks( ...
            fixture.masksZero, zeroEvidence);
        zeroPolicyFull = masks.buildStageProtectionMasks( ...
            fixture.masksFull, zeroEvidence);
        verifyEqual(testCase, zeroPolicyZero.(fieldName), ...
            legacyZero.(fieldName), 'AbsTol', 0);
        verifyEqual(testCase, zeroPolicyFull.(fieldName), ...
            legacyFull.(fieldName), 'AbsTol', 0);
        singleArgPolicy = masks.buildStageProtectionMasks(fixture.masksZero);
        verifyEqual(testCase, singleArgPolicy.(fieldName), ...
            legacyZero.(fieldName), 'AbsTol', 0);
    end

    % 带外（evidence 全零像素）逐位还原 legacy。
    outside = evidence.periocular == 0 & evidence.lip == 0;
    for fieldIndex = 1:numel(fieldNames)
        fieldName = fieldNames{fieldIndex};
        verifyEqual(testCase, ...
            policyFull.(fieldName)(outside), legacyFull.(fieldName)(outside), ...
            'AbsTol', 0, 'evidence 带外的 stage 字段必须逐位等于 legacy。');
    end

    % 非法 evidence fail-fast，不静默修正。
    badSize = evidence;
    badSize.periocular = evidence.periocular(1:10, 1:10);
    verifyError(testCase, @() masks.buildStageProtectionMasks( ...
        fixture.masksZero, badSize), 'masks:InvalidEvidence');
    badRange = evidence;
    badRange.lip = evidence.lip * 2;
    verifyError(testCase, @() masks.buildStageProtectionMasks( ...
        fixture.masksZero, badRange), 'masks:InvalidEvidence');
    badNaN = evidence;
    badNaN.periocular = evidence.periocular;
    badNaN.periocular(2, 2) = NaN;
    verifyError(testCase, @() masks.buildStageProtectionMasks( ...
        fixture.masksZero, badNaN), 'masks:InvalidEvidence');
end

function testEyeLipPolicyWiringPreservesIdentityAndProcessability(testCase)
%TESTEYLIPPOLICYWIRINGPRESERVESIDENTITYANDPROCESSABILITY T20 生产链路
%   （beautifyImage 经 bridge evidence 转发）端到端断言：
%     identity core 进 hard、soft band 不新增 hard、hard RGB 精确回源；
%     带外（背景/普通脸颊）alphaMap 逐位等于 legacy，背景输出逐位等于
%     源图；detail band 内 Fine/Mid 处理量下降（结构保留），transition
%     band 处理量不低于 legacy（无未处理环带）；美白-only 输出带外
%     （regionBandWhitening == 0）与 legacy 逐位一致，带内差异由
%     regionBandWhitening 单字段承载（T30 激活）；cached 与 uncached
%     输出逐位一致。
[sourceImage, faceBox, parsing] = evidencePortraitFixture();
context = prepareBeautyContext(sourceImage, faceBox, parsing, ...
    emptyBodyParsing(size(sourceImage, [1, 2])));
bareContext = rmfield(context, 'runtimeCache');
legacyContext = rmfield(bareContext, 'evidence');
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);

[policyOut, policyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, bareContext);
[legacyOut, legacyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, legacyContext);

[beautyMasks, ~] = masks.buildBeautyMasks(sourceImage, bareContext, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, bareContext.evidence);
legacyProtection = masks.buildStageProtectionMasks(beautyMasks);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, legacyProtection.hard), ...
    'T20 不得改变 hard identity。');
verifyTrue(testCase, nnz(hardMask) > 0, ...
    '眼/唇语义必须产生非空 hard identity 区域。');

[xGrid, yGrid] = meshgrid(1:size(sourceImage, 2), 1:size(sourceImage, 1));
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
radialDistance = ((xGrid - centerX) / (faceBox(3) / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceBox(4) / 2)) .^ 2;
eyeCoreRow = round(centerY - 30);
eyeCoreCol = round(centerX - 38);
lipCoreRow = round(centerY + 52);
lipCoreCol = round(centerX);
verifyEqual(testCase, hardMask(eyeCoreRow, eyeCoreCol), true, ...
    '眼球语义核心必须位于 hard identity。');
verifyEqual(testCase, hardMask(lipCoreRow, lipCoreCol), true, ...
    '唇部语义核心必须位于 hard identity。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    sourceImage(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

eyeField = bareContext.evidence.periocular;
lipField = bareContext.evidence.lip;
detailBand = max(smoothStep(eyeField, .50, .78), ...
    smoothStep(lipField, .55, .85));
transitionBand = max(smoothStep(eyeField, .08, .40), ...
    smoothStep(lipField, .12, .50)) .* (1 - detailBand);
softBand = detailBand > .5 & ~hardMask;
transitionSoft = transitionBand > .5 & ~hardMask;
outside = eyeField == 0 & lipField == 0;
verifyTrue(testCase, nnz(softBand) > 0 && nnz(transitionSoft) > 0, ...
    'fixture 必须产生非空 soft detail band 与 transition band。');

% 带外（背景与普通脸颊）逐位不变：policy 层与最终 alphaMap 双重守卫。
alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaLegacy = legacyDiagnostics.smoothing.alphaMap;
verifyEqual(testCase, protection.smoothingFine(outside), ...
    legacyProtection.smoothingFine(outside), 'AbsTol', 0, ...
    'evidence 带外的 smoothingFine 必须逐位等于 legacy。');
verifyEqual(testCase, alphaPolicy(outside), alphaLegacy(outside), ...
    'AbsTol', 0, 'evidence 带外的 Fine alphaMap 必须逐位等于 legacy。');
background = radialDistance >= 1.15;
verifyEqual(testCase, policyOut(repmat(background, [1, 1, 3])), ...
    sourceImage(repmat(background, [1, 1, 3])), ...
    '背景区域输出必须与源图逐位相等。');

% detail band：Fine/Mid 处理量受控下降（保护抬升；探针实测 Fine 比值
%   ≈.50、Mid 比值≈.07，阈值留有几何余量且远低于 1）。
verifyLessThanOrEqual(testCase, mean(alphaPolicy(softBand)), ...
    .75 * mean(alphaLegacy(softBand)), ...
    'detail band 的 Fine 处理量必须明显低于 legacy（identity 细节保留）。');
verifyLessThanOrEqual(testCase, ...
    mean(policyDiagnostics.smoothing.midAlphaMap(softBand)), ...
    .40 * mean(legacyDiagnostics.smoothing.midAlphaMap(softBand)), ...
    'detail band 的 Mid 处理量必须明显低于 legacy（睫毛/唇缘中频细节此前被全强度磨除）。');

% transition band：处理量不低于 legacy（皮肤过渡带不得被冻结成环带）。
verifyGreaterThanOrEqual(testCase, mean(alphaPolicy(transitionSoft)), ...
    mean(alphaLegacy(transitionSoft)) - 1e-12, ...
    'transition band 的 Fine 处理量不得低于 legacy（眼周皮肤仍可处理）。');

% 结构保留：detail band 高频能量不低于 legacy。
graySource = im2double(rgb2gray(sourceImage));
grayPolicy = im2double(rgb2gray(policyOut));
grayLegacy = im2double(rgb2gray(legacyOut));
faceScale = min(faceBox(3:4));
sigma = max(1, .008 * faceScale);
hpPolicy = grayPolicy - imgaussfilt(grayPolicy, sigma, 'Padding', 'replicate');
hpLegacy = grayLegacy - imgaussfilt(grayLegacy, sigma, 'Padding', 'replicate');
verifyGreaterThanOrEqual(testCase, mean(abs(hpPolicy(softBand))), ...
    mean(abs(hpLegacy(softBand))) - 1e-12, ...
    'detail band 的高频细节能量不得低于 legacy。');

% 美白-only：T30 激活后 whitening consumer 的算术门控为
%   contract.featureGate = (1 - whitening) .* (1 - protection.regionBandWhitening)。
%   T30 激活前该断言为 bit-exact（快照不进入美白算术）；激活后改为
%   "带外 bit-exact + 带内单字段归因"：
%     * 带外（regionBandWhitening == 0）逐位等于 legacy；
%     * 带内确有可观测的假白退让差异；
%     * 差异只由 regionBandWhitening 承载——置零该字段的证据来源
%       （periocular/lip/nostril）后逐位回到 legacy；置零其他带来源
%       （noseStructure/earStructure）则美白-only 输出不变，仍不等于
%       legacy。
whiteningParams = struct('smoothingStrength', 0, 'whiteningStrength', 100);
whiteningPolicyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    bareContext);
whiteningLegacyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    legacyContext);
outsideWhitening = protection.regionBandWhitening == 0;
whiteningDiff = mean(abs(double(whiteningPolicyOut) - ...
    double(whiteningLegacyOut)), 3);
verifyEqual(testCase, nnz(whiteningDiff(outsideWhitening) > 0), 0, ...
    '带外（regionBandWhitening == 0）美白-only 输出必须与 legacy 逐位一致。');
verifyGreaterThan(testCase, nnz(whiteningDiff(~outsideWhitening) > 0), 0, ...
    'regionBandWhitening 带内必须出现可观测的美白退让差异。');
noWhiteningBandContext = bareContext;
noWhiteningBandContext.evidence = zeroEvidenceFields( ...
    noWhiteningBandContext.evidence, {'periocular', 'lip', 'nostril'}, ...
    size(sourceImage, 1:2));
verifyEqual(testCase, beautifyImage(sourceImage, whiteningParams, faceBox, ...
    noWhiteningBandContext), whiteningLegacyOut, ...
    '置零 regionBandWhitening 后美白-only 输出必须逐位回到 legacy。');
noStructureBandContext = bareContext;
noStructureBandContext.evidence = zeroEvidenceFields( ...
    noStructureBandContext.evidence, {'noseStructure', 'earStructure'}, ...
    size(sourceImage, 1:2));
verifyNotEqual(testCase, beautifyImage(sourceImage, whiteningParams, ...
    faceBox, noStructureBandContext), whiteningLegacyOut, ...
    '置零其他带（regionBandBase/Mid 来源）不得抹平美白-only 差异。');
verifyGreaterThanOrEqual(testCase, ...
    min(protection.whitening(softBand)), ...
    .85 * min(detailBand(softBand)) - 1e-12, ...
    'whitening 字段必须在 detail band 内携带 >= .85*detailBand 的假白光晕退让。');

% cached 与 uncached 输出逐位一致（evidence 经缓存指纹同源转发）。
[cachedOut, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOut, policyOut, ...
    'cached 路径必须与 uncached 逐位一致。');
end

function [fixture, evidence, hardIdentity] = eyeLipPolicyUnitFixture
%EYLIPPOLICYUNITFIXTURE 构造受控的 Beauty Masks 与 eye/lip evidence：
%   eye/lip 硬核（rows 18--23）周围一圈 evidence=1 的 soft detail band，
%   再外圈 evidence=.30 的 transition band，其余像素 evidence=0。
imageSize = [40, 60];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
eyeCore = xGrid >= 8 & xGrid <= 20 & yGrid >= 18 & yGrid <= 23;
lipCore = xGrid >= 38 & xGrid <= 50 & yGrid >= 18 & yGrid <= 23;
hardIdentity = double(eyeCore | lipCore);
eyeSoftRing = (xGrid >= 7 & xGrid <= 21 & yGrid >= 17 & yGrid <= 24) & ~eyeCore;
lipSoftRing = (xGrid >= 37 & xGrid <= 51 & yGrid >= 17 & yGrid <= 24) & ~lipCore;
eyeOuterRing = (xGrid >= 5 & xGrid <= 23 & yGrid >= 15 & yGrid <= 26) & ...
    ~(eyeCore | eyeSoftRing);
lipOuterRing = (xGrid >= 35 & xGrid <= 53 & yGrid >= 15 & yGrid <= 26) & ...
    ~(lipCore | lipSoftRing);
eyeField = zeros(imageSize);
eyeField(eyeSoftRing) = 1;
eyeField(eyeOuterRing) = .30;
lipField = zeros(imageSize);
lipField(lipSoftRing) = 1;
lipField(lipOuterRing) = .30;
lipField(lipCore) = 1;
evidence = struct('periocular', eyeField, 'lip', lipField);
fixture = struct( ...
    'imageSize', imageSize, ...
    'masksZero', unitMasks(zeros(imageSize), hardIdentity, imageSize), ...
    'masksFull', unitMasks(ones(imageSize), hardIdentity, imageSize), ...
    'eyeDetailPoint', [17, 14], ...
    'lipDetailPoint', [24, 44], ...
    'transitionPoint', [16, 14]);
end

function masksStruct = unitMasks(texture, hard, imageSize)
%UNITMASKS 构建只含 buildStageProtectionMasks 必需字段的 mask 产物。
masksStruct = struct( ...
    'textureProtectionMask', texture, ...
    'structureProtectionMask', zeros(imageSize), ...
    'chromaProtectionMask', zeros(imageSize), ...
    'whiteningProtectionMask', zeros(imageSize), ...
    'hardProtectionMask', hard, ...
    'noseMask', zeros(imageSize), ...
    'faceSkinMask', zeros(imageSize));
end

function evidence = zeroEvidenceFields(evidence, names, imageSize)
%ZEROEVIDENCEFIELDS 把 evidence 中指定语义字段清零（T30 单字段归因用）。
%   buildBeautyMasks 不读 evidence，故该消融只影响 policy-time 的
%   regionBand* 带，不改变 processability/semantic 层与任何 stage 快照。
for index = 1:numel(names)
    if isfield(evidence, names{index})
        evidence.(names{index}) = zeros(imageSize);
    end
end
end

function value = smoothStep(inputValue, low, high)
%SMOOTHSTEP 复现生产 smoothstep 曲线（t^2*(3-2t)）。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
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

function testInjectedParsingProducesV4CanonicalContext(testCase)
%TESTINJECTEDPARSINGPRODUCESV4CANONICALCONTEXT 注入语义经生产链构建后
%   得到 V4 canonical Context（T08 有意切换点：schemaVersion 从 '3.1'
%   升级为 '4.0'，compat alias 保留），buildBeautyMasks 的 hard 保护
%   仍由注入语义驱动。
image = uint8(ones(40, 40, 3) * 128);
parsing = syntheticParsingForContext([40 40]);
parsing.regions.skin(10:30, 10:30) = 1;
parsing.regionConfidence.skin(10:30, 10:30) = 1;
parsing.regions.hair(10:13, 10:30) = 1;
parsing.regionConfidence.hair(10:13, 10:30) = 1;
context = prepareBeautyContext(image, [5 5 30 30], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
verifyEqual(testCase, context.schemaVersion, '4.0');
verifyEqual(testCase, numel(fieldnames(context.regions)), 19);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, [5 5 30 30]);
verifyEqual(testCase, beautyMasks.hardProtectionMask(12, 20), 1);
end

function testSoftParsingKeepsBoundaryAndEarCoverage(testCase)
image = uint8(ones(60, 80, 3) * 128);
parsing = syntheticParsingForContext([60 80]);
parsing.regions.skin(20:40, 20:60) = .4;
parsing.regionConfidence.skin(20:40, 20:60) = .4;
parsing.regions.leftEar(26:36, 12:18) = .85;
parsing.regionConfidence.leftEar(26:36, 12:18) = .85;
context = prepareBeautyContext(image, [10 10 60 40], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
verifyGreaterThan(testCase, context.faceSkinMask(30, 30), 0);
verifyLessThan(testCase, context.faceSkinMask(30, 30), 1);
verifyGreaterThan(testCase, mean(context.faceSkinMask(28:34, 13:17), 'all'), .5);
end

function testSoftParsingClosesProbabilityHoleContinuously(testCase)
image = uint8(ones(60, 80, 3) * 128);
parsing = syntheticParsingForContext([60 80]);
parsing.regions.skin(20:40, 20:60) = 1;
parsing.regionConfidence.skin(20:40, 20:60) = 1;
parsing.regions.skin(29:31, 39:41) = 0;
parsing.regionConfidence.skin(29:31, 39:41) = 0;
context = prepareBeautyContext(image, [10 10 60 40], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
verifyGreaterThan(testCase, context.faceSkinMask(30, 40), .5);
verifyGreaterThan(testCase, abs(context.faceSkinMask(30, 38) - .35), 1e-12);
verifyLessThanOrEqual(testCase, max(abs(diff(context.faceSkinMask(27:34, 37:43), 1, 2)), [], 'all'), .65);
end

function testFeatureProtectionHasCoreAndGradientBand(testCase)
image = uint8(ones(60, 80, 3) * 128);
parsing = syntheticParsingForContext([60 80]);
parsing.regions.skin(15:45, 20:60) = 1;
parsing.regionConfidence.skin(15:45, 20:60) = 1;
parsing.regions.leftEye(27:31, 35:42) = 1;
parsing.regionConfidence.leftEye(27:31, 35:42) = 1;
context = prepareBeautyContext(image, [10 10 60 40], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, [10 10 60 40]);
verifyEqual(testCase, beautyMasks.hardProtectionMask(29, 38), 1);
verifyGreaterThan(testCase, beautyMasks.textureProtectionMask(29, 34), 0);
verifyLessThan(testCase, beautyMasks.textureProtectionMask(29, 34), 1);
end

function parsing = syntheticParsingForContext(imageSize)
names = faceParsingClassNames();
regions = struct(); confidences = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidences.(names{index}) = zeros(imageSize);
end
parsing = struct('regions', regions, 'regionConfidence', confidences);
end

function [sourceImage, faceBox, parsing] = evidencePortraitFixture
%EVIDENCEPORTRAITFIXTURE 带眼/鼻/唇语义的合成人像，供 policy evidence
%   测试使用；区域公式与测试文件内其他人像夹具保持一致风格。
[sourceImage, faceBox, skinRegion, ~] = syntheticPortrait(240, 320);
[xGrid, yGrid] = meshgrid(1:size(sourceImage, 2), 1:size(sourceImage, 1));
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
noseRegion = ((xGrid - centerX) / 14) .^ 2 + ...
    ((yGrid - (centerY + 10)) / 34) .^ 2 <= 1;
leftEyeRegion = ((xGrid - (centerX - 38)) / 13) .^ 2 + ...
    ((yGrid - (centerY - 30)) / 6) .^ 2 <= 1;
rightEyeRegion = ((xGrid - (centerX + 38)) / 13) .^ 2 + ...
    ((yGrid - (centerY - 30)) / 6) .^ 2 <= 1;
lipRegion = ((xGrid - centerX) / 20) .^ 2 + ...
    ((yGrid - (centerY + 52)) / 6) .^ 2 <= 1;
parsing = syntheticParsingForContext(size(sourceImage, [1 2]));
parsing.regions.skin = double(skinRegion);
parsing.regionConfidence.skin = double(skinRegion);
parsing.regions.nose = double(noseRegion & skinRegion);
parsing.regionConfidence.nose = double(noseRegion & skinRegion);
parsing.regions.leftEye = double(leftEyeRegion & skinRegion);
parsing.regionConfidence.leftEye = double(leftEyeRegion & skinRegion);
parsing.regions.rightEye = double(rightEyeRegion & skinRegion);
parsing.regionConfidence.rightEye = double(rightEyeRegion & skinRegion);
parsing.regions.upperLip = double(lipRegion & skinRegion);
parsing.regionConfidence.upperLip = double(lipRegion & skinRegion);
parsing.regions.lowerLip = double(lipRegion & skinRegion);
parsing.regionConfidence.lowerLip = double(lipRegion & skinRegion);
end

function context = contextForTestImage(image, faceBox, skinMask, hardMask, neckMask)
parsing = syntheticParsingForContext(size(image, [1 2]));
if nargin < 3 || isempty(skinMask)
    skinMask = false(size(image, [1 2]));
    x1 = max(1, floor(faceBox(1)));
    y1 = max(1, floor(faceBox(2)));
    x2 = min(size(image, 2), ceil(faceBox(1) + faceBox(3) - 1));
    y2 = min(size(image, 1), ceil(faceBox(2) + faceBox(4) - 1));
    skinMask(y1:y2, x1:x2) = true;
end
if nargin < 4 || isempty(hardMask), hardMask = false(size(skinMask)); end
if nargin < 5 || isempty(neckMask), neckMask = false(size(skinMask)); end
parsing.regions.skin = double(skinMask);
parsing.regionConfidence.skin = double(skinMask);
parsing.regions.hair = double(hardMask);
parsing.regionConfidence.hair = double(hardMask);
parsing.regions.neck = double(neckMask);
parsing.regionConfidence.neck = double(neckMask);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, [1 2])));
end

function options = emptyBodyParsing(imageSize)
options = struct('probabilities', zeros([imageSize, 20], 'single'));
end
