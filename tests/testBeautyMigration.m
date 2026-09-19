function tests = testBeautyMigration
%TESTBEAUTYMIGRATION 验证瑕疵、统一肤色和结构感知美白模块。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testBlemishMapIsFixedAndContinuous(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, diagnostics] = beauty.buildBlemishMap( ...
    image, frequency, beautyMasks);
[secondMap, secondDiagnostics] = beauty.buildBlemishMap( ...
    image, frequency, beautyMasks);

verifySize(testCase, blemishMap, [120, 160]);
verifyGreaterThanOrEqual(testCase, min(blemishMap(:)), 0);
verifyLessThanOrEqual(testCase, max(blemishMap(:)), 1);
verifyEqual(testCase, secondMap, blemishMap, 'AbsTol', 1e-12);
verifyEqual(testCase, secondDiagnostics.fineEvidence, ...
    diagnostics.fineEvidence, 'AbsTol', 1e-12);
verifyTrue(testCase, all(isfield(diagnostics, ...
    {'fineEvidence', 'midEvidence', 'chromaEvidence', ...
    'structureProtectionMask', 'skinCandidate'})));
end

function testBlemishRepairKeepsBaseAndSeparatesWeights(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);
strengths = [0, 25, 50, 75, 100];
fineEnergy = zeros(size(strengths));
blemishEnergy = zeros(size(strengths));
for index = 1:numel(strengths)
    [repaired, details] = beauty.repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, strengths(index));
    verifyEqual(testCase, repaired.base, frequency.base, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, repaired.mid, ...
        frequency.mid + details.mediumCorrection, 'AbsTol', 1e-12);
    fineEnergy(index) = details.fineEnergyAfter;
    blemishEnergy(index) = details.blemishEnergyAfter;
end
verifyEqual(testCase, fineEnergy(1), fineEnergy(1), 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(fineEnergy) <= 1e-10));
verifyTrue(testCase, all(diff(blemishEnergy) <= 1e-10));
verifyTrue(testCase, any(blemishMap(:) > 0));
end

function testToneUsesOneCandidateAndZeroIsIdentity(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(image, frequency, beautyMasks);
[tone, diagnostics] = beauty.normalizeSkinTone(image, frequency, ...
    beautyMasks, blemishMap, 50);
[zeroTone, ~] = beauty.normalizeSkinTone(image, frequency, ...
    beautyMasks, blemishMap, 0);

verifyEqual(testCase, tone.candidateCb, diagnostics.candidateCb, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, tone.candidateCr, diagnostics.candidateCr, ...
    'AbsTol', 1e-12);
verifyEqual(testCase, size(tone.outputImage), size(image));
verifyEqual(testCase, zeroTone.outputImage, image);
verifyEqual(testCase, max(abs(diagnostics.deltaCb(:))) <= .55, true);
verifyEqual(testCase, max(abs(diagnostics.deltaCr(:))) <= .55, true);
end

function testWhiteningIsIndependentAndProtected(testCase)
[image, faceBox, parsing] = fixtureImage(120, 160);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([120, 160])));
[beautyMasks, ~] = masks.buildBeautyMasks(image, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(image, faceBox);
[white, diagnostics] = beauty.applySkinWhitening( ...
    image, frequency, beautyMasks, 50);
[zeroWhite, ~] = beauty.applySkinWhitening(image, frequency, beautyMasks, 0);

verifyEqual(testCase, white.fineAfter, frequency.fine, 'AbsTol', 1e-12);
verifyEqual(testCase, white.midAfter, frequency.mid, 'AbsTol', 1e-12);
verifyTrue(testCase, diagnostics.whiteningCurve > 0);
verifyGreaterThanOrEqual(testCase, diagnostics.whiteningCurve, 0);
verifyLessThanOrEqual(testCase, diagnostics.whiteningCurve, 1);
verifyEqual(testCase, zeroWhite.outputImage, image);
verifyEqual(testCase, white.outputLuminance, ...
    frequency.sourceLuminance + diagnostics.delta, 'AbsTol', 1e-12);
verifyEqual(testCase, double(max(white.whiteningSupport( ...
    beautyMasks.hardProtectionMask >= .999))), 0, 'AbsTol', 1e-12);
end

function testV3DiagnosticsExposeMigrationResults(testCase)
[image, faceBox, parsing] = fixtureImage(96, 128);
context = normalizeBeautyContext(image, faceBox, ...
    prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([96, 128])));
