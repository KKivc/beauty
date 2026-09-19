function tests = testBeautyV3
%TESTBEAUTYV3 v3 Mask package 和频率 tracer 测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testPackagesResolveWithSourcePathOnly(testCase)
verifyNotEmpty(testCase, which('masks.buildBeautyMasks'));
verifyNotEmpty(testCase, which('masks.buildTextureProtectionMask'));
verifyNotEmpty(testCase, which('beauty.decomposeSkinFrequency'));
verifyNotEmpty(testCase, which('beauty.smoothSkinTexture'));
verifyNotEmpty(testCase, which('beauty.evenSkinLuminance'));
verifyNotEmpty(testCase, which('beauty.composeBeautyResult'));
end

function testBeautyMasksReturnPurposeSpecificContinuousMaps(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));

[beautyMasks, diagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
requiredFields = {'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', ...
    'nonFaceStrengthMap', 'hardProtectionMask'};
verifyTrue(testCase, all(isfield(beautyMasks, requiredFields)));
for index = 1:numel(requiredFields)
    verifySize(testCase, beautyMasks.(requiredFields{index}), [120, 160]);
end
verifyTrue(testCase, isfield(diagnostics, 'structure'));
verifyTrue(testCase, isfield(diagnostics.structure, 'orientationCoherence'));
verifyEqual(testCase, beautyMasks.chromaProtectionMask, ...
    beautyMasks.toneProtectionMask, 'AbsTol', 0);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.textureProtectionMask(parsing.regions.leftEye > .5)), .5);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.toneProtectionMask(parsing.regions.upperLip > .5)), .5);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.structureProtectionMask(parsing.regions.nose > .5)), 0);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.structureProtectionMask(parsing.regions.neck > .5)), 0);
verifyEqual(testCase, max(beautyMasks.strengthMap( ...
    context.skinMask <= .01)), 0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, ...
    mean(beautyMasks.faceStrengthMap(parsing.regions.skin > .5)), ...
    mean(beautyMasks.nonFaceStrengthMap(parsing.regions.neck > .5)));

[texture, structure, tone, strength] = masks.buildBeautyMasks( ...
    image, context, faceBox);
verifyEqual(testCase, texture, beautyMasks.textureProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, structure, beautyMasks.structureProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, tone, beautyMasks.toneProtectionMask, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, strength, beautyMasks.strengthMap, ...
    'AbsTol', 1e-12);
end

function testFrequencyDecompositionReconstructsAndKeepsScalesFixed(testCase)
[image, faceBox, parsing] = fixtureImage(96, 128);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([96, 128])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, decomposition] = beauty.decomposeSkinFrequency(image, faceBox);
verifyLessThanOrEqual(testCase, decomposition.reconstructionError, 1e-12);
verifyEqual(testCase, frequency.base + frequency.mid + frequency.fine, ...
    frequency.sourceLuminance, 'AbsTol', 1e-12);

strengths = [0, 25, 50, 75, 100];
retentions = zeros(size(strengths));
fineEnergies = zeros(size(strengths));
midRetentions = zeros(size(strengths));
midEnergies = zeros(size(strengths));
for index = 1:numel(strengths)
    [smoothed, details] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strengths(index));
    retentions(index) = mean(details.fineActualRetentionMap(:));
    fineEnergies(index) = details.fineEnergyAfter;
    midRetentions(index) = mean(details.midActualRetentionMap(:));
    midEnergies(index) = details.midEnergyAfter;
    verifyEqual(testCase, details.fineActualRetentionMap, ...
        1 - details.alphaMap .* (1 - details.fineRetention), ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, details.midActualRetentionMap, ...
        1 - details.midAlphaMap .* (1 - details.midRetention), ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, smoothed.base, frequency.base, ...
        'AbsTol', 1e-12);
    if strengths(index) == 0
        verifyEqual(testCase, smoothed.mid, frequency.mid, ...
            'AbsTol', 1e-12);
    else
        verifyGreaterThan(testCase, ...
            nnz(abs(smoothed.mid(:) - frequency.mid(:)) > 1e-12), 0);
    end
