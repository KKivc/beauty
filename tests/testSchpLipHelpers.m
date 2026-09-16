function tests = testSchpLipHelpers
tests = functiontests(localfunctions);
end

function testOfficialClassOrder(testCase)
names = schpLipClassNames();
verifyEqual(testCase, numel(names), 20);
verifyEqual(testCase, names([1, 14, 20]), ...
    {'background', 'face', 'rightShoe'});
end

function testOfficialAffineAndBgrNormalization(testCase)
image = zeros(9, 9, 3, 'uint8');
image(:, :, 1) = 10;
image(:, :, 2) = 20;
image(:, :, 3) = 30;
[networkInput, transform] = prepareSchpLipInput(image);
verifySize(testCase, networkInput, [3, 473, 473]);
verifyEqual(testCase, transform.center, single([4, 4]));
verifyEqual(testCase, transform.scale, single([8, 8]));
verifyEqual(testCase, transform.forwardAffine(:, 1:2), ...
    single([59, 0; 0, 59]));
expected = single([(30 / 255 - .406) / .225, ...
    (20 / 255 - .456) / .224, (10 / 255 - .485) / .229]);
verifyEqual(testCase, squeeze(networkInput(:, 237, 237)), expected', ...
    'AbsTol', single(2e-6));

[~, wideTransform] = prepareSchpLipInput(uint8(ones(5, 9, 3)));
verifyEqual(testCase, wideTransform.center, single([4, 2]));
verifyEqual(testCase, wideTransform.scale, single([8, 8]));
end

function testFusionOutputDimensionsAndAffineMap(testCase)
image = uint8(ones(30, 50, 3));
[~, transform] = prepareSchpLipInput(image);
logits = zeros(119, 119, 20, 'single');
logits(:, :, 15) = repmat(single(linspace(-3, 3, 119)), 119, 1);
[probabilities, confidence, labels] = mapSchpLipOutput(logits, transform, size(image));
verifySize(testCase, probabilities, [30, 50, 20]);
verifySize(testCase, confidence, [30, 50]);
verifyClass(testCase, labels, 'uint8');
verifyEqual(testCase, sum(probabilities, 3), ones(30, 50, 'single'), ...
    'AbsTol', single(2e-6));
verifyGreaterThan(testCase, probabilities(15, 48, 15), ...
    probabilities(15, 3, 15));
end

function testMultiOutputAndDimensionExtraction(testCase)
chw = zeros(20, 119, 119, 'single');
chw(15, :, :) = 7;
raw = {zeros(1, 2, 4, 4, 'single'), reshape(chw, [1, 20, 119, 119])};
logits = extractSchpLipLogits(raw);
verifySize(testCase, logits, [119, 119, 20]);
verifyEqual(testCase, logits(1, 1, 15), single(7));

image = uint8(ones(20, 30, 3));
options.runner = @(~) struct('edge', zeros(1, 2, 30, 30, 'single'), ...
    'fusion', reshape(chw, [1, 20, 119, 119]));
probabilities = inferSchpLipProbabilities(image, options);
verifySize(testCase, probabilities, [20, 30, 20]);
verifyGreaterThan(testCase, min(probabilities(:, :, 15), [], 'all'), .97);
end

function testMainPersonStrongWeakColorConnectivityAndExclusion(testCase)
[image, probabilities, referenceMask] = syntheticBodyCase();
[bodyMask, personMask, limbMask] = buildBodySkinMaskFromSchp( ...
    probabilities, referenceMask, image);

verifyTrue(testCase, personMask(20, 20));
verifyFalse(testCase, personMask(20, 110));
verifyGreaterThan(testCase, bodyMask(55, 9), .5);       % 主体强四肢
verifyGreaterThan(testCase, bodyMask(70, 9), .25);      % 肤色匹配且连到强区
verifyEqual(testCase, bodyMask(48, 9), 0);              % glove 排除
verifyEqual(testCase, bodyMask(55, 105), 0);            % 旁人排除
verifyFalse(testCase, limbMask(70, 35));                % 异色弱区排除
verifyFalse(testCase, limbMask(85, 20));                % 未连接弱区排除
verifyGreaterThan(testCase, nnz(bodyMask > 0 & bodyMask < 1), 0); % 软边
end

function testBodySkinMaskFillsSmallClosedHole(testCase)
[image, probabilities, referenceMask] = syntheticLimbCase();
names = schpLipClassNames();
leftArm = find(strcmp(names, 'leftArm'), 1);
probabilities(42:43, 34:35, leftArm) = 0;

[bodyMask, ~, limbMask] = buildBodySkinMaskFromSchp( ...
    probabilities, referenceMask, image);

verifyTrue(testCase, limbMask(42, 34));
verifyGreaterThan(testCase, bodyMask(42, 34), .35);
end

function testBodySkinMaskKeepsOpenFingerGap(testCase)
[image, probabilities, referenceMask] = syntheticFingerCase();
[bodyMask, ~, limbMask] = buildBodySkinMaskFromSchp( ...
    probabilities, referenceMask, image);

% 中间空隙贯通到外部，不应被小孔洞闭合填平。
verifyFalse(testCase, limbMask(25, 40));
verifyEqual(testCase, bodyMask(25, 40), 0);
verifyGreaterThan(testCase, bodyMask(48, 40), .35);
end