[output, diagnostics] = beautifyImage(image, struct( ...
    'smoothingStrength', 75, 'whiteningStrength', 25), faceBox, context);

verifySize(testCase, output, size(image));
verifyTrue(testCase, isfield(diagnostics, 'blemishMap'));
verifyTrue(testCase, isfield(diagnostics, 'repairResult'));
verifyTrue(testCase, isfield(diagnostics, 'skinToneResult'));
verifyTrue(testCase, isfield(diagnostics, 'whiteningResult'));
verifyEqual(testCase, diagnostics.compose.alphaMap, ...
    max(cat(3, diagnostics.compose.smoothingAlpha, ...
    diagnostics.compose.baseSupport, diagnostics.compose.whiteningSupport, ...
    diagnostics.compose.toneSupport), ...
    [], 3), 'AbsTol', 1e-12);
verifyEqual(testCase, output(repmat(diagnostics.beautyMasks.hardProtectionMask >= .999, ...
    [1, 1, 3])), image(repmat(diagnostics.beautyMasks.hardProtectionMask >= .999, ...
    [1, 1, 3])));
end

function testMigrationToV4CanonicalKeepsAliasesSeparate(testCase)
%TESTMIGRATIONTOV4CANONICALKEEPSALIASESSEPARATE v3.1 → V4 canonical：
%   T08 起迁移必须补齐 T05/T06/T07 遗留——源 Context 已携带的
%   semantic 分组字段、processability/evidence/protection 分层与
%   diagnostics.policyEvidence 元数据原样带入 canonical 层，不得再丢；
%   legacy general masks 仅保留为顶层 compat alias；迁移产物可被
%   reader 读回。夹具模拟 T05--T07 期间生产链输出的 v3.1 Context
%   （带分层、契约戳 '3.1'）。
[image, faceBox, parsing] = fixtureImage(96, 128);
v31 = makeLayeredV31Context(image, faceBox, parsing);
v4 = migrateBeautyContext(v31, '4.0');

verifyEqual(testCase, v4.schemaVersion, '4.0');
verifyTrue(testCase, all(isfield(v4.semantic, ...
    {'regions', 'confidence', 'faceSkin', 'bodySkin'})));
verifyEqual(testCase, v4.semantic.regions.skin, ...
    v31.semantic.regions.skin, 'AbsTol', 0);
verifyEqual(testCase, v4.semantic.confidence.skin, ...
    v31.semantic.confidence.skin, 'AbsTol', 0);
verifyEqual(testCase, v4.semantic.faceSkin, v31.semantic.faceSkin, ...
    'AbsTol', 0);
verifyEqual(testCase, v4.semantic.bodySkin, v31.semantic.bodySkin, ...
    'AbsTol', 0);
verifyEqual(testCase, v4.processability, v31.processability, 'AbsTol', 0);
verifyEqual(testCase, v4.evidence, v31.evidence, 'AbsTol', 0);
verifyEqual(testCase, v4.protection, v31.protection, 'AbsTol', 0);
verifyEqual(testCase, v4.diagnostics.policyEvidence, ...
    v31.diagnostics.policyEvidence);
verifyEqual(testCase, v4.diagnostics.sourceSchemaVersion, '3.1');
verifyEqual(testCase, v4.diagnostics.canonicalLayers, ...
    {'semantic', 'processability', 'evidence', 'protection', ...
    'diagnostics'});