end
verifyEqual(testCase, retentions(1), 1, 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(retentions) <= 0));
verifyTrue(testCase, all(diff(fineEnergies) <= 1e-12));
verifyEqual(testCase, midRetentions(1), 1, 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(midRetentions) <= 0));
verifyTrue(testCase, all(diff(midEnergies) <= 1e-12));
verifyGreaterThan(testCase, retentions(end), .55);
verifyGreaterThan(testCase, midRetentions(end), .50);
end

function testV3PipelineUsesOneAlphaAndPreservesProtectedPixels(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
params = struct('smoothingStrength', 100, ...
    'whiteningStrength', 50);
[output, diagnostics] = beautifyImage(image, params, faceBox, context);
verifyClass(testCase, output, 'uint8');
verifySize(testCase, output, size(image));
verifyEqual(testCase, output(repmat(diagnostics.beautyMasks.hardProtectionMask >= .999, ...
    [1, 1, 3])), image(repmat(diagnostics.beautyMasks.hardProtectionMask >= .999, ...
    [1, 1, 3])));
verifyEqual(testCase, output(repmat(context.skinMask <= .01, ...
    [1, 1, 3])), image(repmat(context.skinMask <= .01, ...
    [1, 1, 3])));

[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[smoothed, ~] = beauty.smoothSkinTexture(frequency, beautyMasks, 100);
[~, diagnostics] = beauty.composeBeautyResult( ...
    image, frequency, smoothed, beautyMasks, 50);
verifyEqual(testCase, diagnostics.alphaMap, ...
    max(smoothed.alphaMap, diagnostics.whiteningSupport), ...
    'AbsTol', 1e-12);
end

function testStageProtectionGatesReproduceProductionGating(testCase)
%TESTSTAGEPROTECTIONGATESREPRODUCEPRODUCTIONGATING T07：八个 stage
%   protection 字段满足唯一语义与 [0,1]；hard 可严格离散化（二值）且
%   nostrilCore/lashCore 的 hard identity 原样保留；用 stage protection
%   重算各生产 stage 的兼容门控，与生产诊断逐像素等价（容差仅为
%   1-x 补码往返与乘法结合顺序的浮点噪声，不放宽行为）。
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);

stageNames = {'smoothingFine'; 'smoothingMid'; 'repairFine'; ...
    'repairMid'; 'baseLuminance'; 'tone'; 'whitening'; 'hard'};
verifyEqual(testCase, fieldnames(protection), stageNames);
for index = 1:numel(stageNames)
    value = protection.(stageNames{index});
    verifyTrue(testCase, isnumeric(value) && ~islogical(value) && ...
        isreal(value));
    verifySize(testCase, value, [120, 160]);
    verifyTrue(testCase, all(isfinite(value(:))));
    verifyGreaterThanOrEqual(testCase, min(value(:)), 0);
    verifyLessThanOrEqual(testCase, max(value(:)), 1);
end

% hard：二值 identity，与生产 hardProtectionMask bit-exact；
% nostrilCore/lashCore/lipCore 全部保留在 hard 内。
verifyEqual(testCase, protection.hard, ...
    beautyMasks.hardProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, protection.hard, ...
    double(maskDiagnostics.texture.hardProtectionMask), 'AbsTol', 0);
verifyTrue(testCase, all(protection.hard(:) == 0 | ...
    protection.hard(:) == 1));
identityCore = maskDiagnostics.texture.lipCore | ...
    maskDiagnostics.texture.nostrilCore | ...
    maskDiagnostics.texture.lashCore;
verifyTrue(testCase, nnz(identityCore) > 0);
verifyTrue(testCase, all(protection.hard(identityCore) == 1), ...
    'nostrilCore/lashCore 的 hard identity 必须原样保留。');

% Fine/Mid smoothing：alphaMap 与 midAlphaMap 用 stage fields 重算。
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
strengths = [0, 25, 50, 75, 100];
for index = 1:numel(strengths)
    strength = strengths(index);
    [smoothed, details] = beauty.smoothSkinTexture(frequency, ...
        beautyMasks, strength);
    profile = beautySmoothingProfile(strength);
    effectStrength = profile.alphaCurve .* beautyMasks.strengthMap;
    nonFacePixels = beautyMasks.nonFaceStrengthMap > .01;
    effectStrength(nonFacePixels) = profile.outsideFaceStrength .* ...
        beautyMasks.nonFaceStrengthMap(nonFacePixels);
    fineGate = 1 - max(protection.smoothingFine, protection.hard);
    verifyEqual(testCase, details.alphaMap, effectStrength .* fineGate, ...
        'AbsTol', 1e-12);

    midGate = 1 - protection.smoothingMid;
    midRecomputed = details.alphaMap .* midGate;
    nosePixels = beautyMasks.noseMask > 0;
    if profile.alphaCurve == 1
        % 满档（alphaCurve=1）：mid 门控整体与生产逐像素等价。
        verifyEqual(testCase, details.midAlphaMap, midRecomputed, ...
            'AbsTol', 1e-12);
    else
        % 静态结构部分全场等价；nose 项生产值为快照与 1 的凸组合
        % （快照即最强保护），逐像素核对凸组合差值。
        verifyEqual(testCase, details.midAlphaMap(~nosePixels), ...
            midRecomputed(~nosePixels), 'AbsTol', 1e-12);
        midGap = details.midAlphaMap(nosePixels) - ...
            midRecomputed(nosePixels);
        expectedGap = details.alphaMap(nosePixels) .* ...
            details.fineStructureGate(nosePixels) .* ...
            (.50 * (1 - profile.alphaCurve));
        verifyGreaterThanOrEqual(testCase, min(midGap), 0);
        verifyEqual(testCase, midGap, expectedGap, 'AbsTol', 1e-9);
    end
end

% Repair：零瑕疵参考点的生产 structureGate（blemish=0）与
% textureGate/noseMidGate 的组合必须 bit-exact 重建两个 stage 字段。
blemishMap = zeros(size(image, 1), size(image, 2));
[~, repairDetails] = beauty.repairSkinBlemishes(smoothed, beautyMasks, ...
    blemishMap, 50);
verifyEqual(testCase, protection.repairFine, ...
    1 - repairDetails.structureGate .* ...
    (1 - beautyMasks.textureProtectionMask), 'AbsTol', 0);
verifyEqual(testCase, protection.repairMid, ...
    1 - repairDetails.structureGate .* repairDetails.noseMidGate .* ...
    (1 - beautyMasks.textureProtectionMask), 'AbsTol', 0);

% Base luminance：supportMap 完整重算（该 stage 无 runtime 耦合）。
[~, baseDetails] = beauty.evenSkinLuminance(frequency, beautyMasks, 50);
baseSupport = baseDetails.baseWeightCurve .* ...
    baseDetails.regionalSkinWeight .* (1 - protection.hard) .* ...
    (1 - protection.baseLuminance) .* baseDetails.referenceCoverage;
verifyEqual(testCase, baseDetails.supportMap, baseSupport, 'AbsTol', 1e-12);

% Tone：主 weight 分支重算（s=25 时 uniform 分支未激活）。
[~, toneDetails] = beauty.normalizeSkinTone(image, frequency, ...
    beautyMasks, blemishMap, 25);
profile25 = beautySmoothingProfile(25);
toneCurveMap = profile25.toneStrength + ((25 / 100) ^ .85 - ...
    profile25.toneStrength) .* smoothStep( ...
    toneDetails.chromaEvidence, .25, .65);
toneCurveMap = max(toneCurveMap, ...
    (25 / 100) ^ .85 .* toneDetails.localChromaEvidence);
toneAllowed = min(beautyMasks.skinMask, beautyMasks.strengthMap) .* ...
    (1 - protection.hard);
evidenceTerm = .08 + .35 * toneDetails.chromaEvidence + ...
    .35 * toneDetails.localChromaEvidence + ...
    .20 * toneDetails.blemishEvidence;
toneWeight = min(max(toneCurveMap .* toneAllowed .* ...
    (1 - protection.tone) .* evidenceTerm, 0), .55);
verifyEqual(testCase, toneDetails.weightMap, toneWeight, 'AbsTol', 1e-12);

% Whitening：supportMap 完整重算（该 stage 无 runtime 耦合）。
[~, whiteningDetails] = beauty.applySkinWhitening(image, frequency, ...
    beautyMasks, 50);
whiteningAllowed = min(beautyMasks.skinMask, beautyMasks.strengthMap) .* ...
    (1 - protection.hard);
faceSkin = beautyMasks.faceSkinMask >= .5;
whiteningAllowed(faceSkin) = max(whiteningAllowed(faceSkin), .85);
whiteningSupport = min(max((50 / 100) ^ .85 .* whiteningAllowed .* ...
    whiteningDetails.highlightProtection .* ...
    (1 - protection.whitening), 0), 1);
verifyEqual(testCase, whiteningDetails.supportMap, whiteningSupport, ...
    'AbsTol', 1e-12);
end

function testFineSmoothingConsumesStageProtectionContract(testCase)
%TESTFINESMOOTHINGCONSUMESSTAGEPROTECTIONCONTRACT T12：提供 stage
%   contract（protection 分层）时，Fine smoothing 只从
%   protection.smoothingFine / protection.hard 派生 Fine 门控，不再自行
%   解释 general texture/structure masks：扰动 textureProtectionMask 不
%   改变 stage 路径的任何输出，而 legacy 路径会随之变化。统计路径
%   （processableSkin → fineEnergy/blemishMean/fineRetention）改读生产
%   端合并 protectionMask，与旧 max(texture,structure,hard) bit-exact
%   同值；strength、频段分解与合成公式不变（Mid 门控自 T13 起迁移至
%   stage contract，见 testMidSmoothingConsumesStageProtectionContract）。
%   Fine alpha 与输出增量相对 legacy 仅有 1-x 补码与乘法结合顺序的
%   浮点噪声（≤1e-15，T07 推导基线 1.11e-16 同量级）。
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);

