function tests = testPhase3Enhancements
%TESTPHASE3ENHANCEMENTS 第三阶段方向、五官保护和高档曲线测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testSmoothingProfileKeepsCanonicalCurves(testCase)
half = beautySmoothingProfile(50);
verifyEqual(testCase, half.ratio, .5, 'AbsTol', 1e-12);
verifyEqual(testCase, half.naturalRatio, .75, 'AbsTol', 1e-12);
verifyEqual(testCase, half.highEndSmoothingCurve, 0, 'AbsTol', 0);
verifyEqual(testCase, half.highEndRepairGate, 0, 'AbsTol', 0);
verifyEqual(testCase, half.highEndToneGate, 0, 'AbsTol', 0);
verifyEqual(testCase, half.blemishStrength, .5 ^ .85, ...
    'AbsTol', 1e-12);

maximum = beautySmoothingProfile(100);
highNatural = beautySmoothingProfile(75);
verifyGreaterThan(testCase, maximum.naturalRatio, highNatural.naturalRatio);
verifyGreaterThan(testCase, maximum.alphaCurve, highNatural.alphaCurve);
verifyLessThan(testCase, maximum.fineRetention, highNatural.fineRetention);
verifyLessThan(testCase, maximum.mediumRetention, highNatural.mediumRetention);
verifyGreaterThan(testCase, maximum.blemishStrength, ...
    highNatural.blemishStrength);
verifyGreaterThan(testCase, maximum.toneStrength, highNatural.toneStrength);
verifyGreaterThan(testCase, maximum.outsideFaceStrength, ...
    highNatural.outsideFaceStrength);
verifyEqual(testCase, highNatural.highEndRepairGate, 0, 'AbsTol', 0);
verifyEqual(testCase, maximum.highEndRepairGate, 1, 'AbsTol', 0);
verifyEqual(testCase, maximum.highEndToneGate, 1, 'AbsTol', 0);
end

function testSmoothingKeepsEffectiveSkinYCbCrMedians(testCase)
imageSize = [96, 112];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
base = 138 + 13 * sin(2 * pi * xGrid / 17) .* ...
    sin(2 * pi * yGrid / 13);
