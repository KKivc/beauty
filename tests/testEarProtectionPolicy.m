function tests = testEarProtectionPolicy
%TESTEARPROTECTIONPOLICY 验证耳朵作为皮肤参与磨皮且耳轮/耳甲腔结构得到保护。
%   T22 起新增 ear region policy 断言：受控 contract 测试（ear 结构带、
%   hard 零膨胀、partial V4 逐位还原、fail-fast）、evidence 层断言
%   （earStructure 被 ear 语义支持域约束，耳外严格为零）与生产链路
%   wiring 测试（hard RGB 回源、带外零泄漏、耳-颊 tone/whitening 连续、
%   普通脸颊不受影响、cached 一致性）。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testEarStructureEvidenceIsBoundedByEarSemantic(testCase)
%TESTEARSTRUCTUREEVIDENCEISBOUNDEDBYEARSEMANTIC T22 evidence 层契约：
%   earStructure = smoothStep(semantic.ear,.20,.45) .* max(edgeDetail,
%   darkDetail)，因此
%     * 逐字段满足 V4 evidence 规范（HxW double、real、finite、[0,1]）；
%     * ear semantic 支持域外（ear < .20，含全部耳外背景）严格为零
%       ——工单第 4 条：不用纯几何扩张、耳外背景不被误纳入；
%     * 受支持域上界约束（earStructure <= smoothStep(ear,.20,.45)）；
%     * 耳内存在非零结构证据（合成耳轮/耳甲腔）；
%     * semantic 层缺失（compat/partial V4）时退化为全零，不报错；
%       semantic.ear 非法（尺寸/取值）时 fail-fast，不静默修正。
[image, faceBox, parsing, earData] = earPolicyPortrait();
context = buildBeautyContextFromParsing(image, faceBox, parsing);
evidence = context.evidence;
verifyTrue(testCase, isfield(evidence, 'earStructure'));
verifyClass(testCase, evidence.earStructure, 'double');
verifySize(testCase, evidence.earStructure, size(image, [1, 2]));
verifyTrue(testCase, all(isfinite(evidence.earStructure(:))));
verifyGreaterThanOrEqual(testCase, min(evidence.earStructure(:)), 0);
verifyLessThanOrEqual(testCase, max(evidence.earStructure(:)), 1);

ear = context.semantic.ear;
verifyGreaterThan(testCase, nnz(ear >= .5), 0, ...
    '合成耳必须发布非空 ear 语义。');
verifyEqual(testCase, nnz(evidence.earStructure(ear < .20) > 0), 0, ...
    'ear semantic 支持域外的 earStructure 必须严格为零（无几何外溢）。');
supportGate = smoothStepValue(ear, .20, .45);
verifyLessThanOrEqual(testCase, ...
    max(evidence.earStructure(:) - supportGate(:)), 1e-12, ...
    'earStructure 不得超过 ear 语义支持域门。');
verifyGreaterThan(testCase, ...
    nnz(evidence.earStructure(ear >= .5) > .30), 0, ...
    '合成耳轮/耳甲腔必须产生非零 ear 结构证据。');
verifyGreaterThan(testCase, ...
    nnz(evidence.earStructure(earData.helix) > .30), 0, ...
    '耳轮脊线必须进入 ear 结构证据。');

metadata = context.diagnostics.policyEvidence;
verifyTrue(testCase, isfield(metadata.sources, 'earStructure'), ...
    '新增 evidence 字段必须在 metadata.sources 中登记来源。');

% 缺 semantic 层（compat / partial V4）：earStructure 全零，不报错。
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, ...
    faceBox);
noSemantic = rmfield(context, 'semantic');
[noSemanticEvidence, ~] = masks.buildBeautyPolicyEvidence(image, ...
    noSemantic, faceBox, maskDiagnostics);
verifyEqual(testCase, noSemanticEvidence.earStructure, ...
    zeros(size(ear)), 'AbsTol', 0);

% semantic 缺少 ear 分组字段：同样全零。
noEar = context;
noEar.semantic = rmfield(noEar.semantic, 'ear');
[noEarEvidence, ~] = masks.buildBeautyPolicyEvidence(image, noEar, ...
    faceBox, maskDiagnostics);
