function tests = testColorSensitiveProtectionPolicy
%TESTCOLORSENSITIVEPROTECTIONPOLICY 验证颜色敏感皮肤证据构建及在 Base/Tone/Whitening 的退让策略。
%   v3.3 新增 colorSensitiveSkin：
%     - 证据层：只在可处理面部皮肤内非零；由原图 YCbCr Cb/Cr 偏差分位归一构建；
%       排除 hard 与高风险区；参考样本不足时显式报告诊断，不静默伪造；
%     - 策略层：不增加 stageProtection 公共字段；
%       不得影响 smoothingFine/smoothingMid/repairFine/repairMid；
%       只进入 Base/Tone/Whitening 的 target 与 support；
%     - 生产端：0 强度返回源图，缓存与无缓存逐位一致。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testColorSensitiveSkinEvidenceContract(testCase)
%TESTCOLORSENSITIVEPOSITIONSKIN CONTRACT 验证证据层规范
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, metadata] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

verifyTrue(testCase, isfield(evidence, 'colorSensitiveSkin'), ...
    'evidence 结构必须包含 colorSensitiveSkin 字段。');
field = evidence.colorSensitiveSkin;
verifyClass(testCase, field, 'double');
verifySize(testCase, field, size(image, [1, 2]));
verifyTrue(testCase, all(isfinite(field(:))));
verifyGreaterThanOrEqual(testCase, min(field(:)), 0);
verifyLessThanOrEqual(testCase, max(field(:)), 1);

% 验证只在可处理面部皮肤内非零
faceSkin = context.faceSkinMask;
skin = context.skinMask;
processableFaceSkin = min(faceSkin, skin) > .05;
verifyEqual(testCase, nnz(field(~processableFaceSkin) > 0), 0, ...
    'colorSensitiveSkin 在可处理面部皮肤外必须严格为零。');

% 验证 metadata 包含明确来源与诊断
verifyTrue(testCase, isfield(metadata.sources, 'colorSensitiveSkin'), ...
    'metadata.sources 必须登记 colorSensitiveSkin。');
verifyTrue(testCase, isfield(metadata, 'colorSensitiveSkinDiagnostics'), ...
    'metadata 必须包含 colorSensitiveSkinDiagnostics 显式诊断。');
verifyTrue(testCase, metadata.colorSensitiveSkinDiagnostics.valid, ...
    '正常人像测试夹具的参考样本诊断必须为 valid=true。');
end

function testInsufficientReferenceExplicitDiagnostics(testCase)
%TESTINSUFFICIENTREFERENCEEXPLICITDIAGNOSTICS 验证参考不足时显式诊断，不静默伪造
[image, faceBox, context] = syntheticPortraitFixture();
% 构造几乎无普通皮肤的极端情景（使参考样本 < minRequired）
context.skinMask = zeros(size(context.skinMask));
context.faceSkinMask = zeros(size(context.faceSkinMask));
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, metadata] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

verifyEqual(testCase, evidence.colorSensitiveSkin, zeros(size(image, [1, 2])), ...
    '无有效参考皮肤时，colorSensitiveSkin 必须全零。');
verifyFalse(testCase, metadata.colorSensitiveSkinDiagnostics.valid, ...
    '参考样本不足时，必须显式诊断 valid=false，不得静默伪造成功。');
end

function testColorSensitiveSkinStageProtectionContract(testCase)
%TESTCOLORSENSITIVESKINSSTAGEPROTECTIONCONTRACT 验证策略层消费契约
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, faceBox, maskDiagnostics);

% 无 colorSensitiveSkin 的基准保护
evidenceNoSensitive = rmfield(evidence, 'colorSensitiveSkin');
legacyProtection = masks.buildStageProtectionMasks(beautyMasks, evidenceNoSensitive);
policyProtection = masks.buildStageProtectionMasks(beautyMasks, evidence);

% 1. 不得新增 stage contract 公共字段
legacyFields = fieldnames(legacyProtection);
policyFields = fieldnames(policyProtection);
verifyEqual(testCase, policyFields, legacyFields, ...
    'buildStageProtectionMasks 不得新增公共字段。');

% 2. 不得影响 smoothingFine/smoothingMid/repairFine/repairMid
verifyEqual(testCase, policyProtection.target.smoothingFine, ...
    legacyProtection.target.smoothingFine, 'AbsTol', 0, ...
    'colorSensitiveSkin 不得影响 target.smoothingFine。');
