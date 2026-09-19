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
