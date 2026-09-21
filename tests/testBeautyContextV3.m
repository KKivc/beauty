function tests = testBeautyContextV3
%TESTBEAUTYCONTEXTV3 验证 v3 Context 和原尺寸派生 Mask。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testPrepareProducesCanonicalV4Context(testCase)
%TESTPREPAREPRODUCESCANONICALV4CONTEXT T08 起生产链默认输出 schema
%   V4 的分层 Context（架构 expand，算法行为 v3.2 不变），同时保留
%   迁移期 compat alias 与完整 runtime cache。
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));

verifyEqual(testCase, context.schemaVersion, '4.0');
required = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'semanticProbabilities', ...
    'semanticConfidence', 'imageSize', 'faceBox'};
verifyTrue(testCase, all(isfield(context, required)));
verifyFalse(testCase, any(isfield(context, ...
    {'featureProtectionMask', 'hardProtectionMask'})));
verifyTrue(testCase, all(isfield(context, ...
    {'semantic', 'processability', 'evidence', 'protection', ...
    'diagnostics'})));
verifyTrue(testCase, isfield(context.diagnostics, 'policyEvidence'));
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
% T08：缓存记录的契约戳随生产 Context 升为 '4.0'；缓存兼容由
% artifactVersion（'v3.2'）把握。
verifyEqual(testCase, cache.schemaVersion, '4.0');
verifyEqual(testCase, cache.algorithmVersion, 'v3.6');
verifyEqual(testCase, cache.artifactVersion, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.beautyMasks, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.frequency, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.blemishMap, 'v3.2');
verifyEqual(testCase, cache.beautyMasks.chromaProtectionMask, ...
    cache.beautyMasks.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, cache.frequency.schemaVersion, '4.0');
verifyEqual(testCase, cache.blemishDiagnostics.schemaVersion, '4.0');
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
% 迁移重建的缓存按当前生产契约落戳（T08 起为 '4.0'）。
verifyEqual(testCase, migrated.runtimeCache.schemaVersion, '4.0');
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
tampered.runtimeCache.algorithmVersion = 'v3.5';
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

function testLegacyStampedCacheMeetsV4ProducerContext(testCase)
%TESTLEGACYSTAMPEDCACHEMEETSV4PRODUCERCONTEXT T08 风险覆盖：旧 '3.1'
%   契约戳缓存与新 V4 分层 Context 相遇。'3.1' 仍是缓存读者的合法
%   形态，缓存兼容由 artifactVersion 把握——Mask 指纹一致时安全复用，
%   指纹不一致时必须安全重建且不误命中，重建输出与无缓存路径
%   bit-exact。
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
[uncachedOutput, ~] = beautifyImage(image, params, faceBox, ...
    rmfield(context, 'runtimeCache'));

legacyStamped = context;
legacyStamped.runtimeCache.schemaVersion = '3.1';
legacyStamped.runtimeCache.artifactInfo.schemaVersion = '3.1';
legacyStamped.runtimeCache.artifacts.schemaVersion = '3.1';
legacyStamped.runtimeCache.beautyMasks.schemaVersion = '3.1';
legacyStamped.runtimeCache.frequency.schemaVersion = '3.1';
legacyStamped.runtimeCache.maskDiagnostics.schemaVersion = '3.1';
legacyStamped.runtimeCache.decompositionDiagnostics.schemaVersion = '3.1';
legacyStamped.runtimeCache.blemishDiagnostics.schemaVersion = '3.1';
[output, diagnostics] = beautifyImage(image, params, faceBox, legacyStamped);
verifyTrue(testCase, diagnostics.reusedRuntimeCache, ...
    '旧 3.1 契约戳缓存与 V4 Context 指纹一致时必须可安全复用。');
verifyEqual(testCase, output, uncachedOutput);

tampered = legacyStamped;
tampered.runtimeCache.beautyMasks.skinMask(1, 1) = ...
    1 - tampered.runtimeCache.beautyMasks.skinMask(1, 1);
[rebuiltOutput, rebuiltDiagnostics] = beautifyImage(image, params, ...
    faceBox, tampered);
