function tests = testBeautyContextV3
%TESTBEAUTYCONTEXTV3 验证 v3 Context 和原尺寸派生 Mask。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testPrepareProducesCanonicalV31Context(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));

verifyEqual(testCase, context.schemaVersion, '3.1');
required = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'semanticProbabilities', ...
    'semanticConfidence', 'imageSize', 'faceBox'};
verifyTrue(testCase, all(isfield(context, required)));
verifyFalse(testCase, any(isfield(context, ...
    {'featureProtectionMask', 'hardProtectionMask'})));
verifyTrue(testCase, isfield(context, 'runtimeCache'));
verifyEqual(testCase, context.runtimeCache.inputImage, image);
verifyEqual(testCase, size(context.semanticProbabilities), [40, 60, 19]);
verifyEqual(testCase, size(context.nonFaceSkinMask), [40, 60]);
verifyEqual(testCase, context.chromaProtectionMask, ...
    context.toneProtectionMask, 'AbsTol', 0);

params = struct('smoothingStrength', 25, 'whiteningStrength', 15);
[output, diagnostics] = beautifyImage(image, params, faceBox, context);
verifySize(testCase, output, [40, 60, 3]);
verifyTrue(testCase, diagnostics.reusedRuntimeCache);
uncachedContext = rmfield(context, 'runtimeCache');
[uncachedOutput, uncachedDiagnostics] = beautifyImage( ...
    image, params, faceBox, uncachedContext);
verifyFalse(testCase, uncachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, output, uncachedOutput);
changedImage = image;
changedImage(1, 1, 1) = changedImage(1, 1, 1) + uint8(1);
[changedOutput, changedDiagnostics] = beautifyImage( ...
    changedImage, params, faceBox, context);
verifySize(testCase, changedOutput, [40, 60, 3]);
verifyFalse(testCase, changedDiagnostics.reusedRuntimeCache);
recommended = recommendBeautyParams(image, faceBox, context);
verifyTrue(testCase, isfield(recommended, 'smoothingStrength'));
end

function testRuntimeCacheDeclaresCanonicalArtifacts(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
cache = context.runtimeCache;
verifyEqual(testCase, cache.schemaVersion, '3.1');
verifyEqual(testCase, cache.algorithmVersion, 'v3.2');
verifyEqual(testCase, cache.artifactVersion, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.beautyMasks, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.frequency, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.blemishMap, 'v3.1');
verifyEqual(testCase, cache.beautyMasks.chromaProtectionMask, ...
    cache.beautyMasks.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, cache.frequency.schemaVersion, '3.1');
verifyEqual(testCase, cache.blemishDiagnostics.schemaVersion, '3.1');
end

function testHistoricalRuntimeCacheIsRegenerated(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
historical = context;
historical.runtimeCache.algorithmVersion = 'v3.1';
[output, diagnostics] = beautifyImage(image, struct( ...
    'smoothingStrength', 25, 'whiteningStrength', 15), faceBox, historical);
verifySize(testCase, output, [40, 60, 3]);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, diagnostics.runtimeCache.status, 'regenerated');
verifyEqual(testCase, diagnostics.runtimeCache.sourceAlgorithmVersion, 'v3.1');
end

function testExplicitMigrationRegeneratesHistoricalCache(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
legacy = rmfield(context, 'chromaProtectionMask');
legacy.schemaVersion = '3.0';
legacy.runtimeCache.schemaVersion = '3.0';
migrated = migrateBeautyContext(legacy);
verifyEqual(testCase, migrated.schemaVersion, '3.1');
verifyEqual(testCase, migrated.migrationDiagnostics.status, 'regenerated');
verifyEqual(testCase, migrated.migrationDiagnostics.sourceSchemaVersion, '3.0');
verifyEqual(testCase, migrated.runtimeCache.schemaVersion, '3.1');
verifyEqual(testCase, migrated.runtimeCache.migration.status, 'regenerated');
end

function testResizedContextCarriesCompleteSchema(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
resized = resizeBeautyContext(context, [targetSize, 3], targetFaceBox);
required = {'regions', 'regionConfidence', 'strengthMap', ...
    'faceStrengthMap', 'nonFaceStrengthMap', 'chromaProtectionMask', ...
    'toneProtectionMask', 'protectionMasks'};
verifyTrue(testCase, all(isfield(resized, required)));
verifySize(testCase, resized.regions.nose, [80, 120]);
verifyFalse(testCase, isfield(resized, 'runtimeCache'));

targetImage = imresize(image, targetSize, 'bilinear');
[output, diagnostics] = beautifyImage(targetImage, struct( ...
    'smoothingStrength', 25, 'whiteningStrength', 15), ...
    targetFaceBox, resized);
verifySize(testCase, output, [80, 120, 3]);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
end

function testOriginalSizeContextCacheCanBeReusedExactly(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
targetImage = imresize(image, [80, 120], 'bilinear');
targetFaceBox = [20, 16, 60, 48];
resized = resizeBeautyContext(context, [80, 120, 3], ...
    targetFaceBox, targetImage);
params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
[cachedOutput, cachedDiagnostics] = beautifyImage( ...
    targetImage, params, targetFaceBox, resized);
uncached = rmfield(resized, 'runtimeCache');
uncachedOutput = beautifyImage(targetImage, params, targetFaceBox, uncached);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOutput, uncachedOutput);
end

function testNormalizeRejectsLegacyAndInvalidContext(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));

unsupported = context;
unsupported.schemaVersion = '9.0';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, unsupported), ...
    'normalizeBeautyContext:UnsupportedVersion');