% 统计路径数据源：合并 protectionMask 与 max(texture, structure, hard)
% 必须逐像素 bit-exact，保证可处理皮肤统计口径不变。
combinedProtection = max(cat(3, beautyMasks.textureProtectionMask, ...
    beautyMasks.structureProtectionMask, ...
    beautyMasks.hardProtectionMask), [], 3);
verifyEqual(testCase, beautyMasks.protectionMask, combinedProtection, ...
    'AbsTol', 0);

strengths = [0, 25, 50, 75, 100];
for index = 1:numel(strengths)
    strength = strengths(index);
    [smoothedLegacy, legacyDetails] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strength, blemishMap);
    [smoothedStage, stageDetails] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strength, blemishMap, protection);

    % stage 路径 Fine alpha 恰为 stage contract 重算（统一语义
    % gate = 1 - max(field, hard)），bit-exact；hard identity 保持。
    profile = beautySmoothingProfile(strength);
    effectStrength = profile.alphaCurve .* beautyMasks.strengthMap;
    nonFacePixels = beautyMasks.nonFaceStrengthMap > .01;
    effectStrength(nonFacePixels) = profile.outsideFaceStrength .* ...
        beautyMasks.nonFaceStrengthMap(nonFacePixels);
    verifyEqual(testCase, stageDetails.alphaMap, ...
        effectStrength .* (1 - max(protection.smoothingFine, ...
        protection.hard)), 'AbsTol', 0);
    verifyEqual(testCase, ...
        nnz(stageDetails.alphaMap(protection.hard >= .999)), 0);

    % 与 legacy 路径的等价性：alpha 与 Fine/Mid 输出增量仅浮点噪声；
    % 统计标量与合并保护图 bit-exact 不变；结构锚点同值（T13 起 Mid
    % 门控契约见 testMidSmoothingConsumesStageProtectionContract）。
    verifyLessThanOrEqual(testCase, ...
        max(abs(stageDetails.alphaMap(:) - legacyDetails.alphaMap(:))), ...
        1e-15);
    verifyLessThanOrEqual(testCase, ...
        max(abs(smoothedStage.fine(:) - smoothedLegacy.fine(:))), 1e-15);
    verifyLessThanOrEqual(testCase, ...
        max(abs(smoothedStage.mid(:) - smoothedLegacy.mid(:))), 1e-15);
    verifyEqual(testCase, stageDetails.fineEnergy, ...
        legacyDetails.fineEnergy, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.blemishMean, ...
        legacyDetails.blemishMean, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.fineRetention, ...
        legacyDetails.fineRetention, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.protectionMask, ...
        legacyDetails.protectionMask, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.fineStructureGate, ...
        legacyDetails.fineStructureGate, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.midStructureGate, ...
        legacyDetails.midStructureGate, 'AbsTol', 0);
    verifyLessThanOrEqual(testCase, ...
        max(abs(stageDetails.midAlphaMap(:) - ...
        legacyDetails.midAlphaMap(:))), 1e-15);
    % 合成公式与 base identity 不变。
    verifyEqual(testCase, smoothedStage.base, frequency.base, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.fineRetentionMap, ...
        1 - stageDetails.alphaMap .* (1 - stageDetails.fineRetention), ...
        'AbsTol', 0);
