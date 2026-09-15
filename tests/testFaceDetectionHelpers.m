function tests = testFaceDetectionHelpers
%TESTFACEDETECTIONHELPERS 非 GUI 人脸检测 helper 单元测试。

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testAnnotateFaceDetectionPreservesImageSize(testCase)
sourceImage = uint8(zeros(40, 60, 3));
detectedImage = annotateFaceDetection(sourceImage, [10, 8, 20, 16]);

verifySize(testCase, detectedImage, size(sourceImage));
verifyNotEqual(testCase, detectedImage, sourceImage);
end

function testDetectSingleFaceRejectsNonRgbImage(testCase)
grayscaleImage = uint8(zeros(40, 60));

verifyError(testCase, @() detectSingleFace(grayscaleImage), ...
    'detectSingleFace:InvalidImage');
end
