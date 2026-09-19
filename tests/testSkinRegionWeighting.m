function tests = testSkinRegionWeighting
%TESTSKINREGIONWEIGHTING 验证脸外皮肤的非线性弱化和独立色调统计。

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testNonFaceSmoothingIsWeakAndNonlinear(testCase)
imageSize = [180, 240];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 14 * sin(2 * pi * xGrid / 5) .* sin(2 * pi * yGrid / 7);
sourceGray = uint8(round(145 + texture));
sourceImage = repmat(sourceGray, [1, 1, 3]);

faceRegion = false(imageSize);
faceRegion(45:125, 95:174) = true;
bodyRegion = false(imageSize);
bodyRegion(45:125, 15:94) = true;
skinMask = faceRegion | bodyRegion;
faceBox = [95, 45, 80, 80];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

strengths = [25, 100];
faceChange = zeros(size(strengths));
bodyChange = zeros(size(strengths));
for index = 1:numel(strengths)
    outputImage = beautifyImage(sourceImage, struct( ...
        'smoothingStrength', strengths(index), 'whiteningStrength', 0), ...
        faceBox, context);
    difference = mean(abs(double(outputImage) - double(sourceImage)), 3);
    faceInterior = faceRegion & xGrid >= 108 & xGrid <= 161 & ...
        yGrid >= 58 & yGrid <= 111;
    bodyInterior = bodyRegion & xGrid >= 28 & xGrid <= 81 & ...
        yGrid >= 58 & yGrid <= 111;
    faceChange(index) = mean(difference(faceInterior));
    bodyChange(index) = mean(difference(bodyInterior));
end

verifyGreaterThan(testCase, faceChange(end), .5);
verifyGreaterThan(testCase, bodyChange(end), 0);
verifyLessThanOrEqual(testCase, bodyChange(end), .80 * faceChange(end), ...
    '身体皮肤需要达到参考级均肤，但整体变化仍应弱于脸部。');
verifyLessThan(testCase, bodyChange(1), .15 * faceChange(end) + .1);
end

function testNonFaceWhiteningIsWeakAndUsesOwnTone(testCase)
imageSize = [140, 220];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 7 * sin(2 * pi * xGrid / 9) .* sin(2 * pi * yGrid / 11);
sourceGray = 170 * ones(imageSize);
faceRegion = false(imageSize);
faceRegion(35:105, 95:164) = true;
bodyRegion = false(imageSize);
bodyRegion(35:105, 15:84) = true;
sourceGray(faceRegion) = 120 + texture(faceRegion);
sourceGray(bodyRegion) = 170 + texture(bodyRegion);
sourceImage = repmat(uint8(round(sourceGray)), [1, 1, 3]);
skinMask = faceRegion | bodyRegion;
faceBox = [95, 35, 70, 70];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, context);
difference = mean(double(outputImage) - double(sourceImage), 3);
faceInterior = faceRegion & xGrid >= 106 & xGrid <= 153 & ...
    yGrid >= 46 & yGrid <= 93;
bodyInterior = bodyRegion & xGrid >= 26 & xGrid <= 73 & ...
    yGrid >= 46 & yGrid <= 93;
faceIncrease = mean(difference(faceInterior));
bodyIncrease = mean(difference(bodyInterior));

verifyGreaterThan(testCase, faceIncrease, 0);
verifyGreaterThan(testCase, bodyIncrease, 0);
verifyLessThanOrEqual(testCase, bodyIncrease, .55 * faceIncrease);
end

function testRegionalSmoothingKeepsIndependentMedians(testCase)
imageSize = [160, 220];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
texture = 12 * sin(2 * pi * xGrid / 6) .* sin(2 * pi * yGrid / 8);
sourceGray = 155 * ones(imageSize);
faceRegion = false(imageSize);
faceRegion(40:119, 95:174) = true;
bodyRegion = false(imageSize);
bodyRegion(40:119, 15:94) = true;
sourceGray(faceRegion) = 112 + texture(faceRegion);
sourceGray(bodyRegion) = 188 + texture(bodyRegion);
sourceImage = repmat(uint8(round(sourceGray)), [1, 1, 3]);
skinMask = faceRegion | bodyRegion;
faceBox = [95, 40, 80, 80];
context = regionalContext(imageSize, faceBox, skinMask, faceRegion);

outputImage = beautifyImage(sourceImage, struct( ...
    'smoothingStrength', 100, 'whiteningStrength', 0), faceBox, context);
inputY = im2double(rgb2ycbcr(sourceImage));
outputY = im2double(rgb2ycbcr(outputImage));
faceInterior = faceRegion & xGrid >= 108 & xGrid <= 161 & ...
    yGrid >= 53 & yGrid <= 106;
bodyInterior = bodyRegion & xGrid >= 28 & xGrid <= 81 & ...
    yGrid >= 53 & yGrid <= 106;

verifyLessThanOrEqual(testCase, abs(median(outputY(faceInterior)) - ...
    median(inputY(faceInterior))), .01);
