function tests = testBeautyRegression
%TESTBEAUTYREGRESSION 可重复合成基线、统一指标和单调性测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testSyntheticRegressionEntryPasses(testCase)
report = runBeautyRegression('Assert', true);
verifyTrue(testCase, report.passed);
verifyEqual(testCase, report.strengths, [0, 25, 50, 75, 100]);
verifyEqual(testCase, numel(report.smoothing), 5);
verifyEqual(testCase, numel(report.whitening), 5);
verifyEmpty(testCase, report.violations);
verifyGreaterThan(testCase, report.baseline.noseStructure, 0);
verifyGreaterThan(testCase, report.baseline.outsideStructure, 0);
verifyGreaterThanOrEqual(testCase, ...
    report.baseline.noseStructure, ...
    report.thresholds.noseStructureLowerBound);
verifyGreaterThanOrEqual(testCase, ...
    report.baseline.outsideStructure, ...
    report.thresholds.outsideStructureLowerBound);
end

function testStructureMetricsUseOneFixedMeasurementContract(testCase)
report = runBeautyRegression();
configs = [report.smoothing.config];
verifyTrue(testCase, all(strcmp({configs.colorSpace}, 'YCbCr')));
verifyEqual(testCase, unique([configs.lowPassSigma]), ...
    configs(1).lowPassSigma, 'AbsTol', 1e-12);
verifyEqual(testCase, unique([configs.structurePercentile]), ...
    configs(1).structurePercentile, 'AbsTol', 1e-12);
verifyTrue(testCase, all([report.smoothing.sameSize]));
verifyTrue(testCase, all([report.smoothing.sameChannels]));
verifyLessThanOrEqual(testCase, ...
    max([report.smoothing.backgroundMaxChange]), 1);
verifyEqual(testCase, ...
    max([report.smoothing.hardProtectionMaxChange]), 0);
end

