function tests = testFaceParsingHelpers
tests = functiontests(localfunctions);
end

function testClassNames(testCase)
names = faceParsingClassNames();
verifyEqual(testCase, numel(names), 19);
verifyEqual(testCase, names{1}, 'background');
verifyEqual(testCase, names{19}, 'hat');
end

function testLetterboxAndMap(testCase)
image = uint8(ones(40, 60, 3) * 128);
[networkInput, transform] = prepareFaceParsingInput(image, [10 8 20 16]);
verifyEqual(testCase, size(networkInput), [512 512 3]);
verifyEqual(testCase, transform.inputSize, [512 512]);
logits = zeros(64, 64, 19, 'single'); logits(:, :, 2) = 4;
[masks, confidence, labels] = mapFaceParsingOutput(logits, transform, size(image));
verifyEqual(testCase, size(masks), [40 60 19]);
verifyEqual(testCase, size(confidence), [40 60]);
verifyEqual(testCase, size(labels), [40 60]);
verifyGreaterThan(testCase, max(confidence(:)), .75);
end

function testInjectedContextAndProtection(testCase)
image = uint8(ones(80, 100, 3) * 128);
parsing = syntheticParsing([80 100]);
context = prepareBeautyContext(image, [20 15 60 50], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
verifyEqual(testCase, context.schemaVersion, '3.1');
verifyEqual(testCase, numel(fieldnames(context.regions)), 19);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, [20 15 60 50]);
verifyEqual(testCase, beautyMasks.hardProtectionMask(35, 45), 1);
verifyEqual(testCase, beautyMasks.hardProtectionMask(5, 5), 0);
end

function testInvalidInjectedMask(testCase)
image = uint8(ones(20, 20, 3)); parsing = syntheticParsing([20 20]);
parsing.regions.skin = ones(3);
verifyError(testCase, @() buildBeautyContextFromParsing(image, [2 2 15 15], parsing), ...
    'buildBeautyContextFromParsing:InvalidMask');
end

function testResizeBeautyContextPreservesTargetGeometry(testCase)
image = uint8(ones(40, 60, 3) * 128);
names = faceParsingClassNames();
regions = struct(); confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(40, 60);
    confidence.(names{index}) = zeros(40, 60);
end
regions.skin(10:30, 15:45) = 1;
confidence.skin(10:30, 15:45) = 1;
parsing = struct('regions', regions, 'regionConfidence', confidence);
context = prepareBeautyContext(image, [10 8 30 24], parsing, ...
    emptyBodyParsing(size(image, [1 2])));
resized = resizeBeautyContext(context, [80 120 3], [20 16 60 48]);
verifySize(testCase, resized.skinMask, [80 120]);
verifySize(testCase, resized.textureProtectionMask, [80 120]);
verifyEqual(testCase, resized.imageSize, [80 120 3]);
verifyEqual(testCase, resized.faceBox, [20 16 60 48]);
end

function testResizeBeautyContextIsLightweightAndValidatesTargets(testCase)
image = uint8(ones(40, 60, 3) * 128);
names = faceParsingClassNames();
regions = struct(); confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(40, 60);
    confidence.(names{index}) = zeros(40, 60);
end
regions.skin(10:30, 15:45) = 1;
confidence.skin(10:30, 15:45) = 1;
regions.hair(15:18, 25:35) = 1;
confidence.hair(15:18, 25:35) = 1;
context = prepareBeautyContext(image, [10 8 30 24], ...
    struct('regions', regions, 'regionConfidence', confidence), ...
    emptyBodyParsing(size(image, [1 2])));
resized = resizeBeautyContext(context, [2500 2000 3], [500 400 1200 1600]);
% 无目标原图时保留完整语义概率，供后续保存重建使用。
verifyTrue(testCase, isfield(resized, 'regions'));
verifyTrue(testCase, isfield(resized.regions, 'nose'));
verifySize(testCase, resized.regions.nose, [2500 2000]);
verifyTrue(testCase, isfield(resized, 'regionConfidence'));
verifyFalse(testCase, isfield(resized, 'geometry'));
verifyTrue(testCase, isfield(resized, 'bodySkinMask'));
verifySize(testCase, resized.bodySkinMask, [2500 2000]);
targetImage = imresize(image, [2500, 2000], 'bilinear');
rebuiltContext = resizeBeautyContext(context, [2500, 2000, 3], ...
    [500 400 1200 1600], targetImage);
[resizedMasks, ~] = masks.buildBeautyMasks(targetImage, rebuiltContext, ...
    [500 400 1200 1600]);
% 硬保护由目标图像上的 package 重新生成。
verifyTrue(testCase, all(resizedMasks.hardProtectionMask(:) >= 0) && ...
    all(resizedMasks.hardProtectionMask(:) <= 1));
verifyEqual(testCase, max(resizedMasks.hardProtectionMask(:)), 1);
memoryInfo = whos('resized');
verifyLessThan(testCase, memoryInfo.bytes, 400e6);
verifyError(testCase, @() resizeBeautyContext(context, [80.5 120 3], ...
    [20 16 60 48]), 'resizeBeautyContext:InvalidTarget');
verifyError(testCase, @() resizeBeautyContext(context, [80 120 3], ...
    [0 16 60 48]), 'resizeBeautyContext:InvalidTarget');
verifyError(testCase, @() resizeBeautyContext(context, [80 120 3], ...
    [20 16 102 48]), 'resizeBeautyContext:InvalidTarget');
end

function testModelErrors(testCase)
verifyError(testCase, @() loadFaceParsingModel('missing-face-model.onnx'), ...
    'loadFaceParsingModel:MissingModel');
modelPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'models', ...
    'face_parsing_bisenet_resnet18.onnx');
if isfile(modelPath)
    verifyError(testCase, @() loadFaceParsingModel(modelPath, repmat('0', 1, 64)), ...
        'loadFaceParsingModel:HashMismatch');
end
end

function parsing = syntheticParsing(imageSize)
names = faceParsingClassNames();
regions = struct(); confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidence.(names{index}) = zeros(imageSize);
end
regions.skin(20:60, 25:75) = 1; confidence.skin(20:60, 25:75) = 1;
regions.hair(20:28, 25:75) = 1; confidence.hair(20:28, 25:75) = 1;
regions.leftEye(34:38, 40:48) = 1; confidence.leftEye(34:38, 40:48) = 1;
regions.neck(61:72, 38:62) = 1; confidence.neck(61:72, 38:62) = 1;
parsing = struct('regions', regions, 'regionConfidence', confidence);
end

function options = emptyBodyParsing(imageSize)
options = struct('probabilities', zeros([imageSize, 20], 'single'));
end
