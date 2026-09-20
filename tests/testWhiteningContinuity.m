function tests = testWhiteningContinuity
%TESTWHITENINGCONTINUITY 验证独立亮度保护和 Context/缓存传播。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testNoseIsNotBlockedByFeatureOrChromaProtection(testCase)
imageSize = [180, 240];
image = uint8(ones([imageSize, 3]) * 150);
faceBox = [1, 1, imageSize(2), imageSize(1)];
parsing = emptyParsing(imageSize);
parsing.regions.skin(:) = 1;
parsing.regionConfidence.skin(:) = 1;
parsing.regions.nose(70:120, 105:135) = 1;
parsing.regionConfidence.nose(70:120, 105:135) = 1;
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, diagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);
nose = false(imageSize);
nose(70:120, 105:135) = true;

verifyTrue(testCase, isfield(context, 'whiteningProtectionMask'));
verifyLessThanOrEqual(testCase, max(beautyMasks.whiteningProtectionMask(nose)), ...
    1e-12, '整个鼻部语义不得成为亮度阻断。');
verifyLessThanOrEqual(testCase, max(beautyMasks.toneProtectionMask(nose)), ...
    1e-12, '整个鼻部语义不得成为色度硬阻断。');
verifyEqual(testCase, diagnostics.whitening.faceScale, min(faceBox(3:4)), ...
    'AbsTol', 0);
