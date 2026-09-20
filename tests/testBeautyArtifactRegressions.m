function tests = testBeautyArtifactRegressions
%TESTBEAUTYARTIFACTREGRESSIONS 三处美颜瑕疵的量化回归断言。
% 防止调参时倒退回：眉周雀斑带“掉皮”、唇周深色描边、鼻部立体感被抹平。
% T20/T21 起新增 region policy 的 artifact 诊断对比断言（policy 路径
% vs legacy 路径：缝合、光晕、结构损失、hard identity 与缓存一致性）。
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

function testNosePolicyDoesNotWorsenSeamHaloOrStructureLoss(testCase)
% T21：nose region policy 的 artifact 诊断对比断言。同一"平坦鼻 +
%   浅鼻孔暗谷 + 鼻内雀斑"合成人像分别以 T21 policy 路径（V4 Context
%   携带 evidence）与 legacy 路径（剥离 evidence，T07 折叠）运行，用
%   现有 smoothing 诊断与输出统计比较缝合、光晕与结构损失：
%     identity —— hard 与 legacy 逐位相等（nostrilCore 已在 hard 中，
%       零膨胀），hard 区域 RGB 与源图逐位相等；
%     缝合 —— alphaMap 变化只出现在 nostril 羽化 footprint 内（带外
%       逐位等于 legacy），8 个 stage 字段在两带之外逐位等于 legacy，
%       tone 字段全图 bit-equal（无鼻部项）；
%     结构损失 —— nostril 软带内 Fine 处理量受控下降（探针实测比值
%       ≈.81），鼻孔边界边缘能量与鼻孔-鼻内低频对比度幅值不低于
%       legacy（T30 起按真实符号约定比较幅值），雀斑处 alphaMap 逐位
%       不变（雀斑仍按瑕疵处理）；
%     光晕 —— T30 激活后 whitening consumer 读 regionBandWhitening：
%       美白-only 输出带外（band == 0）逐位等于 legacy，带内变化由
%       regionBandWhitening 单字段承载（见下方归因断言）；
%     cached 与 uncached 输出逐位一致。
[sourceImage, faceBox, parsing, freckle, valleyRegion] = ...
    gentleNosePolicyFixture();
context = buildBeautyContextFromParsing(sourceImage, faceBox, parsing);
legacyContext = rmfield(context, 'evidence');
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);
[policyOut, policyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
[legacyOut, legacyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, legacyContext);

[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, context.evidence);
legacyProtection = masks.buildStageProtectionMasks(beautyMasks);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, legacyProtection.hard), ...
    'T21 不得新增或减少 hard identity 像素。');
