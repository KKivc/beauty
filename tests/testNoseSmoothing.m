function tests = testNoseSmoothing
%TESTNOSESMOOTHING 验证鼻内斑点参与磨皮且鼻部结构得到保护。
%   T21 起新增 nose region policy 断言：受控 contract 测试
%   （nostril/structure 两条证据带、hard 零膨胀、partial V4 逐位还
%   原、fail-fast）与生产链路 wiring 测试（hard RGB 回源、tone 连续、
%   雀斑 processability、cached 一致性）。
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

function testRepairRequiresValidSkinAndStrengthMasks(testCase)
% T31：repair 执行层只读取 skinMask/strengthMap（processability 与
%   strength 层），保护门全部来自 stage contract，不再校验/读取任何
%   legacy general protection mask。兼容入口（4 参）在内部向 policy 层
%   索取零带 stage protection，mask 产物不完整时仍 fail-fast。
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
blemishMap = .10 * ones(size(noseRegion));
blemishMap(noseRegion) = .95;

missing = rmfield(beautyMasks, 'skinMask');
verifyError(testCase, @() beauty.repairSkinBlemishes( ...
    frequency, missing, blemishMap, 100), ...
    'beauty:InvalidBlemishRepair');

invalid = beautyMasks;
invalid.strengthMap(1, 1) = NaN;
verifyError(testCase, @() beauty.repairSkinBlemishes( ...
    frequency, invalid, blemishMap, 100), ...
    'beauty:InvalidBlemishRepair');

incomplete = rmfield(beautyMasks, 'textureProtectionMask');
verifyError(testCase, @() beauty.repairSkinBlemishes( ...
    frequency, incomplete, blemishMap, 100), 'masks:InvalidMasks', ...
    '兼容入口必须向 policy 层索取 stage protection 并在 mask 不完整时 fail-fast。');
end

function testRepairTargetProtectionScalesFaceAndNonFaceRepair(testCase)
% T31：逐像素修复权重由 stage contract 的 target 门（纹理退让保护）
%   线性缩放，脸部与脸外一致；参考池统计由 support 门（与 target 门
%   解耦）单独缩放。只改 target/support 门、不改 blemish 证据即可验证
%   二者独立。
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
imageSize = size(noseRegion);
faceBlemish = false(imageSize);
faceBlemish(48:52, 70:74) = true;
nonFaceBlemish = false(imageSize);
nonFaceBlemish(90:94, 110:114) = true;
blemishMap = .10 * ones(imageSize);
blemishMap(faceBlemish | nonFaceBlemish) = .95;
beautyMasks.nonFaceStrengthMap(nonFaceBlemish) = 1;

protection = masks.buildStageProtectionMasks(beautyMasks);
protectedProtection = protection;
protectedProtection.support.repairFine = .50 * ones(imageSize);
protectedProtection.target.repairFine = .50 * ones(imageSize);

baselineContract = beauty.repairStageContract(protection, blemishMap);
protectedContract = beauty.repairStageContract(protectedProtection, blemishMap);

[~, baseline] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100, baselineContract);
[~, protected] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100, protectedContract);

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

function testNosePolicyBandsFollowEvidenceContract(testCase)
%TESTNOSEPOLICYBANDSFOLLOWEVIDENCECONTRACT T21 nose region policy 的受控
%   contract 断言（直接调用 buildStageProtectionMasks，屏蔽几何噪声），
%   范式与 T20 的 eye/lip policy contract 测试一致：
%     identity core —— hard 字段与输入 hardProtectionMask 逐位相等，
%       不新增任何 hard 像素（nostrilCore 已在 hard 中）；
%     nostril detail band —— band=1 像素抬升到固定档位
%       smoothingFine/repairFine=.95（与 v3.1 nostrilProtection 峰值
%       对齐）、smoothingMid=.90（与 T20 检测细节档位一致）、
%       regionBandBase=.95（baseLuminance 分级保护，T32 起经纯 policy
%       带注入）、whitening=.85；repairMid 的 .90 是 max 下界，
%       core 内因 (1 - policyTexture) 项实际为 .95（同 T20 约定）；
%       tone 保持 legacy（鼻部无 identity 色度语义，肤色变化与脸颊
%       连续）；
%     nose structure band —— band=1 像素抬升 smoothingMid/repairMid=
%       .85、regionBandBase=.80（baseLuminance 分级保护）；
%       smoothingFine/repairFine/whitening/tone 保持 legacy（结构带不进
%       texture 通道、不阻断美白）；
%     evidence 零带或缺少 nostril/noseStructure 字段（partial V4）时
%       与 T07 legacy 折叠逐位相等；带外像素逐位还原 legacy；
%     非法 evidence（尺寸/取值）或 nostril 证据非零而缺少 faceScale
%       时 fail-fast。
[fixture, evidence] = nosePolicyUnitFixture();
legacy = masks.buildStageProtectionMasks(fixture.masks);
policy = masks.buildStageProtectionMasks(fixture.masks, evidence);

