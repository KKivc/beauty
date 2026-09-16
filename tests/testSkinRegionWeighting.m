function tests = testSkinRegionWeighting
%TESTSKINREGIONWEIGHTING 验证脸外皮肤的非线性弱化和独立色调统计。

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testNonFaceSmoothingIsWeakAndNonlinear(testCase)
imageSize = [180, 240];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 14 * sin(2 * pi * xGrid / 5) .* sin(2 * pi * yGrid / 7);
sourceGray = uint8(round(145 + texture));
sourceImage = repmat(sourceGray, [1, 1, 3]);

faceRegion = false(imageSize);
faceRegion(45:125, 95:174) = true;
bodyRegion = false(imageSize);
bodyRegion(45:125, 15:94) = true;
skinMask = faceRegion | bodyRegion;
faceBox = [95, 45, 80, 80];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

strengths = [25, 100];
faceChange = zeros(size(strengths));
bodyChange = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), 'whiteningStrength', 0), ...
        faceBox, context);
    difference = mean(abs(double(outputImage) - double(sourceImage)), 3);
    faceInterior = faceRegion & xGrid >= 108 & xGrid <= 161 & ...
        yGrid >= 58 & yGrid <= 111;
    bodyInterior = bodyRegion & xGrid >= 28 & xGrid <= 81 & ...
        yGrid >= 58 & yGrid <= 111;
    faceChange(index) = mean(difference(faceInterior));
    bodyChange(index) = mean(difference(bodyInterior));
end

verifyGreaterThan(testCase, faceChange(end), .5);
verifyGreaterThan(testCase, bodyChange(end), 0);
verifyLessThanOrEqual(testCase, bodyChange(end), .80 * faceChange(end), ...
    '身体皮肤需要达到参考级均肤，但整体变化仍应弱于脸部。');
verifyLessThan(testCase, bodyChange(1), .15 * faceChange(end) + .1);
end

function testNonFaceWhiteningIsWeakAndUsesOwnTone(testCase)
imageSize = [140, 220];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 7 * sin(2 * pi * xGrid / 9) .* sin(2 * pi * yGrid / 11);
sourceGray = 170 * ones(imageSize);
faceRegion = false(imageSize);
faceRegion(35:105, 95:164) = true;
bodyRegion = false(imageSize);
bodyRegion(35:105, 15:84) = true;
sourceGray(faceRegion) = 120 + texture(faceRegion);
sourceGray(bodyRegion) = 170 + texture(bodyRegion);
sourceImage = repmat(uint8(round(sourceGray)), [1, 1, 3]);
skinMask = faceRegion | bodyRegion;
faceBox = [95, 35, 70, 70];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, context);
difference = mean(double(outputImage) - double(sourceImage), 3);
faceInterior = faceRegion & xGrid >= 106 & xGrid <= 153 & ...
    yGrid >= 46 & yGrid <= 93;
bodyInterior = bodyRegion & xGrid >= 26 & xGrid <= 73 & ...
    yGrid >= 46 & yGrid <= 93;
faceIncrease = mean(difference(faceInterior));
bodyIncrease = mean(difference(bodyInterior));

verifyGreaterThan(testCase, faceIncrease, 0);
verifyGreaterThan(testCase, bodyIncrease, 0);
verifyLessThanOrEqual(testCase, bodyIncrease, .55 * faceIncrease);
end

function testRegionalSmoothingKeepsIndependentMedians(testCase)
imageSize = [160, 220];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 12 * sin(2 * pi * xGrid / 6) .* sin(2 * pi * yGrid / 8);
sourceGray = 155 * ones(imageSize);
faceRegion = false(imageSize);
faceRegion(40:119, 95:174) = true;
bodyRegion = false(imageSize);
bodyRegion(40:119, 15:94) = true;
sourceGray(faceRegion) = 112 + texture(faceRegion);
sourceGray(bodyRegion) = 188 + texture(bodyRegion);
sourceImage = repmat(uint8(round(sourceGray)), [1, 1, 3]);
skinMask = faceRegion | bodyRegion;
faceBox = [95, 40, 80, 80];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputY = im2double(rgb2ycbcr(sourceImage));
outputY = im2double(rgb2ycbcr(outputImage));
faceInterior = faceRegion & xGrid >= 108 & xGrid <= 161 & ...
    yGrid >= 53 & yGrid <= 106;
bodyInterior = bodyRegion & xGrid >= 28 & xGrid <= 81 & ...
    yGrid >= 53 & yGrid <= 106;

verifyLessThanOrEqual(testCase, abs(median(outputY(faceInterior)) - ...
    median(inputY(faceInterior))), .01);
verifyLessThanOrEqual(testCase, abs(median(outputY(bodyInterior)) - ...
    median(inputY(bodyInterior))), .01);
end

function context = regionalContext(imageSize, faceBox, skinMask, faceSkinMask)
semanticProbabilities = zeros([imageSize, 19], 'single');
nonFaceSkinMask = max(double(skinMask) - double(faceSkinMask), 0);
context = struct( ...
    'skinMask', double(skinMask), ...
    'faceSkinMask', double(faceSkinMask), ...
    'nonFaceSkinMask', nonFaceSkinMask, ...
    'textureProtectionMask', zeros(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'toneProtectionMask', zeros(imageSize), ...
    'strengthMap', max(double(faceSkinMask), .55 * nonFaceSkinMask), ...
    'faceStrengthMap', double(faceSkinMask), ...
    'nonFaceStrengthMap', .55 * nonFaceSkinMask, ...
    'schemaVersion', '3.0', ...
    'semanticProbabilities', semanticProbabilities, ...
    'semanticConfidence', semanticProbabilities, ...
    'imageSize', [imageSize, 3], ...
    'faceBox', faceBox);
end