verifyTrue(testCase, nnz(hardMask) > 0, ...
    'fixture 必须检测到鼻孔暗谷并产生非空 hard identity。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    sourceImage(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

evidence = context.evidence;
faceScale = beautyMasks.faceScale;
nostrilRadius = min(4, max(2, round(.006 * double(faceScale))));
feather = max(0, 1 - bwdist(evidence.nostril >= .999) ./ ...
    (nostrilRadius + 1));
nostrilBand = smoothStep(feather, .40, .80);
structureBand = smoothStep(evidence.noseStructure, .15, .50);
softBand = nostrilBand > .5 & ~hardMask;
verifyTrue(testCase, nnz(softBand) > 0 && nnz(structureBand > .5) > 0, ...
    'fixture 必须同时产生非空 nostril 软带与结构带。');
verifyEqual(testCase, nnz(nostrilBand > .5 & freckle), 0, ...
    '鼻孔软带不得覆盖鼻内雀斑。');

% 缝合：alphaMap 变化只出现在羽化 footprint 内；带外字段逐位还原。
alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaLegacy = legacyDiagnostics.smoothing.alphaMap;
verifyEqual(testCase, ...
    nnz((alphaPolicy ~= alphaLegacy) & feather == 0), 0, ...
    'Fine alphaMap 的变化必须局限在 nostril 羽化 footprint 内。');
outside = nostrilBand == 0 & structureBand == 0;
fieldNames = fieldnames(protection);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, protection.(fieldName)(outside), ...
        legacyProtection.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于 legacy。');
end
verifyEqual(testCase, protection.tone, legacyProtection.tone, ...
    'AbsTol', 0, 'T21 不得给 tone 增加鼻部项。');
diffMap = mean(abs(double(policyOut) - double(legacyOut)), 3);
inBandUnion = nostrilBand > 0 | structureBand > 0;
verifyEqual(testCase, nnz(diffMap(~inBandUnion) > 0), 0, ...
    '输出差异不得泄漏到 evidence 带外。');

% 结构损失：软带内 Fine 处理量下降但雀斑保持可处理；鼻孔边缘能量与
%   暗谷对比度不低于 legacy。
%   T30 符号约定：valleyContrast = mean(低频谷底) - mean(低频鼻内)，
%   鼻孔暗谷更暗时该值为负，"对比度更强"对应"更负/幅值更大"。T30 激活
%   后 nostril 保护真正进入算术，谷底保留更深（实测 policy=-0.024465
%   vs legacy=-0.023011），故按真实输出把断言改为幅值比较（算法不动）。
verifyGreaterThan(testCase, mean(alphaLegacy(softBand)), 0, ...
    'legacy 在软带内必须有非零 Fine 处理量，否则比值断言无意义。');
verifyLessThanOrEqual(testCase, mean(alphaPolicy(softBand)), ...
    .90 * mean(alphaLegacy(softBand)), ...
    'nostril 软带内 Fine 处理量必须明显低于 legacy（暗边界保留）。');
verifyEqual(testCase, alphaPolicy(freckle), alphaLegacy(freckle), ...
    'AbsTol', 0, '雀斑处的 Fine 处理量不得因鼻部 policy 改变。');
inputGray = im2double(rgb2gray(sourceImage));
edgeBefore = boundaryEdgeEnergy(inputGray, maskDiagnostics.texture.nostrilBoundary);
edgeLegacy = boundaryEdgeEnergy(im2double(rgb2gray(legacyOut)), ...
    maskDiagnostics.texture.nostrilBoundary);
edgePolicy = boundaryEdgeEnergy(im2double(rgb2gray(policyOut)), ...
    maskDiagnostics.texture.nostrilBoundary);
verifyGreaterThanOrEqual(testCase, edgePolicy, edgeLegacy - 1e-12, ...
    'policy 路径的鼻孔边界边缘能量不得低于 legacy。');
verifyGreaterThanOrEqual(testCase, ...
    abs(valleyContrast(policyOut, inputGray, valleyRegion, beautyMasks)), ...
    abs(valleyContrast(legacyOut, inputGray, valleyRegion, beautyMasks)) - 1e-12, ...
    'policy 路径的鼻孔-鼻内低频对比度幅值不得低于 legacy。');

% 光晕：T30 激活后 whitening consumer 的算术门控为
%   contract.featureGate = (1 - whitening) .* (1 - protection.regionBandWhitening)。
%   T30 激活前该断言为 bit-exact（快照不进入美白算术）；激活后改为
%   "带外 bit-exact + 带内单字段归因"：
%     * 带外（regionBandWhitening == 0）逐位等于 legacy；
%     * 带内确有可观测的假白退让差异；
%     * 差异只由 regionBandWhitening 承载——把该字段的证据来源
%       （periocular/lip/nostril）清零后输出逐位回到 legacy；把其他带
%       （regionBandBase/Mid 的 noseStructure 来源）清零则美白-only
%       输出不变，仍不等于 legacy。
whiteningParams = struct('smoothingStrength', 0, 'whiteningStrength', 100);
whiteningPolicyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    context);
whiteningLegacyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    legacyContext);
outsideWhitening = protection.regionBandWhitening == 0;
whiteningDiff = mean(abs(double(whiteningPolicyOut) - ...
    double(whiteningLegacyOut)), 3);
verifyEqual(testCase, nnz(whiteningDiff(outsideWhitening) > 0), 0, ...
    '带外（regionBandWhitening == 0）美白-only 输出必须与 legacy 逐位一致。');