% identity core：hard 原样拷贝，不新增任何 hard 像素。
verifyEqual(testCase, policy.hard, fixture.hardIdentity, 'AbsTol', 0);
corePoint = fixture.corePoint;
verifyEqual(testCase, ...
    policy.target.smoothingFine(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.target.smoothingMid(corePoint(1), corePoint(2)), .90, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.target.repairFine(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
% repairMid 的 .90 是 max 下界；identity core 内 policyTexture 已被抬到
% .95，(1 - policyTexture) 项使实际值升到 .95（与 T20 eye/lip detail
% band 的同一约定一致：repairMid = 1 - gate*(1-texture) 先于 max 下界）。
verifyEqual(testCase, ...
    policy.target.repairMid(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
% T32：baseLuminance 的鼻带分级保护经纯 policy 带 regionBandBase 承载
% （消费侧 regionBandGate = 1 - regionBandBase），不再折进
% target.baseLuminance。
verifyEqual(testCase, ...
    policy.regionBandBase(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.whitening(corePoint(1), corePoint(2)), .85, 'AbsTol', 1e-12);
verifyEqual(testCase, policy.tone(corePoint(1), corePoint(2)), ...
    legacy.tone(corePoint(1), corePoint(2)), 'AbsTol', 0, ...
    '鼻部无 identity 色度语义，tone 不得被鼻带抬升。');

% nose structure band：只抬升 Mid 家族与 regionBandBase。
ridgePoint = fixture.ridgePoint;
verifyEqual(testCase, ...
    policy.target.smoothingMid(ridgePoint(1), ridgePoint(2)), .85, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.regionBandBase(ridgePoint(1), ridgePoint(2)), .80, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.target.smoothingFine(ridgePoint(1), ridgePoint(2)), ...
    legacy.target.smoothingFine(ridgePoint(1), ridgePoint(2)), 'AbsTol', 0, ...
    '结构带不得进入 texture 通道（鼻梁 Fine 处理量保持 legacy）。');
verifyEqual(testCase, ...
    policy.target.repairFine(ridgePoint(1), ridgePoint(2)), ...
    legacy.target.repairFine(ridgePoint(1), ridgePoint(2)), 'AbsTol', 0);
verifyEqual(testCase, ...
    policy.whitening(ridgePoint(1), ridgePoint(2)), ...
    legacy.whitening(ridgePoint(1), ridgePoint(2)), 'AbsTol', 0, ...
    '鼻梁/鼻翼结构不得阻断美白（美白与脸颊连续）。');

% 平坦鼻皮肤（evidence 低于下支撑点）：两带皆零，保持 processability。
flatPoint = fixture.flatPoint;
flatPolicy = flattenProtection(policy);
flatLegacy = flattenProtection(legacy);
fieldNames = fieldnames(flatPolicy);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, ...
        flatPolicy.(fieldName)(flatPoint(1), flatPoint(2)), ...
        flatLegacy.(fieldName)(flatPoint(1), flatPoint(2)), 'AbsTol', 0, ...
        '普通鼻皮肤零带，stage 字段必须逐位等于 legacy。');
end

% 证据零带（partial V4 / 缺字段 / 缺省输入）：与 legacy 逐位相等。
zeroEvidence = struct('nostril', zeros(fixture.imageSize), ...
    'noseStructure', zeros(fixture.imageSize));
missingEvidence = struct('periocular', zeros(fixture.imageSize), ...
    'lip', zeros(fixture.imageSize));
for variant = {zeroEvidence, missingEvidence}
    zeroPolicy = flattenProtection(masks.buildStageProtectionMasks( ...
        fixture.masks, variant{1}));
    for fieldIndex = 1:numel(fieldNames)
        fieldName = fieldNames{fieldIndex};
        verifyEqual(testCase, zeroPolicy.(fieldName), ...
            flatLegacy.(fieldName), 'AbsTol', 0);
    end
end
singleArgPolicy = flattenProtection(masks.buildStageProtectionMasks( ...
    fixture.masks));
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, singleArgPolicy.(fieldName), ...
        flatLegacy.(fieldName), 'AbsTol', 0);
end

% 带外（两带皆零的像素）逐位还原 legacy。
feather = max(0, 1 - bwdist(evidence.nostril >= .999) ./ 3);
nostrilBand = smoothStepValue(feather, .40, .80);
structureBand = smoothStepValue(evidence.noseStructure, .15, .50);
outside = nostrilBand == 0 & structureBand == 0;
verifyTrue(testCase, nnz(outside) > 0, 'fixture 必须包含带外像素。');
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, flatPolicy.(fieldName)(outside), ...
        flatLegacy.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于 legacy。');
end

% 非法 evidence fail-fast，不静默修正。
badSize = evidence;
badSize.nostril = evidence.nostril(1:10, 1:10);
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badSize), 'masks:InvalidEvidence');
badRange = evidence;
badRange.noseStructure = evidence.noseStructure * 2;
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badRange), 'masks:InvalidEvidence');
badNaN = evidence;
badNaN.nostril = evidence.nostril;
badNaN.nostril(2, 2) = NaN;
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badNaN), 'masks:InvalidEvidence');
masksNoScale = rmfield(fixture.masks, 'faceScale');
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    masksNoScale, evidence), 'masks:InvalidMasks', ...
    'nostril 证据非零而缺少 faceScale 时必须 fail-fast。');