verifyEqual(testCase, v4.diagnostics.deferredLayers, {});
verifyEqual(testCase, v4.textureProtectionMask, ...
    v31.textureProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, v4.skinMask, v31.skinMask, 'AbsTol', 0);
verifyEqual(testCase, v4.semanticProbabilities, ...
    v31.semanticProbabilities, 'AbsTol', 0);
verifyEqual(testCase, v4.runtimeCache.schemaVersion, '4.0');
verifyEqual(testCase, v4.migrationDiagnostics.status, 'regenerated');

reread = normalizeBeautyContext(image, faceBox, v4);
verifyEqual(testCase, reread.schemaVersion, '4.0');
verifyEqual(testCase, reread.semantic.regions.skin, ...
    v4.semantic.regions.skin, 'AbsTol', 0);
verifyEqual(testCase, reread.semantic.faceSkin, ...
    v4.semantic.faceSkin, 'AbsTol', 0);
verifyEqual(testCase, reread.evidence, v4.evidence, 'AbsTol', 0);
verifyEqual(testCase, reread.protection, v4.protection, 'AbsTol', 0);
verifyEqual(testCase, reread.diagnostics.policyEvidence, ...
    v4.diagnostics.policyEvidence);
end

function testMigrationToV4WithoutImageUsesCanonicalSemantic(testCase)
%TESTMIGRATIONTOV4WITHOUTIMAGEUSESCANONICALSEMANTIC 无原图时迁移到
%   V4：canonical semantic 取自 v3 语义字段，色度字段走既有 alias 迁移；
%   pre-T05 旧 Context（无分层）迁移后保持 partial V4。
[image, faceBox, parsing] = fixtureImage(96, 128);
v31 = makeLegacyV31Context(image, faceBox, parsing, false);
v4 = migrateBeautyContext(v31, '4.0');

verifyEqual(testCase, v4.schemaVersion, '4.0');
verifyEqual(testCase, v4.semantic.regions.nose, v31.regions.nose, ...
    'AbsTol', 0);
verifyEqual(testCase, v4.semantic.confidence.nose, ...
    v31.regionConfidence.nose, 'AbsTol', 0);
verifyEqual(testCase, v4.migrationDiagnostics.status, 'aliasMigrated');
verifyEqual(testCase, v4.diagnostics.sourceSchemaVersion, '3.1');
verifyFalse(testCase, any(isfield(v4, ...
    {'processability', 'evidence', 'protection'})));
verifyEqual(testCase, v4.diagnostics.canonicalLayers, ...
    {'semantic', 'diagnostics'});
verifyEqual(testCase, v4.diagnostics.deferredLayers, ...
    {'processability', 'evidence', 'protection'});
verifyTrue(testCase, isfield(v4.diagnostics, 'compatAliases'));
end

function testMigrationFromV30ToV4Canonical(testCase)
%TESTMIGRATIONFROMV30TOV4CANONICAL 旧 v3.0 Context（无色度规范字段）
%   迁移到 V4：diagnostics 记录来源版本，色度 alias 迁移结果一致。
[image, faceBox, parsing] = fixtureImage(96, 128);
v31 = makeLegacyV31Context(image, faceBox, parsing, false);
legacy = rmfield(v31, 'chromaProtectionMask');
legacy.schemaVersion = '3.0';
v4 = migrateBeautyContext(legacy, '4.0');

verifyEqual(testCase, v4.schemaVersion, '4.0');
verifyEqual(testCase, v4.diagnostics.sourceSchemaVersion, '3.0');
verifyEqual(testCase, v4.chromaProtectionMask, ...
    v4.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, v4.semantic.regions.skin, legacy.regions.skin, ...
    'AbsTol', 0);
verifyEqual(testCase, v4.migrationDiagnostics.status, 'aliasMigrated');
end