verifyLessThanOrEqual(testCase, abs(median(outputY(bodyInterior)) - ...
    median(inputY(bodyInterior))), .01);
end

function testSemanticAndProcessabilityLayersAreValidAndConsistent(testCase)
%TESTSEMANTICANDPROCESSABILITYLAYERSAREVALIDANDCONSISTENT prepare 输出
%   必须携带合法的 V4 semantic/processability 分层：semantic.regions/
%   confidence 键名限定 19 类词表，所有 Mask 为 HxW、real、finite、
%   [0,1]；分层与旧字段的兼容关系为 bit-exact，分组语义配方可由词表
%   语义逐位复现。
[image, faceBox, parsing] = layeredFixture();
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, 1:2)));

verifyTrue(testCase, isfield(context, 'semantic'));
verifyTrue(testCase, isfield(context, 'processability'));
verifyTrue(testCase, isscalar(context.semantic));
verifyTrue(testCase, isscalar(context.processability));

names = faceParsingClassNames();
verifyEqual(testCase, sort(fieldnames(context.semantic.regions)), ...
    sort(names(:)), 'semantic.regions 必须恰为 19 类词表。');
verifyEqual(testCase, sort(fieldnames(context.semantic.confidence)), ...
    sort(names(:)), 'semantic.confidence 必须恰为 19 类词表。');
assertValidLayerMasks(testCase, context.semantic.regions, ...
    size(image, 1:2), names);
assertValidLayerMasks(testCase, context.semantic.confidence, ...
    size(image, 1:2), names);

grouped = {'faceSkin', 'nose', 'ear', 'eye', 'brow', 'lip', 'hair', ...
    'neck', 'bodySkin'};
verifyTrue(testCase, all(isfield(context.semantic, grouped)), ...
    'semantic 层必须发布全部分组语义字段。');
assertValidLayerMasks(testCase, context.semantic, size(image, 1:2), grouped);
verifyTrue(testCase, isfield(context.processability, 'skin'));
assertValidLayerMasks(testCase, context.processability, ...
    size(image, 1:2), {'skin'});

% 与旧字段的兼容关系（兼容阶段 bit-exact，旧 consumer 零修改）。
verifyEqual(testCase, context.processability.skin, context.skinMask, ...
    'AbsTol', 0);
verifyEqual(testCase, context.semantic.bodySkin, context.bodySkinMask, ...
    'AbsTol', 0);
verifyEqual(testCase, context.semantic.regions, context.regions, ...
    'AbsTol', 0);
verifyEqual(testCase, context.semantic.confidence, ...
    context.regionConfidence, 'AbsTol', 0);

% 分组语义来源映射：逐类别 min(region, confidence) 后跨类别取 max。
verifyEqual(testCase, context.semantic.faceSkin, ...
    semanticUnionOf(context, {'skin', 'nose', 'leftEar', 'rightEar'}), ...
    'AbsTol', 0);
verifyEqual(testCase, context.semantic.nose, ...
    semanticUnionOf(context, {'nose'}), 'AbsTol', 0);
verifyEqual(testCase, context.semantic.ear, ...
    semanticUnionOf(context, {'leftEar', 'rightEar'}), 'AbsTol', 0);
verifyEqual(testCase, context.semantic.eye, ...
    semanticUnionOf(context, {'leftEye', 'rightEye'}), 'AbsTol', 0);
verifyEqual(testCase, context.semantic.brow, ...
    semanticUnionOf(context, {'leftBrow', 'rightBrow'}), 'AbsTol', 0);
verifyEqual(testCase, context.semantic.lip, ...
    semanticUnionOf(context, {'mouth', 'upperLip', 'lowerLip'}), ...
    'AbsTol', 0);
verifyEqual(testCase, context.semantic.hair, ...
    semanticUnionOf(context, {'hair'}), 'AbsTol', 0);
verifyEqual(testCase, context.semantic.neck, ...
    semanticUnionOf(context, {'neck'}), 'AbsTol', 0);
end

function testSchpBodySkinRaisesCoverageAndRefreshesLayers(testCase)
%TESTSCHPBODYSKINRAISESCOVERAGEANDREFRESHERSLAYERS 注入 SCHP face +
%   leftArm 概率后，prepare 合并身体皮肤：skin coverage 不下降（此
%   处严格增大），semantic.bodySkin 与 processability.skin 按最终皮
%   肤域刷新；零 SCHP 路径的分层同样与旧字段 bit-exact。
[image, faceBox, parsing] = layeredFixture();
zeroBody = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, 1:2)));
withLimb = prepareBeautyContext(image, faceBox, parsing, ...
    limbBodyParsing(size(image, 1:2)));

verifyTrue(testCase, nnz(withLimb.bodySkinMask > .5) > 0, ...
    '注入 leftArm 概率必须产生非空身体皮肤。');
verifyGreaterThan(testCase, nnz(withLimb.skinMask > .5), ...
    nnz(zeroBody.skinMask > .5), ...
    '合并身体皮肤后 skin coverage 必须不下降。');
verifyEqual(testCase, withLimb.semantic.bodySkin, ...
    withLimb.bodySkinMask, 'AbsTol', 0);
