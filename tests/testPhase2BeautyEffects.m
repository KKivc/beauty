function tests = testPhase2BeautyEffects
%TESTPHASE2BEAUTYEFFECTS 验证高档磨皮、美白和一键推荐行为。

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testBaselineWeightSmoothsOrdinarySkin(testCase)
imageSize = [96, 96];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 16 * mod(xGrid + yGrid, 2) - 8;
sourceImage = uint8(repmat(140 + texture, [1, 1, 3]));
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = simpleContext(imageSize, faceBox, true(imageSize), true(imageSize));

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputAmplitude = checkerAmplitude(sourceImage);
outputAmplitude = checkerAmplitude(outputImage);

verifyLessThan(testCase, outputAmplitude, 0.90 * inputAmplitude);
verifyGreaterThanOrEqual(testCase, outputAmplitude, 0.55 * inputAmplitude);
end

function testMaximumSmoothingRetentionBounds(testCase)
imageSize = [160, 160];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
fineTexture = 10 * mod(xGrid + yGrid, 2) - 5;
mediumTexture = 12 * sin(2 * pi * xGrid / 28);
sourceGray = uint8(round(135 + fineTexture + mediumTexture));
sourceImage = repmat(sourceGray, [1, 1, 3]);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = simpleContext(imageSize, faceBox, true(imageSize), true(imageSize));

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputGray = double(rgb2gray(sourceImage));
outputGray = double(rgb2gray(outputImage));
inputFine = mean(abs(inputGray(:, 2:end) - inputGray(:, 1:end - 1)), 'all');
outputFine = mean(abs(outputGray(:, 2:end) - outputGray(:, 1:end - 1)), 'all');
inputMedium = std(mean(inputGray, 1));
outputMedium = std(mean(outputGray, 1));

verifyGreaterThanOrEqual(testCase, outputFine, 0.55 * inputFine);
verifyGreaterThanOrEqual(testCase, outputMedium, 0.35 * inputMedium);
end

function testWhiteningNeedDependsOnSkinMedian(testCase)
imageSize = [80, 100];
faceBox = [11, 11, 80, 60];
skinMask = false(imageSize);
skinMask(15:66, 20:81) = true;
context = simpleContext(imageSize, faceBox, skinMask, skinMask);
darkImage = uint8(105 * ones([imageSize, 3]));
brightImage = uint8(205 * ones([imageSize, 3]));
params = struct('smoothingStrength', 0, 'whiteningStrength', 100);

darkOutput = beautifyImage(darkImage, params, faceBox, context);
brightOutput = beautifyImage(brightImage, params, faceBox, context);
darkIncrease = mean(double(darkOutput(:, :, 1)) - double(darkImage(:, :, 1)), ...
    'all');
brightIncrease = mean(double(brightOutput(:, :, 1)) - ...
    double(brightImage(:, :, 1)), 'all');

verifyGreaterThan(testCase, darkIncrease, 2 * brightIncrease);
verifyGreaterThan(testCase, brightIncrease, 0);
end

function testFaceAndBodySkinUseWeakWhiteningOutsideFace(testCase)
imageSize = [120, 140];
faceBox = [46, 12, 48, 48];
faceRegion = false(imageSize);
faceRegion(20:51, 54:85) = true;
bodyRegion = false(imageSize);
bodyRegion(78:109, 18:49) = true;
skinMask = faceRegion | bodyRegion;
sourceImage = uint8(125 * ones([imageSize, 3]));
context = simpleContext(imageSize, faceBox, skinMask, faceRegion);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 70), faceBox, context);
difference = mean(double(outputImage) - double(sourceImage), 3);

verifyGreaterThan(testCase, mean(difference(faceRegion)), 0);
verifyGreaterThan(testCase, mean(difference(bodyRegion)), 0);
verifyLessThanOrEqual(testCase, mean(difference(bodyRegion)), ...
    .80 * mean(difference(faceRegion)));
end

function testRecommendationUsesSkinAndStaysBounded(testCase)
imageSize = [120, 160];
faceBox = [56, 12, 48, 48];
faceSkin = false(imageSize);
faceSkin(20:51, 64:95) = true;
bodySkin = false(imageSize);
bodySkin(70:112, 20:140) = true;
skinMask = faceSkin | bodySkin;
sourceImage = uint8(225 * ones([imageSize, 3]));
for channel = 1:3
    channelData = sourceImage(:, :, channel);
    channelData(bodySkin) = uint8(80);
    sourceImage(:, :, channel) = channelData;
end
context = simpleContext(imageSize, faceBox, skinMask, faceSkin);

params = recommendBeautyParams(sourceImage, faceBox, context);
verifyGreaterThanOrEqual(testCase, params.smoothingStrength, 45);
verifyLessThanOrEqual(testCase, params.smoothingStrength, 75);
verifyGreaterThanOrEqual(testCase, params.whiteningStrength, 5);
verifyLessThanOrEqual(testCase, params.whiteningStrength, 25);
% 脸部已接近高光时，暗色身体区域不能把一键美白推到高档。
verifyEqual(testCase, params.whiteningStrength, 5, 'AbsTol', 1e-12);

noSkinContext = simpleContext(imageSize, faceBox, false(imageSize), ...
    false(imageSize));