function testMigrationToV4IsIdempotent(testCase)
%TESTMIGRATIONTOV4ISIDEMPOTENT 对同一合法 V4 输入连续 migrate/normalize
%   两次结果 bit-exact；pre-T05 旧 Context 的完整迁移路径同样幂等。
[image, faceBox, parsing] = fixtureImage(96, 128);
v31 = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([96, 128]));
v4 = migrateBeautyContext(v31, '4.0');
again = migrateBeautyContext(v4, '4.0');
verifyEqual(testCase, again, v4);

first = normalizeBeautyContext(image, faceBox, v4);
second = normalizeBeautyContext(image, faceBox, first);
verifyEqual(testCase, second, first);

legacy = makeLegacyV31Context(image, faceBox, parsing, false);
legacyV4 = migrateBeautyContext(legacy, '4.0');
legacyAgain = migrateBeautyContext(legacyV4, '4.0');
verifyEqual(testCase, legacyAgain, legacyV4);
end

function testMigrationTargetSchemaIsExplicitAndValidated(testCase)
%TESTMIGRATIONTARGETSCHEMAISEXPLICITANDVALIDATED 默认目标仍为 v3.1；
%   V4 目标必须显式声明；V4 输入不允许降级到 v3.1；with-image 形式
%   同样支持显式 V4 目标并保持幂等。
[image, faceBox, parsing] = fixtureImage(96, 128);
v31 = makeLegacyV31Context(image, faceBox, parsing, false);

verifyError(testCase, @() migrateBeautyContext(v31, '9.9'), ...
    'migrateBeautyContext:UnsupportedTarget');

explicitV31 = migrateBeautyContext(v31, 'v3.1');
verifyEqual(testCase, explicitV31.schemaVersion, '3.1');
verifyEqual(testCase, explicitV31.migrationDiagnostics.status, ...
    'aliasMigrated');

v4 = migrateBeautyContext(v31, '4.0');
verifyError(testCase, @() migrateBeautyContext(v4), ...
    'migrateBeautyContext:UnsupportedVersion');

v4WithImage = migrateBeautyContext(image, faceBox, ...
    makeLegacyV31Context(image, faceBox, parsing, true), '4.0');
verifyEqual(testCase, v4WithImage.schemaVersion, '4.0');
verifyEqual(testCase, v4WithImage.semantic.regions.skin, ...
    v31.regions.skin, 'AbsTol', 0);
verifyEqual(testCase, v4WithImage.runtimeCache.schemaVersion, '4.0');
reread = migrateBeautyContext(image, faceBox, v4WithImage, '4.0');
verifyEqual(testCase, reread, v4WithImage);
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

function context = stripCanonicalLayers(context)
%STRIPCANONICALLAYERS 剥离 V4 canonical 分层，得到 pre-T05 旧 v3.1 形态。
names = {'semantic', 'processability', 'evidence', 'protection', ...
    'diagnostics'};
names = names(isfield(context, names));
if ~isempty(names)
    context = rmfield(context, names);
end
end

function context = makeLegacyV31Context(image, faceBox, parsing, withCache)
%MAKELEGACYV31CONTEXT 构造 T08 之前生产链输出的 v3.1 compat Context：
%   仅 compat alias 与 v3 语义字段，无 canonical 分层（pre-T05 形态）。
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, [1, 2])));
context = stripCanonicalLayers(context);
context.schemaVersion = '3.1';
if ~withCache
    context = rmfield(context, 'runtimeCache');
end
end

function context = makeLayeredV31Context(image, faceBox, parsing)
%MAKELAYEREDV31CONTEXT 构造 T05--T07 期间生产链输出的 v3.1 Context：
%   已携带 semantic/processability/evidence/protection/diagnostics
%   分层，但契约戳仍为 '3.1'。
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing(size(image, [1, 2])));
context.schemaVersion = '3.1';
context.runtimeCache.schemaVersion = '3.1';
end