end

% 负向证明：stage 路径的输出对 textureProtectionMask 扰动完全不变
% （Fine 不再读取该字段），legacy 路径则会随之改变。
perturbedMasks = beautyMasks;
perturbedMasks.textureProtectionMask = ...
    min(1, beautyMasks.textureProtectionMask * .5 + .25);
[smoothedPerturbedLegacy, perturbedLegacyDetails] = ...
    beauty.smoothSkinTexture(frequency, perturbedMasks, 60, blemishMap);
[smoothedPerturbedStage, perturbedStageDetails] = ...
    beauty.smoothSkinTexture(frequency, perturbedMasks, 60, blemishMap, ...
    protection);
[smoothedStage60, stageDetails60] = beauty.smoothSkinTexture( ...
    frequency, beautyMasks, 60, blemishMap, protection);
[~, unperturbedLegacyDetails60] = beauty.smoothSkinTexture( ...
    frequency, beautyMasks, 60, blemishMap);
verifyTrue(testCase, ...
    nnz(perturbedLegacyDetails.alphaMap ~= ...
    unperturbedLegacyDetails60.alphaMap) > 0, ...
    'texture 扰动必须确实影响 legacy 路径，否则本断言无意义。');
verifyEqual(testCase, perturbedStageDetails.alphaMap, ...
    stageDetails60.alphaMap, 'AbsTol', 0);
