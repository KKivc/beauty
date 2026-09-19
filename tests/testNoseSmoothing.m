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
% 取消 nose 的高档额外权重后，任务契约只要求真实瑕疵随强度下降，
% 并保留非零残留纹理；旧的 25% 比例依赖鼻部位置特权，不再作为门槛。
verifyLessThan(testCase, freckleContrast(end), freckleContrast(1), ...
    '高档磨皮应降低鼻部真实瑕疵对比度。');
verifyGreaterThan(testCase, freckleContrast(end), 0, ...
    '鼻部高档磨皮仍应保留非零残留纹理。');
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

function testNoseRepairCannotBypassGlobalOrBlobGates(testCase)
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();

% 只有鼻部小区域有高置信度时，全局证据不足不得因 nose 语义放行。
blemishMap = zeros(size(noseRegion));
blemishMap(noseRegion) = .95;
[~, sparseDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100);
verifyEqual(testCase, sparseDetails.globalGate, 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(sparseDetails.repairEvidence(noseRegion)), ...
    0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(sparseDetails.highEndConfidence(noseRegion)), ...
    0, 'AbsTol', 1e-12);

% 没有任何瑕疵证据时，nose 位置本身不能改变 Fine/Mid。
[unmodified, noEvidenceDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, zeros(size(noseRegion)), 100);
verifyEqual(testCase, unmodified.fine, frequency.fine, 'AbsTol', 1e-12);
verifyEqual(testCase, unmodified.mid, frequency.mid, 'AbsTol', 1e-12);
verifyEqual(testCase, noEvidenceDetails.repairWeight, ...
    zeros(size(noseRegion)), 'AbsTol', 1e-12);

% 美白单独运行时也不能隐式触发磨皮瑕疵修复。
blemishMap = .10 * ones(size(noseRegion));
blemishMap(noseRegion) = .95;
[zeroStrength, zeroStrengthDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 0);
verifyEqual(testCase, zeroStrength.fine, frequency.fine, 'AbsTol', 1e-12);
verifyEqual(testCase, zeroStrength.mid, frequency.mid, 'AbsTol', 1e-12);
verifyEqual(testCase, zeroStrengthDetails.repairWeight, ...
    zeros(size(noseRegion)), 'AbsTol', 1e-12);

% 入口的美白单独路径同样不应携带瑕疵修复权重。
[realImage, realFaceBox, realNoseData] = syntheticNosePortrait();
realContext = buildBeautyContextFromParsing(realImage, realFaceBox, ...
    parsingForPortrait(size(realImage, [1, 2]), realNoseData));
[~, whiteningOnlyDiagnostics] = beautifyImage(realImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 50), realFaceBox, ...
    realContext);
verifyEqual(testCase, whiteningOnlyDiagnostics.repair.repairWeight, ...
    zeros(size(realImage, [1, 2])), 'AbsTol', 1e-12);

% 全局证据充足但高置信区域是长条时，鼻部不能替代紧凑 Blob Gate。
blemishMap = .10 * ones(size(noseRegion));
longAnomaly = false(size(noseRegion));
longAnomaly(48:52, 70:84) = true;
blemishMap(longAnomaly) = .95;
beautyMasks.noseMask = double(longAnomaly);
[~, longDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100);
verifyGreaterThan(testCase, max(longDetails.highConfidence(longAnomaly)), 0);
verifyFalse(testCase, any(longDetails.blobMask(longAnomaly)));
verifyEqual(testCase, max(longDetails.highEndConfidence(longAnomaly)), ...
    0, 'AbsTol', 1e-12);
end

function testRepairRequiresValidTextureProtectionMask(testCase)
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
blemishMap = .10 * ones(size(noseRegion));
blemishMap(noseRegion) = .95;

missing = rmfield(beautyMasks, 'textureProtectionMask');
verifyError(testCase, @() beauty.repairSkinBlemishes( ...
    frequency, missing, blemishMap, 100), ...
    'beauty:InvalidBlemishRepair');

invalid = beautyMasks;
invalid.textureProtectionMask(1, 1) = NaN;
verifyError(testCase, @() beauty.repairSkinBlemishes( ...
    frequency, invalid, blemishMap, 100), ...
    'beauty:InvalidBlemishRepair');
end

