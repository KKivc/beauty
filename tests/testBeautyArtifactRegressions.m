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
% 鼻侧影量级的软光影由结构保护标记后，在 100 档仍须保留至少 90%。
imageSize = [240, 320];
[yGrid, ~] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.60 - 0.10 * exp(-(yGrid - 120) .^ 2 / (2 * 12 ^ 2));
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);
context.structureProtectionMask = double(0.92 * exp( ...
    -(yGrid - 120) .^ 2 / (2 * 28 ^ 2)));

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputY = im2double(sourceImage(:, :, 2));
outputY = im2double(outputImage(:, :, 2));
roi = yGrid > 60 & yGrid < 180;
slopeBefore = softShadingSlope(inputY, roi);
slopeAfter = softShadingSlope(outputY, roi);
verifyGreaterThan(testCase, slopeAfter, .90 * slopeBefore, ...
    '高档磨皮后受保护软光影的明暗过渡坡度须保留至少 90%。');
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

[outputImage, pipelineDiagnostics] = beautifyImage(sourceImage, struct( ...
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
verifyGreaterThan(testCase, textureRatio, .03, ...
    '雀斑边缘的残留纹理不得被完全抹平。');
actualFineRetention = pipelineDiagnostics.repairResult.actualFineRetentionMap;
evaluation = rimMask & pipelineDiagnostics.smoothing.protectionMask < .20;
verifyGreaterThan(testCase, mean(actualFineRetention(evaluation)), .55, ...
    '普通皮肤的实际 Fine 保留率应保持在自然质感范围内。');
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

function testTamperedCacheArtifactVersionRegeneratesWithoutRgbDrift(testCase)
% 缓存 artifactVersion 被篡改时必须重建而不是误命中；复用、篡改重建
% 与无缓存三条路径的最终 RGB 必须完全一致，防止缓存复用缺陷悄悄
% 改变美颜结果。
imageSize = [120, 160];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.55 + 0.02 * sin(2 * pi * xGrid / 23) .* ...
    sin(2 * pi * yGrid / 19);
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
context.runtimeCache = buildBeautyRuntimeCache(sourceImage, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
params = struct('smoothingStrength', 80, 'whiteningStrength', 30);

[uncachedOutput, uncachedDiagnostics] = beautifyImage(sourceImage, ...
    params, faceBox, rmfield(context, 'runtimeCache'));
verifyFalse(testCase, uncachedDiagnostics.reusedRuntimeCache);
[cachedOutput, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOutput, uncachedOutput);

context.runtimeCache.artifactVersion = 'v0.0';
[tamperedOutput, tamperedDiagnostics] = beautifyImage(sourceImage, ...
    params, faceBox, context);
verifyFalse(testCase, tamperedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, tamperedDiagnostics.runtimeCache.status, ...
    'regenerated');
verifyEqual(testCase, tamperedOutput, uncachedOutput);
end

function testRuntimeEvidenceCachedUncachedAndRegeneratedAreBitExact(testCase)
% T11：runtime evidence（blemish map / frequency 分解）在 uncached、
%   cached、篡改缓存后安全重建三条路径下必须 bit-exact 一致；缓存命中
%   时直接消费缓存产物，组装的运行期 evidence 不因来源不同而改变，
%   最终 RGB 也不漂移。
imageSize = [120, 160];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.55 + 0.02 * sin(2 * pi * xGrid / 23) .* ...
    sin(2 * pi * yGrid / 19);
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
context = plainSkinContext(imageSize, faceBox);
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
context.runtimeCache = buildBeautyRuntimeCache(sourceImage, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
params = struct('smoothingStrength', 80, 'whiteningStrength', 30);

[uncachedOutput, uncachedDiagnostics] = beautifyImage(sourceImage, ...
    params, faceBox, rmfield(context, 'runtimeCache'));
verifyFalse(testCase, uncachedDiagnostics.reusedRuntimeCache);
[cachedOutput, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOutput, uncachedOutput);

% blemish map：cached == uncached == 缓存存储的产物字段（命中缓存时
%   runtime evidence 直接来自缓存产物，不重算）。
verifyEqual(testCase, cachedDiagnostics.blemishMap, ...
    uncachedDiagnostics.blemishMap, 'AbsTol', 0);
verifyEqual(testCase, cachedDiagnostics.blemishMap, ...
    context.runtimeCache.blemishMap, 'AbsTol', 0);
evidenceNames = {'fineEvidence', 'midEvidence', 'chromaEvidence', ...
    'skinCandidate'};
for index = 1:numel(evidenceNames)
    verifyEqual(testCase, ...
        cachedDiagnostics.blemish.(evidenceNames{index}), ...
        uncachedDiagnostics.blemish.(evidenceNames{index}), 'AbsTol', 0);
end

% frequency 分解：数值频带与重建误差一致（缓存诊断带版本戳，只比较
%   数值字段，不比较戳）。
bandNames = {'base', 'mid', 'fine'};
for index = 1:numel(bandNames)
    verifyEqual(testCase, ...
        cachedDiagnostics.frequency.(bandNames{index}), ...
        uncachedDiagnostics.frequency.(bandNames{index}), 'AbsTol', 0);
end
verifyEqual(testCase, cachedDiagnostics.frequency.reconstructionError, ...
    uncachedDiagnostics.frequency.reconstructionError, 'AbsTol', 0);
verifyEqual(testCase, cachedDiagnostics.frequency.fineSigma, ...
    uncachedDiagnostics.frequency.fineSigma, 'AbsTol', 0);

% 篡改缓存版本后安全重建：blemish map 与最终 RGB 仍与 uncached 一致。
context.runtimeCache.artifactVersion = 'v0.0';
[tamperedOutput, tamperedDiagnostics] = beautifyImage(sourceImage, ...
    params, faceBox, context);
verifyFalse(testCase, tamperedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, tamperedDiagnostics.runtimeCache.status, ...
    'regenerated');
verifyEqual(testCase, tamperedDiagnostics.blemishMap, ...
    uncachedDiagnostics.blemishMap, 'AbsTol', 0);
verifyEqual(testCase, tamperedOutput, uncachedOutput);
end

function testFineStageContractWiringIsBitExactAndCacheStable(testCase)
% T12/T13：生产管线（beautifyImage）把本次 beautyMasks 产物推导的
%   stage protection 传给 smoothing；Fine alphaMap 必须与独立
%   stage-contract 重算 bit-exact 一致，统计保护图保持生产原值，Mid
%   alphaMap 与 contract 派生的 midGate 重算 bit-exact（T13），cached/
%   uncached 两条路径的最终 RGB 与 Fine alphaMap 完全一致（缓存复用
%   不得改变 stage contract 的消费结果）。
imageSize = [160, 200];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.55 + 0.02 * sin(2 * pi * xGrid / 23) .* ...
    sin(2 * pi * yGrid / 19);
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
hardMask = (yGrid - 80) .^ 2 + (xGrid - 100) .^ 2 <= 12 ^ 2;
context = plainSkinContext(imageSize, faceBox, hardMask);
% 注入连续结构保护，使折叠后的 smoothingFine 覆盖 (0,1) 全程。
context.structureProtectionMask = 0.92 * exp( ...
    -((yGrid - 80) .^ 2) / (2 * 28 ^ 2));
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
params = struct('smoothingStrength', 80, 'whiteningStrength', 30);

[uncachedOutput, uncachedDiagnostics] = beautifyImage(sourceImage, ...
    params, faceBox, context);

% Fine alphaMap 与 stage contract 重算逐像素 bit-exact：
% gate = 1 - max(protection.smoothingFine, protection.hard)。
profile = beautySmoothingProfile(params.smoothingStrength);
effectStrength = profile.alphaCurve .* beautyMasks.strengthMap;
nonFacePixels = beautyMasks.nonFaceStrengthMap > .01;
effectStrength(nonFacePixels) = profile.outsideFaceStrength .* ...
    beautyMasks.nonFaceStrengthMap(nonFacePixels);
fineGate = 1 - max(protection.smoothingFine, protection.hard);
verifyEqual(testCase, uncachedDiagnostics.smoothing.alphaMap, ...
    effectStrength .* fineGate, 'AbsTol', 0);
hard = beautyMasks.hardProtectionMask >= .999;
verifyTrue(testCase, nnz(hard) > 0, ...
    '注入语义必须产生非空 hard identity 区域。');
verifyEqual(testCase, ...
    nnz(uncachedDiagnostics.smoothing.alphaMap(hard)), 0);

% 统计路径保持生产原值；T13 起 Mid 门控由 stage contract 派生为单一
% midGate（α 插值归属 effect-strength 侧的凸组合），midAlphaMap 与
% alphaMap .* midGate 逐像素 bit-exact。
verifyEqual(testCase, uncachedDiagnostics.smoothing.protectionMask, ...
    beautyMasks.protectionMask, 'AbsTol', 0);
verifyEqual(testCase, uncachedDiagnostics.smoothing.midAlphaMap, ...
    uncachedDiagnostics.smoothing.alphaMap .* ...
    uncachedDiagnostics.smoothing.midGate, 'AbsTol', 0);

% cached 路径：stage protection 从缓存的同一份 beautyMasks 产物推导，
% 最终 RGB 与 Fine alphaMap 必须 bit-exact 一致。
context.runtimeCache = buildBeautyRuntimeCache(sourceImage, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
[cachedOutput, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOutput, uncachedOutput);
verifyEqual(testCase, cachedDiagnostics.smoothing.alphaMap, ...
    uncachedDiagnostics.smoothing.alphaMap, 'AbsTol', 0);
end

function testFineRepairStageContractWiringIsEquivalent(testCase)
% T14/T15：生产管线（beautifyImage）把生产端拼装的 repair stage
%   contract 传给 repairSkinBlemishes。注入瑕疵 + 结构保护场景下，生产
%   stage 路径的 fineWeight/fineCorrection 与 legacy 直接重算逐位等价
%   （bit-exact，v3.2 texture linear gate 完整保留），T15 收口后的共享
%   referenceReliability/mediumWeight/chromaWeight 与 legacy 重算
%   bit-exact 一致；cached/uncached 两条路径的最终 RGB 与 repair 诊断
%   完全一致（缓存复用不得改变 contract 的组装与消费）。
imageSize = [160, 200];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
rng(11);
luma = 0.55 + 0.02 * sin(2 * pi * xGrid / 23) .* ...
    sin(2 * pi * yGrid / 19);
% 注入雀斑斑（真实 blemish 证据来源）与连续结构保护带，使 blemish
% 放宽量在结构保护区域内被重建。
freckleCenters = [round(60 + 50 * rand(36, 1)), ...
    round(30 + 140 * rand(36, 1))];
for index = 1:size(freckleCenters, 1)
    mask = (yGrid - freckleCenters(index, 1)) .^ 2 + ...
        (xGrid - freckleCenters(index, 2)) .^ 2 <= 4;
    luma = luma - 0.10 * mask;
end
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
hardMask = (yGrid - 100) .^ 2 + (xGrid - 60) .^ 2 <= 10 ^ 2;
context = plainSkinContext(imageSize, faceBox, hardMask);
context.structureProtectionMask = 0.92 * exp( ...
    -((yGrid - 100) .^ 2) / (2 * 30 ^ 2));
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
[frequency, ~] = beauty.decomposeSkinFrequency(sourceImage, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(sourceImage, frequency, ...
    beautyMasks);
verifyTrue(testCase, max(blemishMap(:)) > .60, ...
    '注入雀斑必须产生中高置信瑕疵证据，否则放宽量重建未被覆盖。');
verifyTrue(testCase, ...
    nnz(blemishMap(:) .* beautyMasks.structureProtectionMask(:)) > 0, ...
    '瑕疵证据必须与结构保护重叠，否则 blemish 放宽量未被覆盖。');
contract = makeRegressionRepairContract(beautyMasks, protection, ...
    blemishMap);

strengthCombos = [80, 30; 100, 0; 25, 75; 0, 100];
context.runtimeCache = buildBeautyRuntimeCache(sourceImage, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
for index = 1:size(strengthCombos, 1)
    params = struct('smoothingStrength', strengthCombos(index, 1), ...
        'whiteningStrength', strengthCombos(index, 2));
    [uncachedOutput, uncachedDiagnostics] = beautifyImage(sourceImage, ...
        params, faceBox, rmfield(context, 'runtimeCache'));
    [cachedOutput, cachedDiagnostics] = beautifyImage(sourceImage, ...
        params, faceBox, context);
    verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
    verifyEqual(testCase, cachedOutput, uncachedOutput);
    verifyEqual(testCase, cachedDiagnostics.repair.fineWeight, ...
        uncachedDiagnostics.repair.fineWeight, 'AbsTol', 0);
    verifyEqual(testCase, cachedDiagnostics.repair.fineGateRuntime, ...
        uncachedDiagnostics.repair.fineGateRuntime, 'AbsTol', 0);
    if params.smoothingStrength > 0
        verifyTrue(testCase, ...
            nnz(uncachedDiagnostics.repair.fineWeight) > 0, ...
            '瑕疵修复权重必须非零，否则等价断言无意义。');
    end

    % 生产 stage 路径与独立重算逐位等价：Fine 权重/增量 bit-exact，
    % 共享路径与重建门控 bit-exact。
    [smoothed, ~] = beauty.smoothSkinTexture(frequency, beautyMasks, ...
        params.smoothingStrength, blemishMap, protection);
    [repairedLegacy, legacyDetails] = beauty.repairSkinBlemishes( ...
        smoothed, beautyMasks, blemishMap, params.smoothingStrength);
    [repairedStage, stageDetails] = beauty.repairSkinBlemishes( ...
        smoothed, beautyMasks, blemishMap, ...
        params.smoothingStrength, contract);
    stageDiagnostics = uncachedDiagnostics.repair;
    verifyEqual(testCase, stageDiagnostics.fineWeight, ...
        legacyDetails.fineWeight, 'AbsTol', 0);
    verifyEqual(testCase, stageDiagnostics.fineCorrection, ...
        legacyDetails.fineCorrection, 'AbsTol', 0);
    verifyEqual(testCase, stageDiagnostics.fineGateRuntime, ...
        stageDetails.fineGateRuntime, 'AbsTol', 0);
    verifyEqual(testCase, stageDiagnostics.referenceReliability, ...
        legacyDetails.referenceReliability, 'AbsTol', 0);
    verifyEqual(testCase, stageDiagnostics.mediumWeight, ...
        legacyDetails.mediumWeight, 'AbsTol', 0);
    verifyEqual(testCase, stageDiagnostics.chromaWeight, ...
        legacyDetails.chromaWeight, 'AbsTol', 0);
    verifyEqual(testCase, repairedStage.fine, ...
        uncachedDiagnostics.repairResult.fine, 'AbsTol', 0);
end
end

function testComposeStageContractWiringIsBitExactAndCacheStable(testCase)
% T19：生产管线（beautifyImage）把生产端拼装的 Final Compose stage
%   contract 传给 composeBeautyResult。hard identity restore 的唯一来
%   源是 protection.hard（T07 与 legacy beautyMasks.hardProtectionMask
%   bit-exact 同值，严格二值），hard restore 在合成最终权威位置执行，
%   hard 区域最终 RGB 与源图逐位相等；生产 stage 路径的最终 RGB 与独
%   立 legacy 6 参 compose 重算逐位等价（bit-exact，T19 迁移不改变任
%   何数值）；cached/uncached 两条路径的最终 RGB 与 compose hard 诊断
%   完全一致（缓存复用不得改变 contract 的组装与消费）。
imageSize = [160, 200];
[yGrid, xGrid] = ndgrid(1:imageSize(1), 1:imageSize(2));
luma = 0.55 + 0.02 * sin(2 * pi * xGrid / 23) .* ...
    sin(2 * pi * yGrid / 19);
sourceImage = grayToUint8Rgb(luma);
faceBox = [1, 1, imageSize(2), imageSize(1)];
hardMask = (yGrid - 80) .^ 2 + (xGrid - 100) .^ 2 <= 12 ^ 2;
context = plainSkinContext(imageSize, faceBox, hardMask);
context.structureProtectionMask = 0.92 * exp( ...
    -((yGrid - 80) .^ 2) / (2 * 28 ^ 2));
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
context.runtimeCache = buildBeautyRuntimeCache(sourceImage, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
[frequency, ~] = beauty.decomposeSkinFrequency(sourceImage, faceBox);
verifyTrue(testCase, nnz(protection.hard >= .999) > 0, ...
    '注入语义必须产生非空 hard identity 区域，否则断言无意义。');
verifyTrue(testCase, all(protection.hard(:) == 0 | ...
    protection.hard(:) == 1), 'hard 必须是严格二值 identity mask。');

strengthCombos = [80, 30; 100, 0; 25, 75; 0, 100];
hardPixels = repmat(protection.hard >= .999, [1, 1, 3]);
for index = 1:size(strengthCombos, 1)
    params = struct('smoothingStrength', strengthCombos(index, 1), ...
        'whiteningStrength', strengthCombos(index, 2));
    [uncachedOutput, uncachedDiagnostics] = beautifyImage(sourceImage, ...
        params, faceBox, rmfield(context, 'runtimeCache'));
    [cachedOutput, cachedDiagnostics] = beautifyImage(sourceImage, ...
        params, faceBox, context);
    verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
    verifyEqual(testCase, cachedOutput, uncachedOutput);
    verifyEqual(testCase, ...
        cachedDiagnostics.compose.hardProtectionMask, ...
        uncachedDiagnostics.compose.hardProtectionMask, 'AbsTol', 0);

    % hard restore 权威位置：hard 区域最终 RGB 与源图逐位相等；
    % compose 的 hard 与 T07 protection 分层 bit-exact 同值。
    verifyEqual(testCase, uncachedOutput(hardPixels), ...
        sourceImage(hardPixels));
    verifyEqual(testCase, ...
        uncachedDiagnostics.compose.hardProtectionMask, ...
        protection.hard, 'AbsTol', 0);
    verifyEqual(testCase, ...
        uncachedDiagnostics.compose.hardProtectionUnchanged, 0);

    % 生产 stage 路径与独立 legacy compose 重算逐位等价：用生产诊断
    % 中未被 compose 改动的 stage 产物重建 processing 输入。
    processing = struct( ...
        'baseLuminance', uncachedDiagnostics.baseLuminanceResult, ...
        'skinTone', uncachedDiagnostics.skinToneResult, ...
        'whitening', uncachedDiagnostics.whiteningResult);
    [directOutput, directDiagnostics] = beauty.composeBeautyResult( ...
        sourceImage, frequency, uncachedDiagnostics.repairResult, ...
        beautyMasks, params.whiteningStrength, processing);
    verifyEqual(testCase, uncachedOutput, directOutput, 'AbsTol', 0);
    verifyTrue(testCase, isequaln(uncachedDiagnostics.compose, ...
        directDiagnostics), ...
        '生产 compose 诊断必须与独立 legacy 重算逐位一致。');
end
end

function contract = makeRegressionRepairContract(beautyMasks, ...
    protection, blemishMap)
%MAKEREGRESSIONREPAIRCONTRACT 复现生产端
%   makeRepairStageContract（T14/T15）的未折叠字段公式。
hard = protection.hard;
hardFeatureBand = bwdist(hard >= .999) <= 3;
strongStructure = smoothStep(beautyMasks.structureProtectionMask, ...
    .70, .90) .* double(hardFeatureBand);
contract = struct( ...
    'repairFine', protection.repairFine, ...
    'repairMid', protection.repairMid, ...
    'hard', hard, ...
    'blemishRelaxedGate', 1 - beautyMasks.structureProtectionMask .* ...
    (1 - .90 * blemishMap), ...
    'strongStructureCap', 1 - .65 * strongStructure, ...
    'textureGate', 1 - beautyMasks.textureProtectionMask, ...
    'noseMidGate', 1 - .50 * beautyMasks.noseMask);
end

function value = smoothStep(inputValue, low, high)
%SMOOTHSTEP 复现生产 smoothstep 曲线（t^2*(3-2t)）。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
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
