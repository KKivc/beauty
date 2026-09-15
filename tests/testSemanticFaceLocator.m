function tests = testSemanticFaceLocator
%TESTSEMANTICFACELOCATOR 语义人脸校验与定位单元测试。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testWrongBoxUsesStrictAndPredicate(testCase)
imageSize = [20, 20, 3];
candidateBox = [1, 1, 10, 10];
parsing = emptyParsing(imageSize(1:2));
parsing = addFeaturePixels(parsing, {'nose', 'leftEye'});
parsing.regions.skin(1, 1:4) = 1;
parsing.regionConfidence.skin(1, 1:4) = 1;
[isWrong, ~, details] = assessSemanticFaceCandidate( ...
    parsing, candidateBox, imageSize);
verifyTrue(testCase, isWrong);
verifyEqual(testCase, details.featureCount, 2);
verifyEqual(testCase, details.skinCoverage, 0.04, 'AbsTol', 1e-12);

parsing.regions.skin(1, 5) = 1;
parsing.regionConfidence.skin(1, 5) = 1;
isWrong = assessSemanticFaceCandidate(parsing, candidateBox, imageSize);
verifyFalse(testCase, isWrong, '5% coverage is not below the threshold.');

parsing = emptyParsing(imageSize(1:2));
parsing = addFeaturePixels(parsing, {'nose', 'leftEye', 'mouth'});
isWrong = assessSemanticFaceCandidate(parsing, candidateBox, imageSize);
verifyFalse(testCase, isWrong, 'Three feature classes do not meet the AND predicate.');
end

function testTruncationChecksOnlyInteriorRoiEdges(testCase)
imageSize = [20, 30, 3];
candidateBox = [5, 4, 10, 12];
parsing = emptyParsing(imageSize(1:2));
parsing.roiBox = candidateBox;
parsing.regions.skin(4:15, 5:6) = 0.2;
parsing.regionConfidence.skin(4:15, 5:6) = 0.2;
[~, isTruncated] = assessSemanticFaceCandidate( ...
    parsing, candidateBox, imageSize);
verifyTrue(testCase, isTruncated);

edgeParsing = emptyParsing(imageSize(1:2));
edgeParsing.roiBox = [1, 4, 10, 12];
edgeParsing.regions.skin(4:15, 1:2) = 0.2;
edgeParsing.regionConfidence.skin(4:15, 1:2) = 0.2;
[~, isTruncated] = assessSemanticFaceCandidate( ...
    edgeParsing, [1, 4, 10, 12], imageSize);
verifyFalse(testCase, isTruncated);
end

function testSuspiciousCandidateRunsFullParsingOnce(testCase)
sourceImage = uint8(zeros(100, 120, 3));
localParsing = emptyParsing([100, 120]);
fullParsing = emptyParsing([100, 120]);
fullParsing.regions.skin(20:59, 30:69) = 1;
fullParsing.regionConfidence.skin(20:59, 30:69) = 1;
[runner, getCallCount] = countingParsingRunner(localParsing, fullParsing);
options = struct('candidateBoxes', [20, 15, 40, 40], ...
    'parsingRunner', runner);

[faceBox, isSingleFace, details] = detectSingleFace(sourceImage, options);

verifyTrue(testCase, isSingleFace);
verifyEqual(testCase, faceBox, [28, 16, 44, 48]);
verifyTrue(testCase, details.usedFullImageParsing);
verifyEqual(testCase, details.fullParsingCount, 1);
verifyEqual(testCase, getCallCount(), [2, 1]);
end

function testValidLocalParsingSkipsFullFallback(testCase)
sourceImage = uint8(zeros(100, 120, 3));
localParsing = emptyParsing([100, 120]);
localParsing.regions.skin(25:54, 35:64) = 1;
localParsing.regionConfidence.skin(25:54, 35:64) = 1;
localParsing = addFeaturePixels(localParsing, {'nose', 'leftEye', 'mouth'});
options = struct('candidateBoxes', [20, 15, 50, 50], ...
    'localParsing', localParsing, 'fullParsing', emptyParsing([100, 120]));

[faceBox, isSingleFace, details] = detectSingleFace(sourceImage, options);

verifyTrue(testCase, isSingleFace);
verifyNotEmpty(testCase, faceBox);
verifyFalse(testCase, details.usedFullImageParsing);
verifyEqual(testCase, details.fullParsingCount, 0);
end

function testFullFallbackWithoutSemanticFaceReturnsEmpty(testCase)
sourceImage = uint8(zeros(60, 80, 3));
options = struct('candidateBoxes', zeros(0, 4), ...
    'fullParsing', emptyParsing([60, 80]));

[faceBox, isSingleFace, details] = detectSingleFace(sourceImage, options);

verifyFalse(testCase, isSingleFace);
verifyEmpty(testCase, faceBox);
verifySize(testCase, faceBox, [0, 4]);
verifyEqual(testCase, details.fullParsingCount, 1);
end

function testSemanticFaceBoxUsesLargestComponentAndPadding(testCase)
parsing = emptyParsing([100, 120]);
parsing.regions.skin(20:59, 30:69) = 1;
parsing.regionConfidence.skin(20:59, 30:69) = 1;
parsing.regions.nose(80:82, 90:92) = 1;
parsing.regionConfidence.nose(80:82, 90:92) = 1;

[faceBox, hasFace] = semanticFaceBoxFromParsing(parsing, [100, 120, 3]);

verifyTrue(testCase, hasFace);
verifyEqual(testCase, faceBox, [28, 16, 44, 48]);
end

function testNoSemanticFaceReturnsEmpty(testCase)
[faceBox, hasFace] = semanticFaceBoxFromParsing( ...
    emptyParsing([30, 40]), [30, 40, 3]);
verifyFalse(testCase, hasFace);
verifyEmpty(testCase, faceBox);
verifySize(testCase, faceBox, [0, 4]);
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

function parsing = addFeaturePixels(parsing, names)
for index = 1:numel(names)
    row = index + 2;
    col = index + 2;
    parsing.regions.(names{index})(row, col) = 1;
    parsing.regionConfidence.(names{index})(row, col) = 1;
end
end

function [runner, getCallCount] = countingParsingRunner(localParsing, fullParsing)
callCount = 0;
fullCallCount = 0;
runner = @runParsing;
getCallCount = @readCallCount;

    function count = readCallCount
        count = [callCount, fullCallCount];
    end

    function parsing = runParsing(~, ~, phase)
        callCount = callCount + 1;
        if strcmp(phase, 'full')
            fullCallCount = fullCallCount + 1;
            parsing = fullParsing;
        else
            parsing = localParsing;
        end
    end
end