verifyEqual(testCase, policyProtection.target.smoothingMid, ...
    legacyProtection.target.smoothingMid, 'AbsTol', 0, ...
    'colorSensitiveSkin 不得影响 target.smoothingMid。');
verifyEqual(testCase, policyProtection.target.repairFine, ...
    legacyProtection.target.repairFine, 'AbsTol', 0, ...
    'colorSensitiveSkin 不得影响 target.repairFine。');
verifyEqual(testCase, policyProtection.target.repairMid, ...
    legacyProtection.target.repairMid, 'AbsTol', 0, ...
    'colorSensitiveSkin 不得影响 target.repairMid。');
verifyEqual(testCase, policyProtection.support.smoothingFine, ...
    legacyProtection.support.smoothingFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.smoothingMid, ...
    legacyProtection.support.smoothingMid, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.repairFine, ...
    legacyProtection.support.repairFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.repairMid, ...
    legacyProtection.support.repairMid, 'AbsTol', 0);

% 3. 只进入 Base/Tone/Whitening 的 target 与 support
verifyGreaterThanOrEqual(testCase, ...
    min(policyProtection.target.baseLuminance(:) - legacyProtection.target.baseLuminance(:)), 0, ...
    'target.baseLuminance 保护只增不减。');
verifyGreaterThanOrEqual(testCase, ...
    min(policyProtection.support.baseLuminance(:) - legacyProtection.support.baseLuminance(:)), 0, ...
    'support.baseLuminance 保护只增不减。');
verifyGreaterThanOrEqual(testCase, ...
    min(policyProtection.target.tone(:) - legacyProtection.target.tone(:)), 0, ...
    'target.tone 保护只增不减。');
verifyGreaterThanOrEqual(testCase, ...
    min(policyProtection.target.whitening(:) - legacyProtection.target.whitening(:)), 0, ...
    'target.whitening 保护只增不减。');

% 4. 保持 hard 独立
verifyEqual(testCase, policyProtection.hard, legacyProtection.hard, 'AbsTol', 0, ...
    'hard identity 必须完全独立不变。');
end

function testColorSensitiveExecutionGatesWiring(testCase)
%TESTCOLORSENSITIVEEXECUTIONGATESWIRING 验证非零 evidence 降低执行门并与 target 快照语义一致
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, faceBox, maskDiagnostics);

sensitiveMask = evidence.colorSensitiveSkin > 0.05;
verifyGreaterThan(testCase, nnz(sensitiveMask), 50, '测试夹具必须包含足够的敏感像素。');

policyProtection = masks.buildStageProtectionMasks(beautyMasks, evidence);
evidenceNoSensitive = rmfield(evidence, 'colorSensitiveSkin');
legacyProtection = masks.buildStageProtectionMasks(beautyMasks, evidenceNoSensitive);

% 1. 执行门降低断言：非零敏感像素处必须严格降低实际 feature gate
gateDiffTone = policyProtection.toneGates.featureGate(sensitiveMask) - ...
    legacyProtection.toneGates.featureGate(sensitiveMask);
verifyLessThan(testCase, max(gateDiffTone), 0, ...
    '非零 colorSensitiveSkin 必须严格降低 Tone 主分支 featureGate。');

gateDiffUniform = policyProtection.toneGates.uniformFeatureGate(sensitiveMask) - ...
    legacyProtection.toneGates.uniformFeatureGate(sensitiveMask);
verifyLessThan(testCase, max(gateDiffUniform), 0, ...
    '非零 colorSensitiveSkin 必须严格降低 Tone uniform 分支 uniformFeatureGate。');

gateDiffWhite = policyProtection.whiteningGates.featureGate(sensitiveMask) - ...
    legacyProtection.whiteningGates.featureGate(sensitiveMask);
verifyLessThan(testCase, max(gateDiffWhite), 0, ...
    '非零 colorSensitiveSkin 必须严格降低 Whitening 分支 featureGate。');

% 2. target 快照与未折叠门控语义一致性断言（残差 <= 1e-15）
verifyLessThanOrEqual(testCase, max(abs( ...
    policyProtection.toneGates.structureGate(:) .* ...
    policyProtection.toneGates.featureGate(:) - ...
    (1 - policyProtection.target.tone(:)))), 1e-15, ...
    'target.tone 快照必须与 Tone 实际未折叠门控语义严格一致。');