end

function testNosePolicyWiringPreservesIdentityAndProcessability(testCase)
%TESTNOSEPOLICYWIRINGPRESERVESIDENTITYANDPROCESSABILITY T21 生产链路
%   （beautifyImage 经 bridge evidence 转发）端到端断言：
%     identity —— hard 与 legacy 逐位相等（零膨胀），hard 区域 RGB 与
%       源图逐位相等；
%     processability —— 鼻内雀斑不进入 nostril 软带，雀斑处 alphaMap
%       逐位不变（雀斑仍按瑕疵处理）；普通鼻皮肤带外 8 字段逐位等于
%       legacy；
%     tone 字段全图逐位等于 legacy（无鼻部项，肤色与脸颊连续）；
%     nostril 软带内 Fine 处理量受控下降（探针实测比值≈.81，阈值
%       .90 留几何余量）；repairFine 在带内严格抬升（快照先行发布）；
%     美白-only 输出带外（regionBandWhitening == 0）与 legacy 逐位一致，
%       带内差异由 regionBandWhitening 单字段承载（T30 激活）；
%     cached 与 uncached 输出逐位一致。
%   夹具说明：Fine 处理量下降只能在鼻内结构保护未饱和（Fine 门打开）
%   的人像上观测。高结构脊的合成鼻（syntheticNosePortrait）在 nostril
%   软带内 legacy smoothingFine 已为 1、alphaMap 恒为 0，比值断言无
%   法成立；故本测试使用平坦鼻夹具 gentleNosePolicyPortrait（与
%   t21_probe3 / T21 artifact 回归同一几何，探针实测比值≈.81）。
[image, faceBox, noseData] = gentleNosePolicyPortrait();
parsing = parsingForPortrait(size(image, [1, 2]), noseData);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
bareContext = context;
legacyContext = rmfield(bareContext, 'evidence');
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);

[policyOut, policyDiagnostics] = beautifyImage(image, params, faceBox, ...
    bareContext);