sourceImage = cat(3, ...
    uint8(min(max(round(base + 7 * sin(2 * pi * yGrid / 29)), 0), 255)), ...
    uint8(min(max(round(base), 0), 255)), ...
    uint8(min(max(round(base - 6 * cos(2 * pi * xGrid / 23)), 0), 255)));
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = struct('skinMask', ones(imageSize), ...
    'faceSkinMask', ones(imageSize), ...
    'nonFaceSkinMask', zeros(imageSize), ...
    'textureProtectionMask', zeros(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'toneProtectionMask', zeros(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'faceStrengthMap', ones(imageSize), ...
    'nonFaceStrengthMap', zeros(imageSize), ...
    'schemaVersion', '3.0', ...
    'semanticProbabilities', zeros([imageSize, 19], 'single'), ...
    'semanticConfidence', zeros([imageSize, 19], 'single'), ...
    'imageSize', [imageSize, 3], 'faceBox', faceBox);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputYCbCr = rgb2ycbcr(im2double(sourceImage));
outputYCbCr = rgb2ycbcr(im2double(outputImage));
medianShifts = zeros(1, 3);
for channel = 1:3
    inputChannel = inputYCbCr(:, :, channel);
    outputChannel = outputYCbCr(:, :, channel);
    medianShifts(channel) = abs(median(outputChannel(:)) - ...
        median(inputChannel(:)));
end

verifyLessThanOrEqual(testCase, medianShifts, 2 / 255);
end

function testOrientationScoreRequiresNoseLipAndEyeBrow(testCase)
weak = emptyFaceParsing([40, 60]);
weak = addRegion(weak, 'leftEye', 10:12, 20:22, 1);
weak = addRegion(weak, 'leftBrow', 7:9, 20:22, 1);
assessment = scoreFaceParsingOrientation(weak);
verifyTrue(testCase, assessment.needsFallback);
verifyFalse(testCase, assessment.isStrong);

strong = weak;
strong = addRegion(strong, 'nose', 14:20, 28:33, 1);
strong = addRegion(strong, 'upperLip', 24:27, 25:36, 1);
strong = addRegion(strong, 'rightEye', 10:12, 38:40, 1);
assessment = scoreFaceParsingOrientation(strong);
verifyTrue(testCase, assessment.hasNose);
verifyTrue(testCase, assessment.hasLipGroup);
verifyTrue(testCase, assessment.hasEyeBrow);
verifyGreaterThanOrEqual(testCase, assessment.score, 6);
verifyTrue(testCase, assessment.isStrong);
end

function testDetectionChoosesNegativeNinetyAndMapsBack(testCase)
image = uint8(zeros(40, 60, 3));
weak = emptyFaceParsing([40, 60]);
weak = addRegion(weak, 'skin', 8:33, 12:49, 1);
options = struct('candidateBoxes', zeros(0, 4), ...
    'fullParsing', weak, 'orientationRunner', @orientationParsing);

[box, hasFace, details] = detectSingleFace(image, options);

verifyTrue(testCase, hasFace);
verifyEqual(testCase, details.orientationDegrees, -90);
verifyEqual(testCase, details.orientationParsingCount, 1);
verifyTrue(testCase, details.orientationScores(2).isStrong);
verifySize(testCase, details.selectedParsing.regions.skin, [40, 60]);
verifyGreaterThanOrEqual(testCase, box(1:2), [1, 1]);
verifyLessThanOrEqual(testCase, box(1) + box(3) - 1, 60);
verifyLessThanOrEqual(testCase, box(2) + box(4) - 1, 40);
end

function parsing = orientationParsing(image, ~, angle)
parsing = emptyFaceParsing(size(image, [1, 2]));
parsing = addRegion(parsing, 'skin', ...
    8:size(image, 1) - 8, 8:size(image, 2) - 8, 1);
if angle == -90
    parsing = addRegion(parsing, 'nose', 20:26, 18:23, 1);
    parsing = addRegion(parsing, 'upperLip', 29:32, 15:26, 1);
    parsing = addRegion(parsing, 'leftEye', 12:15, 12:16, 1);
    parsing = addRegion(parsing, 'rightEye', 12:15, 28:32, 1);
    parsing = addRegion(parsing, 'leftBrow', 8:11, 12:17, 1);
end
end

function testFeatureProtectionSeparatesNoseAndLipBoundaries(testCase)
image = uint8(ones(80, 100, 3) * 150);
image(25:55, 44:45, :) = 70;
parsing = emptyFaceParsing([80, 100]);
parsing = addRegion(parsing, 'skin', 10:70, 20:80, 1);
parsing = addRegion(parsing, 'nose', 25:55, 44:56, .8);
parsing = addRegion(parsing, 'upperLip', 61:64, 40:60, .8);
parsing = addRegion(parsing, 'lowerLip', 65:68, 40:60, .8);

context = buildBeautyContextFromParsing(image, [1, 1, 100, 80], parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 100, 80]);
hard = beautyMasks.hardProtectionMask >= .999;
diagnostics = allDiagnostics.texture;

verifyTrue(testCase, hard(62, 50));
verifyTrue(testCase, diagnostics.noseCore(35, 44));
verifyFalse(testCase, diagnostics.noseBoundary(40, 50));
verifyFalse(testCase, hard(35, 44), ...
    '鼻子语义外轮廓不得进入硬保护。');
verifyGreaterThan(testCase, diagnostics.lipProtection(60, 50), 0);
% 唇周过渡带加宽后，紧邻唇核上方应存在部分保护；远离唇核处仍为 0。
verifyGreaterThan(testCase, diagnostics.lipProtection(57, 50), 0);
verifyTrue(testCase, diagnostics.lipProtection(54, 50) == 0);
verifyGreaterThan(testCase, diagnostics.noseProtection(35, 44), ...
    diagnostics.noseProtection(40, 50));
end

function testEyeAdjacentFineLinesAreProtected(testCase)
image = uint8(ones(96, 128, 3) * 170);
% 眼睛语义区外侧的连续暗线模拟睫毛；另加一个远离眼睑的孤立斑点。
image(42:46, 43:56, :) = 105;
image(39, 46:53, :) = 35;
image(70, 74, :) = 35;
parsing = emptyFaceParsing([96, 128]);
parsing = addRegion(parsing, 'skin', 20:80, 20:108, 1);
parsing = addRegion(parsing, 'leftEye', 42:46, 43:56, 1);

context = buildBeautyContextFromParsing(image, [1, 1, 128, 96], parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 128, 96]);
hard = beautyMasks.hardProtectionMask >= .999;
diagnostics = allDiagnostics.texture;