verifyLessThanOrEqual(testCase, max(abs( ...
    policyProtection.whiteningGates.structureGate(:) .* ...
    policyProtection.whiteningGates.featureGate(:) - ...
    (1 - policyProtection.target.whitening(:)))), 1e-15, ...
    'target.whitening 快照必须与 Whitening 实际未折叠门控语义严格一致。');

% 3. 零证据区域逐位一致（Bit-Exact）
nonSensitive = evidence.colorSensitiveSkin == 0;
verifyEqual(testCase, policyProtection.toneGates.featureGate(nonSensitive), ...
    legacyProtection.toneGates.featureGate(nonSensitive), 'AbsTol', 0, ...
    '敏感度为 0 区域 Tone 主分支 featureGate 必须与零证据基准逐位一致。');
verifyEqual(testCase, policyProtection.toneGates.uniformFeatureGate(nonSensitive), ...
    legacyProtection.toneGates.uniformFeatureGate(nonSensitive), 'AbsTol', 0, ...
    '敏感度为 0 区域 Tone uniform 分支 featureGate 必须逐位一致。');
verifyEqual(testCase, policyProtection.whiteningGates.featureGate(nonSensitive), ...
    legacyProtection.whiteningGates.featureGate(nonSensitive), 'AbsTol', 0, ...
    '敏感度为 0 区域 Whitening featureGate 必须逐位一致。');
verifyEqual(testCase, policyProtection.target.tone(nonSensitive), ...
    legacyProtection.target.tone(nonSensitive), 'AbsTol', 0, ...
    '敏感度为 0 区域 target.tone 必须逐位一致。');
verifyEqual(testCase, policyProtection.target.whitening(nonSensitive), ...
    legacyProtection.target.whitening(nonSensitive), 'AbsTol', 0, ...
    '敏感度为 0 区域 target.whitening 必须逐位一致。');
end

function testToneAndWhiteningConsumerDeltaReduction(testCase)
%TESTTONEANDWHITENINGCONSUMERDELTAREDUCTION 验证相同输入下敏感区实际修改量显著减小
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, faceBox, maskDiagnostics);

sensitiveMask = evidence.colorSensitiveSkin > 0.05;
nonSensitive = evidence.colorSensitiveSkin == 0;

[freq, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, freq, beautyMasks);

policyProtection = masks.buildStageProtectionMasks(beautyMasks, evidence);
evidenceNoSensitive = rmfield(evidence, 'colorSensitiveSkin');
legacyProtection = masks.buildStageProtectionMasks(beautyMasks, evidenceNoSensitive);

% 1. Tone 消费结果测试 (s=85 激活主分支与 uniform 分支)
toneContractPolicy = beauty.toneStageContract(policyProtection);
toneContractLegacy = beauty.toneStageContract(legacyProtection);
[toneOutPolicy, ~] = beauty.normalizeSkinTone(image, freq, beautyMasks, ...
    blemishMap, 85, toneContractPolicy);
[toneOutLegacy, ~] = beauty.normalizeSkinTone(image, freq, beautyMasks, ...
    blemishMap, 85, toneContractLegacy);

ycbcrOrig = rgb2ycbcr(im2double(image));
ycbcrPolicy = rgb2ycbcr(im2double(toneOutPolicy.outputImage));
ycbcrLegacy = rgb2ycbcr(im2double(toneOutLegacy.outputImage));
dChromaPolicy = hypot(ycbcrPolicy(:, :, 2) - ycbcrOrig(:, :, 2), ...
                      ycbcrPolicy(:, :, 3) - ycbcrOrig(:, :, 3));
dChromaLegacy = hypot(ycbcrLegacy(:, :, 2) - ycbcrOrig(:, :, 2), ...
                      ycbcrLegacy(:, :, 3) - ycbcrOrig(:, :, 3));

verifyLessThan(testCase, mean(dChromaPolicy(sensitiveMask)), ...
    mean(dChromaLegacy(sensitiveMask)), ...
    '颜色敏感区域 Tone 色度偏移均值必须显著小于零证据基准。');
verifyLessThan(testCase, max(dChromaPolicy(sensitiveMask)), ...
    max(dChromaLegacy(sensitiveMask)), ...
    '颜色敏感区域 Tone 最大色度偏移必须小于零证据基准。');