function testTextureProtectionGatesFaceAndNonFaceRepair(testCase)
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
imageSize = size(noseRegion);
faceBlemish = false(imageSize);
faceBlemish(48:52, 70:74) = true;
nonFaceBlemish = false(imageSize);
nonFaceBlemish(90:94, 110:114) = true;
blemishMap = .10 * ones(imageSize);
blemishMap(faceBlemish | nonFaceBlemish) = .95;
beautyMasks.nonFaceStrengthMap(nonFaceBlemish) = 1;

baselineMasks = beautyMasks;
baselineMasks.textureProtectionMask = zeros(imageSize);
protectedMasks = baselineMasks;
protectedMasks.textureProtectionMask(faceBlemish | nonFaceBlemish) = .50;

[~, baseline] = beauty.repairSkinBlemishes( ...
    frequency, baselineMasks, blemishMap, 100);
[~, protected] = beauty.repairSkinBlemishes( ...
    frequency, protectedMasks, blemishMap, 100);

verifyGreaterThan(testCase, min(baseline.fineWeight(faceBlemish)), 0);
verifyGreaterThan(testCase, min(baseline.fineWeight(nonFaceBlemish)), 0);
verifyEqual(testCase, max(abs(protected.fineWeight(faceBlemish) - ...
    .50 * baseline.fineWeight(faceBlemish))), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(abs(protected.mediumWeight(faceBlemish) - ...
    .50 * baseline.mediumWeight(faceBlemish))), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(abs(protected.fineWeight(nonFaceBlemish) - ...
    .50 * baseline.fineWeight(nonFaceBlemish))), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(abs(protected.mediumWeight(nonFaceBlemish) - ...
    .50 * baseline.mediumWeight(nonFaceBlemish))), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(abs(protected.referenceReliability(faceBlemish) - ...
    .50 * baseline.referenceReliability(faceBlemish))), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, max(abs(protected.referenceReliability(nonFaceBlemish) - ...
    .50 * baseline.referenceReliability(nonFaceBlemish))), 0, 'AbsTol', 1e-12);
end

function testNoseMidGateIsContinuousAndFineUsesCommonEvidence(testCase)
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
blemishMap = .10 * ones(size(noseRegion));
blemishMap(noseRegion) = .95;

ordinaryMasks = beautyMasks;
ordinaryMasks.noseMask = zeros(size(noseRegion));
[~, ordinary] = beauty.repairSkinBlemishes( ...
    frequency, ordinaryMasks, blemishMap, 100);

halfMasks = beautyMasks;
halfMasks.noseMask = .50 * double(noseRegion);
[~, halfNose] = beauty.repairSkinBlemishes( ...
    frequency, halfMasks, blemishMap, 100);

fullMasks = beautyMasks;
fullMasks.noseMask = double(noseRegion);
[~, fullNose] = beauty.repairSkinBlemishes( ...
    frequency, fullMasks, blemishMap, 100);

verifyEqual(testCase, halfNose.fineWeight, ordinary.fineWeight, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, fullNose.fineWeight, ordinary.fineWeight, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, fullNose.repairEvidence, ordinary.repairEvidence, ...
    'AbsTol', 1e-12);
verifyGreaterThan(testCase, max(ordinary.highEndConfidence(noseRegion)), 0);
verifyEqual(testCase, unique(halfNose.noseMidGate(noseRegion)), .75, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, unique(fullNose.noseMidGate(noseRegion)), .50, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, halfNose.mediumWeight(noseRegion), ...
    .75 * ordinary.mediumWeight(noseRegion), 'AbsTol', 1e-12);
verifyEqual(testCase, fullNose.mediumWeight(noseRegion), ...
    .50 * ordinary.mediumWeight(noseRegion), 'AbsTol', 1e-12);
end

function testNoseRepairEnergyAndStructureUseFixedYCbCrContract(testCase)
[image, faceBox, noseData] = syntheticNosePortrait();
parsing = parsingForPortrait(size(image, [1, 2]), noseData);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);

[~, zeroDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 0);
[highRepair, highDetails] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100);
noseRoi = noseData.freckle & beautyMasks.hardProtectionMask < .999;
zeroEnergy = mean(abs(zeroDetails.fineBefore(noseRoi)) + ...
    abs(zeroDetails.midBefore(noseRoi)));
