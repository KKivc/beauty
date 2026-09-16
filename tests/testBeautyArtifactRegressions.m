function tests = testBeautyArtifactRegressions
%TESTBEAUTYARTIFACTREGRESSIONS 三处美颜瑕疵的量化回归断言。
% 防止调参时倒退回：眉周雀斑带“掉皮”、唇周深色描边、鼻部立体感被抹平。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testSoftShadingSlopeSurvivesMaximumSmoothing(testCase)
% 鼻侧影量级的软光影（逐像素梯度低于 structureProtection 起判阈值）
% 在 100 档磨皮后，其明暗过渡坡度须保留至少 75%。
imageSize = [240, 320];
[yGrid, ~] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.60 - 0.10 * exp(-(yGrid - 120) .^ 2 / (2 * 12 ^ 2));
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputY = im2double(sourceImage(:, :, 2));
outputY = im2double(outputImage(:, :, 2));
roi = yGrid > 60 & yGrid < 180;
slopeBefore = softShadingSlope(inputY, roi);
slopeAfter = softShadingSlope(outputY, roi);
verifyGreaterThan(testCase, slopeAfter, .75 * slopeBefore, ...
    '高档磨皮后软光影的明暗过渡坡度须保留至少 75%。');
end

function testFreckleBandKeepsResidualTexture(testCase)
% 雀斑边缘（中等异常度像素）在 100 档后须保留可见残留纹理，
% 防止雀斑带被全强度抹平形成“掉皮”式的苍白斑块。
imageSize = [240, 320];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
rng(7);
luma = 0.60 + 0.006 * imgaussfilt(randn(imageSize), 0.8);
freckleCenters = [round(90 + 60 * rand(40, 1)), ...
    round(40 + 240 * rand(40, 1))];
for index = 1:size(freckleCenters, 1)
    mask = (yGrid - freckleCenters(index, 1)) .^ 2 + ...
        (xGrid - freckleCenters(index, 2)) .^ 2 <= 4;
    luma = luma - 0.10 * mask;
end
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputY = im2double(sourceImage(:, :, 2));
outputY = im2double(outputImage(:, :, 2));
bandMask = yGrid > 80 & yGrid < 160 & xGrid > 30 & xGrid < 290;
detailBefore = inputY - imgaussfilt(inputY, 2.5, 'Padding', 'replicate');
detailAfter = outputY - imgaussfilt(outputY, 2.5, 'Padding', 'replicate');
rimMask = bandMask & abs(detailBefore) > .02 & abs(detailBefore) < .06;
verifyGreaterThan(testCase, nnz(rimMask), 300, ...
    '测试图须包含足够的雀斑边缘像素。');
textureRatio = std(detailAfter(rimMask)) / std(detailBefore(rimMask));
% 斑点核心现在清除得更彻底；边缘保留比例约 0.05--0.08，
% 旧的保留率悬崖实现约为 0.03（近乎全抹平）。
verifyGreaterThan(testCase, textureRatio, .05, ...
    '雀斑边缘的残留纹理不得被完全抹平。');
end

function testMidProbabilityBrowReceivesSoftProtection(testCase)
% 概率 0.45--0.65 的浅色眉毛必须进入软保护，且不得进入硬保护。
image = uint8(ones(80, 100, 3) * 150);
parsing = emptyParsing([80, 100]);
parsing = addRegion(parsing, 'skin', 10:70, 20:80, 1);
parsing = addRegion(parsing, 'leftBrow', 30:34, 30:70, .55);
parsing = addRegion(parsing, 'rightBrow', 44:48, 30:70, .90);

context = buildBeautyContextFromParsing(image, [1, 1, 100, 80], parsing);
[beautyMasks, ~] = masks.buildBeautyMasks( ...
    image, context, [1, 1, 100, 80]);
protection = beautyMasks.textureProtectionMask;
hard = beautyMasks.hardProtectionMask >= .999;

verifyGreaterThan(testCase, protection(32, 50), .3, ...
    '中等概率的眉毛应得到软保护。');