verifyGreaterThan(testCase, nnz(diagnostics.lashCore), 0, ...
    '应检测到眼睑邻接的连续细线。');
verifyTrue(testCase, any(hard(39, 46:53)));
verifyFalse(testCase, hard(70, 74), ...
    '远离眼睑的孤立斑点不得被判定为睫毛。');
verifyGreaterThanOrEqual(testCase, ...
    min(diagnostics.lashProtection(diagnostics.lashCore)), .95);
end

function testUpperEyelidFoldReceivesStrongSoftProtection(testCase)
image = uint8(ones(96, 128, 3) * 170);
image(42:46, 43:56, :) = 105;
% 眼睛上方的低对比连续弧线模拟双眼皮，远处圆斑不得进入眼周保护。
image(38, 45:54, :) = 155;
image(70, 74, :) = 155;
parsing = emptyFaceParsing([96, 128]);
parsing = addRegion(parsing, 'skin', 20:80, 20:108, 1);
parsing = addRegion(parsing, 'leftEye', 42:46, 43:56, 1);

context = buildBeautyContextFromParsing(image, [1, 1, 128, 96], parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 128, 96]);
protection = beautyMasks.textureProtectionMask;
hard = beautyMasks.hardProtectionMask >= .999;
diagnostics = allDiagnostics.texture;

verifyGreaterThan(testCase, mean(protection(38, 45:54)), .55, ...
    '双眼皮所在的上眼睑带应得到强软保护。');
verifyFalse(testCase, any(hard(38, 45:54)), ...
    '双眼皮褶皱应使用软保护，不能扩大为硬保护。');
verifyEqual(testCase, protection(70, 74), 0, 'AbsTol', 1e-12, ...
    '远离眼睛的低对比斑点不得进入眼周保护。');
verifyGreaterThan(testCase, ...
    mean(diagnostics.periocularProtection(38, 45:54)), .55);
end

function testLowConfidenceEyeSoftSupportStartsWithoutHardCore(testCase)
image = uint8(ones(96, 128, 3) * 170);
% 眼部语义只有中低置信度，但局部仍存在眼睑/睫毛结构。
image(42:46, 43:56, :) = 105;
image(39, 46:53, :) = 35;
parsing = emptyFaceParsing([96, 128]);
parsing = addRegion(parsing, 'skin', 20:80, 20:108, 1);
parsing = addRegion(parsing, 'leftEye', 42:46, 43:56, .30);

context = buildBeautyContextFromParsing(image, [1, 1, 128, 96], parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 128, 96]);
diagnostics = allDiagnostics.texture;
hard = beautyMasks.hardProtectionMask >= .999;

verifyGreaterThan(testCase, nnz(diagnostics.eyeNeighborhood), 0, ...
    '0.30 的单眼证据应启动有限眼周邻域。');
verifyGreaterThan(testCase, nnz(diagnostics.eyeDetailProtection), 0, ...
    '低/中置信眼部证据配合真实局部结构时应产生软眼部保护。');
verifyGreaterThan(testCase, nnz(diagnostics.lashProtection), 0, ...
    '低/中置信眼部证据应允许现有睫毛检测器产生软保护。');
verifyEqual(testCase, nnz(diagnostics.lashCore), 0, ...
    '低/中置信 eye soft support 不得新增 hard lash core。');