verifyEqual(testCase, noEarEvidence.earStructure, zeros(size(ear)), ...
    'AbsTol', 0);

% semantic.ear 非法（尺寸 / 取值）：fail-fast。
badSize = context;
badSize.semantic = context.semantic;
badSize.semantic.ear = context.semantic.ear(1:10, 1:10);
verifyError(testCase, @() masks.buildBeautyPolicyEvidence(image, badSize, ...
    faceBox, maskDiagnostics), 'masks:InvalidContext');
badRange = context;
badRange.semantic = context.semantic;
badRange.semantic.ear = 2 * context.semantic.ear;
verifyError(testCase, @() masks.buildBeautyPolicyEvidence(image, badRange, ...
    faceBox, maskDiagnostics), 'masks:InvalidContext');
end

function testEarPolicyBandsFollowEvidenceContract(testCase)
%TESTEARPOLICYBANDSFOLLOWEVIDENCECONTRACT T22 ear region policy 的受控
%   contract 断言（直接调用 buildStageProtectionMasks，屏蔽几何噪声），
%   范式与 T20/T21 的 region policy contract 测试一致：
%     identity core —— hard 字段与输入 hardProtectionMask 逐位相等，
%       不新增任何 hard 像素（耳轮/沟槽一律软保护，不整耳 hard 化）；
%     ear structure band —— band=1 像素抬升到固定档位
%       smoothingFine/repairFine=.95（Fine 侧与 T20/T21 检测细节带同档，
%       保留 >=5% Fine 处理量）、smoothingMid=.90、baseLuminance=.80；
%       repairMid 的 .90 是 max 下界，带内因 (1 - policyTexture) 项
%       实际为 .95（与 T20/T21 同一约定）；tone/whitening 保持 legacy
%       （耳部无 identity 色度语义，肤色与脸颊/颈部连续）；
%     平坦耳皮肤（earStructure 低于 .05 下支撑点）：带为零，8 个 stage
%       字段逐位等于 legacy（普通耳皮肤保持可处理性）；
%     evidence 零带或缺少 earStructure 字段（partial V4）时与 T07
%       legacy 折叠逐位相等；带外像素逐位还原 legacy；
%     非法 evidence（尺寸/取值/NaN）fail-fast。
[fixture, evidence] = earPolicyUnitFixture();
legacy = masks.buildStageProtectionMasks(fixture.masks);
policy = masks.buildStageProtectionMasks(fixture.masks, evidence);
% T31 起 protection 含嵌套 target/support（标量结构，不可按像素索引），
% 逐字段 bit-exact 循环统一在展平后的叶子字段名上进行。
flatPolicy = flattenProtection(policy);
flatLegacy = flattenProtection(legacy);
fieldNames = fieldnames(flatPolicy);

% identity：hard 原样拷贝，严格二值、nnz 不变。
verifyEqual(testCase, policy.hard, fixture.hardIdentity, 'AbsTol', 0);
verifyTrue(testCase, all(policy.hard(:) == 0 | policy.hard(:) == 1), ...
    'hard 必须是严格二值 identity mask。');
verifyEqual(testCase, nnz(policy.hard), nnz(fixture.hardIdentity), ...
    'T22 不得新增或减少 hard identity 像素。');