verifyFalse(testCase, hard(32, 50), ...
    '中等概率眉毛不得进入硬保护。');
verifyTrue(testCase, hard(46, 50), ...
    '高概率眉毛仍应进入硬保护。');
end

function testWhiteningSetbackNearHardFeature(testCase)
% 美白在硬保护边界附近必须平滑退让，不得形成亮度台阶。
imageSize = [160, 200];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
hardMask = (yGrid - 80) .^ 2 + (xGrid - 100) .^ 2 <= 12 ^ 2;
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox, hardMask);

sourceImage = grayToUint8Rgb(0.55 * ones(imageSize));
outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, context);
outputY = im2double(outputImage(:, :, 2));
inputY = 0.55;

nearRing = ~hardMask & (yGrid - 80) .^ 2 + (xGrid - 100) .^ 2 <= 15 ^ 2;
farArea = (yGrid - 80) .^ 2 + (xGrid - 100) .^ 2 >= 40 ^ 2;
liftNear = median(outputY(nearRing)) - inputY;
liftFar = median(outputY(farArea)) - inputY;
verifyGreaterThan(testCase, liftFar, 0, '远离特征处应有美白提亮。');
verifyLessThan(testCase, liftNear, .60 * liftFar, ...
    '硬保护边界附近的美白必须明显退让。');
end

function testNoseShadingContrastSurvivesWhitening(testCase)
% 美白后鼻梁-鼻侧的明暗差须保留至少 90%。
imageSize = [120, 240];
[yGrid, ~] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.45 + 0.30 * min(max((yGrid - 30) / 60, 0), 1);
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 97), faceBox, context);
inputY = im2double(sourceImage(:, :, 2));
outputY = im2double(outputImage(:, :, 2));
shadowBefore = median(inputY(20:28, 60:180));
bridgeBefore = median(inputY(92:100, 60:180));
shadowAfter = median(outputY(20:28, 60:180));
bridgeAfter = median(outputY(92:100, 60:180));
contrastBefore = bridgeBefore - shadowBefore;
contrastAfter = bridgeAfter - shadowAfter;
verifyGreaterThan(testCase, contrastAfter, .90 * contrastBefore, ...
    '美白不得压缩鼻部明暗对比超过 10%。');
verifyGreaterThan(testCase, bridgeAfter, shadowAfter, ...
    '美白后仍须保留亮度排序。');
end

function rgb = grayToUint8Rgb(luma)
value = uint8(min(max(round(luma * 255), 0), 255));
rgb = cat(3, value, value, value);
end

function context = plainSkinContext(imageSize, faceBox, hardMask)
semanticProbabilities = zeros([imageSize, 19], 'single');
if nargin >= 3 && any(hardMask(:))
    names = faceParsingClassNames();
    eyeIndex = find(strcmp(names, 'leftEye'), 1);
    semanticProbabilities(:, :, eyeIndex) = single(hardMask);
end
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
    'semanticProbabilities', semanticProbabilities, ...
    'semanticConfidence', semanticProbabilities, ...
    'imageSize', [imageSize, 3], 'faceBox', faceBox);
end

function detail = highPass(luma, mask)
filtered = imgaussfilt(luma, 2.5, 'Padding', 'replicate');
detail = luma(mask) - filtered(mask);
end

function slope = softShadingSlope(luma, roi)
smoothed = imgaussfilt(luma, 2, 'Padding', 'replicate');
[gradientX, gradientY] = gradient(smoothed);
gradientMagnitude = hypot(gradientX, gradientY);
values = gradientMagnitude(roi);
slope = sort(values);
slope = slope(1 + round(.95 * (numel(slope) - 1)));
end

function parsing = emptyParsing(imageSize)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidence.(names{index}) = zeros(imageSize);
end
parsing = struct('regions', regions, 'regionConfidence', confidence);
end

function parsing = addRegion(parsing, name, rowRange, columnRange, value)
parsing.regions.(name)(rowRange, columnRange) = value;
parsing.regionConfidence.(name)(rowRange, columnRange) = value;
end
