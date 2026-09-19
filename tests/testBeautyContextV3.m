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

function testV4ReaderModeCacheReusesAndMatchesUncached(testCase)
%TESTV4READERMODECACHEREUSESANDMATCHESUNCACHED V4 reader 模式下缓存
%   复用与重建必须等价：合法 V4 分层 Context 携带运行时缓存时复用，
%   剥离缓存后重建，两者最终 RGB bit-exact；缓存级 Context 契约戳
%   升为 '4.0'（模拟 V4 producer 落戳）时，只要 algorithmVersion 和
%   artifactVersion 不变，缓存仍然有效（schema 管 Context 契约，
%   artifact 管缓存兼容）。
[image, faceBox, parsing] = fixtureContext(40, 60);
v31 = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
v4 = rmfield(v31, 'runtimeCache');
v4.schemaVersion = '4.0';
v4.semantic = struct('regions', v31.regions, ...
    'confidence', v31.regionConfidence);
v4.processability = struct('skin', v31.skinMask > .5);
v4.diagnostics = struct('note', 'cache reader fixture');

params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
[uncachedOutput, uncachedDiagnostics] = beautifyImage(image, params, ...
    faceBox, v4);
verifyFalse(testCase, uncachedDiagnostics.reusedRuntimeCache);

withCache = v4;
withCache.runtimeCache = v31.runtimeCache;
[cachedOutput, cachedDiagnostics] = beautifyImage(image, params, ...
    faceBox, withCache);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, cachedOutput, uncachedOutput);

v4Stamped = withCache;
v4Stamped.runtimeCache.schemaVersion = '4.0';
v4Stamped.runtimeCache.artifactInfo.schemaVersion = '4.0';
v4Stamped.runtimeCache.artifacts.schemaVersion = '4.0';
v4Stamped.runtimeCache.beautyMasks.schemaVersion = '4.0';
v4Stamped.runtimeCache.frequency.schemaVersion = '4.0';
v4Stamped.runtimeCache.maskDiagnostics.schemaVersion = '4.0';
v4Stamped.runtimeCache.decompositionDiagnostics.schemaVersion = '4.0';
v4Stamped.runtimeCache.blemishDiagnostics.schemaVersion = '4.0';
[v4StampedOutput, v4StampedDiagnostics] = beautifyImage(image, params, ...
    faceBox, v4Stamped);
verifyTrue(testCase, v4StampedDiagnostics.reusedRuntimeCache);
verifyEqual(testCase, v4StampedOutput, uncachedOutput);
end

function testIncompatibleCacheMetadataAlwaysRebuilds(testCase)
%TESTINCOMPATIBLECACHEMETADATAALWAYSREBUILDS 缓存版本元数据不兼容
%   （artifactVersion、algorithmVersion、未知 schema 形态、产物清单
%   落戳、Mask 指纹不一致）必须全部触发重建而不是误命中，且重建输出
%   与无缓存路径 bit-exact。
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
[uncachedOutput, ~] = beautifyImage(image, params, faceBox, ...
    rmfield(context, 'runtimeCache'));

tampered = context;
tampered.runtimeCache.artifactVersion = 'v3.0';
[output, diagnostics] = beautifyImage(image, params, faceBox, tampered);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, diagnostics.runtimeCache.status, 'regenerated');
verifyEqual(testCase, output, uncachedOutput);

tampered = context;
tampered.runtimeCache.algorithmVersion = 'v3.3';
[output, diagnostics] = beautifyImage(image, params, faceBox, tampered);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, diagnostics.runtimeCache.status, 'regenerated');
verifyEqual(testCase, output, uncachedOutput);

tampered = context;
tampered.runtimeCache.schemaVersion = '9.9';
[output, diagnostics] = beautifyImage(image, params, faceBox, tampered);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, diagnostics.runtimeCache.status, 'regenerated');
verifyEqual(testCase, output, uncachedOutput);

tampered = context;
tampered.runtimeCache.artifactInfo.blemishMap = 'v3.0';
[output, diagnostics] = beautifyImage(image, params, faceBox, tampered);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, output, uncachedOutput);

tampered = context;
tampered.runtimeCache.beautyMasks.skinMask(1, 1) = ...
    1 - tampered.runtimeCache.beautyMasks.skinMask(1, 1);