% ear structure band 核心档位。
corePoint = fixture.corePoint;
verifyEqual(testCase, ...
    policy.target.smoothingFine(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.target.smoothingMid(corePoint(1), corePoint(2)), .90, 'AbsTol', 1e-12);
verifyEqual(testCase, ...
    policy.target.repairFine(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
% repairMid 的 .90 是 max 下界；带内 policyTexture 已被抬到 .95，
% (1 - policyTexture) 项使实际值升到 .95（与 T20/T21 同一约定）。
verifyEqual(testCase, ...
    policy.target.repairMid(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
% baseLuminance：耳结构带给出 >= .80 的亮度结构保护下界；带内
% policyTexture 已被抬到 .95，(1 - max(texture,chroma)) 项使实际值升到
% .95（.80 是 max 下界，与 T21 鼻结构带同一写法）。
verifyGreaterThanOrEqual(testCase, ...
    policy.baseLuminance(corePoint(1), corePoint(2)), .80 - 1e-12, ...
    'ear 结构带必须给出 >= .80 的亮度结构保护下界。');
verifyEqual(testCase, ...
    policy.baseLuminance(corePoint(1), corePoint(2)), .95, 'AbsTol', 1e-12);
verifyEqual(testCase, policy.tone(corePoint(1), corePoint(2)), ...
    legacy.tone(corePoint(1), corePoint(2)), 'AbsTol', 0, ...
    '耳部无 identity 色度语义，tone 不得被耳带抬升。');
verifyEqual(testCase, policy.whitening(corePoint(1), corePoint(2)), ...
    legacy.whitening(corePoint(1), corePoint(2)), 'AbsTol', 0, ...
    '耳部不设美白退让，保持与脸部/颈部肤色连续。');

% 平坦耳皮肤（低于下支撑点）：两带皆零，保持 processability。
flatPoint = fixture.flatPoint;
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, ...
        flatPolicy.(fieldName)(flatPoint(1), flatPoint(2)), ...
        flatLegacy.(fieldName)(flatPoint(1), flatPoint(2)), 'AbsTol', 0, ...
        '平坦耳皮肤零带，stage 字段必须逐位等于 legacy。');
end

% 证据零带（partial V4 / 缺字段 / 缺省输入）：与 legacy 逐位相等。
zeroEvidence = struct('earStructure', zeros(fixture.imageSize));
missingEvidence = struct('periocular', zeros(fixture.imageSize), ...
    'nostril', zeros(fixture.imageSize));
for variant = {zeroEvidence, missingEvidence, struct()}
    zeroPolicy = flattenProtection( ...
        masks.buildStageProtectionMasks(fixture.masks, variant{1}));
    for fieldIndex = 1:numel(fieldNames)
        fieldName = fieldNames{fieldIndex};
        verifyEqual(testCase, zeroPolicy.(fieldName), ...
            flatLegacy.(fieldName), 'AbsTol', 0);
    end
end
singleArgPolicy = flattenProtection( ...
    masks.buildStageProtectionMasks(fixture.masks));
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, singleArgPolicy.(fieldName), ...
        flatLegacy.(fieldName), 'AbsTol', 0);
end

% 带外（band 为零的像素）逐位还原 legacy。
band = smoothStepValue(evidence.earStructure, .05, .30);
outside = band == 0;
verifyTrue(testCase, nnz(outside) > 0, 'fixture 必须包含带外像素。');
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, flatPolicy.(fieldName)(outside), ...
        flatLegacy.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于 legacy。');
end

% 带内单调性：结构保护只增不减，且 tone/whitening 全图逐位不变。
verifyGreaterThanOrEqual(testCase, ...
    min(policy.target.smoothingMid(:) - legacy.target.smoothingMid(:)), 0);
verifyGreaterThanOrEqual(testCase, ...
    min(policy.target.smoothingFine(:) - legacy.target.smoothingFine(:)), 0);
verifyGreaterThanOrEqual(testCase, ...
    min(policy.baseLuminance(:) - legacy.baseLuminance(:)), 0);
verifyEqual(testCase, policy.tone, legacy.tone, 'AbsTol', 0, ...
    'T22 不得给 tone 增加耳部项（肤色与脸颊/颈部连续）。');
verifyEqual(testCase, policy.whitening, legacy.whitening, 'AbsTol', 0, ...
    'T22 不得给 whitening 增加耳部项（不引入耳-颊异色块）。');

% 非法 evidence fail-fast，不静默修正。
badSize = evidence;
badSize.earStructure = evidence.earStructure(1:10, 1:10);
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badSize), 'masks:InvalidEvidence');
badRange = evidence;
badRange.earStructure = evidence.earStructure * 2;
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badRange), 'masks:InvalidEvidence');
badNaN = evidence;
badNaN.earStructure = evidence.earStructure;
badNaN.earStructure(2, 2) = NaN;
verifyError(testCase, @() masks.buildStageProtectionMasks( ...
    fixture.masks, badNaN), 'masks:InvalidEvidence');