function testBodySkinMaskUsesSoftEdgeAndExcludesClothing(testCase)
[image, probabilities, referenceMask] = syntheticLimbCase();
names = schpLipClassNames();
clothes = find(strcmp(names, 'upperClothes'), 1);
probabilities(30:36, 30:45, clothes) = .9;
[bodyMask, ~, limbMask] = buildBodySkinMaskFromSchp( ...
    probabilities, referenceMask, image);

verifyEqual(testCase, bodyMask(32, 35), 0);
verifyFalse(testCase, limbMask(32, 35));
verifyGreaterThan(testCase, nnz(bodyMask > 0 & bodyMask < 1), 0);
end

function testInjectedContextKeepsFaceAndAddsOnlyBody(testCase)
[image, probabilities, referenceMask] = syntheticBodyCase();
parsing = syntheticFaceParsing(size(image, 1:2), referenceMask);
context = prepareBeautyContext(image, [12, 10, 18, 16], parsing, ...
    struct('probabilities', probabilities));
verifySize(testCase, context.bodySkinMask, size(referenceMask));
verifyGreaterThan(testCase, context.faceSkinMask(18, 20), 0);
verifyGreaterThanOrEqual(testCase, context.skinMask, context.faceSkinMask);
verifyGreaterThan(testCase, context.skinMask(55, 9), .5);
end

function testResizeOptionalBodyMask(testCase)
semanticProbabilities = zeros([10, 10, 19], 'single');
context = struct('skinMask', ones(10), 'faceSkinMask', ones(10), ...
    'nonFaceSkinMask', zeros(10), ...
    'textureProtectionMask', zeros(10), ...
    'structureProtectionMask', zeros(10), ...
    'toneProtectionMask', zeros(10), ...
    'strengthMap', ones(10), 'faceStrengthMap', ones(10), ...
    'nonFaceStrengthMap', zeros(10), 'bodySkinMask', eye(10), ...
    'schemaVersion', '3.0', 'semanticProbabilities', semanticProbabilities, ...
    'semanticConfidence', semanticProbabilities, ...
    'imageSize', [10, 10, 3], 'faceBox', [1, 1, 10, 10]);
resized = resizeBeautyContext(context, [20, 30, 3], [2, 2, 10, 10]);
verifySize(testCase, resized.bodySkinMask, [20, 30]);
verifySize(testCase, resized.skinMask, [20, 30]);
end

function testMissingModelIsExplicit(testCase)
verifyError(testCase, @() loadSchpLipModel('missing-schp-lip.onnx'), ...
    'loadSchpLipModel:MissingModel');
end

function [image, probabilities, referenceMask] = syntheticBodyCase()
height = 90;
width = 140;
image = zeros(height, width, 3, 'uint8');
image(:, :, 1) = 165;
image(:, :, 2) = 120;
image(:, :, 3) = 100;
probabilities = zeros(height, width, 20, 'single');
names = schpLipClassNames();
setClass('face', 10:25, 14:29, .9);
setClass('upperClothes', 25:65, 12:40, .8);
setClass('leftArm', 38:64, 7:12, .8);
setClass('leftArm', 65:76, 7:12, .3);
setClass('glove', 46:50, 7:12, .8);
setClass('rightArm', 65:75, 32:38, .3);
image(65:75, 32:38, :) = 20;
setClass('leftLeg', 82:87, 18:23, .3);

setClass('face', 10:25, 105:120, .9);
setClass('upperClothes', 25:65, 100:125, .8);
setClass('rightArm', 38:64, 102:108, .9);

referenceMask = zeros(height, width);
referenceMask(10:25, 14:29) = 1;

    function setClass(name, rows, columns, value)
        index = find(strcmp(names, name), 1);
        probabilities(rows, columns, index) = value;
    end
end

function [image, probabilities, referenceMask] = syntheticLimbCase()
height = 80;
width = 90;
image = repmat(reshape(uint8([165, 120, 100]), 1, 1, 3), height, width);
probabilities = zeros(height, width, 20, 'single');
names = schpLipClassNames();
face = find(strcmp(names, 'face'), 1);
arm = find(strcmp(names, 'leftArm'), 1);
setClass(face, 8:20, 35:48, .9);
setClass(find(strcmp(names, 'upperClothes'), 1), 21:35, 35:48, .9);
setClass(arm, 25:70, 30:55, .9);
referenceMask = zeros(height, width);
referenceMask(8:20, 35:48) = 1;

    function setClass(index, rows, columns, value)
        probabilities(rows, columns, index) = value;
    end
end

function [image, probabilities, referenceMask] = syntheticFingerCase()
[image, probabilities, referenceMask] = syntheticLimbCase();
names = schpLipClassNames();
arm = find(strcmp(names, 'leftArm'), 1);
probabilities(:, :, arm) = 0;
probabilities(20:40, 30:37, arm) = .9;
probabilities(20:40, 43:50, arm) = .9;
probabilities(40:70, 30:50, arm) = .9;
end

function parsing = syntheticFaceParsing(imageSize, skinMask)
names = faceParsingClassNames();
regions = struct();
confidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = zeros(imageSize);
    confidence.(names{index}) = zeros(imageSize);
end
regions.skin = skinMask;
confidence.skin = skinMask;
parsing = struct('regions', regions, 'regionConfidence', confidence);
end