[output, diagnostics] = beautifyImage(image, params, faceBox, tampered);
verifyFalse(testCase, diagnostics.reusedRuntimeCache);
verifyEqual(testCase, output, uncachedOutput);
end

function testV4ContextWithoutCompatAliasNeverReusesCache(testCase)
%TESTV4CONTEXTWITHOUTCOMPATALIASNEVERREUSESCACHE V4 分层 Context 缺少
%   compat alias 时无法核对缓存 Mask 指纹，必须走安全重建（此处表现
%   为重建路径因缺少 v3 基础字段而报错），绝不允许静默复用缓存产物：
%   若发生误命中，beautifyImage 会直接返回缓存结果而不报错。
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
fragment = rmfield(context, 'runtimeCache');
fragment.schemaVersion = '4.0';
fragment = rmfield(fragment, {'skinMask', 'faceSkinMask', ...
    'nonFaceSkinMask', 'textureProtectionMask', ...
    'structureProtectionMask', 'whiteningProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', 'nonFaceStrengthMap'});
fragment.semantic = struct('regions', context.regions);
fragmentWithCache = fragment;
fragmentWithCache.runtimeCache = context.runtimeCache;
verifyError(testCase, @() beautifyImage(image, struct( ...
    'smoothingStrength', 50, 'whiteningStrength', 25), faceBox, ...
    fragmentWithCache), 'masks:InvalidContext');
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
%   T06 起 policy evidence 层也由本桥接统一生成，纳入同一比较。
[image, faceBox, parsing] = fixtureContext(40, 60);
baseNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask'};
derivedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'evidence'};

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
verifyEqual(testCase, fromParsing.diagnostics.policyEvidence, ...
    prepared.diagnostics.policyEvidence);

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
verifyEqual(testCase, rebuilt.diagnostics.policyEvidence, ...
    resized.diagnostics.policyEvidence);
end

function testPolicyEvidenceLayerIsValidAndBounded(testCase)
%TESTPOLICYEVIDENCELAYERISVALIDANDBOUNDED 生产链发布的 policy evidence
%   必须逐字段满足 V4 evidence 规范（HxW double、real、finite、[0,1]），
%   元数据挂在 diagnostics.policyEvidence；预览→原尺寸迁移路径在目标
%   尺寸重建 evidence，且与直接桥接重建 bit-exact 一致。
[image, faceBox, parsing] = fixtureContext(40, 60);
prepared = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
evidenceFields = {'periocular'; 'nostril'; 'noseStructure'; 'lip'; ...
    'edgeDetail'; 'structureGradient'; 'darkDetail'};
assertPolicyEvidenceValid(testCase, prepared.evidence, ...
    evidenceFields, size(image, [1, 2]));
metadata = prepared.diagnostics.policyEvidence;
verifyEqual(testCase, metadata.builder, 'masks.buildBeautyPolicyEvidence');

targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(prepared, [targetSize, 3], ...
    targetFaceBox, targetImage);
assertPolicyEvidenceValid(testCase, resized.evidence, ...
    evidenceFields, targetSize);
rebuilt = rebuildBeautyDerivedMasks(targetImage, ...
    rmfield(resized, 'runtimeCache'), targetFaceBox);
verifyEqual(testCase, rebuilt.evidence, resized.evidence, 'AbsTol', 0);
end

function assertPolicyEvidenceValid(testCase, evidence, evidenceFields, imageSize)
verifyTrue(testCase, isstruct(evidence) && isscalar(evidence));
verifyEqual(testCase, fieldnames(evidence), evidenceFields);
for index = 1:numel(evidenceFields)
    value = evidence.(evidenceFields{index});
    verifyTrue(testCase, isnumeric(value) && ~islogical(value));
    verifySize(testCase, value, imageSize);
    verifyTrue(testCase, all(isfinite(value(:))));
    verifyGreaterThanOrEqual(testCase, min(value(:)), 0);
    verifyLessThanOrEqual(testCase, max(value(:)), 1);
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