verifyFalse(testCase, rebuiltDiagnostics.reusedRuntimeCache, ...
    '指纹不一致时不得误命中旧缓存。');
verifyEqual(testCase, rebuiltDiagnostics.runtimeCache.status, 'regenerated');
verifyEqual(testCase, rebuiltOutput, uncachedOutput);
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

function testBeautifyImageWrapsV4ReaderErrors(testCase)
%TESTBEAUTIFYIMAGEWRAPSV4READERERRORS T08 风险覆盖：producer 切 V4 后
%   normalizeBeautyContextV4:* 错误族成为主路径，beautifyImage 的
%   fallback 必须同样把它包装为 beautifyImage:InvalidContext，而不是
%   裸抛 reader 错误或改变错误语义。
[image, faceBox, parsing] = fixtureContext(40, 60);
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
malformed = rmfield(context, 'runtimeCache');
malformed.diagnostics = 'not-a-struct';
verifyError(testCase, @() beautifyImage(image, struct( ...
    'smoothingStrength', 50, 'whiteningStrength', 25), faceBox, ...
    malformed), 'beautifyImage:InvalidContext');
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

% 生产 Context 为 V4 形态：imageSize 冲突由 V4 reader 报告。
wrongSize = context;
wrongSize.imageSize = [39, 60, 3];
verifyError(testCase, @() normalizeBeautyContext(image, faceBox, wrongSize), ...
    'normalizeBeautyContextV4:SizeMismatch');

% semanticProbabilities alias 校验属 v3 旧形态路径，用 '3.1' 夹具覆盖。
wrongSemantic = context;
wrongSemantic.schemaVersion = '3.1';
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

% T08 起 4 参数 resize 在目标尺寸重建 V4 分层 Context。
verifyEqual(testCase, savedContext.schemaVersion, '4.0');
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

function testResizeRefreshesCanonicalLayersAtTargetSize(testCase)
%TESTRESIZEREFRESHESCANONICALLAYERSATTARGETSIZE T09 契约：四参数 resize
%   在合并缩放皮肤域后必须按最终 regions/skinMask/bodySkinMask 刷新
%   semantic/processability 分层，分层与 compat alias bit-exact 一致。
%   夹具注入 SCHP 手臂身体皮肤，保证合并确实向皮肤域添加解析语义之外
%   的区域（零 SCHP 下合并可能恰好无操作，掩盖陈旧分层）。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = prepareBeautyContext(image, faceBox, parsing, ...
    armBodyParsing([40, 60]));
verifyTrue(testCase, any(preview.bodySkinMask(:) > .5), ...
    '手臂夹具必须产生身体皮肤。');
verifyTrue(testCase, any(preview.nonFaceSkinMask(:) > .5), ...
    '手臂夹具必须在脸外皮肤中留下手臂区域。');

targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(preview, [targetSize, 3], ...
    targetFaceBox, targetImage);

verifyTrue(testCase, any(resized.bodySkinMask(:) > .5), ...
    '目标尺寸 Context 必须保留缩放后的身体皮肤。');
verifyTrue(testCase, nnz(resized.skinMask > .5) > ...
    nnz(resized.faceSkinMask > .5), ...
    '合并后的皮肤域必须比脸内皮肤多出手臂区域。');
verifyEqual(testCase, resized.processability.skin, ...
    resized.skinMask, 'AbsTol', 0, ...
    'processability.skin 必须与最终合并后的 skinMask 一致。');
verifyEqual(testCase, resized.semantic.bodySkin, ...
    resized.bodySkinMask, 'AbsTol', 0, ...
    'semantic.bodySkin 必须与缩放后的 bodySkinMask 一致。');
verifyEqual(testCase, resized.semantic.regions, ...
    resized.regions, 'AbsTol', 0);
verifyEqual(testCase, resized.semantic.confidence, ...
    resized.regionConfidence, 'AbsTol', 0);
verifySize(testCase, resized.processability.skin, targetSize);
verifySize(testCase, resized.semantic.bodySkin, targetSize);
end