% 零证据区域逐位一致
verifyEqual(testCase, toneOutPolicy.outputImage(repmat(nonSensitive, [1 1 3])), ...
    toneOutLegacy.outputImage(repmat(nonSensitive, [1 1 3])), ...
    '非敏感区域 Tone 输出必须与零证据基准逐位一致。');

% 2. Whitening 消费结果测试 (w=50)
whiteContractPolicy = beauty.whiteningStageContract(policyProtection);
whiteContractLegacy = beauty.whiteningStageContract(legacyProtection);
[whiteOutPolicy, ~] = beauty.applySkinWhitening(image, freq, beautyMasks, ...
    50, whiteContractPolicy);
[whiteOutLegacy, ~] = beauty.applySkinWhitening(image, freq, beautyMasks, ...
    50, whiteContractLegacy);

verifyLessThan(testCase, mean(whiteOutPolicy.whiteningDelta(sensitiveMask)), ...
    mean(whiteOutLegacy.whiteningDelta(sensitiveMask)), ...
    '颜色敏感区域 Whitening 修改量均值必须小于零证据基准。');
verifyLessThan(testCase, max(whiteOutPolicy.whiteningDelta(sensitiveMask)), ...
    max(whiteOutLegacy.whiteningDelta(sensitiveMask)), ...
    '颜色敏感区域 Whitening 修改量最大值必须小于零证据基准。');

% 零证据区域逐位一致
verifyEqual(testCase, whiteOutPolicy.outputImage(repmat(nonSensitive, [1 1 3])), ...
    whiteOutLegacy.outputImage(repmat(nonSensitive, [1 1 3])), ...
    '非敏感区域 Whitening 输出必须与零证据基准逐位一致。');
end

function testNegativeGateSensitivityAssertion(testCase)
%TESTNEGATIVEGATESENSITIVITYASSERTION 验证若删除执行门接线（只改 target/support）测试必失败
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, faceBox, maskDiagnostics);

[freq, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, freq, beautyMasks);

policyProtection = masks.buildStageProtectionMasks(beautyMasks, evidence);
evidenceNoSensitive = rmfield(evidence, 'colorSensitiveSkin');
legacyProtection = masks.buildStageProtectionMasks(beautyMasks, evidenceNoSensitive);

% 模拟旧的断线实现：target/support 有保护，但执行门 toneGates/whiteningGates 未接线
disconnectedProt = policyProtection;
disconnectedProt.toneGates = legacyProtection.toneGates;
disconnectedProt.whiteningGates = legacyProtection.whiteningGates;

% Tone 负向验证
discToneContract = beauty.toneStageContract(disconnectedProt);
[discToneOut, ~] = beauty.normalizeSkinTone(image, freq, beautyMasks, ...
    blemishMap, 85, discToneContract);
toneContractLegacy = beauty.toneStageContract(legacyProtection);
[toneOutLegacy, ~] = beauty.normalizeSkinTone(image, freq, beautyMasks, ...
    blemishMap, 85, toneContractLegacy);
verifyEqual(testCase, discToneOut.outputImage, toneOutLegacy.outputImage, ...
    '执行门未接线时 Tone 无法产生任何退让，输出与 legacy 完全一致（负向断线证明）。');

% Whitening 负向验证
discWhiteContract = beauty.whiteningStageContract(disconnectedProt);
[discWhiteOut, ~] = beauty.applySkinWhitening(image, freq, beautyMasks, ...
    50, discWhiteContract);
whiteContractLegacy = beauty.whiteningStageContract(legacyProtection);
[whiteOutLegacy, ~] = beauty.applySkinWhitening(image, freq, beautyMasks, ...
    50, whiteContractLegacy);
verifyEqual(testCase, discWhiteOut.outputImage, whiteOutLegacy.outputImage, ...
    '执行门未接线时 Whitening 无法产生任何退让，输出与 legacy 完全一致（负向断线证明）。');
end

function testZeroEvidenceBitExactEquality(testCase)
%TESTZEROEVIDENCEBITEXACTEQUALITY 验证 colorSensitiveSkin 全零与缺省字段时逐位一致
[image, faceBox, context] = syntheticPortraitFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, faceBox, maskDiagnostics);

evZero = evidence;
evZero.colorSensitiveSkin = zeros(size(image, 1:2));
evNone = rmfield(evidence, 'colorSensitiveSkin');

