function tests = testNoseSmoothing
%TESTNOSESMOOTHING 验证鼻内斑点参与磨皮且鼻部结构得到保护。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testNoseFrecklesAreSmoothedMonotonically(testCase)
[image, faceBox, noseData] = syntheticNosePortrait();
context = buildBeautyContextFromParsing(image, faceBox, ...
    parsingForPortrait(size(image, [1, 2]), noseData));
strengths = [0, 25, 50, 75, 100];
inputGray = im2double(rgb2gray(image));
localBase = imgaussfilt(inputGray, 5, 'Padding', 'replicate');
freckleContrast = zeros(size(strengths));
for index = 1:numel(strengths)
    output = beautifyImage(image, struct( ...
        'smoothingStrength', strengths(index), 'whiteningStrength', 0), ...
        faceBox, context);
    outputGray = im2double(rgb2gray(output));
    freckleContrast(index) = mean(abs(outputGray(noseData.freckle) - ...
        localBase(noseData.freckle)));
end

verifyTrue(testCase, all(diff(freckleContrast) <= 1e-6), ...
    '鼻内雀斑对比度应随磨皮档位单调下降。');
verifyLessThanOrEqual(testCase, freckleContrast(end), ...
    .25 * freckleContrast(1) + 2e-3);
end

function testNoseStructureAndNostrilEdgeRemainProtected(testCase)
[image, faceBox, noseData] = syntheticNosePortrait();
parsing = parsingForPortrait(size(image, [1, 2]), noseData);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
hard = beautyMasks.hardProtectionMask >= .999;
diagnostics = allDiagnostics.texture;
output = beautifyImage(image, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);

inputGray = im2double(rgb2gray(image));
outputGray = im2double(rgb2gray(output));
inputLow = imgaussfilt(inputGray, 6, 'Padding', 'replicate');
outputLow = imgaussfilt(outputGray, 6, 'Padding', 'replicate');
ridgeContrast = mean(inputLow(noseData.noseRidge)) - ...
    mean(inputLow(noseData.cheek));
outputRidgeContrast = mean(outputLow(noseData.noseRidge)) - ...
    mean(outputLow(noseData.cheek));
verifyGreaterThanOrEqual(testCase, outputRidgeContrast, ...
    .85 * ridgeContrast);

[inputX, inputY] = gradient(inputGray);
[outputX, outputY] = gradient(outputGray);
inputEdge = hypot(inputX, inputY);
outputEdge = hypot(outputX, outputY);
verifyGreaterThan(testCase, nnz(diagnostics.nostrilBoundary), 0, ...
    '合成鼻孔应得到连续边界候选。');
verifyGreaterThanOrEqual(testCase, mean(outputEdge(diagnostics.nostrilBoundary)), ...
    .85 * mean(inputEdge(diagnostics.nostrilBoundary)));

expectedHard = diagnostics.lipCore | diagnostics.nostrilCore | ...
    diagnostics.lashCore | diagnostics.occluderProtection >= 1;
verifyEqual(testCase, hard, expectedHard);
verifyEqual(testCase, nnz(hard & diagnostics.noseBoundary), 0, ...
    '鼻子语义外轮廓不得进入硬保护。');
end

function testNoseHardProtectionDoesNotContainFreckleDots(testCase)
[image, faceBox, noseData] = syntheticNosePortrait();
parsing = parsingForPortrait(size(image, [1, 2]), noseData);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
hard = beautyMasks.hardProtectionMask >= .999;
diagnostics = allDiagnostics.texture;

verifyEqual(testCase, nnz(hard & noseData.freckle), 0, ...
    '鼻内雀斑不得进入硬保护。');
interiorHard = hard & diagnostics.noseInterior & ...
    ~diagnostics.nostrilCore;
verifyEqual(testCase, nnz(interiorHard), 0, ...
    '鼻内非鼻孔结构不得形成硬保护点。');
verifyGreaterThan(testCase, nnz(diagnostics.noseBoundary), 0);
verifyEqual(testCase, nnz(hard & diagnostics.noseBoundary), 0, ...
    '鼻子外轮廓只能使用软保护。');
verifyGreaterThan(testCase, nnz(hard), 0);
end

function [image, faceBox, masks] = syntheticNosePortrait
imageHeight = 192;
imageWidth = 256;
faceBox = [31, 19, 194, 154];
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = imageWidth / 2;
centerY = 99;
face = ((xGrid - centerX) / 79) .^ 2 + ...
    ((yGrid - centerY) / 72) .^ 2 <= 1;
nose = ((xGrid - centerX) / 19) .^ 2 + ...
    ((yGrid - 101) / 35) .^ 2 <= 1;
ridge = 18 * exp(-((xGrid - centerX) / 8) .^ 2 - ...
    ((yGrid - 96) / 48) .^ 2);
base = 166 + ridge;
red = base + 22;
green = base - 14;
blue = base - 30;

freckle = false(imageHeight, imageWidth);
centers = [centerX - 10, 84; centerX + 9, 91; ...
    centerX - 11, 106; centerX + 10, 112; centerX, 124];
for index = 1:size(centers, 1)
    spot = ((xGrid - centers(index, 1)) / 2.2) .^ 2 + ...
        ((yGrid - centers(index, 2)) / 1.8) .^ 2 <= 1;
    freckle = freckle | spot;
    red(spot) = red(spot) - 48;
    green(spot) = green(spot) - 36;
    blue(spot) = blue(spot) - 28;
end

nostril = (((xGrid - (centerX - 8)) / 5) .^ 2 + ...
    ((yGrid - 119) / 3.2) .^ 2 <= 1) | ...
    (((xGrid - (centerX + 8)) / 5) .^ 2 + ...
    ((yGrid - 119) / 3.2) .^ 2 <= 1);
red(nostril) = red(nostril) - 64;
green(nostril) = green(nostril) - 52;
blue(nostril) = blue(nostril) - 44;

image = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));
masks = struct('skin', face, 'nose', nose, 'freckle', freckle, ...
    'nostril', nostril, 'noseRidge', nose & abs(xGrid - centerX) <= 4 & ...
    yGrid >= 76 & yGrid <= 108, 'cheek', face & ...
    abs(xGrid - centerX) >= 32 & abs(xGrid - centerX) <= 46 & ...
    yGrid >= 76 & yGrid <= 108);
end

function parsing = parsingForPortrait(imageSize, masks)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidence.(names{index}) = zeros(imageSize);
end
regions.skin = double(masks.skin);
confidence.skin = double(masks.skin);
regions.nose = double(masks.nose);
confidence.nose = double(masks.nose);
parsing = struct('regions', regions, 'regionConfidence', confidence);
end