function testResizedSemanticProbabilitiesAreResizedAndClamped(testCase)
%TESTRESIZEDSEMANTICPROBABILITIESARERESIZEDANDCLAMPED T09 契约：四参数
%   路径的 semantic probabilities/confidence 必须逐类双线性插值缩放并
%   重新裁剪 [0,1]，与规范流程期望值 bit-exact。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
targetSize = [80, 120];
resized = resizeBeautyContext(preview, [targetSize, 3], ...
    [20, 16, 60, 48], imresize(image, targetSize, 'bilinear'));
names = faceParsingClassNames();
fieldNames = {'semanticProbabilities', 'semanticConfidence'};
for index = 1:numel(fieldNames)
    fieldName = fieldNames{index};
    verifyEqual(testCase, size(resized.(fieldName)), ...
        [targetSize, numel(names)]);
    source = preview.(fieldName);
    expected = zeros([targetSize, numel(names)], 'single');
    for classIndex = 1:numel(names)
        expected(:, :, classIndex) = single(min(1, max(0, imresize( ...
            double(source(:, :, classIndex)), targetSize, 'bilinear'))));
    end
    verifyEqual(testCase, resized.(fieldName), expected, 'AbsTol', 0, ...
        sprintf('%s 必须等于逐类双线性缩放加 [0,1] 裁剪。', fieldName));
end
end

function testResizedProtectionHardStaysBinaryAtTargetSize(testCase)
%TESTRESIZEDPROTECTIONHARDSTAYSBINARYATTARGETSIZE T09 契约：protection.
%   hard 在四参数路径由目标图像重建，生成即二值，缩放灰边不得进入
%   compose identity（hard 区域最终 RGB 必须与源图一致）。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
verifyTrue(testCase, any(preview.protection.hard(:) >= .999), ...
    '夹具必须产生非空 hard identity 区域。');
targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(preview, [targetSize, 3], ...
    targetFaceBox, targetImage);
hard = resized.protection.hard;
verifyTrue(testCase, all(hard(:) == 0 | hard(:) == 1), ...
    'resize 后 protection.hard 必须保持二值，不允许出现缩放灰边。');
verifyTrue(testCase, any(hard(:) >= .999));
verifyEqual(testCase, double(hard), double( ...
    resized.runtimeCache.beautyMasks.hardProtectionMask), 'AbsTol', 0, ...
    'protection.hard 必须与目标尺寸重建的 hard identity 一致。');
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);
[output, diagnostics] = beautifyImage(targetImage, params, ...
    targetFaceBox, rmfield(resized, 'runtimeCache'));
hardRgb = repmat(diagnostics.beautyMasks.hardProtectionMask >= .999, ...
    1, 1, 3);
verifyEqual(testCase, output(hardRgb), targetImage(hardRgb), ...
    'hard identity 区域的最终 RGB 必须与源图一致。');
end

function testResizedEvidenceRecomputesFromTargetImage(testCase)
%TESTRESIZEDEVIDENCERECOMPUTESFROMTARGETIMAGE T09 契约：带目标原图的
%   resize 必须在目标分辨率重算 image-dependent policy evidence——与
%   直接桥接重建 bit-exact，不得等于缩放预览 evidence，且目标图像内
%   容变化必须反映到 evidence。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(preview, [targetSize, 3], ...
    targetFaceBox, targetImage);

rebuilt = rebuildBeautyDerivedMasks(targetImage, ...
    rmfield(resized, 'runtimeCache'), targetFaceBox);
verifyEqual(testCase, rebuilt.evidence, resized.evidence, 'AbsTol', 0, ...
    'resize 输出的 evidence 必须与目标分辨率桥接重建 bit-exact。');

imageDependent = {'edgeDetail', 'structureGradient', 'darkDetail'};
for index = 1:numel(imageDependent)
    name = imageDependent{index};
    scaledPreview = imresize(preview.evidence.(name), targetSize, ...
        'bilinear');
    verifyFalse(testCase, isequal(resized.evidence.(name), ...
        scaledPreview), ...
        sprintf('%s 必须在目标分辨率重算，不得缩放预览 evidence。', name));