verifyEqual(testCase, diagnostics.whitening.radii.eye, .0125 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.whitening.radii.lip, .0100 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.whitening.radii.nostril, .0075 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.whitening.radii.brow, .00375 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
verifyEqual(testCase, diagnostics.whitening.radii.lash, .00375 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
end

function testWhiteningIgnoresChromaProtection(testCase)
imageSize = [80, 100];
image = uint8(ones([imageSize, 3]) * 125);
faceBox = [1, 1, imageSize(2), imageSize(1)];
nose = false(imageSize);
nose(30:50, 45:55) = true;
frequency = beauty.decomposeSkinFrequency(image, faceBox);
beautyMasks = struct( ...
    'skinMask', ones(imageSize), ...
    'strengthMap', ones(imageSize), ...
    'structureProtectionMask', zeros(imageSize), ...
    'whiteningProtectionMask', zeros(imageSize), ...
    'chromaProtectionMask', double(nose), ...
    'toneProtectionMask', double(nose), ...
    'hardProtectionMask', zeros(imageSize));
[white, diagnostics] = beauty.applySkinWhitening( ...
    image, frequency, beautyMasks, 100);

verifyGreaterThan(testCase, median(diagnostics.whiteningSupport(nose)), 0, ...
    '亮度美白不得读取色度保护作为门控。');
verifyEqual(testCase, diagnostics.chromaGate, ones(imageSize), ...
    'AbsTol', 0);
[zeroWhite, ~] = beauty.applySkinWhitening(image, frequency, beautyMasks, 0);
verifyEqual(testCase, zeroWhite.outputImage, image, ...
    '零强度 RGB 必须逐像素保持不变。');
verifyEqual(testCase, white.fineAfter, frequency.fine, 'AbsTol', 1e-12);
verifyEqual(testCase, white.midAfter, frequency.mid, 'AbsTol', 1e-12);
end

function testBrowTransitionDoesNotCreateWideSetback(testCase)
imageSize = [200, 240];
image = uint8(ones([imageSize, 3]) * 150);
faceBox = [1, 1, imageSize(2), imageSize(1)];
parsing = emptyParsing(imageSize);
parsing.regions.skin(:) = 1;
parsing.regionConfidence.skin(:) = 1;
parsing.regions.leftBrow(80:84, 80:160) = .9;
parsing.regionConfidence.leftBrow(80:84, 80:160) = .9;
context = buildBeautyContextFromParsing(image, faceBox, parsing);
[beautyMasks, diagnostics] = masks.buildBeautyMasks( ...
    image, context, faceBox);

near = beautyMasks.whiteningProtectionMask(86:87, 100:140);
far = beautyMasks.whiteningProtectionMask(100:112, 100:140);
verifyLessThanOrEqual(testCase, max(far(:)), 1e-12, ...
    '眉周远区不得保留宽退让带。');
verifyLessThanOrEqual(testCase, max(near(:)), .20, ...
    '眉周近区保护必须保持窄而连续。');
verifyEqual(testCase, diagnostics.whitening.radii.brow, .00375 * min(faceBox(3:4)), ...
    'AbsTol', 1e-12);
end

function testWhiteningLuminanceIsMonotonicAndContextCarriesMask(testCase)
imageSize = [60, 80];
image = uint8(ones([imageSize, 3]) * 135);
faceBox = [1, 1, imageSize(2), imageSize(1)];
parsing = emptyParsing(imageSize);
parsing.regions.skin(10:50, 15:65) = 1;
parsing.regionConfidence.skin(10:50, 15:65) = 1;
bodyOptions = struct('probabilities', zeros([imageSize, 20], 'single'));
context = prepareBeautyContext(image, faceBox, parsing, bodyOptions);
verifyTrue(testCase, isfield(context, 'whiteningProtectionMask'));
verifyTrue(testCase, isfield(context.runtimeCache.beautyMasks, ...
    'whiteningProtectionMask'));

targetSize = [120, 160];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(context, [targetSize, 3], ...
    [1, 1, targetSize(2), targetSize(1)], targetImage);
verifySize(testCase, resized.whiteningProtectionMask, targetSize);
verifyTrue(testCase, isfield(resized.runtimeCache.beautyMasks, ...
    'whiteningProtectionMask'));

frequency = beauty.decomposeSkinFrequency(image, faceBox);
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
strengths = [0, 25, 50, 75, 100];
medians = zeros(size(strengths));
for index = 1:numel(strengths)
    white = beauty.applySkinWhitening(image, frequency, ...
        beautyMasks, strengths(index));
    medians(index) = median(white.outputLuminance(:));
    if strengths(index) == 0
        verifyEqual(testCase, white.outputImage, image);
    end
end
verifyGreaterThanOrEqual(testCase, diff(medians), -2 / 255);
end

function testWhiteningConsumesStageContractInPipeline(testCase)
%TESTWHITENINGCONSUMESSTAGECONTRACTINPIPELINE T18：生产管线向美白注入
%   whitening stage contract（beautifyImage.makeWhiteningStageContract）：
%   美白诊断不再报告 structure/whitening 兼容 alias，改报 T07 whitening
%   快照参考门 whiteningGateSnapshot；脸部浅退让分支由生产端保留，鼻
%   部美白不因 consumer migration 被整体排除；strengthMap/skinMask 继
%   续独立控制效果幅度；输出保持输入尺寸与 uint8 契约。
imageSize = [120, 160];
image = uint8(ones([imageSize, 3]) * 140);
faceBox = [round(imageSize(2) * .17), round(imageSize(1) * .08), ...
    round(imageSize(2) * .66), round(imageSize(1) * .67)];
parsing = emptyParsing(imageSize);
parsing.regions.skin(:) = 1;
parsing.regionConfidence.skin(:) = 1;
parsing.regions.nose(50:80, 70:95) = 1;
parsing.regionConfidence.nose(50:80, 70:95) = 1;
context = prepareBeautyContext(image, faceBox, parsing, ...
    struct('probabilities', zeros([imageSize, 20], 'single')));

params = struct('smoothingStrength', 0, 'whiteningStrength', 50);
[output, diagnostics] = beautifyImage(image, params, faceBox, context);
verifySize(testCase, output, [imageSize, 3]);
verifyClass(testCase, output, 'uint8');
verifyTrue(testCase, nnz(diagnostics.whitening.supportMap) > 0, ...
    '样例必须产生非零美白 support，否则 wiring 断言无意义。');
verifyEqual(testCase, isfield(diagnostics.whitening, ...
    {'structureProtectionMask', 'whiteningProtectionMask'}), ...
    [false, false], ...
    '管线美白诊断不得再报告兼容 alias 保护字段。');
verifyTrue(testCase, isfield(diagnostics.whitening, ...
    'whiteningGateSnapshot'));
verifyEqual(testCase, diagnostics.whitening.hardProtectionMask, ...
    diagnostics.beautyMasks.hardProtectionMask, 'AbsTol', 0);

% T07 快照衔接：whiteningGateSnapshot 与 protection.target.whitening 一致。
[beautyMasks, ~] = masks.buildBeautyMasks(image, ...
    normalizeBeautyContext(image, faceBox, context), faceBox);
protection = masks.buildStageProtectionMasks(beautyMasks);
verifyEqual(testCase, diagnostics.whitening.whiteningGateSnapshot, ...
    1 - protection.target.whitening, 'AbsTol', 0);

% 鼻部不得因 consumer migration 被整体排除：鼻部语义内美白增量非零。
noseRegion = beautyMasks.noseMask > .5;
verifyTrue(testCase, nnz(noseRegion) > 0, ...
    'fixture 必须包含非空 noseMask，否则鼻部断言无意义。');
verifyGreaterThan(testCase, ...
    sum(diagnostics.whitening.delta(noseRegion)), 0, ...
    '鼻部美白不得因 consumer migration 被整体排除。');
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