legacyVersion = context;
legacyVersion.schemaVersion = '2.0';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, legacyVersion), ...
    'normalizeBeautyContext:UnsupportedVersion');

legacyField = context;
legacyField.featureProtectionMask = zeros(40, 60);
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, legacyField), ...
    'normalizeBeautyContext:LegacyFields');

wrongSize = context;
wrongSize.imageSize = [39, 60, 3];
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSize), ...
    'normalizeBeautyContext:SizeMismatch');

wrongSemantic = context;
wrongSemantic.semanticProbabilities = zeros(40, 60, 18, 'single');
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSemantic), ...
    'normalizeBeautyContext:InvalidSemantic');

unsupportedMinor = context;
unsupportedMinor.schemaVersion = '3.2';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, unsupportedMinor), ...
    'normalizeBeautyContext:UnsupportedVersion');
end

function testOriginalSizeRebuildsDerivedProtectionMasks(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
previewContext = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
targetImage = imresize(image, [80, 120], 'bilinear');
targetFaceBox = [20, 16, 60, 48];
savedContext = resizeBeautyContext(previewContext, ...
    [80, 120, 3], targetFaceBox, targetImage);

verifyEqual(testCase, savedContext.schemaVersion, '3.1');
verifyEqual(testCase, savedContext.imageSize, [80, 120, 3]);
verifyEqual(testCase, savedContext.faceBox, targetFaceBox);
verifyEqual(testCase, size(savedContext.semanticProbabilities), [80, 120, 19]);
verifyEqual(testCase, size(savedContext.textureProtectionMask), [80, 120]);
verifyEqual(testCase, size(savedContext.structureProtectionMask), [80, 120]);
verifyEqual(testCase, size(savedContext.toneProtectionMask), [80, 120]);
verifyEqual(testCase, savedContext.chromaProtectionMask, ...
    savedContext.toneProtectionMask, 'AbsTol', 0);
verifyTrue(testCase, any(savedContext.structureProtectionMask(:) > 0));

params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
previewOutput = beautifyImage(image, params, faceBox, previewContext);
savedOutput = beautifyImage(targetImage, params, targetFaceBox, savedContext);
verifySize(testCase, previewOutput, [40, 60, 3]);
verifySize(testCase, savedOutput, [80, 120, 3]);
verifyClass(testCase, savedOutput, 'uint8');
end

function testBridgeUnifiesDerivedFieldsAcrossEntries(testCase)
%TESTBRIDGEUNIFIESDERIVEDFIELDSACROSSENTRIES 三个入口的派生字段必须由
%   rebuildBeautyDerivedMasks 统一回填：同一输入下 build 与 prepare
%   （零 SCHP 不改变皮肤基础字段）的派生字段 bit-exact 一致；原尺寸
%   重建路径的结果与对同一基础字段的直接桥接重建 bit-exact 一致。
[image, faceBox, parsing] = fixtureContext(40, 60);
baseNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask'};
derivedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks'};

fromParsing = buildBeautyContextFromParsing(image, faceBox, parsing);
prepared = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
for index = 1:numel(baseNames)
    verifyEqual(testCase, fromParsing.(baseNames{index}), ...
        prepared.(baseNames{index}), 'AbsTol', 0);
end
for index = 1:numel(derivedNames)
    verifyEqual(testCase, fromParsing.(derivedNames{index}), ...
        prepared.(derivedNames{index}), 'AbsTol', 0);
end

targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(prepared, [targetSize, 3], ...
    targetFaceBox, targetImage);
rebuilt = rebuildBeautyDerivedMasks(targetImage, ...
    rmfield(resized, 'runtimeCache'), targetFaceBox);
for index = 1:numel(derivedNames)
    verifyEqual(testCase, rebuilt.(derivedNames{index}), ...
        resized.(derivedNames{index}), 'AbsTol', 0);
end
end

function testLegacyAndCanonicalChromaFieldsAreEquivalent(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
canonical = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));