end

changedImage = targetImage;
changedImage(30:45, 40:60, :) = uint8(235);
changed = resizeBeautyContext(preview, [targetSize, 3], ...
    targetFaceBox, changedImage);
for index = 1:numel(imageDependent)
    name = imageDependent{index};
    verifyFalse(testCase, isequal(changed.evidence.(name), ...
        resized.evidence.(name)), ...
        sprintf('目标图像变化必须改变 %s。', name));
end
end

function testLightweightResizeIsCompatibilityPath(testCase)
%TESTLIGHTWEIGHTRESIZEISCOMPATIBILITYPATH T09 契约：三参数轻量 resize
%   是显式 compatibility path——输出 v3.1 compat 形态，丢弃 V4
%   canonical 分层，不生成 runtimeCache；保存链路不得复用预览缓存，
%   即使强行挂上预览缓存也必须安全重建并与无缓存路径 bit-exact。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
resized = resizeBeautyContext(preview, [80, 120, 3], [20, 16, 60, 48]);
verifyEqual(testCase, resized.schemaVersion, '3.1');
verifyFalse(testCase, any(isfield(resized, {'semantic', ...
    'processability', 'evidence', 'protection', 'diagnostics', ...
    'runtimeCache'})), ...
    '轻量兼容路径不得携带 canonical 分层或 runtime cache。');
verifyEqual(testCase, resized.migrationDiagnostics.status, 'resized');

maskNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap'};
for index = 1:numel(maskNames)
    value = resized.(maskNames{index});
    verifySize(testCase, value, [80, 120]);
    verifyTrue(testCase, all(isfinite(value(:))) && ...
        all(value(:) >= 0) && all(value(:) <= 1), ...
        sprintf('轻量缩放字段 %s 必须保持在 [0,1]。', maskNames{index}));
end

params = struct('smoothingStrength', 50, 'whiteningStrength', 25);
targetImage = imresize(image, [80, 120], 'bilinear');
targetFaceBox = [20, 16, 60, 48];
[noCacheOut, noCacheDiagnostics] = beautifyImage(targetImage, ...
    params, targetFaceBox, resized);
verifyFalse(testCase, noCacheDiagnostics.reusedRuntimeCache);

withStaleCache = resized;
withStaleCache.runtimeCache = preview.runtimeCache;
[staleOut, staleDiagnostics] = beautifyImage(targetImage, params, ...
    targetFaceBox, withStaleCache);
verifyFalse(testCase, staleDiagnostics.reusedRuntimeCache, ...
    '预览缓存不得经轻量兼容路径进入保存链路。');
verifyEqual(testCase, staleOut, noCacheOut);
end

function testFullSizeSaveChainCacheEquivalence(testCase)
%TESTFULLSIZESAVECHAINCACHEEQUIVALENCE T10 验收：GUI 保存链路
%   （preview Context → 四参数 authoritative resize → beautifyImage）
%   的缓存纪律。1) 保存缓存必须在目标原图上全量重建，预览缓存不得
%   直接充当保存缓存；2) 缓存命中与剥离缓存重建的最终 RGB bit-exact；
%   3) 两条路径发布的 V4 stage protection 层与缓存产物的保护 mask 关
%   键统计（nnz/sum 摘要）一致；4) 强行把预览缓存挂进保存链路必须拒
%   绝复用、安全重建，且输出与统计均与无缓存路径一致。
[image, faceBox, parsing] = fixtureContext(40, 60);
preview = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60]));
targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
full = resizeBeautyContext(preview, [targetSize, 3], targetFaceBox, ...
    targetImage);
params = struct('smoothingStrength', 50, 'whiteningStrength', 25);

% 1) 保存链路缓存是目标尺寸全量重建：挂在原尺寸输入上，与预览缓存
%    （预览尺寸输入）不同。
verifyEqual(testCase, full.runtimeCache.inputImage, targetImage);
verifyEqual(testCase, full.runtimeCache.imageSize, [targetSize, 3]);
verifyFalse(testCase, isequal(full.runtimeCache, preview.runtimeCache), ...
    '保存链路缓存不得是预览缓存。');

