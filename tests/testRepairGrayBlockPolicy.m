function tests = testRepairGrayBlockPolicy
%TESTREPAIRGRAYBLOCKPOLICY 验证 Repair 的结构不可放宽与紧凑斑点策略。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testPolicyContractKeepsNonRelaxableStructure(testCase)
imageSize = [80, 100];
protection = makeRepairProtection(imageSize);
protection.support.repairMid(:) = .60;
protection.regionBandFine(20:25, 30:35) = .95;
protection.regionBandMid(20:25, 30:35) = .80;

withoutBlemish = beauty.repairStageContract(protection, zeros(imageSize));
withBlemish = beauty.repairStageContract(protection, ones(imageSize));
critical = false(imageSize);
critical(20:25, 30:35) = true;
ordinary = ~critical;

verifyTrue(testCase, withBlemish.policyRepairEnabled, ...
    '存在 policy region band 时必须启用严格 Repair 策略。');
verifyEqual(testCase, withBlemish.support.repairMid(critical), ...
    withoutBlemish.support.repairMid(critical), 'AbsTol', 0, ...
    '高瑕疵置信度不得削弱关键结构保护。');
verifyLessThanOrEqual(testCase, ...
    withBlemish.support.repairMid(ordinary), ...
    withoutBlemish.support.repairMid(ordinary) + 1e-12, ...
    '普通结构仍允许有限的 blemish 退让。');
verifyEqual(testCase, withBlemish.nonRelaxableProtection(critical), ...
    .95 * ones(nnz(critical), 1), 'AbsTol', 0);
end

function testCompactPolicyRejectsLongAndBroadCandidates(testCase)
imageSize = [120, 160];
frequency = struct( ...
    'base', zeros(imageSize), ...
    'mid', .02 * ones(imageSize), ...
    'fine', .01 * ones(imageSize), ...
    'sourceLuminance', .03 * ones(imageSize), ...
    'imageSize', [imageSize, 3], ...
    'faceScale', 120, ...
    'faceBox', [20, 10, 120, 100]);
frequency.fine(40:44, 50:54) = .20;
frequency.fine(70:74, 60:100) = .20;
frequency.fine(85:105, 105:125) = .20;

beautyMasks = struct( ...
    'skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'nonFaceStrengthMap', zeros(imageSize));
protection = makeRepairProtection(imageSize);
% 非零 policy band 只用于打开 V4 Repair policy，不覆盖候选区域。
protection.regionBandFine(5, 5) = .95;
blemishMap = zeros(imageSize);
blemishMap(40:44, 50:54) = .95;
blemishMap(70:74, 60:100) = .95;
blemishMap(85:105, 105:125) = .95;

contract = beauty.repairStageContract(protection, blemishMap);
[~, diagnostics] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100, contract);

compact = false(imageSize);
compact(40:44, 50:54) = true;
longLine = false(imageSize);
longLine(70:74, 60:100) = true;
broadArea = false(imageSize);
broadArea(85:105, 105:125) = true;

verifyTrue(testCase, diagnostics.policyRepairEnabled);
verifyTrue(testCase, any(diagnostics.blobMask(compact)));
verifyFalse(testCase, any(diagnostics.blobMask(longLine)));
verifyFalse(testCase, any(diagnostics.blobMask(broadArea)));
verifyGreaterThan(testCase, max(diagnostics.fineWeight(compact)), 0, ...
    '紧凑斑点必须保留 Fine 修复。');
verifyEqual(testCase, max(diagnostics.fineWeight(longLine)), 0, 'AbsTol', 0);
verifyEqual(testCase, max(diagnostics.fineWeight(broadArea)), 0, 'AbsTol', 0);
verifyEqual(testCase, max(diagnostics.mediumWeight(longLine)), 0, 'AbsTol', 0);
verifyEqual(testCase, max(diagnostics.mediumWeight(broadArea)), 0, 'AbsTol', 0);
verifyLessThanOrEqual(testCase, diagnostics.referenceRadius, 12);
end

function testCompatContractDoesNotEnableNewPolicy(testCase)
imageSize = [40, 50];
protection = makeRepairProtection(imageSize);
contract = beauty.repairStageContract(protection, ones(imageSize));
verifyFalse(testCase, contract.policyRepairEnabled, ...
    '没有新增 policy evidence 的兼容路径不得静默切换 Repair 策略。');

frequency = struct('base', zeros(imageSize), 'mid', zeros(imageSize), ...
    'fine', zeros(imageSize), 'sourceLuminance', zeros(imageSize), ...
    'imageSize', [imageSize, 3], 'faceScale', 40, ...
    'faceBox', [1, 1, 40, 40]);
beautyMasks = struct('skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), 'nonFaceStrengthMap', zeros(imageSize));
[~, diagnostics] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, ones(imageSize), 100, contract);
verifyFalse(testCase, diagnostics.policyRepairEnabled);
verifyEqual(testCase, diagnostics.compactCandidate, ...
    true(imageSize), 'AbsTol', 0);
end

function testMissingReferenceDisablesRepairWeights(testCase)
imageSize = [40, 50];
frequency = struct( ...
    'base', zeros(imageSize), ...
    'mid', .03 * ones(imageSize), ...
    'fine', .06 * ones(imageSize), ...
    'sourceLuminance', .09 * ones(imageSize), ...
    'imageSize', [imageSize, 3], ...
    'faceScale', 40, ...
    'faceBox', [1, 1, 40, 40]);
frequency.fine(20:22, 24:26) = .20;
frequency.mid(20:22, 24:26) = .10;

beautyMasks = struct( ...
    'skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'nonFaceStrengthMap', zeros(imageSize));
protection = makeRepairProtection(imageSize);
protection.support.repairFine(:) = 1;
protection.regionBandFine(5, 5) = .95;
blemishMap = zeros(imageSize);
blemishMap(20:22, 24:26) = .95;
contract = beauty.repairStageContract(protection, blemishMap);

[repaired, diagnostics] = beauty.repairSkinBlemishes( ...
    frequency, beautyMasks, blemishMap, 100, contract);
missingReference = diagnostics.referenceWeight <= eps;
verifyTrue(testCase, any(missingReference(:)));
verifyEqual(testCase, diagnostics.fineWeight(missingReference), ...
    zeros(nnz(missingReference), 1), 'AbsTol', 0);
verifyEqual(testCase, diagnostics.mediumWeight(missingReference), ...
    zeros(nnz(missingReference), 1), 'AbsTol', 0);
verifyEqual(testCase, repaired.fine, frequency.fine, 'AbsTol', 0);
verifyEqual(testCase, repaired.mid, frequency.mid, 'AbsTol', 0);
end

function protection = makeRepairProtection(imageSize)
zero = zeros(imageSize);
protection = struct( ...
    'hard', zero, ...
    'target', struct('repairFine', zero, 'repairMid', zero), ...
    'support', struct('repairFine', zero, 'repairMid', zero), ...
    'noseMidProtection', zero, ...
    'regionBandFine', zero, ...
    'regionBandMid', zero);
end