verifyFalse(testCase, any(hard(:)), ...
    '单独的 0.30 眼部证据不得形成 hard protection。');
verifyGreaterThan(testCase, mean(diagnostics.eyeDetailProtection(39, 46:53)), 0);
end

function testEyeSoftSupportRemainsIndependentAndRejectsIsolatedDarkPoint(testCase)
image = uint8(ones(120, 190, 3) * 170);
% 左右眼各有独立的局部眼睑/睫毛，鼻梁中部另放一个孤立暗点。
image(48:52, 35:50, :) = 105;
image(45, 38:47, :) = 35;
image(48:52, 140:155, :) = 105;
image(45, 143:152, :) = 35;
image(80, 95, :) = 35;
faceBox = [1, 1, 190, 120];

leftOnly = emptyFaceParsing([120, 190]);
leftOnly = addRegion(leftOnly, 'skin', 20:100, 20:170, 1);
leftOnly = addRegion(leftOnly, 'leftEye', 48:52, 35:50, .30);
[~, leftDiagnostics] = masks.buildBeautyMasks(image, ...
    buildBeautyContextFromParsing(image, faceBox, leftOnly), faceBox);
leftTexture = leftDiagnostics.texture;

rightOnly = emptyFaceParsing([120, 190]);
rightOnly = addRegion(rightOnly, 'skin', 20:100, 20:170, 1);
rightOnly = addRegion(rightOnly, 'rightEye', 48:52, 140:155, .30);
[rightMasks, rightDiagnostics] = masks.buildBeautyMasks(image, ...
    buildBeautyContextFromParsing(image, faceBox, rightOnly), faceBox);
rightTexture = rightDiagnostics.texture;

zero = emptyFaceParsing([120, 190]);
zero = addRegion(zero, 'skin', 20:100, 20:170, 1);
[~, zeroDiagnostics] = masks.buildBeautyMasks(image, ...
    buildBeautyContextFromParsing(image, faceBox, zero), faceBox);
zeroTexture = zeroDiagnostics.texture;

verifyGreaterThan(testCase, nnz(leftTexture.eyeDetailProtection(:, 1:90)), 0);
verifyEqual(testCase, nnz(leftTexture.eyeDetailProtection(:, 100:end)), 0, ...
    '左眼 soft support 不得跨鼻梁激活右侧眼周。');
verifyEqual(testCase, nnz(leftTexture.eyeNeighborhood(:, 100:end)), 0, ...
    '左眼有限邻域不得扩张到另一只眼。');
verifyGreaterThan(testCase, nnz(rightTexture.eyeDetailProtection(:, 100:end)), 0);
verifyEqual(testCase, nnz(rightTexture.eyeDetailProtection(:, 1:90)), 0, ...
    '右眼 soft support 不得跨鼻梁激活左侧眼周。');
verifyEqual(testCase, nnz(rightTexture.eyeNeighborhood(:, 1:90)), 0, ...
    '右眼有限邻域不得扩张到另一只眼。');
verifyEqual(testCase, zeroTexture.eyeDetailProtection, zeros(120, 190), ...
    'AbsTol', 1e-12, '无眼证据时眼部软保护必须为空。');
verifyEqual(testCase, nnz(zeroTexture.lashCore), 0);
verifyEqual(testCase, nnz(rightTexture.lashCore), 0, ...
    '中置信右眼不得新增 hard lash core。');
verifyEqual(testCase, rightMasks.hardProtectionMask(80, 95), 0, ...
    '远离眼睑的孤立暗点不得进入 hard protection。');
verifyTrue(testCase, rightTexture.eyeDetailProtection(80, 95) == 0, ...
    '远离眼睑的孤立暗点不得进入 eye detail protection。');
end

function testLowConfidenceEyeWithNoLocalStructureRemainsEmpty(testCase)
image = uint8(ones(96, 128, 3) * 170);
parsing = emptyFaceParsing([96, 128]);
parsing = addRegion(parsing, 'skin', 20:80, 20:108, 1);
parsing = addRegion(parsing, 'leftEye', 42:46, 43:56, .30);
context = buildBeautyContextFromParsing(image, [1, 1, 128, 96], parsing);
[~, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 128, 96]);
diagnostics = allDiagnostics.texture;