[legacyOut, legacyDiagnostics] = beautifyImage(image, params, faceBox, ...
    legacyContext);

[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, ...
    bareContext, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, ...
    bareContext.evidence);
legacyProtection = masks.buildStageProtectionMasks(beautyMasks);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, legacyProtection.hard), ...
    'T21 不得改变 hard identity（nostrilCore 已在 hard 中，零膨胀）。');
verifyTrue(testCase, nnz(hardMask) > 0, ...
    '合成鼻孔必须产生非空 hard identity 区域。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    image(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

evidence = bareContext.evidence;
faceScale = beautyMasks.faceScale;
nostrilRadius = min(4, max(2, round(.006 * double(faceScale))));
feather = max(0, 1 - bwdist(evidence.nostril >= .999) ./ ...
    (nostrilRadius + 1));
nostrilBand = smoothStepValue(feather, .40, .80);
structureBand = smoothStepValue(evidence.noseStructure, .15, .50);
softBand = nostrilBand > .5 & ~hardMask;
verifyTrue(testCase, nnz(softBand) > 0, ...
    'fixture 必须产生非空 nostril 软带。');

% 雀斑 processability：软带与雀斑不相交，雀斑 alphaMap 逐位不变。
verifyEqual(testCase, nnz(nostrilBand > .5 & noseData.freckle), 0, ...
    '鼻孔软带不得覆盖鼻内雀斑。');
alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaLegacy = legacyDiagnostics.smoothing.alphaMap;
verifyEqual(testCase, alphaPolicy(noseData.freckle), ...
    alphaLegacy(noseData.freckle), 'AbsTol', 0, ...
    '雀斑处的 Fine 处理量不得因鼻部 policy 改变。');

% tone 字段全图 bit-equal（无鼻部项）；T30 激活后 whitening consumer 的
%   算术门控为 contract.featureGate = (1 - whitening) .*
%   (1 - protection.regionBandWhitening)，故美白-only 断言由 bit-exact
%   改为"带外 bit-exact + 带内单字段归因"：
%     * 带外（regionBandWhitening == 0）逐位等于 legacy；
%     * 带内确有可观测的假白退让差异；
%     * 差异只由 regionBandWhitening 承载——置零该字段的证据来源
%       （periocular/lip/nostril）后逐位回到 legacy；置零其他带来源
%       （noseStructure）则美白-only 输出不变，仍不等于 legacy。
verifyEqual(testCase, protection.tone, legacyProtection.tone, 'AbsTol', 0, ...
    'T21 不得给 tone 增加鼻部项（肤色与脸颊连续）。');
whiteningParams = struct('smoothingStrength', 0, 'whiteningStrength', 100);
whiteningPolicyOut = beautifyImage(image, whiteningParams, faceBox, ...
    bareContext);
whiteningLegacyOut = beautifyImage(image, whiteningParams, faceBox, ...
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
    size(image, 1:2));
verifyEqual(testCase, beautifyImage(image, whiteningParams, faceBox, ...
    noWhiteningBandContext), whiteningLegacyOut, ...
    '置零 regionBandWhitening 后美白-only 输出必须逐位回到 legacy。');
noNoseStructureContext = bareContext;
noNoseStructureContext.evidence = zeroEvidenceFields( ...
    noNoseStructureContext.evidence, {'noseStructure'}, size(image, 1:2));
verifyNotEqual(testCase, beautifyImage(image, whiteningParams, faceBox, ...
    noNoseStructureContext), whiteningLegacyOut, ...
    '置零其他带（regionBandBase/Mid 的鼻结构来源）不得抹平美白-only 差异。');

% nostril 软带：Fine 处理量受控下降，保护字段不低于 legacy，
% repairFine 快照在带内严格抬升。
verifyGreaterThan(testCase, mean(alphaLegacy(softBand)), 0, ...
    'legacy 在软带内必须有非零 Fine 处理量，否则比值断言无意义。');
verifyLessThanOrEqual(testCase, mean(alphaPolicy(softBand)), ...
    .90 * mean(alphaLegacy(softBand)), ...
    'nostril 软带内 Fine 处理量必须明显低于 legacy（暗边界保留）。');
verifyGreaterThanOrEqual(testCase, ...
    min(protection.target.smoothingMid(softBand) - ...
    legacyProtection.target.smoothingMid(softBand)), 0);
verifyGreaterThanOrEqual(testCase, ...
    min(protection.target.repairMid(softBand) - ...
    legacyProtection.target.repairMid(softBand)), 0);
verifyTrue(testCase, any(protection.target.repairFine(softBand) > ...
    legacyProtection.target.repairFine(softBand)), ...
    'nostril 软带内 repairFine 快照必须严格抬升。');

% 带外（两带皆零）：全部 stage 叶子字段逐位等于 legacy。
outside = nostrilBand == 0 & structureBand == 0;
flatProtection = flattenProtection(protection);
flatLegacyProtection = flattenProtection(legacyProtection);
fieldNames = fieldnames(flatProtection);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, flatProtection.(fieldName)(outside), ...
        flatLegacyProtection.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于 legacy。');
end

% cached 与 uncached 输出逐位一致。
cachedContext = context;
cachedContext.runtimeCache = buildBeautyRuntimeCache(image, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '回归测试生成运行时产物。'));
[cachedOut, cachedDiagnostics] = beautifyImage(image, params, faceBox, ...
    cachedContext);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOut, policyOut, ...
    'cached 路径必须与 uncached 逐位一致。');