function testNormalizeReadsCanonicalV4LayeredContext(testCase)
%TESTNORMALIZEREADSCANONICALV4LAYEREDCONTEXT V4 reader 分支：接受合法
%   分层 Context，规范化 canonical 层，不改写顶层 compat alias。
[image, faceBox, parsing] = fixtureContext(40, 60);
v31 = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
v4 = v31;
v4.schemaVersion = '4.0';
v4.semantic = struct('regions', v31.regions, ...
    'confidence', v31.regionConfidence);
v4.processability = struct('skin', v31.skinMask > .5);
v4.evidence = struct('edgeDetail', reshape(single(0:2399) / 2399, 40, 60));
v4.protection = struct('hard', ones(40, 60));
v4.diagnostics = struct('note', 'reader fixture');

normalized = normalizeBeautyContext(image, faceBox, v4);
verifyEqual(testCase, normalized.schemaVersion, '4.0');
verifyEqual(testCase, fieldnames(normalized.semantic), ...
    {'regions'; 'confidence'});
verifyEqual(testCase, normalized.semantic.regions.skin, ...
    v31.regions.skin, 'AbsTol', 0);
verifyEqual(testCase, normalized.semantic.confidence.nose, ...
    v31.regionConfidence.nose, 'AbsTol', 0);
verifyEqual(testCase, normalized.processability.skin, ...
    double(v31.skinMask > .5), 'AbsTol', 0);
verifyEqual(testCase, normalized.evidence.edgeDetail, ...
    double(reshape(single(0:2399) / 2399, 40, 60)), 'AbsTol', 0);
verifyEqual(testCase, normalized.protection.hard, ones(40, 60), 'AbsTol', 0);
% compat alias 与 canonical layer 分离：顶层 legacy 字段原样保留，
% canonical protection 不被 legacy general mask 覆盖。
verifyEqual(testCase, normalized.textureProtectionMask, ...
    v31.textureProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, normalized.skinMask, v31.skinMask, 'AbsTol', 0);
verifyEqual(testCase, normalized.semanticProbabilities, ...
    v31.semanticProbabilities, 'AbsTol', 0);
verifyEqual(testCase, normalized.imageSize, [40, 60, 3]);
verifyEqual(testCase, normalized.faceBox, double(faceBox));
verifyEqual(testCase, normalized.faceScale, 24);
end

function testNormalizeAcceptsPartialV4Contexts(testCase)
%TESTNORMALIZEACCEPTSPARTIALV4CONTEXTS 部分分层（partial V4）同样合法：
%   只带 semantic 或只带 protection 的 V4 Context 都能通过 reader。
	[image, faceBox, parsing] = fixtureContext(40, 60);
	v31 = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
	    emptyBodyParsing([40, 60])), 'runtimeCache');
	semanticOnly = v31;
	semanticOnly.schemaVersion = '4.0';
	% T05 起生产 Context 自带 processability 分层，T06 起自带
	% evidence 分层与 diagnostics 元数据；本用例验证"只有
	% semantic 层"的 partial V4，须先剥离生产链附加的分层。
	extraLayers = {'processability', 'evidence', 'diagnostics'};
	extraLayers = extraLayers(isfield(semanticOnly, extraLayers));
	if ~isempty(extraLayers)
	    semanticOnly = rmfield(semanticOnly, extraLayers);
	end
	semanticOnly.semantic = struct('regions', v31.regions);
normalized = normalizeBeautyContext(image, faceBox, semanticOnly);
verifyEqual(testCase, normalized.schemaVersion, '4.0');
verifyEqual(testCase, normalized.semantic.regions.skin, ...
    v31.regions.skin, 'AbsTol', 0);
verifyFalse(testCase, any(isfield(normalized, ...
    {'processability', 'evidence', 'protection'})));

fragment.schemaVersion = '4.0';
fragment.protection = struct('hard', zeros(40, 60));
normalizedFragment = normalizeBeautyContext(image, faceBox, fragment);
verifyEqual(testCase, normalizedFragment.schemaVersion, '4.0');
verifyEqual(testCase, normalizedFragment.protection.hard, ...
    zeros(40, 60), 'AbsTol', 0);
% 片段缺失身份字段时由当前输入图像补齐
verifyEqual(testCase, normalizedFragment.imageSize, [40, 60, 3]);
verifyEqual(testCase, normalizedFragment.faceBox, double(faceBox));
verifyFalse(testCase, isfield(normalizedFragment, 'semantic'));
end