[cachedOutput, cachedDiagnostics] = beautifyImage(targetImage, params, ...
    targetFaceBox, full);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
[rebuiltOutput, rebuiltDiagnostics] = beautifyImage(targetImage, ...
    params, targetFaceBox, rmfield(full, 'runtimeCache'));
verifyFalse(testCase, rebuiltDiagnostics.reusedRuntimeCache);

% 2) 最终 RGB bit-exact。
verifyEqual(testCase, cachedOutput, rebuiltOutput);

% 3) stage protection 等价：缓存复用与重建产物的保护 mask 关键统计
%    一致；重建产物推导的 V4 stage 层在两条口径下都与发布值一致：
%      a) 零带证据（显式传入全零 evidence 结构）必须逐位还原 T07 legacy
%         折叠（= 单参缺省形态），即"无证据时逐位还原 legacy 折叠"这一
%         真实契约；
%      b) 携带保存链路 Context 发布的同一份 evidence 时必须逐位等于
%         full.protection。
%    T20 起 periocular/lip、T21 起 nostril/noseStructure、T22 起
%    earStructure 均参与分级保护（本夹具实测贡献：periocular 234px、
%    noseStructure 11px、earStructure 0px），故 603 行原有的"单参
%    （无 evidence）对照 full.protection"自 T20 起已不成立——它不是
%    legacy 折叠契约的正确表述，必须以零带证据为基准重新表达。
assertProtectionStatsEqual(testCase, cachedDiagnostics.beautyMasks, ...
    rebuiltDiagnostics.beautyMasks, '缓存复用与重建');
zeroEvidence = struct();
evidenceNames = fieldnames(full.evidence);
for index = 1:numel(evidenceNames)
    zeroEvidence.(evidenceNames{index}) = zeros([targetSize, 1]);
end
verifyEqual(testCase, ...
    masks.buildStageProtectionMasks(rebuiltDiagnostics.beautyMasks, ...
    zeroEvidence), ...
    masks.buildStageProtectionMasks(rebuiltDiagnostics.beautyMasks), ...
    'AbsTol', 0, ...
    '零带证据必须逐位还原 T07 legacy 折叠（单参缺省形态）。');
verifyEqual(testCase, ...
    masks.buildStageProtectionMasks(rebuiltDiagnostics.beautyMasks, ...
    full.evidence), ...
    full.protection, 'AbsTol', 0, ...
    '重建产物推导的 stage 层必须与保存链路 Context 发布的 protection 一致（须携带同一份 evidence）。');

% 4) 预览缓存混入保存链路：拒绝复用并安全重建，输出与统计不变。
polluted = full;
polluted.runtimeCache = preview.runtimeCache;
[pollutedOutput, pollutedDiagnostics] = beautifyImage(targetImage, ...
    params, targetFaceBox, polluted);
verifyFalse(testCase, pollutedDiagnostics.reusedRuntimeCache, ...
    '预览缓存不得经保存链路误命中。');
verifyEqual(testCase, pollutedDiagnostics.runtimeCache.status, ...
    'regenerated');
verifyEqual(testCase, pollutedOutput, rebuiltOutput);
assertProtectionStatsEqual(testCase, pollutedDiagnostics.beautyMasks, ...
    rebuiltDiagnostics.beautyMasks, '污染缓存重建');
end

function assertProtectionStatsEqual(testCase, cachedMasks, rebuiltMasks, label)
%ASSERTPROTECTIONSTATSEQUAL T10 口径：逐保护字段比较 nnz(>0)、
%   nnz(>=.999) 与 sum 摘要——同时覆盖软保护权重总量与二值 identity。
names = {'textureProtectionMask'; 'structureProtectionMask'; ...
    'whiteningProtectionMask'; 'chromaProtectionMask'; ...
    'toneProtectionMask'; 'protectionMask'; 'noseMask'; ...
    'hardProtectionMask'};
for index = 1:numel(names)
    name = names{index};
    verifyEqual(testCase, protectionStats(cachedMasks.(name)), ...
        protectionStats(rebuiltMasks.(name)), 'AbsTol', 0, ...
        sprintf('%s路径的 %s 关键统计必须一致。', label, name));