highEnergy = mean(abs(highDetails.fineAfter(noseRoi)) + ...
    abs(highDetails.midAfter(noseRoi)));
verifyLessThan(testCase, highEnergy, zeroEnergy, ...
    '鼻部真实瑕疵的 Fine/Mid 能量应在高档下降。');
verifyTrue(testCase, highDetails.baseUnchanged);

sourceY = rgb2ycbcr(im2double(image));
output = beautifyImage(image, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
outputY = rgb2ycbcr(im2double(output));
sourceY = sourceY(:, :, 1);
outputY = outputY(:, :, 1);
noseRoi = noseData.nose & context.skinMask >= .35;
baseValues = frequency.base(noseRoi);
lowBase = percentileValue(baseValues, .25);
highBase = percentileValue(baseValues, .75);
lightRoi = noseRoi & frequency.base >= highBase;
darkRoi = noseRoi & frequency.base <= lowBase;
lowSigma = frequency.scales.mediumSigma;
inputLow = imgaussfilt(sourceY, lowSigma, 'Padding', 'replicate');
outputLow = imgaussfilt(outputY, lowSigma, 'Padding', 'replicate');
inputContrast = mean(inputLow(lightRoi)) - mean(inputLow(darkRoi));
outputContrast = mean(outputLow(lightRoi)) - mean(outputLow(darkRoi));
contrastFloor = 2 / 255;
if abs(inputContrast) > contrastFloor
    verifyGreaterThan(testCase, inputContrast * outputContrast, 0);
    verifyGreaterThanOrEqual(testCase, abs(outputContrast), ...
        .90 * abs(inputContrast));
else
    verifyLessThanOrEqual(testCase, abs(outputContrast - inputContrast), ...
        contrastFloor);
end

hard = beautyMasks.hardProtectionMask >= .999;
blemishCore = noseData.freckle;
exclusionRadius = .01 * min(faceBox(3:4));
gradientRoi = noseRoi & ~hard & ~lightRoi & ~darkRoi & ...
    ~blemishCore & bwdist(blemishCore) > exclusionRadius;
[repairInputLow, repairOutputLow] = deal( ...
    imgaussfilt(frequency.sourceLuminance, lowSigma, ...
    'Padding', 'replicate'), ...
    imgaussfilt(highRepair.reconstructedLuminance, lowSigma, ...
    'Padding', 'replicate'));
[inputX, inputY] = gradient(repairInputLow);
[outputX, outputY] = gradient(repairOutputLow);
inputGradient = hypot(inputX, inputY);
correctionGradient = hypot(outputX - inputX, outputY - inputY);
if nnz(gradientRoi) >= 16
    correctionP95 = percentileValue(correctionGradient(gradientRoi), .95);
    inputP95 = percentileValue(inputGradient(gradientRoi), .95);
    correctionLimit = .10 * max(inputP95, 2 / (255 * min(faceBox(3:4))));
    verifyLessThanOrEqual(testCase, correctionP95, correctionLimit, ...
        '单独鼻部修复的校正梯度超过约束。');
end
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

function [frequency, beautyMasks, noseRegion] = standaloneRepairFixture
imageSize = [120, 160];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
noseRegion = false(imageSize);
noseRegion(48:52, 70:74) = true;
spot = exp(-((xGrid - 72) / 2.0) .^ 2 - ...
    ((yGrid - 50) / 2.0) .^ 2);
base = .56 + .04 * exp(-((xGrid - 80) / 18) .^ 2);
mid = .045 * spot;
fine = .065 * spot;
frequency = struct('base', base, 'mid', mid, 'fine', fine, ...
    'sourceLuminance', base + mid + fine, ...
    'imageSize', [imageSize, 3], 'faceScale', 100, ...
    'faceBox', [31, 11, 100, 100]);
beautyMasks = struct('skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'textureProtectionMask', zeros(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'hardProtectionMask', zeros(imageSize), ...
    'noseMask', double(noseRegion), ...
    'nonFaceStrengthMap', zeros(imageSize));
end

function value = percentileValue(values, fraction)
values = sort(double(values(:)));
position = 1 + (numel(values) - 1) * fraction;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    weight = position - lower;
    value = (1 - weight) * values(lower) + weight * values(upper);
end
end