protZero = masks.buildStageProtectionMasks(beautyMasks, evZero);
protNone = masks.buildStageProtectionMasks(beautyMasks, evNone);

verifyEqual(testCase, protZero.hard, protNone.hard, 'AbsTol', 0);
verifyEqual(testCase, protZero.target, protNone.target, 'AbsTol', 0);
verifyEqual(testCase, protZero.support, protNone.support, 'AbsTol', 0);
verifyEqual(testCase, protZero.toneGates, protNone.toneGates, 'AbsTol', 0);
verifyEqual(testCase, protZero.whiteningGates, protNone.whiteningGates, 'AbsTol', 0);
verifyEqual(testCase, protZero.regionBandFine, protNone.regionBandFine, 'AbsTol', 0);
verifyEqual(testCase, protZero.regionBandMid, protNone.regionBandMid, 'AbsTol', 0);
verifyEqual(testCase, protZero.regionBandBase, protNone.regionBandBase, 'AbsTol', 0);
verifyEqual(testCase, protZero.regionBandTone, protNone.regionBandTone, 'AbsTol', 0);
verifyEqual(testCase, protZero.regionBandWhitening, protNone.regionBandWhitening, 'AbsTol', 0);
end

function testFullEndToEndWiringAndCacheConsistency(testCase)
%TESTFULLENDTOENDWIRINGANDCACHECONSISTENCY 端到端接线及缓存一致性
[image, faceBox, context] = syntheticPortraitFixture();

% 零强度原图恒等返回
zeroParams = struct('smoothingStrength', 0, 'whiteningStrength', 0);
[zeroOutput, zeroDiagnostics] = beautifyImage(image, zeroParams, faceBox, context);
verifyEqual(testCase, zeroOutput, image, '零强度必须返回 bit-exact 原图。');
verifyTrue(testCase, zeroDiagnostics.identity);

% 正常磨皮运行与缓存一致性
params = struct('smoothingStrength', 85, 'whiteningStrength', 20);
[uncachedOutput, uncachedDiagnostics] = beautifyImage(image, params, faceBox, context);
verifySize(testCase, uncachedOutput, size(image));
verifyClass(testCase, uncachedOutput, 'uint8');

% 生成运行时缓存后复用验证
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
contract = beautyPipelineContract();
cachedContext = context;
cachedContext.runtimeCache = buildBeautyRuntimeCache(image, faceBox, ...
    beautyMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', contract.schemaVersion, ...
    'message', '单测生成运行时缓存'));
[cachedOutput, cachedDiagnostics] = beautifyImage(image, params, faceBox, cachedContext);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache, '必须复用运行时缓存。');
verifyEqual(testCase, cachedOutput, uncachedOutput, '缓存与无缓存必须逐位一致。');
end

function testPaleSkinWeakColorDifferenceAdaptiveResponse(testCase)
%TESTPALESKINWEAKCOLORDIFFERENCEADAPTIVERESPONSE 验证浅色弱色差区域自适应产生非零连续响应
[image, faceBox, context, weakSpotMask, ~] = paleSkinWeakDifferenceFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, metadata] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

% 1. 验证诊断表明自适应有效且支撑点由图像统计决定
diag = metadata.colorSensitiveSkinDiagnostics;
verifyTrue(testCase, diag.valid, '浅色弱色差样本诊断必须为 valid=true。');
verifyLessThan(testCase, diag.pLow, 0.050, ...
    '浅色皮肤自适应 pLow 必须低于硬编码的 0.050 阈值。');

% 2. 计算弱色差斑块的色度偏差
ycbcr = rgb2ycbcr(im2double(image));
chromaDelta = hypot(ycbcr(:, :, 2) - diag.medianCb, ycbcr(:, :, 3) - diag.medianCr);
maxSpotDelta = max(chromaDelta(weakSpotMask));
verifyLessThan(testCase, maxSpotDelta, 0.050, ...
    '测试夹具的弱色差斑块最大色偏必须严格低于旧的 0.050 门限。');

% 3. 验证旧的固定 .050 门限会导致漏检（为零）
oldFixedResponse = smoothStepLocal(maxSpotDelta, 0.050, 0.075);
verifyEqual(testCase, oldFixedResponse, 0, '旧固定 .050 门限在弱色差处必定漏检为 0。');