verifyEqual(testCase, smoothedPerturbedStage.fine, ...
    smoothedStage60.fine, 'AbsTol', 0);
verifyEqual(testCase, smoothedPerturbedStage.mid, ...
    smoothedStage60.mid, 'AbsTol', 0);
end

function testMidSmoothingConsumesStageProtectionContract(testCase)
%TESTMIDSMOOTHINGCONSUMESSTAGEPROTECTIONCONTRACT T13：提供 stage
%   contract 时，Mid smoothing 只从 protection.smoothingMid 派生 Mid
%   门控，不再读取 noseMask/局部 nose 特判。快照 smoothingMid 取
%   alphaCurve=1 满档（T07），生产 noseMidGate 的强度插值归属
%   effect-strength 侧：midGate = alphaCurve .* (1 - smoothingMid) +
%   (1 - alphaCurve) .* fineStructureGate。该凸组合代数上恒等于生产
%   门控 fineStructureGate .* (1 - .50*nose.*alphaCurve)（快照为最强
%   保护端点，强度无关结构锚点为零 nose 保护端点），与生产仅差乘法
%   结合顺序与 1-x 补码往返的浮点噪声（≤1e-15，T07 推导基线
%   1.11e-16 同量级）。诊断收口：stage 路径不再报告 noseMask/
%   noseMidGate，新增 midGate 快照；legacy 路径字段不变。
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);
verifyTrue(testCase, nnz(beautyMasks.noseMask > 0) > 0, ...
    'fixture 必须包含非空 noseMask，否则 nose 特判退役断言无意义。');