end

function testNoseMidGateIsContinuousAndUsesCommonEvidence(testCase)
% T31：Mid 鼻部退让门只来自 stage contract 的 target.repairMid
%   （= protection.noseMidProtection，policy 层发布 .50·nose），算法侧
%   不再读取 noseMask。鼻门是连续量：连续抬升保护 → mediumWeight 连续
%   下降（比例恰为 1 - 保护），Fine 权重与 blemish 证据完全不受影响
%   （Blemish ≠ Should Repair：证据与 target 门独立）。
[frequency, beautyMasks, noseRegion] = standaloneRepairFixture();
blemishMap = .10 * ones(size(noseRegion));
blemishMap(noseRegion) = .95;
protection = masks.buildStageProtectionMasks(beautyMasks);

zeroProtection = protection;
zeroProtection.noseMidProtection = zeros(size(noseRegion));
halfProtection = protection;
halfProtection.noseMidProtection = .25 * double(noseRegion);
fullProtection = protection;
fullProtection.noseMidProtection = .50 * double(noseRegion);

[~, ordinary] = beauty.repairSkinBlemishes(frequency, beautyMasks, ...
    blemishMap, 100, beauty.repairStageContract(zeroProtection, blemishMap));
[~, halfNose] = beauty.repairSkinBlemishes(frequency, beautyMasks, ...
    blemishMap, 100, beauty.repairStageContract(halfProtection, blemishMap));
[~, fullNose] = beauty.repairSkinBlemishes(frequency, beautyMasks, ...
    blemishMap, 100, beauty.repairStageContract(fullProtection, blemishMap));

verifyEqual(testCase, halfNose.fineWeight, ordinary.fineWeight, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, fullNose.fineWeight, ordinary.fineWeight, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, fullNose.repairEvidence, ordinary.repairEvidence, ...
    'AbsTol', 1e-12);