verifyGreaterThan(testCase, nnz(diagnostics.eyeNeighborhood), 0, ...
    '低置信眼部证据即使没有局部结构，也只应启动有限邻域。');
verifyEqual(testCase, nnz(diagnostics.eyeDetailProtection), 0, ...
    '没有眼睑/睫毛/双眼皮图像证据时不得直接生成眼部保护。');
verifyEqual(testCase, nnz(diagnostics.lashProtection), 0);
verifyEqual(testCase, nnz(diagnostics.doubleEyelidProtection), 0);
end

function testMixedEyeConfidenceKeepsHardAndSoftPathsSeparate(testCase)
image = uint8(ones(120, 190, 3) * 170);
image(48:52, 35:50, :) = 105;
image(45, 38:47, :) = 35;
image(48:52, 140:155, :) = 105;
image(45, 143:152, :) = 35;
parsing = emptyFaceParsing([120, 190]);
parsing = addRegion(parsing, 'skin', 20:100, 20:170, 1);
parsing = addRegion(parsing, 'leftEye', 48:52, 35:50, 1);
parsing = addRegion(parsing, 'rightEye', 48:52, 140:155, .30);
faceBox = [1, 1, 190, 120];
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, allDiagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
diagnostics = allDiagnostics.texture;
hard = beautyMasks.hardProtectionMask >= .999;

verifyGreaterThan(testCase, nnz(diagnostics.eyeDetailProtection(:, 1:90)), 0);
verifyGreaterThan(testCase, nnz(diagnostics.eyeDetailProtection(:, 100:end)), 0);
verifyGreaterThan(testCase, nnz(diagnostics.lashCore(:, 1:90)), 0, ...
    '高置信左眼仍应保留原有 hard lash core 路径。');
verifyEqual(testCase, nnz(diagnostics.lashCore(:, 100:end)), 0, ...
    '中置信右眼不得新增 hard lash core。');
verifyFalse(testCase, any(hard(:, 100:end), 'all'), ...
    '中置信右眼不得把 soft support 升级为 hard protection。');
verifyEqual(testCase, nnz(diagnostics.eyeNeighborhood(:, 91:99)), 0, ...
    '左右眼有限邻域不得通过鼻梁中间区域连通。');
end

function testSingleEyeMixedConfidencePreservesIdentitySoftBand(testCase)
image = uint8(ones(120, 160, 3) * 170);
% 同一只眼的上半部是 identity core，下半部只有 soft support；
% 眼周没有额外暗线，便于单独观察高置信软带是否被覆盖。
image(48:53, 48:57, :) = 105;
faceBox = [1, 1, 160, 120];

highOnly = emptyFaceParsing([120, 160]);
highOnly = addRegion(highOnly, 'skin', 20:100, 20:140, 1);
highOnly = addRegion(highOnly, 'leftEye', 48:50, 48:57, .60);
[~, highDiagnostics] = masks.buildBeautyMasks(image, ...
    buildBeautyContextFromParsing(image, faceBox, highOnly), faceBox);
highTexture = highDiagnostics.texture;

mixed = highOnly;
mixed = addRegion(mixed, 'leftEye', 51:53, 48:57, .30);
[mixedMasks, mixedDiagnostics] = masks.buildBeautyMasks(image, ...
    buildBeautyContextFromParsing(image, faceBox, mixed), faceBox);
mixedTexture = mixedDiagnostics.texture;

identitySoftBand = highTexture.periocularProtection > .20 & ...
    highTexture.lashProtection == 0 & ...
    highTexture.doubleEyelidProtection == 0;
verifyGreaterThan(testCase, nnz(identitySoftBand), 0, ...
    '高置信 identity core 应产生可观测的眼周软带。');