darkBackground = uint8(30 * ones([imageSize, 3]));
brightBackground = uint8(240 * ones([imageSize, 3]));
darkParams = recommendBeautyParams(darkBackground, faceBox, noSkinContext);
brightParams = recommendBeautyParams(brightBackground, faceBox, noSkinContext);
verifyEqual(testCase, darkParams, brightParams);
verifyEqual(testCase, darkParams.smoothingStrength, 45, 'AbsTol', 1e-12);
verifyEqual(testCase, darkParams.whiteningStrength, 5, 'AbsTol', 1e-12);
end

function testRecommendationUsesLocalAnomalyAreaAndIntensity(testCase)
imageSize = [128, 128];
faceBox = [1, 1, imageSize(2), imageSize(1)];
skinMask = true(imageSize);
context = simpleContext(imageSize, faceBox, skinMask, skinMask);
baseImage = uint8(170 * ones([imageSize, 3]));

lowAnomalyImage = baseImage;
lowAnomalyImage(48:8:80, 48:8:80, :) = uint8(70);
highAnomalyImage = baseImage;
highAnomalyImage(32:4:96, 32:4:96, :) = uint8(55);

lowParams = recommendBeautyParams(lowAnomalyImage, faceBox, context);
highParams = recommendBeautyParams(highAnomalyImage, faceBox, context);

verifyGreaterThan(testCase, highParams.smoothingStrength, ...
    lowParams.smoothingStrength + 5);
verifyGreaterThanOrEqual(testCase, highParams.smoothingStrength, 65);
verifyLessThanOrEqual(testCase, highParams.smoothingStrength, 75);
verifyGreaterThanOrEqual(testCase, lowParams.smoothingStrength, 45);
verifyLessThanOrEqual(testCase, lowParams.smoothingStrength, 75);
end

function testRecommendationIgnoresProtectedAnomalies(testCase)
imageSize = [96, 96];
faceBox = [1, 1, imageSize(2), imageSize(1)];
skinMask = true(imageSize);
protectedRegion = false(imageSize);
protectedRegion(30:67, 30:67) = true;
sourceImage = uint8(170 * ones([imageSize, 3]));
sourceImage(30:2:67, 30:2:67, :) = uint8(55);

unprotectedContext = simpleContext(imageSize, faceBox, skinMask, ...
    skinMask);
protectedContext = simpleContext(imageSize, faceBox, skinMask, skinMask, ...
    double(protectedRegion));
unprotectedParams = recommendBeautyParams(sourceImage, faceBox, ...
    unprotectedContext);
protectedParams = recommendBeautyParams(sourceImage, faceBox, ...
    protectedContext);

verifyGreaterThan(testCase, unprotectedParams.smoothingStrength, ...
    protectedParams.smoothingStrength + 5);
verifyGreaterThanOrEqual(testCase, protectedParams.smoothingStrength, 45);
verifyLessThanOrEqual(testCase, protectedParams.smoothingStrength, 55);
end

function testRecommendationKeepsModerateSkinWhiteningConservative(testCase)
imageSize = [80, 80];
faceBox = [1, 1, imageSize(2), imageSize(1)];
skinMask = true(imageSize);
context = simpleContext(imageSize, faceBox, skinMask, skinMask);
moderateImage = uint8(170 * ones([imageSize, 3]));
params = recommendBeautyParams(moderateImage, faceBox, context);

verifyGreaterThanOrEqual(testCase, params.whiteningStrength, 8);
verifyLessThanOrEqual(testCase, params.whiteningStrength, 20);
verifyEqual(testCase, params.smoothingStrength, 45, 'AbsTol', 1e-12);
end

function amplitude = checkerAmplitude(imageData)
grayImage = double(rgb2gray(imageData));
oddPixels = grayImage(1:2:end, 1:2:end);
evenPixels = grayImage(1:2:end, 2:2:end);
amplitude = abs(mean(oddPixels, 'all') - mean(evenPixels, 'all'));
end

function context = simpleContext(imageSize, faceBox, skinMask, faceSkinMask, ...
        protectionMask)
if nargin < 5
    protectionMask = zeros(imageSize);
end
semanticProbabilities = zeros([imageSize, numel(faceParsingClassNames())], ...
    'single');
context = struct( ...
    'skinMask', double(skinMask), ...
    'faceSkinMask', double(faceSkinMask), ...
    'nonFaceSkinMask', max(double(skinMask) - double(faceSkinMask), 0), ...
    'textureProtectionMask', double(protectionMask), ...
    'structureProtectionMask', double(protectionMask), ...
    'toneProtectionMask', double(protectionMask), ...
    'strengthMap', max(double(faceSkinMask), ...
        .55 * max(double(skinMask) - double(faceSkinMask), 0)), ...
    'faceStrengthMap', double(faceSkinMask), ...
    'nonFaceStrengthMap', .55 * max(double(skinMask) - ...
        double(faceSkinMask), 0), ...
    'schemaVersion', '3.0', ...
    'semanticProbabilities', semanticProbabilities, ...
    'semanticConfidence', semanticProbabilities, ...
    'imageSize', [imageSize, 3], ...
    'faceBox', faceBox);
end