verifyGreaterThan(testCase, max(ordinary.highEndConfidence(noseRegion)), 0);
verifyEqual(testCase, unique(halfNose.targetMidGate(noseRegion)), .75, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, unique(fullNose.targetMidGate(noseRegion)), .50, ...
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

function [fixture, evidence] = nosePolicyUnitFixture
%NOSEPOLICYUNITFIXTURE 构造受控 Beauty Masks 与鼻部 evidence（40x60）：
%   两个 nostrilCore 块（hard identity，羽化半径按 faceScale=120 为 2px）、
%   一条 noseStructure=1 的结构脊、一块 evidence=.05 的平坦皮肤
%   （低于 .15 下支撑点，两带皆零）。掩码其余通道全部为零，隔离
%   geometry 噪声，使档位断言精确。
imageSize = [40, 60];
nostrilCore = false(imageSize);
nostrilCore(29:32, 20:23) = true;
nostrilCore(29:32, 34:37) = true;
noseStructureEvidence = zeros(imageSize);
noseStructureEvidence(12:13, 15:45) = 1;
noseStructureEvidence(20:27, 10:50) = .05;
evidence = struct('nostril', double(nostrilCore), ...
    'noseStructure', noseStructureEvidence);
fixture = struct( ...
    'imageSize', imageSize, ...
    'hardIdentity', double(nostrilCore), ...
    'corePoint', [30, 21], ...
    'ridgePoint', [12, 30], ...
    'flatPoint', [24, 30], ...
    'masks', unitNoseMasks(double(nostrilCore), imageSize));
end

function masksStruct = unitNoseMasks(hard, imageSize)
%UNITNOSEMASKS 构建只含 buildStageProtectionMasks 必需字段的 mask 产物。
masksStruct = struct( ...
    'textureProtectionMask', zeros(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'chromaProtectionMask', zeros(imageSize), ...
    'whiteningProtectionMask', zeros(imageSize), ...
    'hardProtectionMask', hard, ...
    'noseMask', zeros(imageSize), ...
    'faceSkinMask', zeros(imageSize), ...
    'faceScale', 120);
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

function value = smoothStepValue(inputValue, low, high)
%SMOOTHSTEPVALUE 复现生产 smoothstep 曲线（t^2*(3-2t)）。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
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

function [image, faceBox, masks] = gentleNosePolicyPortrait
%GENTLENOSEPOLICYPORTRAIT 平坦鼻 + 浅鼻孔暗谷 + 鼻内雀斑的合成人像
%   （与 t21_probe3 及 T21 artifact 回归夹具同一几何）。额头/下颌两条
%   暗带抬高皮肤域梯度分位、压低鼻内低频梯度，使鼻内结构保护落在
%   .22 下限、Fine 门打开——nostril 软带内的保护抬升才能被 alphaMap
%   直接观测。鼻孔软带与鼻内雀斑保持不相交。
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
nostril = (((xGrid - (centerX - 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1) | ...
    (((xGrid - (centerX + 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1);
red(nostril) = red(nostril) - 36;
green(nostril) = green(nostril) - 30;
blue(nostril) = blue(nostril) - 26;
freckle = false(imageHeight, imageWidth);
centers = [centerX - 10, faceCenterY - 16; centerX + 10, ...
    faceCenterY - 8; centerX, faceCenterY + 6];
for index = 1:size(centers, 1)
    spot = ((xGrid - centers(index, 1)) / 2.2) .^ 2 + ...
        ((yGrid - centers(index, 2)) / 1.8) .^ 2 <= 1;
    freckle = freckle | spot;
    red(spot) = red(spot) - 46;
    green(spot) = green(spot) - 38;
    blue(spot) = blue(spot) - 30;
end
image = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));
masks = struct('skin', faceRegion, 'nose', noseRegion, ...
    'freckle', freckle, 'nostril', nostril);
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
    'chromaProtectionMask', zeros(imageSize), ...
    'whiteningProtectionMask', zeros(imageSize), ...
    'hardProtectionMask', zeros(imageSize), ...
    'noseMask', double(noseRegion), ...
    'faceSkinMask', ones(imageSize), ...
    'faceScale', 100, ...
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

function flat = flattenProtection(protection)
%FLATTENPROTECTION 把 T31 双门控嵌套展平为 <group>_<name> 叶子字段。
%   protection.target.* / protection.support.* 为标量结构，无法直接按
%   像素索引；逐字段 bit-exact 比较循环需要叶子级字段名，故展平为
%   target_smoothingFine / support_repairMid 等扁平名（顶层扁平字段
%   原样保留）。仅测试辅助，不改变任何生产语义。
flat = struct();
names = fieldnames(protection);
for index = 1:numel(names)
    name = names{index};
    value = protection.(name);
    if isstruct(value) && isscalar(value)
        innerNames = fieldnames(value);
        for innerIndex = 1:numel(innerNames)
            flat.([name '_' innerNames{innerIndex}]) = ...
                value.(innerNames{innerIndex});
        end
    else
        flat.(name) = value;
    end
end
end