strengths = [0, 25, 50, 75, 100];
for index = 1:numel(strengths)
    strength = strengths(index);
    [smoothedLegacy, legacyDetails] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strength, blemishMap);
    [smoothedStage, stageDetails] = beauty.smoothSkinTexture( ...
        frequency, beautyMasks, strength, blemishMap, protection);
    profile = beautySmoothingProfile(strength);

    % Mid 门控恰为 stage contract 凸组合重算（bit-exact），且与生产
    % 组合式 midStructureGate .* noseMidGate 只差浮点噪声（≤1e-15）。
    expectedMidGate = profile.alphaCurve .* ...
        (1 - protection.smoothingMid) + ...
        (1 - profile.alphaCurve) .* stageDetails.fineStructureGate;
    verifyEqual(testCase, stageDetails.midGate, expectedMidGate, ...
        'AbsTol', 0);
    verifyEqual(testCase, stageDetails.midAlphaMap, ...
        stageDetails.alphaMap .* stageDetails.midGate, 'AbsTol', 0);
    verifyLessThanOrEqual(testCase, ...
        max(abs(stageDetails.midGate(:) - ...
        legacyDetails.midStructureGate(:) .* ...
        legacyDetails.noseMidGate(:))), 1e-15);
    verifyLessThanOrEqual(testCase, ...
        max(abs(stageDetails.midAlphaMap(:) - ...
        legacyDetails.midAlphaMap(:))), 1e-15);
    verifyLessThanOrEqual(testCase, ...
        max(abs(smoothedStage.mid(:) - smoothedLegacy.mid(:))), 1e-15);

    % 结构锚点与统计路径保持生产原值；base identity 与合成公式不变。
    verifyEqual(testCase, stageDetails.midStructureGate, ...
        legacyDetails.midStructureGate, 'AbsTol', 0);
    verifyEqual(testCase, stageDetails.fineEnergy, ...
        legacyDetails.fineEnergy, 'AbsTol', 0);
    verifyEqual(testCase, smoothedStage.base, frequency.base, ...
        'AbsTol', 0);
    verifyEqual(testCase, stageDetails.midRetentionMap, ...
        1 - stageDetails.midAlphaMap .* ...
        (1 - stageDetails.midRetention), 'AbsTol', 0);
end

% 满档端点（alphaCurve=1）：Mid 门控恰为 T07 已验证的快照重算
% midAlphaMap = alphaMap .* (1 - smoothingMid)（≤1e-15 噪声）。
[~, stageDetails100] = beauty.smoothSkinTexture(frequency, ...
    beautyMasks, 100, blemishMap, protection);
verifyLessThanOrEqual(testCase, ...
    max(abs(stageDetails100.midAlphaMap(:) - ...
    stageDetails100.alphaMap(:) .* (1 - protection.smoothingMid(:)))), ...
    1e-15);

% 零强度端点（alphaCurve=0）：凸组合退化为纯结构锚点，Mid 保留率恒 1。
[smoothedStage0, stageDetails0] = beauty.smoothSkinTexture(frequency, ...
    beautyMasks, 0, blemishMap, protection);
verifyEqual(testCase, stageDetails0.midGate, ...
    stageDetails0.fineStructureGate, 'AbsTol', 0);
verifyEqual(testCase, smoothedStage0.mid, frequency.mid, 'AbsTol', 0);

% 负向证明：stage 路径的 Mid 输出对 noseMask 扰动完全不变（Mid 不再
% 读取该字段），legacy 路径则会随之变化。
perturbedMasks = beautyMasks;
perturbedMasks.noseMask = min(1, beautyMasks.noseMask * .5 + .25);
[smoothedPerturbedStage, perturbedStageDetails] = ...
    beauty.smoothSkinTexture(frequency, perturbedMasks, 60, ...
    blemishMap, protection);
[smoothedStage60, stageDetails60] = beauty.smoothSkinTexture( ...
    frequency, beautyMasks, 60, blemishMap, protection);
[~, perturbedLegacyDetails] = beauty.smoothSkinTexture( ...
    frequency, perturbedMasks, 60, blemishMap);
[~, legacyDetails60] = beauty.smoothSkinTexture( ...
    frequency, beautyMasks, 60, blemishMap);
verifyTrue(testCase, ...
    nnz(perturbedLegacyDetails.midAlphaMap ~= ...
    legacyDetails60.midAlphaMap) > 0, ...
    'noseMask 扰动必须确实影响 legacy 路径，否则本断言无意义。');