verifyGreaterThan(testCase, nnz(whiteningDiff(~outsideWhitening) > 0), 0, ...
    'regionBandWhitening 带内必须出现可观测的美白退让差异。');
noWhiteningBandContext = context;
noWhiteningBandContext.evidence = zeroEvidenceFields( ...
    noWhiteningBandContext.evidence, {'periocular', 'lip', 'nostril'}, ...
    size(sourceImage, 1:2));
verifyEqual(testCase, beautifyImage(sourceImage, whiteningParams, faceBox, ...
    noWhiteningBandContext), whiteningLegacyOut, ...
    '置零 regionBandWhitening 后美白-only 输出必须逐位回到 legacy。');
noNoseStructureContext = context;
noNoseStructureContext.evidence = zeroEvidenceFields( ...
    noNoseStructureContext.evidence, {'noseStructure'}, ...
    size(sourceImage, 1:2));
verifyNotEqual(testCase, beautifyImage(sourceImage, whiteningParams, ...
    faceBox, noNoseStructureContext), whiteningLegacyOut, ...
    '置零其他带（regionBandBase/Mid 的鼻结构来源）不得抹平美白-only 差异。');
verifyGreaterThanOrEqual(testCase, min(protection.whitening(softBand)), ...
    .85 * min(nostrilBand(softBand)) - 1e-12, ...
    'whitening 字段必须在软带内携带假白光晕退让档位。');

% cached 与 uncached 输出逐位一致。
cachedContext = context;
cachedContext.runtimeCache = buildBeautyRuntimeCache(sourceImage, ...
    faceBox, beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
[cachedOut, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, cachedContext);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOut, policyOut, ...
    'cached 路径必须与 uncached 逐位一致。');
end