legacy = rmfield(canonical, {'chromaProtectionMask', 'runtimeCache'});
legacy.schemaVersion = '3.0';
canonicalOnly = rmfield(canonical, {'toneProtectionMask', 'runtimeCache'});

normalizedLegacy = normalizeBeautyContext(image, faceBox, legacy);
normalizedCanonical = normalizeBeautyContext(image, faceBox, canonicalOnly);
verifyEqual(testCase, normalizedLegacy.schemaVersion, '3.1');
verifyEqual(testCase, normalizedCanonical.schemaVersion, '3.1');
verifyEqual(testCase, normalizedLegacy.chromaProtectionMask, ...
    normalizedLegacy.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, normalizedCanonical.chromaProtectionMask, ...
    normalizedCanonical.toneProtectionMask, 'AbsTol', 0);

params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
legacyOutput = beautifyImage(image, params, faceBox, legacy);
canonicalOutput = beautifyImage(image, params, faceBox, canonicalOnly);
verifyEqual(testCase, legacyOutput, canonicalOutput);

migrated = migrateBeautyContext(legacy);
verifyEqual(testCase, migrated.schemaVersion, '3.1');
verifyEqual(testCase, migrated.chromaProtectionMask, ...
    migrated.toneProtectionMask, 'AbsTol', 0);
migratedWithImage = migrateBeautyContext(image, faceBox, legacy);
verifyEqual(testCase, migratedWithImage.schemaVersion, '3.1');
verifyEqual(testCase, migratedWithImage.chromaProtectionMask, ...
    migratedWithImage.toneProtectionMask, 'AbsTol', 0);
end

function testChromaConflictAndMissingFieldsAreVisible(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
context.chromaProtectionMask(1, 1) = ...
    1 - context.chromaProtectionMask(1, 1);
context = rmfield(context, 'runtimeCache');
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, context), ...
    'normalizeBeautyContext:ChromaProtectionConflict');
verifyError(testCase, @() masks.buildBeautyMasks(image, context, faceBox), ...
    'masks:ChromaProtectionConflict');

missing = rmfield(context, {'chromaProtectionMask', ...
    'toneProtectionMask'});
rebuilt = normalizeBeautyContext(image, faceBox, missing);
verifyEqual(testCase, rebuilt.schemaVersion, '3.1');
verifyEqual(testCase, rebuilt.chromaProtectionMask, ...
    rebuilt.toneProtectionMask, 'AbsTol', 0);
directMasks = masks.buildBeautyMasks(image, missing, faceBox);
verifyEqual(testCase, directMasks.chromaProtectionMask, ...
    directMasks.toneProtectionMask, 'AbsTol', 0);
end

function testResizePublishesCanonicalAndLegacyChromaFields(testCase)
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
legacy = rmfield(context, 'chromaProtectionMask');
legacy.schemaVersion = '3.0';
canonical = rmfield(context, 'toneProtectionMask');

targetFaceBox = [20, 16, 60, 48];
resizedLegacy = resizeBeautyContext(legacy, [80, 120, 3], targetFaceBox);
resizedCanonical = resizeBeautyContext(canonical, ...
    [80, 120, 3], targetFaceBox);
verifyEqual(testCase, resizedLegacy.schemaVersion, '3.1');
verifyEqual(testCase, resizedCanonical.schemaVersion, '3.1');
verifyEqual(testCase, resizedLegacy.chromaProtectionMask, ...
    resizedLegacy.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, resizedCanonical.chromaProtectionMask, ...
    resizedCanonical.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, resizedLegacy.chromaProtectionMask, ...
    resizedCanonical.chromaProtectionMask, 'AbsTol', 0);

targetImage = imresize(image, [80, 120], 'bilinear');
rebuiltLegacy = resizeBeautyContext(legacy, [80, 120, 3], ...
    targetFaceBox, targetImage);
rebuiltCanonical = resizeBeautyContext(canonical, [80, 120, 3], ...
    targetFaceBox, targetImage);
params = struct('smoothingStrength', 25, 'whiteningStrength', 15);
legacyOutput = beautifyImage(targetImage, params, targetFaceBox, rebuiltLegacy);
canonicalOutput = beautifyImage(targetImage, params, targetFaceBox, rebuiltCanonical);
verifyEqual(testCase, legacyOutput, canonicalOutput);
end

function [image, faceBox, parsing] = fixtureContext(height, width)
image = uint8(ones(height, width, 3) * 145);
image(17:24, 28:32, :) = 105;
faceBox = [10, 8, 30, 24];
parsing = emptyFaceParsing([height, width]);
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