function testNormalizeRejectsMalformedV4Contexts(testCase)
%TESTNORMALIZERECTSMALFORMEDV4CONTEXTS 缺 canonical 层、层结构非法、
%   未知语义类别、Mask 越界/尺寸不符、身份字段冲突与未知版本都必须报错。
[image, faceBox, parsing] = fixtureContext(40, 60);
v31 = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');

	aliasOnly = v31;
	aliasOnly.schemaVersion = '4.0';
	% T05 起生产 Context 自带 semantic/processability 分层，T06 起自带
	% evidence 分层与 diagnostics 元数据；alias-only 夹具须剥离全部
	% canonical 层，才能构造真正"只有 compat alias"的 V4 Context。
	canonicalLayers = {'semantic', 'processability', 'evidence', ...
	    'diagnostics'};
	aliasOnly = rmfield(aliasOnly, ...
	    canonicalLayers(isfield(aliasOnly, canonicalLayers)));
	verifyError(testCase, @() normalizeBeautyContext(image, faceBox, aliasOnly), ...
	    'normalizeBeautyContextV4:InvalidStructure');

emptySemantic = aliasOnly;
emptySemantic.semantic = struct();
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, emptySemantic), ...
    'normalizeBeautyContextV4:InvalidStructure');

unknownClass = aliasOnly;
unknownClass.semantic = struct('regions', ...
    struct('unknownRegion', zeros(40, 60)));
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, unknownClass), ...
    'normalizeBeautyContextV4:InvalidSemantic');

outOfRange = aliasOnly;
outOfRange.protection = struct('hard', ones(40, 60));
outOfRange.protection.hard(1, 1) = 1.5;
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, outOfRange), ...
    'normalizeBeautyContextV4:InvalidMask');

wrongSize = aliasOnly;
wrongSize.evidence = struct('edgeDetail', zeros(39, 60));
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSize), ...
    'normalizeBeautyContextV4:InvalidMask');

sizeMismatch = aliasOnly;
sizeMismatch.semantic = struct('regions', v31.regions);
sizeMismatch.imageSize = [39, 60, 3];
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, sizeMismatch), ...
    'normalizeBeautyContextV4:SizeMismatch');

badDiagnostics = aliasOnly;
badDiagnostics.semantic = struct('regions', v31.regions);
badDiagnostics.diagnostics = 'not-a-struct';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, badDiagnostics), ...
    'normalizeBeautyContextV4:InvalidStructure');

nonStructLayer = aliasOnly;
nonStructLayer.protection = zeros(40, 60);
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, nonStructLayer), ...
    'normalizeBeautyContextV4:InvalidStructure');

legacyFieldV4 = aliasOnly;
legacyFieldV4.semantic = struct('regions', v31.regions);
legacyFieldV4.featureProtectionMask = zeros(40, 60);
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, legacyFieldV4), ...
    'normalizeBeautyContext:LegacyFields');

unsupportedMinor = aliasOnly;
unsupportedMinor.semantic = struct('regions', v31.regions);
unsupportedMinor.schemaVersion = '4.1';
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, unsupportedMinor), ...
    'normalizeBeautyContext:UnsupportedVersion');
end

function testNormalizeV4IsIdempotent(testCase)
%TESTNORMALIZEV4ISIDEMPOTENT 同一合法 V4 输入连续 normalize 两次结果
%   bit-exact：logical → double 转换与身份字段补齐都是幂等规范化。
[image, faceBox, parsing] = fixtureContext(40, 60);
v31 = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
v4 = rmfield(v31, {'imageSize', 'faceBox', 'faceScale'});
v4.schemaVersion = '4.0';
v4.semantic = struct('regions', v31.regions, ...
    'confidence', v31.regionConfidence);
v4.processability = struct('skin', v31.skinMask > .5, ...
    'faceSkin', v31.faceSkinMask > .5);
v4.protection = struct('hard', ones(40, 60, 'logical'));
v4.diagnostics = struct('note', 'idempotent fixture');
verifyTrue(testCase, islogical(v4.processability.skin));
verifyTrue(testCase, islogical(v4.protection.hard));