end

function testEarPolicyWiringPreservesIdentityAndSkinContinuity(testCase)
%TESTEARPOLICYWIRINGPRESERVESIDENTITYANDSKINCONTINUITY T22 生产链路
%   （beautifyImage 经 bridge evidence 转发）端到端断言。真实图/合成图
%   同时携带 T20/T21 的 eye/lip/nose 证据，故"无 T22"基线用只去掉
%   earStructure 的 evidence 构造（T21 accept 的同一隔离手法）：两条
%   路径的 T20/T21 贡献逐位同值，二者之差才是 T22 增量。
%     identity —— hard 在 policy / earOnly / legacy 三条路径逐位相等
%       （零膨胀、nnz 不变），hard 区域 RGB 与源图逐位相等；
%     processability —— 耳语义支持域外（ear < .20，含全部耳外背景）
%       的 ear 结构带严格为零；带外 stage 字段逐位等于 earOnly 基线，
%       带外输出差异不超过 1 个灰度级（生产链全局参考统计的舍入）；
%       普通脸颊（ear < .10）的 Fine/Mid alphaMap 逐位不变；
%     skin continuity —— tone/whitening 字段全图逐位等于 earOnly 基线
%       （无耳部项），耳-颊保护差与 legacy 相同（不新增割裂）；
%     structure —— 耳结构带内 smoothingFine 严格抬升（Fine 侧进入
%       texture 通道）、smoothingMid/baseLuminance 只增不减；
%     cached 与 uncached 输出逐位一致。
[image, faceBox, context, earData] = earPolicyPortrait();
params = struct('smoothingStrength', 100, 'whiteningStrength', 0);
[policyOut, policyDiagnostics] = beautifyImage(image, params, faceBox, ...
    context);
earOnlyContext = context;
earOnlyContext.evidence = rmfield(context.evidence, 'earStructure');
[earOnlyOut, earOnlyDiagnostics] = beautifyImage(image, params, faceBox, ...
    earOnlyContext);