function testEarPolicyDoesNotWorsenSeamHaloOrStructureLoss(testCase)
%T22：ear region policy 的 artifact 诊断对比断言。合成耳部人像分别以
%   T22 policy 路径（V4 Context 携带含 earStructure 的 evidence）与
%   "无 T22"基线（只去掉 earStructure 的 evidence；T20/T21 贡献在两条
%   路径逐位同值，T21 accept 的同一隔离手法）运行，用现有 smoothing
%   诊断与输出统计比较缝合、光晕与结构损失：
%     identity —— hard 三条路径逐位相等（耳部不整耳 hard 化，零膨胀），
%       hard 区域 RGB 与源图逐位相等；
%     缝合 —— stage 字段在 ear 结构带外逐位等于无 T22 基线（tone 全图
%       bit-equal），输出差异带外不超过 1 个灰度级（生产链全局参考统计
%       的舍入），普通脸颊 Fine/Mid 处理量逐位不变；
%     结构损失 —— ear 结构带内 Fine/Mid 处理量下降（探针实测 Fine 处理
%       量下降、smoothingFine 严格抬升），带内高频细节能量不低于基线；
%     光晕 —— 美白 consumer 的算术门控不读本层快照，美白-only 输出必须
%       与基线逐位一致；
%     cached 与 uncached 输出逐位一致。
[sourceImage, faceBox, parsing, earData] = earPolicyArtifactFixture();
context = buildBeautyContextFromParsing(sourceImage, faceBox, parsing);
earOnlyContext = context;
earOnlyContext.evidence = rmfield(context.evidence, 'earStructure');
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);
[policyOut, policyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
[earOnlyOut, earOnlyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, earOnlyContext);

[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(sourceImage, ...
    context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, context.evidence);
earOnlyProtection = masks.buildStageProtectionMasks(beautyMasks, ...
    earOnlyContext.evidence);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, earOnlyProtection.hard) && ...
    nnz(hardMask) > 0, 'T22 不得新增或减少 hard identity 像素。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    sourceImage(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

ear = context.semantic.ear;
band = smoothStep(context.evidence.earStructure, .05, .30);
softBand = band > .5 & ~hardMask;
verifyGreaterThan(testCase, nnz(softBand), 0, ...
    'fixture 必须产生非空 ear 结构带。');
verifyEqual(testCase, nnz(band(ear < .20) > 0), 0, ...
    'ear 语义支持域外不得有耳结构带（耳外背景不被误纳入）。');
verifyEqual(testCase, nnz(softBand & earData.face & ear < .10), 0, ...
    '脸颊不得进入 ear 结构带。');

% 缝合：带外 stage 字段逐位还原；tone 全图 bit-equal；输出带外
% 不超过 1 个灰度级（全局参考统计的舍入响应）。
outside = band == 0;
fieldNames = fieldnames(protection);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, protection.(fieldName)(outside), ...
        earOnlyProtection.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于无 T22 基线。');
end
verifyEqual(testCase, protection.tone, earOnlyProtection.tone, ...
    'AbsTol', 0, 'T22 不得给 tone 增加耳部项。');
diffMap = mean(abs(double(policyOut) - double(earOnlyOut)), 3);
verifyLessThanOrEqual(testCase, max(diffMap(outside)), 1 + 1e-9, ...
    '输出差异带外不得超过 1 个灰度级。');
alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaEarOnly = earOnlyDiagnostics.smoothing.alphaMap;
midPolicy = policyDiagnostics.smoothing.midAlphaMap;
midEarOnly = earOnlyDiagnostics.smoothing.midAlphaMap;
cheek = ear < .10;
verifyEqual(testCase, alphaPolicy(cheek), alphaEarOnly(cheek), 'AbsTol', 0, ...
    '普通脸颊的 Fine 处理量不得因耳部 policy 改变。');
verifyEqual(testCase, midPolicy(cheek), midEarOnly(cheek), 'AbsTol', 0, ...
    '普通脸颊的 Mid 处理量不得因耳部 policy 改变。');

% 结构损失：带内 Fine/Mid 处理量下降，Mid 尺度（耳轮脊线/耳甲腔沟槽的
% 实际尺度，mediumSigma = .045*faceScale）细节能量不低于基线。
verifyTrue(testCase, any(protection.smoothingFine(softBand) > ...
    earOnlyProtection.smoothingFine(softBand)), ...
    'ear 结构带内 smoothingFine 必须严格抬升。');
verifyLessThan(testCase, mean(alphaPolicy(softBand)), ...
    mean(alphaEarOnly(softBand)), ...
    'ear 结构带内 Fine 处理量必须低于无 T22 基线。');
verifyLessThanOrEqual(testCase, mean(midPolicy(softBand)), ...
    mean(midEarOnly(softBand)) + 1e-12, ...
    'ear 结构带内 Mid 处理量不得高于无 T22 基线。');
midSigma = min(32, max(5, .045 * min(faceBox(3:4))));
grayPolicy = im2double(rgb2gray(policyOut));
grayEarOnly = im2double(rgb2gray(earOnlyOut));
hpPolicy = grayPolicy - imgaussfilt(grayPolicy, midSigma, ...
    'Padding', 'replicate');
hpEarOnly = grayEarOnly - imgaussfilt(grayEarOnly, midSigma, ...
    'Padding', 'replicate');
verifyGreaterThanOrEqual(testCase, mean(abs(hpPolicy(softBand))), ...
    mean(abs(hpEarOnly(softBand))) - 1e-12, ...
    'ear 结构带内 Mid 尺度结构能量不得低于无 T22 基线。');

% 光晕：T30 起 regionBandWhitening = max(.85·detail, .85·nostrilDetail)
%   不含耳部项（耳-颊肤色连续），故带 T22 的 policy 路径与无 T22 基线的
%   美白-only 输出仍逐位一致。
whiteningParams = struct('smoothingStrength', 0, 'whiteningStrength', 100);
whiteningPolicyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    context);
whiteningEarOnlyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    earOnlyContext);
verifyEqual(testCase, whiteningPolicyOut, whiteningEarOnlyOut, ...
    '美白-only 输出必须与无 T22 基线逐位一致（regionBandWhitening 无耳部项）。');