first = normalizeBeautyContext(image, faceBox, v4);
second = normalizeBeautyContext(image, faceBox, first);
verifyEqual(testCase, second, first);
verifyEqual(testCase, first.processability.skin, ...
    double(v31.skinMask > .5), 'AbsTol', 0);
verifyEqual(testCase, first.processability.faceSkin, ...
    double(v31.faceSkinMask > .5), 'AbsTol', 0);
end

function testSemanticLayersPublishParsingSemantics(testCase)
%TESTSEMANTICLAYERSPUBLISHPARSINGSEMANTICS build 与 prepare 都必须发
%   布 V4 semantic/processability 分层：build 阶段（未合并 SCHP）的
%   bodySkin 语义为全零（Face Parsing 19 类没有 body 类别）；prepare
%   合并后按最终皮肤域刷新；分层与旧字段保持 bit-exact。
[image, faceBox, parsing] = fixtureContext(40, 60);
fromParsing = buildBeautyContextFromParsing(image, faceBox, parsing);
verifyTrue(testCase, all(isfield(fromParsing, ...
    {'semantic', 'processability'})));
verifyEqual(testCase, fromParsing.semantic.bodySkin, zeros(40, 60), ...
    'AbsTol', 0, ...
    'SCHP 合并前 bodySkin 语义必须为全零，不得伪造 body 区域。');
verifyEqual(testCase, fromParsing.processability.skin, ...
    fromParsing.skinMask, 'AbsTol', 0);
verifyEqual(testCase, fromParsing.semantic.regions, ...
    fromParsing.regions, 'AbsTol', 0);
verifyEqual(testCase, fromParsing.semantic.faceSkin, ...
    semanticUnionOf(fromParsing, {'skin', 'nose', 'leftEar', 'rightEar'}), ...
    'AbsTol', 0);

prepared = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
verifyEqual(testCase, prepared.semantic.bodySkin, prepared.bodySkinMask, ...
    'AbsTol', 0);
verifyEqual(testCase, prepared.processability.skin, prepared.skinMask, ...
    'AbsTol', 0);
verifyEqual(testCase, prepared.semantic.regions, prepared.regions, ...
    'AbsTol', 0);
verifyEqual(testCase, prepared.semantic.confidence, ...
    prepared.regionConfidence, 'AbsTol', 0);
end

function testProductionLayersPassV4Reader(testCase)
%TESTPRODUCTIONLAYERSPASSV4READER 生产链附加的 semantic/processability
%   分层必须通过 T03 V4 reader 的结构校验，分组语义字段在 reader 路
%   径中原样保留。
[image, faceBox, parsing] = fixtureContext(40, 60);
prepared = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
v4 = rmfield(prepared, 'runtimeCache');
v4.schemaVersion = '4.0';
normalized = normalizeBeautyContext(image, faceBox, v4);
verifyEqual(testCase, normalized.schemaVersion, '4.0');
verifyEqual(testCase, normalized.processability.skin, ...
    prepared.skinMask, 'AbsTol', 0);
verifyEqual(testCase, normalized.semantic.regions, ...
    prepared.regions, 'AbsTol', 0);
verifyEqual(testCase, normalized.semantic.confidence, ...
    prepared.regionConfidence, 'AbsTol', 0);
verifyEqual(testCase, normalized.semantic.faceSkin, ...
    prepared.semantic.faceSkin, 'AbsTol', 0);
verifyEqual(testCase, normalized.semantic.bodySkin, ...
    prepared.semantic.bodySkin, 'AbsTol', 0);
% T06：evidence 层与 policyEvidence 元数据同样原样通过 reader。
verifyEqual(testCase, normalized.evidence, prepared.evidence, 'AbsTol', 0);
verifyEqual(testCase, normalized.diagnostics.policyEvidence, ...
    prepared.diagnostics.policyEvidence);
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

function union = semanticUnionOf(context, names)
%SEMANTICUNIONOF 在测试侧复现生产 semanticUnion 配方。
union = zeros(size(context.skinMask));
for index = 1:numel(names)
    union = max(union, min(context.regions.(names{index}), ...
        context.regionConfidence.(names{index})));
end
union = min(max(double(union), 0), 1);
end