end
end

function stats = protectionStats(mask)
mask = double(mask);
stats = [nnz(mask > 0), nnz(mask >= .999), sum(mask(:))];
end

function testBridgeUnifiesDerivedFieldsAcrossEntries(testCase)
%TESTBRIDGEUNIFIESDERIVEDFIELDSACROSSENTRIES 三个入口的派生字段必须由
%   rebuildBeautyDerivedMasks 统一回填：同一输入下 build 与 prepare
%   （零 SCHP 不改变皮肤基础字段）的派生字段 bit-exact 一致；原尺寸
%   重建路径的结果与对同一基础字段的直接桥接重建 bit-exact 一致。
%   T06 起 policy evidence 层也由本桥接统一生成，纳入同一比较；T07 起
%   V4 protection 层（八个 stage 字段）同样由本桥接统一生成。
[image, faceBox, parsing] = fixtureContext(40, 60);
baseNames = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask'};
derivedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'protection', 'evidence'};

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
%   T22（2026-09-20）：evidence 层新增 earStructure（耳部结构），字段
%   集合断言同步扩展；其余字段与契约不变。
[image, faceBox, parsing] = fixtureContext(40, 60);
prepared = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
evidenceFields = {'periocular'; 'nostril'; 'noseStructure'; 'lip'; ...
    'edgeDetail'; 'structureGradient'; 'darkDetail'; 'earStructure'; ...
    'colorSensitiveSkin'};
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

function testStageProtectionLayerIsValidAndBounded(testCase)
%TESTSTAGEPROTECTIONLAYERISVALIDANDBOUNDED 生产链发布的 V4 protection
%   层必须逐字段满足规范（T31/T32 起为独立 hard + 规范双门控
%   target.*/support.*（各五个 stage 门，T32 追加 baseLuminance）+
%   过渡扁平字段 noseMidProtection/tone/whitening + T30 五条纯 policy 带
%   regionBand*，HxW double、real、finite、[0,1]），hard 严格二值；
%   预览→原尺寸迁移路径在目标尺寸重建 protection，且与直接桥接重建
%   bit-exact 一致。
[image, faceBox, parsing] = fixtureContext(40, 60);
prepared = rmfield(prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([40, 60])), 'runtimeCache');
stageNames = {'hard'; 'target'; 'support'; 'noseMidProtection'; ...
    'toneGates'; 'whiteningGates'; 'whiteningAmplitudeCeiling'; ...
    'regionBandFine'; 'regionBandMid'; 'regionBandBase'; ...
    'regionBandTone'; 'regionBandWhitening'};
assertStageProtectionValid(testCase, prepared.protection, stageNames, ...
    size(image, [1, 2]));
verifyTrue(testCase, all(prepared.protection.hard(:) == 0 | ...
    prepared.protection.hard(:) == 1), ...
    'protection.hard 必须可严格离散化为二值 identity。');

targetSize = [80, 120];
targetFaceBox = [20, 16, 60, 48];
targetImage = imresize(image, targetSize, 'bilinear');
resized = resizeBeautyContext(prepared, [targetSize, 3], ...
    targetFaceBox, targetImage);
assertStageProtectionValid(testCase, resized.protection, stageNames, ...
    targetSize);
rebuilt = rebuildBeautyDerivedMasks(targetImage, ...
    rmfield(resized, 'runtimeCache'), targetFaceBox);
verifyEqual(testCase, rebuilt.protection, resized.protection, 'AbsTol', 0);
end

function assertStageProtectionValid(testCase, protection, stageNames, ...
        imageSize)
