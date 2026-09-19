function tests = testResidualFeatureDiagnostics
%TESTRESIDUALFEATUREDIAGNOSTICS 验证残留五官诊断入口的边界输入。
tests = functiontests(localfunctions);
end

function setupOnce(~)
testRoot = fileparts(mfilename('fullpath'));
addpath('E:\image_beauty\src', '-begin');
addpath(testRoot, '-begin');
end

function testRequiresManualRoi(testCase)
options = baselineOptions();
verifyError(testCase, @() diagnoseResidualFeatureArtifacts( ...
    'not-an-image.png', tempdir, options), ...
    'diagnoseResidualFeatureArtifacts:MissingRoi');
end

function testRejectsInvalidRoiBeforeReadingImage(testCase)
options = baselineOptions();
options.earRoi = [0, 20, 10, 10];
verifyError(testCase, @() diagnoseResidualFeatureArtifacts( ...
    'not-an-image.png', tempdir, options), ...
    'diagnoseResidualFeatureArtifacts:InvalidRoi');
end

function testRejectsMissingImageAfterRoiValidation(testCase)
options = baselineOptions();
options.nostrilRoi = [1, 1, 8, 8];
verifyError(testCase, @() diagnoseResidualFeatureArtifacts( ...
    'not-an-image.png', tempdir, options), ...
    'diagnoseResidualFeatureArtifacts:MissingImage');
end

function testAcceptsCurrentProductionBaseline(testCase)
taskRoot = fileparts(fileparts(mfilename('fullpath')));
options = struct('earRoi', [1, 1, 8, 8], ...
    'productionRoot', taskRoot);
verifyError(testCase, @() diagnoseResidualFeatureArtifacts( ...
    'not-an-image.png', tempdir, options), ...
    'diagnoseResidualFeatureArtifacts:MissingImage');
end

function options = baselineOptions()
options = struct('productionRoot', 'E:\image_beauty', ...
    'smoothingStrength', 100, 'whiteningStrength', 15);
end