[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(image, context, ...
    faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks, ...
    context.evidence);
earOnlyProtection = masks.buildStageProtectionMasks(beautyMasks, ...
    earOnlyContext.evidence);
legacyProtection = masks.buildStageProtectionMasks(beautyMasks);
hardMask = protection.hard >= .999;
verifyTrue(testCase, isequal(protection.hard, legacyProtection.hard), ...
    'T22 不得改变 hard identity（耳部不整耳 hard 化，零膨胀）。');
verifyTrue(testCase, isequal(protection.hard, earOnlyProtection.hard), ...
    'T22 增量不得改变 hard identity。');
verifyEqual(testCase, nnz(protection.hard), ...
    nnz(legacyProtection.hard), 'T22 不得新增 hard 像素。');
verifyTrue(testCase, nnz(hardMask) > 0, ...
    '合成 fixture 必须产生非空 hard identity 区域。');
verifyEqual(testCase, policyOut(repmat(hardMask, [1, 1, 3])), ...
    image(repmat(hardMask, [1, 1, 3])), ...
    'hard identity 区域 RGB 必须与源图逐位相等。');

ear = context.semantic.ear;
evidence = context.evidence;
band = smoothStepValue(evidence.earStructure, .05, .30);
verifyTrue(testCase, nnz(band > .5) > 0, ...
    'fixture 必须产生非空 ear 结构带。');
verifyEqual(testCase, nnz(band(ear < .20) > 0), 0, ...
    'ear 语义支持域外不得有耳结构带（耳外背景不被误纳入）。');
verifyEqual(testCase, nnz(band > .5 & earData.face & ear < .10), 0, ...
    '脸颊区域不得进入耳结构带。');

% 带外零泄漏：T22 增量不得出现在 band == 0 处（stage 字段逐位一致）。
outside = band == 0;
flatProtection = flattenProtection(protection);
flatEarOnly = flattenProtection(earOnlyProtection);
fieldNames = fieldnames(flatProtection);
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames{fieldIndex};
    verifyEqual(testCase, flatProtection.(fieldName)(outside), ...
        flatEarOnly.(fieldName)(outside), 'AbsTol', 0, ...
        'evidence 带外的 stage 字段必须逐位等于无 T22 基线。');
end
diffMap = mean(abs(double(policyOut) - double(earOnlyOut)), 3);
verifyEqual(testCase, nnz(diffMap(outside) > 1), 0, ...
    '带外输出泄漏不得超过 1 个灰度级。');
% 带内 stage 字段变化会经生产链的全局参考统计（repair 的
% fineReference/midReference 由参考域卷积得到）传播为 <= 1e-4 量级的
% 修正差，个别像素因此跨过 uint8 舍入边界（T20 记录的同类亚量化
% 泄漏）；stage 字段与 alphaMap 在带外仍是逐位一致（上方断言）。
verifyLessThanOrEqual(testCase, max(diffMap(outside)), 1 + 1e-9, ...
    '带外输出泄漏幅度不得超过 1 个灰度级。');

% 普通脸颊效果不受影响：Fine/Mid alphaMap 逐位不变。
alphaPolicy = policyDiagnostics.smoothing.alphaMap;
alphaEarOnly = earOnlyDiagnostics.smoothing.alphaMap;
midPolicy = policyDiagnostics.smoothing.midAlphaMap;
midEarOnly = earOnlyDiagnostics.smoothing.midAlphaMap;
cheek = ear < .10;
verifyGreaterThan(testCase, nnz(cheek), 0);
verifyEqual(testCase, alphaPolicy(cheek), alphaEarOnly(cheek), 'AbsTol', 0, ...
    '普通脸颊的 Fine 处理量不得因耳部 policy 改变。');
verifyEqual(testCase, midPolicy(cheek), midEarOnly(cheek), 'AbsTol', 0, ...
    '普通脸颊的 Mid 处理量不得因耳部 policy 改变。');

% 肤色连续：tone/whitening 字段相对无 T22 基线全图逐位不变（无耳部项）。
verifyEqual(testCase, protection.tone, earOnlyProtection.tone, 'AbsTol', 0, ...
    'T22 不得给 tone 增加耳部项（耳-颊肤色连续）。');
verifyEqual(testCase, protection.whitening, ...
    earOnlyProtection.whitening, 'AbsTol', 0, ...
    'T22 不得给 whitening 增加耳部项（不引入异色块）。');
earRegion = ear >= .5;
cheekRegion = imdilate(earRegion, ones(31)) & earData.face & ~earRegion;
verifyGreaterThan(testCase, nnz(cheekRegion), 0);
verifyEqual(testCase, ...
    mean(protection.tone(earRegion)) - mean(protection.tone(cheekRegion)), ...
    mean(legacyProtection.tone(earRegion)) - ...
    mean(legacyProtection.tone(cheekRegion)), 'AbsTol', 1e-12, ...
    '耳-颊 tone 保护差必须与 legacy 相同（不新增割裂）。');
verifyEqual(testCase, ...
    mean(protection.whitening(earRegion)) - ...
    mean(protection.whitening(cheekRegion)), ...
    mean(legacyProtection.whitening(earRegion)) - ...
    mean(legacyProtection.whitening(cheekRegion)), 'AbsTol', 1e-12, ...
    '耳-颊 whitening 保护差必须与 legacy 相同（不引入异色块）。');

% 结构保护：耳结构带内 Fine 严格抬升，Mid/baseLuminance 只增不减。
structureBand = band > .5 & ~hardMask;
verifyGreaterThan(testCase, nnz(structureBand), 0);
verifyTrue(testCase, any(protection.target.smoothingFine(structureBand) > ...
    earOnlyProtection.target.smoothingFine(structureBand)), ...
    'ear 结构带内 smoothingFine 必须严格抬升（耳轮/沟槽细节保留）。');
verifyGreaterThanOrEqual(testCase, ...
    min(protection.target.smoothingMid(structureBand) - ...
    earOnlyProtection.target.smoothingMid(structureBand)), 0);
verifyGreaterThanOrEqual(testCase, ...
    min(protection.baseLuminance(structureBand) - ...
    earOnlyProtection.baseLuminance(structureBand)), 0);
verifyLessThanOrEqual(testCase, mean(alphaPolicy(structureBand)), ...
    mean(alphaEarOnly(structureBand)) + 1e-12, ...
    'ear 结构带内 Fine 处理量不得高于无 T22 基线。');

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

function [fixture, evidence] = earPolicyUnitFixture
%EARPOOLICYUNITFIXTURE 构造受控 Beauty Masks 与耳部 evidence（40x60）：
%   earStructure=1 的结构块（满带）、earStructure=.02 的平坦耳皮肤
%   （低于 .05 下支撑点，带为零）、一个 hard identity 块。掩码其余通道
%   全部为零，隔离 geometry 噪声，使档位断言精确。
imageSize = [40, 60];
hardIdentity = zeros(imageSize);
hardIdentity(30:33, 40:43) = 1;
earStructure = zeros(imageSize);
earStructure(10:16, 12:30) = 1;
earStructure(24:34, 12:40) = .02;
evidence = struct('earStructure', earStructure);
fixture = struct( ...
    'imageSize', imageSize, ...
    'hardIdentity', hardIdentity, ...
    'corePoint', [12, 20], ...
    'flatPoint', [28, 20], ...
    'masks', unitEarMasks(hardIdentity, imageSize));
end

function masksStruct = unitEarMasks(hard, imageSize)
%UNITEARMASKS 构建只含 buildStageProtectionMasks 必需字段的 mask 产物。
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

function [image, faceBox, context, earData] = earPolicyPortrait
%EARPOOLICYPORTRAIT 合成耳部人像：椭圆脸 + 右耳（耳轮亮脊 + 耳甲腔暗谷
%   + 轻纹理），通过生产链 buildBeautyContextFromParsing 携带 policy
%   evidence。结构对比度刻意保持温和，使耳内结构保护未饱和、耳结构带
%   的增量可被 stage 字段与 alphaMap 直接观测。
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
% 两个鼻孔暗谷：为 wiring 测试提供非空 hard identity 区域（T22 必须
% 证明 hard 零膨胀且 hard 区 RGB 回源），与 T21 的 gentle 夹具同款。
nostril = (((xGrid - (centerX - 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1) | ...
    (((xGrid - (centerX + 9)) / 6.0) .^ 2 + ...
    ((yGrid - (faceCenterY + 34)) / 3.0) .^ 2 <= 1);
base(nostril) = base(nostril) - .15;
red = base * 255 + 20;
green = base * 255 - 12;
blue = base * 255 - 28;
image = uint8(cat(3, min(max(round(red), 0), 255), ...
    min(max(round(green), 0), 255), min(max(round(blue), 0), 255)));
parsing = emptyParsing([imageHeight, imageWidth]);
parsing.regions.skin = double(faceRegion);
parsing.regionConfidence.skin = double(faceRegion);
parsing.regions.leftEar = double(earRegion);
parsing.regionConfidence.leftEar = double(earRegion);
% 鼻语义：鼻孔暗谷的 hard identity 检测需要 nose 支持域
% （noseInterior = noseCore & ~noseBoundary）。
noseRegion = ((xGrid - centerX) / 20) .^ 2 + ...
    ((yGrid - (faceCenterY + 20)) / 30) .^ 2 <= 1;
parsing.regions.nose = double(noseRegion);
parsing.regionConfidence.nose = double(noseRegion);
faceBox = [centerX - 78, faceCenterY - 95, 156, 190];
context = buildBeautyContextFromParsing(image, faceBox, parsing);
earData = struct('ear', earRegion, 'helix', helix, 'concha', concha, ...
    'face', faceRegion);
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

function value = smoothStepValue(inputValue, low, high)
%SMOOTHSTEPVALUE 复现生产 smoothstep 曲线（t^2*(3-2t)）。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
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