% 4. 验证新自适应证据在弱色差斑块产生连续且显著的非零响应
spotEvidence = evidence.colorSensitiveSkin(weakSpotMask);
verifyGreaterThan(testCase, mean(spotEvidence), 0.30, ...
    '自适应证据在浅色弱色差处必须产生显著的非零均值响应。');
verifyGreaterThan(testCase, max(spotEvidence), 0.80, ...
    '自适应证据在弱色差中心峰值响应必须能够充分退让。');
verifyTrue(testCase, all(spotEvidence >= 0 & spotEvidence <= 1), ...
    '证据取值必须严格位于 [0, 1] 连续区间。');
end

function testPlainCheekSkinNoSpuriousProtection(testCase)
%TESTPLAINCHEEKSKINNOSPURIOUSPROTECTION 验证平坦无色差脸颊不会产生虚假保护
[image, faceBox, context, ~, plainCheekMask] = paleSkinWeakDifferenceFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

cheekEvidence = evidence.colorSensitiveSkin(plainCheekMask);
verifyLessThan(testCase, mean(cheekEvidence), 0.01, ...
    '普通平坦脸颊的平均保护量必须接近 0。');
verifyLessThan(testCase, max(cheekEvidence), 0.05, ...
    '普通平坦脸颊的最大保护量不得超过 0.05。');
verifyEqual(testCase, nnz(cheekEvidence > 0.05), 0, ...
    '普通平坦脸颊上保护量大于 0.05 的像素比例必须严格为 0。');
end

function testDegenerateQuantileIntervalDiagnosis(testCase)
%TESTDEGENERATEQUANTILEINTERVALDIAGNOSIS 验证色差分布过窄时健全诊断，无除以零
[image, faceBox, context] = flatSkinDegenerateFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, metadata] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

diag = metadata.colorSensitiveSkinDiagnostics;
verifyFalse(testCase, diag.valid, ...
    '完全均一肤色导致分位区间退化时，必须显式诊断 valid=false。');
verifyTrue(testCase, contains(diag.reason, '分位区间退化'), ...
    '诊断 reason 必须明确指出分位区间退化。');
verifyTrue(testCase, all(isfinite(evidence.colorSensitiveSkin(:))), ...
    '证据矩阵数值必须完全有限，不得出现除以零导致的 NaN 或 Inf。');
verifyEqual(testCase, evidence.colorSensitiveSkin, zeros(size(image, [1, 2])), ...
    '无任何色差与结构先验时证据必须全零。');
end

function testBoundaryAndNonSkinZeroIntegrity(testCase)
%TESTBOUNDARYANDNONSKINZEROINTEGRITY 验证非皮肤严格全零、hard不变及磨皮合约不变
[image, faceBox, context] = paleSkinWeakDifferenceFixture();
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, faceBox);
[evidence, ~] = masks.buildBeautyPolicyEvidence(image, context, ...
    faceBox, maskDiagnostics);

imageSize = size(image, [1, 2]);
faceSkin = context.faceSkinMask;
skin = context.skinMask;
processableFaceSkin = min(faceSkin, skin) > .05;

% 1. 非皮肤、背景区域严格全零
verifyEqual(testCase, nnz(evidence.colorSensitiveSkin(~processableFaceSkin) > 0), 0, ...
    '非皮肤、头发及背景区域的 colorSensitiveSkin 必须严格全零。');

% 2. hard identity 完全不受影响
legacyProtection = masks.buildStageProtectionMasks(beautyMasks, rmfield(evidence, 'colorSensitiveSkin'));
policyProtection = masks.buildStageProtectionMasks(beautyMasks, evidence);

verifyEqual(testCase, policyProtection.hard, legacyProtection.hard, 'AbsTol', 0, ...
    'hard identity 必须完全不变。');

% 3. Smoothing 与 Repair 阶段 contract 逐位完全一致
verifyEqual(testCase, policyProtection.target.smoothingFine, legacyProtection.target.smoothingFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.target.smoothingMid, legacyProtection.target.smoothingMid, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.target.repairFine, legacyProtection.target.repairFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.target.repairMid, legacyProtection.target.repairMid, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.smoothingFine, legacyProtection.support.smoothingFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.smoothingMid, legacyProtection.support.smoothingMid, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.repairFine, legacyProtection.support.repairFine, 'AbsTol', 0);
verifyEqual(testCase, policyProtection.support.repairMid, legacyProtection.support.repairMid, 'AbsTol', 0);
end