verifyTrue(testCase, isstruct(protection) && isscalar(protection));
verifyEqual(testCase, fieldnames(protection), stageNames);
for index = 1:numel(stageNames)
    name = stageNames{index};
    value = protection.(name);
    if strcmp(name, 'target') || strcmp(name, 'support')
        innerNames = {'smoothingFine'; 'smoothingMid'; 'repairFine'; ...
            'repairMid'; 'baseLuminance'; 'tone'; 'whitening'};
        verifyEqual(testCase, fieldnames(value), innerNames);
        for innerIndex = 1:numel(innerNames)
            assertUnitMask(testCase, value.(innerNames{innerIndex}), imageSize);
        end
    elseif strcmp(name, 'toneGates')
        innerNames = {'structureGate'; 'featureGate'; 'uniformFeatureGate'};
        verifyEqual(testCase, fieldnames(value), innerNames);
        for innerIndex = 1:numel(innerNames)
            assertUnitMask(testCase, value.(innerNames{innerIndex}), imageSize);
        end
    elseif strcmp(name, 'whiteningGates')
        innerNames = {'structureGate'; 'featureGate'};
        verifyEqual(testCase, fieldnames(value), innerNames);
        for innerIndex = 1:numel(innerNames)
            assertUnitMask(testCase, value.(innerNames{innerIndex}), imageSize);
        end
    elseif strcmp(name, 'whiteningAmplitudeCeiling')
        verifyTrue(testCase, isnumeric(value) && isscalar(value) && ...
            isreal(value) && ~isnan(value) && value > 0);
    else
        assertUnitMask(testCase, value, imageSize);
    end
end
end

function assertUnitMask(testCase, value, imageSize)
verifyTrue(testCase, isnumeric(value) && ~islogical(value));
verifySize(testCase, value, imageSize);
verifyTrue(testCase, all(isfinite(value(:))));
verifyGreaterThanOrEqual(testCase, min(value(:)), 0);
verifyLessThanOrEqual(testCase, max(value(:)), 1);
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
% T08 起 canonicalOnly 仍为 V4 形态，reader 只读不改写 alias。
verifyEqual(testCase, normalizedCanonical.schemaVersion, '4.0');
verifyEqual(testCase, normalizedLegacy.chromaProtectionMask, ...
    normalizedLegacy.toneProtectionMask, 'AbsTol', 0);
verifyEqual(testCase, normalizedCanonical.chromaProtectionMask, ...
    canonicalOnly.chromaProtectionMask, 'AbsTol', 0);
verifyFalse(testCase, isfield(normalizedCanonical, 'toneProtectionMask'), ...
    'V4 reader 是只读的，不得伪造缺失的 tone alias。');

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
% 色度冲突/缺失 alias 的补齐与冲突检测属 v3 旧形态 normalize 路径；
% V4 reader 不改写 compat alias（缺失 alias 的 V4 Context 由缓存指纹
% 测试与 masks.buildBeautyMasks 的冲突检查兜底），故夹具显式降戳为
% '3.1' 走旧路径。
context.chromaProtectionMask(1, 1) = ...
    1 - context.chromaProtectionMask(1, 1);
context = rmfield(context, 'runtimeCache');
context.schemaVersion = '3.1';
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
	% evidence 分层与 diagnostics 元数据，T07 起自带 protection
	% 分层；本用例验证"只有
	% semantic 层"的 partial V4，须先剥离生产链附加的分层。
	extraLayers = {'processability', 'evidence', 'protection', ...
	    'diagnostics'};
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
	% evidence 分层与 diagnostics 元数据，T07 起自带 protection 分层；
	% alias-only 夹具须剥离全部
	% canonical 层，才能构造真正"只有 compat alias"的 V4 Context。
	canonicalLayers = {'semantic', 'processability', 'evidence', ...
	    'protection', 'diagnostics'};
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
% T07：protection 层八个 stage 字段同样原样通过 reader。
verifyEqual(testCase, normalized.protection, prepared.protection, ...
    'AbsTol', 0);
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

function options = armBodyParsing(imageSize)
%ARMBODYPARSING 注入左手臂高置信 SCHP 概率：与解析皮肤部分重叠（保证
%   主人物连通），部分超出解析语义（模拟身体皮肤覆盖解析之外）。
options = struct('probabilities', zeros([imageSize, 20], 'single'));
armRegion = false(imageSize);
armRegion(26:38, 18:32) = true;
options.probabilities(:, :, 15) = double(armRegion);
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