verifyEqual(testCase, perturbedStageDetails.midAlphaMap, ...
    stageDetails60.midAlphaMap, 'AbsTol', 0);
verifyEqual(testCase, smoothedPerturbedStage.mid, ...
    smoothedStage60.mid, 'AbsTol', 0);

% 诊断收口：stage 路径不再报告 nose 特判字段，新增 midGate 快照；
% legacy 路径字段保持不变。
verifyEqual(testCase, ...
    isfield(stageDetails60, {'noseMask', 'noseMidGate'}), ...
    [false, false], ...
    'stage 路径不得再报告 nose 特判诊断字段。');
verifyTrue(testCase, isfield(stageDetails60, 'midGate'));
verifyTrue(testCase, isfield(legacyDetails60, 'noseMask') && ...
    isfield(legacyDetails60, 'noseMidGate'));
end

function testRuntimeEvidenceAssemblesProducerArtifactsBitExact(testCase)
%TESTRUNTIMEEVIDENCEASSEMBLESPRODUCERARTIFACTSBITEXACT T11：beautifyImage
%   内部组装的运行期 evidence（frequency/blemish）必须与独立调用
%   producer 的产物 bit-exact 一致，证明编排层只搬运 runtime evidence、
%   不改变任何数值；blemish map 不读取美颜强度，不同参数组合下完全一致。
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));
uncachedContext = rmfield(context, 'runtimeCache');
params = struct('smoothingStrength', 60, 'whiteningStrength', 30);
[~, diagnostics] = beautifyImage(image, params, faceBox, uncachedContext);

[beautyMasks, ~] = masks.buildBeautyMasks(image, uncachedContext, faceBox);
[frequency, decompositionDiagnostics] = beauty.decomposeSkinFrequency( ...
    image, faceBox);
[blemishMap, blemishDiagnostics] = beauty.buildBlemishMap( ...
    image, frequency, beautyMasks);

% blemish map 与 blemish 运行期证据：与 producer 逐字段 bit-exact。
verifyEqual(testCase, diagnostics.blemishMap, blemishMap, 'AbsTol', 0);
evidenceNames = {'fineEvidence', 'midEvidence', 'chromaEvidence', ...
    'skinCandidate', 'structureProtectionMask'};
for index = 1:numel(evidenceNames)
    verifyEqual(testCase, ...
        diagnostics.blemish.(evidenceNames{index}), ...
        blemishDiagnostics.(evidenceNames{index}), 'AbsTol', 0);
end

% frequency 分解：与 producer bit-exact。
bandNames = {'base', 'mid', 'fine'};
for index = 1:numel(bandNames)
    verifyEqual(testCase, ...
        diagnostics.frequency.(bandNames{index}), ...
        decompositionDiagnostics.(bandNames{index}), 'AbsTol', 0);
end
verifyEqual(testCase, diagnostics.frequency.reconstructionError, ...
    decompositionDiagnostics.reconstructionError, 'AbsTol', 0);
verifyEqual(testCase, diagnostics.frequency.fineSigma, ...
    decompositionDiagnostics.fineSigma, 'AbsTol', 0);
verifyEqual(testCase, diagnostics.frequency.mediumSigma, ...
    decompositionDiagnostics.mediumSigma, 'AbsTol', 0);

% blemish map 不读取强度：不同参数组合下与 producer 完全一致。
strengthCombos = [0, 100; 100, 0; 100, 100; 25, 75];
for index = 1:size(strengthCombos, 1)
    comboParams = struct( ...
        'smoothingStrength', strengthCombos(index, 1), ...
        'whiteningStrength', strengthCombos(index, 2));
    [~, comboDiagnostics] = beautifyImage(image, comboParams, faceBox, ...
        uncachedContext);
    verifyEqual(testCase, comboDiagnostics.blemishMap, blemishMap, ...
        'AbsTol', 0);
end
end