% cached 与 uncached 输出逐位一致。
cachedContext = context;
cachedContext.runtimeCache = buildBeautyRuntimeCache(sourceImage, ...
    faceBox, beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
[cachedOut, cachedDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, cachedContext);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOut, policyOut, ...
    'cached 路径必须与 uncached 逐位一致。');
end

function [sourceImage, faceBox, parsing, earData] = earPolicyArtifactFixture
%EARPOOLICYARTIFACTFIXTURE 合成耳部人像（与 testEarProtectionPolicy 的
%   earPolicyPortrait 同款几何）：椭圆脸 + 右耳（耳轮亮脊 + 耳甲腔暗谷
%   + 轻纹理）+ 鼻语义覆盖的两个鼻孔暗谷（提供非空 hard identity）。
%   耳内结构对比度刻意保持温和，使耳结构带的增量可被 stage 字段与
%   alphaMap 直接观测。
imageHeight = 240;
imageWidth = 320;
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = 150;
faceCenterY = 110;
faceRegion = ((xGrid - centerX) / 78) .^ 2 + ...
    ((yGrid - faceCenterY) / 95) .^ 2 <= 1;
earCenterX = centerX + 74;
earCenterY = 108;
earRegion = ((xGrid - earCenterX) / 26) .^ 2 + ...
    ((yGrid - earCenterY) / 40) .^ 2 <= 1;
helix = earRegion & ~(((xGrid - earCenterX) / 18) .^ 2 + ...
    ((yGrid - earCenterY) / 31) .^ 2 <= 1);
concha = ((xGrid - (earCenterX - 4)) / 12) .^ 2 + ...
    ((yGrid - (earCenterY + 8)) / 18) .^ 2 <= 1;