verifyGreaterThanOrEqual(testCase, ...
    mixedTexture.periocularProtection(identitySoftBand), ...
    highTexture.periocularProtection(identitySoftBand) - 1e-12, ...
    '同一只眼的 soft support 不得覆盖高置信 identity core 软带。');

softOnlyRows = false(size(identitySoftBand));
softOnlyRows(51:53, 48:57) = true;
verifyEqual(testCase, nnz(mixedTexture.lashCore(softOnlyRows)), 0, ...
    '同一只眼的中置信 soft support 不得新增 hard lash core。');
verifyEqual(testCase, nnz(mixedMasks.hardProtectionMask(softOnlyRows)), 0, ...
    '同一只眼的中置信 soft support 不得新增 hard protection。');
end

function testHardEyeProtectionKeepsInputRgb(testCase)
image = uint8(ones(96, 128, 3) * 170);
image(42:46, 43:56, :) = 105;
image(39, 46:53, :) = 35;
parsing = emptyFaceParsing([96, 128]);
parsing = addRegion(parsing, 'skin', 20:80, 20:108, 1);
parsing = addRegion(parsing, 'leftEye', 42:46, 43:56, 1);
context = buildBeautyContextFromParsing(image, [1, 1, 128, 96], parsing);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, [1, 1, 128, 96]);
output = beautifyImage(image, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 15), ...
    [1, 1, 128, 96], context);
hard = beautyMasks.hardProtectionMask >= .999;
verifyGreaterThan(testCase, nnz(hard), 0);
hard3 = repmat(hard, 1, 1, 3);
verifyEqual(testCase, max(abs(double(output(hard3)) - double(image(hard3)))), ...
    0, 'AbsTol', 0, '高置信 hard protection 区域最终 RGB 必须与输入逐像素一致。');
end

function testDisconnectedMainLimbIsIncludedButOtherPersonIsRejected(testCase)
height = 100;
width = 140;
image = repmat(reshape(uint8([170, 125, 105]), 1, 1, 3), ...
    height, width);
probabilities = zeros(height, width, 20, 'single');
names = schpLipClassNames();
setClass('face', 10:24, 20:34, .9);
setClass('upperClothes', 24:70, 18:38, .9);
setClass('rightArm', 32:72, 42:48, .9); % 与主体相隔 3 像素。
setClass('face', 10:24, 105:119, .9);
setClass('upperClothes', 24:70, 103:123, .9);
setClass('leftArm', 32:72, 96:102, .9);
reference = zeros(height, width);
reference(10:24, 20:34) = 1;

[bodyMask, personMask] = buildBodySkinMaskFromSchp( ...
    probabilities, reference, image);

verifyTrue(testCase, personMask(50, 45));
verifyGreaterThan(testCase, bodyMask(50, 45), .5);
verifyFalse(testCase, personMask(50, 99));
verifyEqual(testCase, bodyMask(50, 99), 0);

    function setClass(name, rows, columns, value)
        index = find(strcmp(names, name), 1);
        probabilities(rows, columns, index) = value;
    end
end

function testSchpRotationRestoresOriginalSize(testCase)
image = uint8(ones(20, 30, 3) * 128);
logits = zeros(1, 20, 119, 119, 'single');
logits(:, 15, :, :) = 6;
options = struct('rotationDegrees', -90, 'runner', @(~) logits);
probabilities = inferSchpLipProbabilities(image, options);
verifySize(testCase, probabilities, [20, 30, 20]);
verifyGreaterThan(testCase, min(probabilities(:, :, 15), [], 'all'), .94);
verifyError(testCase, @() inferSchpLipProbabilities(image, ...
    struct('rotationDegrees', 45, 'runner', @(~) logits)), ...
    'inferSchpLipProbabilities:InvalidRotation');
end

function parsing = emptyFaceParsing(imageSize)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidence.(names{index}) = zeros(imageSize);
end
parsing = struct('regions', regions, 'regionConfidence', confidence);
end

function parsing = addRegion(parsing, name, rows, columns, value)
parsing.regions.(name)(rows, columns) = value;
parsing.regionConfidence.(name)(rows, columns) = value;
end