function [image, faceBox, context] = syntheticPortraitFixture
imageHeight = 120;
imageWidth = 140;
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = 70;
centerY = 60;
faceRegion = ((xGrid - centerX) / 45) .^ 2 + ((yGrid - centerY) / 50) .^ 2 <= 1;

base = .62 * ones(imageHeight, imageWidth);
base(faceRegion) = .65;
red = base * 255 + 18;
green = base * 255 - 10;
blue = base * 255 - 20;

% 注入一个颜色偏异斑块（用于测试 colorSensitiveSkin 响应）
sensitiveSpot = ((xGrid - (centerX + 15)) / 10) .^ 2 + ...
    ((yGrid - (centerY + 10)) / 10) .^ 2 <= 1;
red(sensitiveSpot) = red(sensitiveSpot) + 35;
green(sensitiveSpot) = green(sensitiveSpot) - 20;

image = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));

faceBox = [centerX - 45, centerY - 50, 90, 100];
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageHeight, imageWidth);
    confidence.(names{index}) = zeros(imageHeight, imageWidth);
end
regions.skin = double(faceRegion);
confidence.skin = double(faceRegion);
regions.leftEye = zeros(imageHeight, imageWidth);
confidence.leftEye = zeros(imageHeight, imageWidth);

parsing = struct('regions', regions, 'regionConfidence', confidence);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
end

function [image, faceBox, context, weakSpotMask, plainCheekMask] = paleSkinWeakDifferenceFixture
imageHeight = 120;
imageWidth = 140;
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = 70;
centerY = 60;
faceRegion = ((xGrid - centerX) / 45) .^ 2 + ((yGrid - centerY) / 50) .^ 2 <= 1;

baseR = 220; baseG = 200; baseB = 190;
red = double(faceRegion) * baseR;
green = double(faceRegion) * baseG;
blue = double(faceRegion) * baseB;

% 弱色差斑块（色度差 ~0.024，位于眼下/鼻翼先验附近但色差微弱，且低于 0.050）
weakSpotMask = ((xGrid - (centerX + 15)) / 12) .^ 2 + ((yGrid - (centerY + 10)) / 8) .^ 2 <= 1;
red(weakSpotMask) = red(weakSpotMask) + 9;
green(weakSpotMask) = green(weakSpotMask) - 5;
blue(weakSpotMask) = blue(weakSpotMask) - 3;

% 平坦脸颊区域（排除弱色斑）
plainCheekMask = faceRegion & ~weakSpotMask & ...
    (((xGrid - (centerX - 15)) / 15) .^ 2 + ((yGrid - (centerY + 10)) / 15) .^ 2 <= 1);

image = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));

faceBox = [centerX - 45, centerY - 50, 90, 100];
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageHeight, imageWidth);
    confidence.(names{index}) = zeros(imageHeight, imageWidth);
end
regions.skin = double(faceRegion);
confidence.skin = double(faceRegion);
regions.leftEye = zeros(imageHeight, imageWidth);
confidence.leftEye = zeros(imageHeight, imageWidth);

parsing = struct('regions', regions, 'regionConfidence', confidence);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
end

function [image, faceBox, context] = flatSkinDegenerateFixture
imageHeight = 120;
imageWidth = 140;
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = 70;
centerY = 60;
faceRegion = ((xGrid - centerX) / 45) .^ 2 + ((yGrid - centerY) / 50) .^ 2 <= 1;

baseR = 210; baseG = 190; baseB = 180;
red = double(faceRegion) * baseR;
green = double(faceRegion) * baseG;
blue = double(faceRegion) * baseB;

image = uint8(cat(3, round(red), round(green), round(blue)));
faceBox = [centerX - 45, centerY - 50, 90, 100];
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageHeight, imageWidth);
    confidence.(names{index}) = zeros(imageHeight, imageWidth);
end
regions.skin = double(faceRegion);
confidence.skin = double(faceRegion);
regions.leftEye = zeros(imageHeight, imageWidth);
confidence.leftEye = zeros(imageHeight, imageWidth);

parsing = struct('regions', regions, 'regionConfidence', confidence);
context = buildBeautyContextFromParsing(image, faceBox, parsing);
end

function val = smoothStepLocal(x, edge0, edge1)
t = min(max((x - edge0) / max(edge1 - edge0, eps), 0), 1);
val = t .* t .* (3 - 2 * t);
end