base = .60 * ones(imageHeight, imageWidth);
base(faceRegion) = .64;
base(earRegion) = .62;
base(helix) = base(helix) + .04;
base(concha) = base(concha) - .05;
base = base + .035 * sin(2 * pi * xGrid / 13) .* sin(2 * pi * yGrid / 11);
nostril = (((xGrid - (centerX - 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1) | ...
    (((xGrid - (centerX + 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1);
base(nostril) = base(nostril) - .15;
red = base * 255 + 20;
green = base * 255 - 12;
blue = base * 255 - 28;
sourceImage = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));
parsing = emptyParsing([imageHeight, imageWidth]);
parsing.regions.skin = double(faceRegion);
parsing.regionConfidence.skin = double(faceRegion);
parsing.regions.leftEar = double(earRegion);
parsing.regionConfidence.leftEar = double(earRegion);
noseRegion = ((xGrid - centerX) / 20) .^ 2 + ...
    ((yGrid - (faceCenterY + 20)) / 30) .^ 2 <= 1;
parsing.regions.nose = double(noseRegion);
parsing.regionConfidence.nose = double(noseRegion);
faceBox = [centerX - 78, faceCenterY - 95, 156, 190];
earData = struct('ear', earRegion, 'helix', helix, 'concha', concha, ...
    'face', faceRegion);
end

function [sourceImage, faceBox, parsing, freckle, valleyRegion] = ...
        gentleNosePolicyFixture
%GENTLENOSEPOLICYFIXTURE 平坦鼻 + 浅鼻孔暗谷 + 鼻内雀斑的合成人像。
%   鼻内低频梯度刻意压低（额头/下颌两条暗带抬高皮肤域梯度分位），
%   使鼻内结构保护落在 .22 下限、Fine 门打开，nostril 软带的保护
%   抬升可被 alphaMap 直接观测。
imageHeight = 200;
imageWidth = 300;
faceBox = [40, 25, 220, 160];
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = 150;
faceCenterY = 105;
faceRegion = ((xGrid - centerX) / 95) .^ 2 + ...
    ((yGrid - faceCenterY) / 78) .^ 2 <= 1;
noseRegion = ((xGrid - centerX) / 24) .^ 2 + ...
    ((yGrid - (faceCenterY + 8)) / 42) .^ 2 <= 1;
base = 0.62 * ones(imageHeight, imageWidth);
base(faceRegion) = 0.64;
tBrow = min(max((yGrid - (faceCenterY - 58)) / 2, 0), 1);
base = base - .32 * (1 - (tBrow .^ 2 .* (3 - 2 * tBrow)));
tChin = min(max(((faceCenterY + 72) - yGrid) / 2, 0), 1);
base = base - .28 * (1 - (tChin .^ 2 .* (3 - 2 * tChin))) .* faceRegion;
base = base + .006 * sin(2 * pi * xGrid / 19) .* ...
    sin(2 * pi * yGrid / 15) .* faceRegion;
red = base .* 255 + 20;
green = base .* 255 - 12;
blue = base .* 255 - 28;
valleyRegion = (((xGrid - (centerX - 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1) | ...
    (((xGrid - (centerX + 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1);
red(valleyRegion) = red(valleyRegion) - 36;
green(valleyRegion) = green(valleyRegion) - 30;
blue(valleyRegion) = blue(valleyRegion) - 26;
freckle = false(imageHeight, imageWidth);
freckleCenters = [centerX - 10, faceCenterY - 16; ...
    centerX + 10, faceCenterY - 8; centerX, faceCenterY + 6];
for index = 1:size(freckleCenters, 1)
    spot = ((xGrid - freckleCenters(index, 1)) / 2.2) .^ 2 + ...
        ((yGrid - freckleCenters(index, 2)) / 1.8) .^ 2 <= 1;
    freckle = freckle | spot;
    red(spot) = red(spot) - 46;
    green(spot) = green(spot) - 38;
    blue(spot) = blue(spot) - 30;
end
sourceImage = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));
parsing = emptyParsing([imageHeight, imageWidth]);
parsing.regions.skin = double(faceRegion);
parsing.regionConfidence.skin = double(faceRegion);
parsing.regions.nose = double(noseRegion);
parsing.regionConfidence.nose = double(noseRegion);
end

function energy = boundaryEdgeEnergy(grayImage, boundaryMask)
[gradientX, gradientY] = gradient(grayImage);
gradientMagnitude = hypot(gradientX, gradientY);
energy = mean(gradientMagnitude(boundaryMask));
end

function contrast = valleyContrast(image, ~, valleyRegion, beautyMasks)
grayImage = im2double(rgb2gray(image));
lowFrequency = imgaussfilt(grayImage, 5, 'Padding', 'replicate');
noseRoi = beautyMasks.noseMask > 0 & ~valleyRegion;
contrast = mean(lowFrequency(valleyRegion)) - ...
    mean(lowFrequency(noseRoi));
end

function testEyeLipPolicyDoesNotWorsenSeamHaloOrStructureLoss(testCase)
% T20：eye/lip identity policy 的 artifact 诊断对比断言。同一合成人像
%   分别以 T20 policy 路径（V4 Context 携带 evidence）与 legacy 路径
%   （剥离 evidence，T07 折叠）运行，用现有 smoothing/whitening 诊断
%   比较缝合、光晕与结构损失：
%     缝合 —— transition band（环带外半程）的 Fine 处理量不得低于
%       legacy（皮肤过渡带不被冻结成未处理环带）；evidence 带外的
%       alphaMap 与最终输出逐位等于 legacy（不引入新不连续）；
%     结构损失 —— detail band 内 Fine/Mid 处理量显著低于 legacy
%       （identity 细节保留；探针实测 Fine 比值≈.50、Mid 比值≈.07），
%       输出高频能量不低于 legacy；
%     光晕 —— T30 激活后 whitening consumer 读 regionBandWhitening：
%       美白-only 输出带外（band == 0）逐位等于 legacy，带内变化由
%       regionBandWhitening 单字段承载（见下方归因断言）。
[sourceImage, faceBox, context] = eyeLipPolicyFixture();
legacyContext = rmfield(context, 'evidence');
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);
[policyOut, policyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, context);
[legacyOut, legacyDiagnostics] = beautifyImage(sourceImage, params, ...
    faceBox, legacyContext);

[beautyMasks, ~] = masks.buildBeautyMasks(sourceImage, context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, context.evidence);
legacyProtection = masks.buildStageProtectionMasks(beautyMasks);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, legacyProtection.hard) && ...
    nnz(hardMask) > 0, 'T20 不得新增或减少 hard identity 像素。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    sourceImage(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

eyeField = context.evidence.periocular;
lipField = context.evidence.lip;
detailBand = max(smoothStep(eyeField, .50, .78), ...
    smoothStep(lipField, .55, .85));
transitionBand = max(smoothStep(eyeField, .08, .40), ...
    smoothStep(lipField, .12, .50)) .* (1 - detailBand);
softBand = detailBand > .5 & ~hardMask;
transitionSoft = transitionBand > .5 & ~hardMask;
outside = eyeField == 0 & lipField == 0;
verifyTrue(testCase, nnz(softBand) > 0 && nnz(transitionSoft) > 0 && ...
    nnz(outside) > 0, 'fixture 必须同时包含三带与带外区域。');

alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaLegacy = legacyDiagnostics.smoothing.alphaMap;
% 缝合：带外逐位一致 + transition band 处理量不下降。
verifyEqual(testCase, alphaPolicy(outside), alphaLegacy(outside), ...
    'AbsTol', 0, 'evidence 带外的 Fine alphaMap 必须逐位等于 legacy。');
verifyGreaterThanOrEqual(testCase, mean(alphaPolicy(transitionSoft)), ...
    mean(alphaLegacy(transitionSoft)) - 1e-12, ...
    'transition band 的 Fine 处理量不得低于 legacy（无未处理环带）。');

% 结构损失：detail band 的 Fine/Mid 处理量显著下降，高频能量保留。
verifyLessThanOrEqual(testCase, mean(alphaPolicy(softBand)), ...
    .75 * mean(alphaLegacy(softBand)), ...
    'detail band 的 Fine 处理量必须明显低于 legacy。');
verifyLessThanOrEqual(testCase, ...
    mean(policyDiagnostics.smoothing.midAlphaMap(softBand)), ...
    .40 * mean(legacyDiagnostics.smoothing.midAlphaMap(softBand)), ...
    'detail band 的 Mid 处理量必须明显低于 legacy。');
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

% 光晕：T30 激活后 whitening consumer 的算术门控为
%   contract.featureGate = (1 - whitening) .* (1 - protection.regionBandWhitening)。
%   T30 激活前该断言为 bit-exact；激活后改为"带外 bit-exact + 带内单
%   字段归因"：带外（regionBandWhitening == 0）逐位等于 legacy；带内
%   差异只由 regionBandWhitening 承载（置零该字段的证据来源
%   periocular/lip/nostril 后逐位回到 legacy；置零其他带来源不改输出）。
whiteningParams = struct('smoothingStrength', 0, 'whiteningStrength', 100);
whiteningPolicyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    context);
whiteningLegacyOut = beautifyImage(sourceImage, whiteningParams, faceBox, ...
    legacyContext);
outsideWhitening = protection.regionBandWhitening == 0;
whiteningDiff = mean(abs(double(whiteningPolicyOut) - ...
    double(whiteningLegacyOut)), 3);
verifyEqual(testCase, nnz(whiteningDiff(outsideWhitening) > 0), 0, ...
    '带外（regionBandWhitening == 0）美白-only 输出必须与 legacy 逐位一致。');
verifyGreaterThan(testCase, nnz(whiteningDiff(~outsideWhitening) > 0), 0, ...
    'regionBandWhitening 带内必须出现可观测的美白退让差异。');
noWhiteningBandContext = context;
noWhiteningBandContext.evidence = zeroEvidenceFields( ...
    noWhiteningBandContext.evidence, {'periocular', 'lip', 'nostril'}, ...
    size(sourceImage, 1:2));
verifyEqual(testCase, beautifyImage(sourceImage, whiteningParams, faceBox, ...
    noWhiteningBandContext), whiteningLegacyOut, ...
    '置零 regionBandWhitening 后美白-only 输出必须逐位回到 legacy。');
noNoseStructureContext = context;
noNoseStructureContext.evidence = zeroEvidenceFields( ...
    noNoseStructureContext.evidence, {'noseStructure', 'earStructure'}, ...
    size(sourceImage, 1:2));
verifyNotEqual(testCase, beautifyImage(sourceImage, whiteningParams, ...
    faceBox, noNoseStructureContext), whiteningLegacyOut, ...
    '置零其他带（regionBandBase/Mid 来源）不得抹平美白-only 差异。');
verifyGreaterThanOrEqual(testCase, min(protection.whitening(softBand)), ...
    .85 * min(detailBand(softBand)) - 1e-12, ...
    'whitening 字段必须在 detail band 内携带假白光晕退让。');

% 分级保护确实作用到输出：带内变化、带外零变化。
%   T30 起 regionBand* 是乘法追加保护量，其 support 是 band > 0（比
%   T20 时代的 > .5 核心 footprint 宽）；带外定义随之取真实的带
%   support（regionBand* 全零），并保持逐位（零容差）断言。
diffMap = mean(abs(double(policyOut) - double(legacyOut)), 3);
inBand = detailBand > 0 | transitionBand > 0;
verifyTrue(testCase, nnz(diffMap(inBand) > 0) > 0, ...
    '分级保护必须在带内产生可观测的输出差异。');
verifyEqual(testCase, nnz(diffMap(~inBand) > 0), 0, ...
    '输出差异不得泄漏到 regionBand* 带 support 之外（逐位一致）。');
end

function [sourceImage, faceBox, context] = eyeLipPolicyFixture
%EYLIPPOLICYFIXTURE 带眼/唇语义的合成人像（公式与
%   testPortraitBeautyHelpers 的 evidencePortraitFixture 一致风格），
%   通过生产链 buildBeautyContextFromParsing 携带 policy evidence。
imageHeight = 240;
imageWidth = 320;
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
faceWidth = round(0.46 * imageWidth);
faceHeight = round(0.73 * imageHeight);
faceX = round((imageWidth - faceWidth) / 2);
faceY = round(0.12 * imageHeight);
faceBox = [faceX, faceY, faceWidth, faceHeight];
centerX = faceX + faceWidth / 2;
centerY = faceY + faceHeight / 2;
radialDistance = ((xGrid - centerX) / (faceWidth / 2)) .^ 2 + ...
    ((yGrid - centerY) / (faceHeight / 2)) .^ 2;
faceRegion = radialDistance <= 0.82;
skinRegion = radialDistance <= 0.45;
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
eyeRegion = ((xGrid - (centerX - 38)) / 13) .^ 2 + ...
    ((yGrid - (centerY - 30)) / 6) .^ 2 <= 1;
lipRegion = ((xGrid - centerX) / 20) .^ 2 + ...
    ((yGrid - (centerY + 52)) / 6) .^ 2 <= 1;
parsing = emptyParsing([imageHeight, imageWidth]);
parsing.regions.skin = double(skinRegion);
parsing.regionConfidence.skin = double(skinRegion);
parsing.regions.leftEye = double(eyeRegion & skinRegion);
parsing.regionConfidence.leftEye = double(eyeRegion & skinRegion);
parsing.regions.upperLip = double(lipRegion & skinRegion);
parsing.regionConfidence.upperLip = double(lipRegion & skinRegion);
parsing.regions.lowerLip = double(lipRegion & skinRegion);
parsing.regionConfidence.lowerLip = double(lipRegion & skinRegion);
context = buildBeautyContextFromParsing(sourceImage, faceBox, parsing);
end

function contract = makeRegressionRepairContract(beautyMasks, ...
    protection, blemishMap)
%MAKEREGRESSIONREPAIRCONTRACT 复现生产端
%   makeRepairStageContract（T14/T15/T30）的未折叠字段公式。T30 起
%   textureGate 保持"未带"语义（全局参考采样），分级保护经
%   textureBandGate（1 - protection.regionBandFine）单独发布，只乘逐像素
%   权重。
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
    'textureBandGate', 1 - protection.regionBandFine, ...
    'noseMidGate', 1 - .50 * beautyMasks.noseMask);
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