verifyEqual(testCase, withLimb.processability.skin, ...
    withLimb.skinMask, 'AbsTol', 0);
verifyEqual(testCase, withLimb.semantic.regions, withLimb.regions, ...
    'AbsTol', 0);
verifyEqual(testCase, zeroBody.semantic.bodySkin, ...
    zeroBody.bodySkinMask, 'AbsTol', 0);
verifyEqual(testCase, zeroBody.processability.skin, ...
    zeroBody.skinMask, 'AbsTol', 0);
end

function testProcessabilitySkinIsIndependentOfProtection(testCase)
%TESTPROCESSABILITYSKINISINDEPENDENTOFPROTECTION processability.skin
%   表达允许进入皮肤算法的皮肤域，明确不等于 1-protection：合成样例
%   背景 protection 为 0，而 processability 皮肤域为 0。
[image, faceBox, parsing] = layeredFixture();
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, 1:2)));
verifyNotEqual(testCase, context.processability.skin, ...
    1 - context.textureProtectionMask, ...
    'processability.skin 不得等价于 1-textureProtection。');
verifyNotEqual(testCase, context.processability.skin, ...
    1 - context.structureProtectionMask, ...
    'processability.skin 不得等价于 1-structureProtection。');
verifyNotEqual(testCase, context.processability.skin, ...
    1 - context.toneProtectionMask, ...
    'processability.skin 不得等价于 1-toneProtection。');
end

function context = regionalContext(imageSize, faceBox, skinMask, faceSkinMask)
semanticProbabilities = zeros([imageSize, 19], 'single');
nonFaceSkinMask = max(double(skinMask) - double(faceSkinMask), 0);
context = struct( ...
    'skinMask', double(skinMask), ...
    'faceSkinMask', double(faceSkinMask), ...
    'nonFaceSkinMask', nonFaceSkinMask, ...
    'textureProtectionMask', zeros(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'toneProtectionMask', zeros(imageSize), ...
    'strengthMap', max(double(faceSkinMask), .55 * nonFaceSkinMask), ...
    'faceStrengthMap', double(faceSkinMask), ...
    'nonFaceStrengthMap', .55 * nonFaceSkinMask, ...
    'schemaVersion', '3.0', ...
    'semanticProbabilities', semanticProbabilities, ...
    'semanticConfidence', semanticProbabilities, ...
    'imageSize', [imageSize, 3], ...
    'faceBox', faceBox);
end

function [image, faceBox, parsing] = layeredFixture
%LAYEREDFIXTURE 40x60 确定性合成人像（与 testBeautyContextV3 的
%   fixtureContext 同公式），用于 V4 分层字段的数值与一致性断言。
image = uint8(ones(40, 60, 3) * 145);
image(17:24, 28:32, :) = 105;
faceBox = [10, 8, 30, 24];
parsing = emptyFaceParsing([40, 60]);
parsing.regions.skin(10:30, 15:45) = 1;
parsing.regionConfidence.skin(10:30, 15:45) = 1;
parsing.regions.nose(16:28, 27:33) = .8;
parsing.regionConfidence.nose(16:28, 27:33) = .8;
parsing.regions.leftEye(18:20, 22:27) = 1;
parsing.regionConfidence.leftEye(18:20, 22:27) = 1;
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

function options = limbBodyParsing(imageSize)
%LIMBBODYPARSING 注入 SCHP face + leftArm 概率（与主脸前景同一连通
%   域），触发 buildBodySkinMaskFromSchp 的身体皮肤合并路径。
probabilities = zeros([imageSize, 20], 'single');
names = schpLipClassNames();
faceIndex = find(strcmp(names, 'face'), 1);
armIndex = find(strcmp(names, 'leftArm'), 1);
probabilities(10:30, 15:45, faceIndex) = 1;
probabilities(26:40, 30:44, armIndex) = .9;
options = struct('probabilities', probabilities);
end

function union = semanticUnionOf(context, names)
%SEMANTICUNIONOF 在测试侧复现生产 semanticUnion 配方。
union = zeros(size(context.skinMask));
for index = 1:numel(names)
    union = max(union, min(context.regions.(names{index}), ...
        context.regionConfidence.(names{index})));
end
union = min(max(double(union), 0), 1);
end

function assertValidLayerMasks(testCase, value, imageSize, fieldNames)
%ASSERTVALIDLAYERMASKS 断言指定字段均为 HxW、real、finite、[0,1]。
for index = 1:numel(fieldNames)
    name = fieldNames{index};
    mask = value.(name);
    verifyEqual(testCase, size(mask), imageSize, ...
        sprintf('字段 %s 的尺寸与图像不匹配。', name));
    verifyTrue(testCase, isreal(mask) && all(isfinite(mask(:))), ...
        sprintf('字段 %s 必须为 real 且 finite。', name));
    verifyTrue(testCase, all(mask(:) >= 0) && all(mask(:) <= 1), ...
        sprintf('字段 %s 的取值必须在 [0,1] 内。', name));
end
end