function testRuntimeEvidenceStaysOutOfPersistedPolicyTimeContext(testCase)
%TESTRUNTIMEEVIDENCESTAYSOUTOFPERSISTEDPOLICYTIMECONTEXT T11 验收：
%   runtime evidence（frequency/blemish）不得成为持久化 policy-time
%   Context 的必要输入——不进 V4 canonical 分层（semantic/
%   processability/evidence/protection），不出现在 T06 policy-time
%   evidence 层，规范化往返后也不引入运行期字段。
[image, faceBox, parsing] = fixtureImage(120, 160);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160]));

runtimeNames = {'runtimeEvidence', 'blemishMap', 'blemish', 'frequency'};
verifyEqual(testCase, isfield(context, runtimeNames), ...
    [false, false, false, false], ...
    '持久化 Context 不得携带 runtime evidence 字段。');
verifyTrue(testCase, isfield(context, 'evidence'));
verifyEqual(testCase, isfield(context.evidence, ...
    {'blemishMap', 'blemish', 'frequency', 'fine', 'mid', 'base'}), ...
    false(1, 6), ...
    'policy-time evidence 层显式不含 blemish/frequency 结果。');

reread = normalizeBeautyContext(image, faceBox, context);
verifyEqual(testCase, isfield(reread, runtimeNames), ...
    [false, false, false, false], ...
    '规范化往返后 Context 不得引入 runtime evidence 字段。');
end

function [image, faceBox, parsing] = fixtureImage(height, width)
image = uint8(ones(height, width, 3) * 145);
[xGrid, yGrid] = meshgrid(1:width, 1:height);
skin = ((xGrid - width * .50) / (width * .33)) .^ 2 + ...
    ((yGrid - height * .43) / (height * .40)) .^ 2 <= 1;
neck = xGrid >= width * .40 & xGrid <= width * .60 & ...
    yGrid >= height * .73 & yGrid <= height * .94;
skin = skin | neck;
for channel = 1:3
    channelImage = image(:, :, channel);
    channelImage(skin) = uint8(168 + 7 * sin(2 * pi * xGrid(skin) / 17));
    image(:, :, channel) = channelImage;
end
nose = ((xGrid - width * .50) / (width * .10)) .^ 2 + ...
    ((yGrid - height * .45) / (height * .20)) .^ 2 <= 1;
image(:, :, 1) = image(:, :, 1) + uint8(12 * nose);
image(:, :, 2) = image(:, :, 2) + uint8(7 * nose);
image(:, :, 3) = image(:, :, 3) + uint8(4 * nose);
image(ceil(height * .45):ceil(height * .55), ...
    ceil(width * .43):ceil(width * .46), :) = uint8(95);
eye = false(height, width);
eye(ceil(height * .30):ceil(height * .33), ...
    ceil(width * .38):ceil(width * .46)) = true;
lip = false(height, width);
lip(ceil(height * .62):ceil(height * .66), ...
    ceil(width * .43):ceil(width * .57)) = true;
faceBox = [round(width * .17), round(height * .08), ...
    round(width * .66), round(height * .67)];
parsing = emptyFaceParsing([height, width]);
parsing.regions.skin = double(skin);
parsing.regionConfidence.skin = double(skin);
parsing.regions.neck = double(neck);
parsing.regionConfidence.neck = double(neck);
parsing.regions.nose = double(nose);
parsing.regionConfidence.nose = double(nose);
parsing.regions.leftEye = double(eye);
parsing.regionConfidence.leftEye = double(eye);
parsing.regions.upperLip = double(lip);
parsing.regionConfidence.upperLip = double(lip);
parsing.regions.lowerLip = double(lip);
parsing.regionConfidence.lowerLip = double(lip);
end

function parsing = emptyFaceParsing(imageSize)
names = faceParsingClassNames();
parsing = struct('regions', struct(), 'regionConfidence', struct());
for index = 1:numel(names)
    parsing.regions.(names{index}) = zeros(imageSize);
    parsing.regionConfidence.(names{index}) = zeros(imageSize);
end
end

function options = emptyBodyParsing(imageSize)
options = struct('probabilities', zeros([imageSize, 20], 'single'));
end

function value = smoothStep(inputValue, low, high)
%SMOOTHSTEP 复现生产 smoothstep 曲线（t^2*(3-2t)），供 tone 重算使用。
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end
