function tests = testMaskSystemV4CompatibilityBaseline
%TESTMASKSYSTEMV4COMPATIBILITYBASELINE 冻结 v3.2 生产输出的 V4 兼容性 oracle。
%   Oracle commit：e889f31ab04de3d10f21be3c3a6f1b09df19dd80（main）。
%   契约版本：schemaVersion=3.1、algorithmVersion=v3.2、artifactVersion=v3.1。
%   记录时间：2026-09-19（MATLAB R2024a，Windows）。
%
%   T08（2026-09-19）起生产 Context 契约由 '3.1' compat 有意切换为
%   '4.0' canonical 分层（架构 schema expand；semantic/
%   processability/evidence/protection/diagnostics 分层发布，compat
%   alias 保留）。这是纯架构迁移：algorithmVersion='v3.2' 与
%   artifactVersion='v3.1' 不变，下列全部 RGB/零强度/hard/cached/
%   preview oracle 摘要必须继续 bit-exact 通过；测试仅同步契约戳
%   断言，不改动任何 oracle 数值。
%
%   比较口径：架构兼容阶段全部断言 bit-exact。最终 RGB 使用 SHA-256 摘要
%   （uint8 列优先字节序）比较；零强度输出、hard identity 区域、
%   cached/uncached 输出和预览/原尺寸路径均要求精确相等。已在基线
%   commit 上验证两次全量重算、缓存复用与重算输出完全一致，因此
%   不设任何数值容差，也禁止视觉阈值。
%
%   样本来源：测试内确定性合成 fixture（解析公式 + 注入语义 + 零 SCHP
%   概率），不读取外部图片，无随机数、无模型推理。真实图 oracle 由
%   tests/runIssue08Validation.m 的固定 77 链路承担，本测试不接触
%   私有人像素材。
%
%   后续 V4 架构迁移 Ticket（只改架构、不改效果）必须保持本测试通过；
%   若确需变更效果，必须先在工单中重立 oracle 并更新基线文档。
%
%   T20（2026-09-19）：第一批真实 V4 policy 行为变化（工单
%   20-eye-lip-identity-policy）。生产链（V4 Context 携带 evidence）对
%   眼周/唇周执行三带分级保护：identity core 不新增 hard；soft detail
%   band 抬升 smoothingFine/ smoothingMid 等 stage 字段；skin
%   transition band 封顶 texture 通道打开处理量。compat Context（无
%   evidence 层）仍走 T07 legacy 折叠，与 e889f31 逐位一致。structural
%   断言（零强度=源图、hard 区域=源图、cached/uncached 一致、预览/
%   原尺寸等价）不放松；仅 RGB digest oracle 按"当前真实输出重新录制"
%   的规则更新（新旧对照见 tests/beauty-regression-baseline.md 的 T20
%   章节；rich 0/100 与 s=0 场景因不触发 smoothing 而保持原值）。
%
%   T21（2026-09-20）：第二批真实 V4 policy 行为变化（工单
%   21-nose-region-policy）。buildStageProtectionMasks 新增消费
%   evidence.nostril / evidence.noseStructure：鼻孔边缘软带（半径
%   2--5px，与 v3.1 nostrilProtection 同一 radius 公式与 footprint）
%   进入 texture/Fine 侧平台档位 .95，鼻结构带（.85）与鼻孔软带（.90）
%   补 smoothingMid/repairMid，鼻结构带补 baseLuminance（.80）；tone/
%   whitening 不追加鼻部项。compat Context（无 evidence 层）仍走 T07
%   legacy 折叠，与 e889f31 逐位一致。structural 断言（零强度=源图、
%   hard 区域=源图、cached/uncached 一致、预览/原尺寸等价）不放松；
%   RGB digest oracle 按"当前真实输出重新录制"规则更新，仅 rich 100/0、
%   rich 100/15 与原尺寸路径变化（新旧对照见
%   tests/beauty-regression-baseline.md 的 T21 章节）。
%
%   T22（2026-09-20）：耳结构 policy（工单 22-ear-region-policy）新增
%   evidence.earStructure 与耳结构带（smoothingFine/smoothingMid/
%   repairMid/baseLuminance）。但 ear 语义在两个合成 fixture 中恒为零
%   （探针实测 earStructure nnz=0、带恒零），因此本文件全部 digest 与
%   T21 录制值逐位相同，无需再次重录；compat 路径仍等于 e889f31。
%
%   T30（2026-09-20）：region policy gate activation（工单 30）。T20/T21
%   施加在 repairFine/repairMid/baseLuminance/tone/whitening 快照上的
%   分级保护此前是惰性值；T30 由 buildStageProtectionMasks 额外发布
%   五条纯 policy 带 regionBand*，并在 beautifyImage 的
%   make*StageContract 中按 gate := gate .* (1 - band) 注入真实算术门控
%   （Repair 的 textureBandGate 只乘逐像素权重、Base 的 regionBandGate
%   只乘 supportMap，两者都不进全局参考统计，保证带外逐位还原 legacy）。
%   两个合成 fixture 的 eye/lip/nostril/noseStructure 证据非零，故全部
%   7 项 digest 按"当前真实输出重新录制"规则更新；compat Context（无
%   evidence 层）仍走 T07 legacy 折叠，与 e889f31 逐位一致。新旧对照见
%   tests/beauty-regression-baseline.md 的 T30 章节。
%
%   T31（2026-09-20）：Smoothing + Repair 执行契约（工单 31-a）。执行层
%   （smoothSkinTexture / repairSkinBlemishes）不再读取 legacy general
%   masks，protection 层改为发布规范双门控 target.*/support.*（T07 扁平
%   折叠名 smoothingFine/smoothingMid/repairFine/repairMid 迁入 target.*
%   并删除），修复门控组装上移到 +beauty/repairStageContract。这是纯执行
%   面重构：算法数值逐位不变（零带路径 = T30 输出），故本文件全部 digest
%   与 T30 录制值逐位相同，无需再次重录；compat 路径仍等于 e889f31。
%   仅 protection 层的字段集断言随之更新（target/support 嵌套）。新旧
%   对照见 tests/beauty-regression-baseline.md 的 T31 章节。

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testFrozenPipelineContract(testCase)
% T08 有意切换点：schemaVersion 从 '3.1' 升级为 '4.0'（架构 schema
% expand，算法行为不变）；algorithmVersion/artifactVersion 冻结不动。
contract = beautyPipelineContract();
verifyEqual(testCase, contract.schemaVersion, '4.0');
verifyEqual(testCase, contract.algorithmVersion, 'v3.6');
verifyEqual(testCase, contract.artifactVersion, 'v3.2');

fixture = buildRichFixture();
cache = fixture.context.runtimeCache;
verifyEqual(testCase, cache.schemaVersion, '4.0');
verifyEqual(testCase, cache.algorithmVersion, 'v3.6');
verifyEqual(testCase, cache.artifactVersion, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.beautyMasks, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.frequency, 'v3.2');
verifyEqual(testCase, cache.artifactInfo.blemishMap, 'v3.2');
end

function testProducerContextIsV4LayeredWithCompatAliases(testCase)
% T08 新增覆盖：生产 Context 冻结为 V4 canonical 分层形态，同时保留
%   迁移期 compat alias；producer 输出必须通过只读 V4 reader 且幂等。
fixture = buildRichFixture();
context = rmfield(fixture.context, 'runtimeCache');
verifyEqual(testCase, context.schemaVersion, '4.0');
layerNames = {'semantic', 'processability', 'evidence', 'protection', ...
    'diagnostics'};
verifyTrue(testCase, all(isfield(context, layerNames)), ...
    '生产 Context 必须携带全部 canonical 分层。');
verifyTrue(testCase, all(isfield(context.semantic, ...
    {'regions', 'confidence', 'faceSkin', 'bodySkin'})));
verifyTrue(testCase, all(isfield(context.protection, ...
    {'hard', 'target', 'support', 'noseMidProtection', ...
    'toneGates', 'whiteningGates', 'whiteningAmplitudeCeiling', ...
    'regionBandFine', 'regionBandMid', 'regionBandBase', ...
    'regionBandTone', 'regionBandWhitening'})), ...
    'T33 起 protection 层发布规范双门控 target.*/support.* 与独立 hard，Tone/Whitening 门源集中到 policy 层。');
verifyTrue(testCase, all(isfield(context.protection.target, ...
    {'smoothingFine', 'smoothingMid', 'repairFine', 'repairMid', ...
    'baseLuminance'})) && ...
    all(isfield(context.protection.support, ...
    {'smoothingFine', 'smoothingMid', 'repairFine', 'repairMid', ...
    'baseLuminance'})), ...
    'target/support 必须各含五个规范 stage 门（T32 追加 baseLuminance）。');
verifyFalse(testCase, isfield(context.protection, 'baseLuminance'), ...
    'T32 起旧扁平折叠名 baseLuminance 已被 target.baseLuminance 取代并删除。');
verifyTrue(testCase, isfield(context.diagnostics, 'policyEvidence') && ...
    strcmp(context.diagnostics.policyEvidence.builder, ...
    'masks.buildBeautyPolicyEvidence'));
compatAliases = {'skinMask', 'faceSkinMask', 'nonFaceSkinMask', ...
    'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'regions', ...
    'regionConfidence', 'semanticProbabilities', 'semanticConfidence'};
verifyTrue(testCase, all(isfield(context, compatAliases)), ...
    '迁移期 compat alias 必须完整保留，供旧 consumer 与缓存指纹使用。');

reread = normalizeBeautyContext(fixture.image, fixture.faceBox, context);
verifyEqual(testCase, reread, context, ...
    'producer Context 经过 V4 reader 必须幂等且 bit-exact。');
end

function testZeroStrengthReturnsSourceImageBitExact(testCase)
fixtureNames = {'rich', 'compact'};
for index = 1:numel(fixtureNames)
    fixture = loadBaselineFixture(fixtureNames{index});
    params = struct('smoothingStrength', 0, 'whiteningStrength', 0);
    [output, diagnostics] = beautifyImage(fixture.image, params, ...
        fixture.faceBox, fixture.context);
    verifyTrue(testCase, diagnostics.identity);
    verifySize(testCase, output, size(fixture.image));
    verifyClass(testCase, output, 'uint8');
    verifyEqual(testCase, output, fixture.image);
    outputWithoutContext = beautifyImage(fixture.image, params, ...
        fixture.faceBox);
    verifyEqual(testCase, outputWithoutContext, fixture.image);
end
end

function testFinalRgbMatchesRecordedBaselineDigests(testCase)
% 最终 RGB oracle：SHA-256（uint8 列优先字节序）。e889f31 录制；T20/T21
%   按"当前真实输出重新录制"规则更新。T22 对本表零影响。T30 激活
%   regionBand* 后全部 5 项按当前真实输出重录（新旧对照见
%   tests/beauty-regression-baseline.md 的 T30 章节）。
[cases, expectedDigests] = recordedRgbBaseline();
for index = 1:numel(cases)
    fixture = loadBaselineFixture(cases(index).fixture);
    params = struct( ...
        'smoothingStrength', cases(index).smoothingStrength, ...
        'whiteningStrength', cases(index).whiteningStrength);
    context = rmfield(fixture.context, 'runtimeCache');
    output = beautifyImage(fixture.image, params, fixture.faceBox, context);
    verifySize(testCase, output, size(fixture.image));
    verifyClass(testCase, output, 'uint8');
    verifyEqual(testCase, rgbDigest(output), expectedDigests{index}, ...
        sprintf('fixture=%s, smoothing=%d, whitening=%d 的最终 RGB 偏离 T30 重录基线。', ...
        cases(index).fixture, cases(index).smoothingStrength, ...
        cases(index).whiteningStrength));
end
end

function testHardIdentityRegionPreservesSourceRgb(testCase)
fixture = buildRichFixture();
combos = [100, 0; 0, 100];
for index = 1:size(combos, 1)
    params = struct('smoothingStrength', combos(index, 1), ...
        'whiteningStrength', combos(index, 2));
    [output, diagnostics] = beautifyImage(fixture.image, params, ...
        fixture.faceBox, rmfield(fixture.context, 'runtimeCache'));
    hard = diagnostics.beautyMasks.hardProtectionMask >= .999;
    verifyTrue(testCase, nnz(hard) > 0, ...
        '合成样例必须产生非空 hard identity 区域。');
    hardRgb = repmat(hard, 1, 1, 3);
    verifyEqual(testCase, output(hardRgb), fixture.image(hardRgb), ...
        sprintf('smoothing=%d, whitening=%d 时 hard identity 区域 RGB 发生变化。', ...
        combos(index, 1), combos(index, 2)));
end
end

function testCachedAndUncachedOutputsAreBitExact(testCase)
fixture = buildRichFixture();
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);
[cachedOutput, cachedDiagnostics] = beautifyImage(fixture.image, params, ...
    fixture.faceBox, fixture.context);
verifyTrue(testCase, cachedDiagnostics.reusedRuntimeCache);
uncachedContext = rmfield(fixture.context, 'runtimeCache');
[uncachedOutput, uncachedDiagnostics] = beautifyImage(fixture.image, ...
    params, fixture.faceBox, uncachedContext);
verifyFalse(testCase, uncachedDiagnostics.reusedRuntimeCache);
repeatOutput = beautifyImage(fixture.image, params, fixture.faceBox, ...
    uncachedContext);
verifyEqual(testCase, cachedOutput, uncachedOutput);
verifyEqual(testCase, repeatOutput, cachedOutput);
end

function testPreviewAndOriginalSizePathsMatchRecordedBaselineDigests(testCase)
% 预览/原尺寸路径：预览图缩放 0.5，原尺寸路径由
% resizeBeautyContext(previewContext, ..., targetImage) 重建，两条
% 路径的最终 RGB 均为 SHA-256 oracle（e889f31 录制，T20 重录；T30
% 激活 regionBand* 后两条路径再次重录）。
fixture = buildRichFixture();
previewScale = 0.5;
previewSize = round([size(fixture.image, 1), size(fixture.image, 2)] * ...
    previewScale);
previewImage = imresize(fixture.image, previewScale, 'bilinear');
previewFaceBox = scaleFaceBox(fixture.faceBox, previewScale, previewSize);
previewParsing = resizeFixtureParsing(fixture.parsing, previewSize);
previewContext = prepareBeautyContext(previewImage, previewFaceBox, ...
    previewParsing, emptyBodyParsing(previewSize));
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);
previewOutput = beautifyImage(previewImage, params, previewFaceBox, ...
    rmfield(previewContext, 'runtimeCache'));
verifySize(testCase, previewOutput, [previewSize, 3]);
verifyEqual(testCase, rgbDigest(previewOutput), recordedPreviewDigest(), ...
    '预览路径最终 RGB 偏离 T30 重录基线。');

fullContext = resizeBeautyContext(previewContext, ...
    [size(fixture.image, 1), size(fixture.image, 2), 3], ...
    fixture.faceBox, fixture.image);
fullOutput = beautifyImage(fixture.image, params, fixture.faceBox, ...
    fullContext);
verifySize(testCase, fullOutput, size(fixture.image));
verifyEqual(testCase, rgbDigest(fullOutput), recordedOriginalSizeDigest(), ...
    '原尺寸路径最终 RGB 偏离 T30 重录基线。');

uncachedFullContext = rmfield(fullContext, 'runtimeCache');
uncachedFullOutput = beautifyImage(fixture.image, params, ...
    fixture.faceBox, uncachedFullContext);
verifyEqual(testCase, uncachedFullOutput, fullOutput);
end

%% Oracle 表与辅助函数

function [cases, expectedDigests] = recordedRgbBaseline
%RECORDEDRGBBASELINE 冻结的最终 RGB oracle（SHA-256）。
%   e889f31 录制；T20（eye/lip identity policy）按当前真实输出重录；
%   T21（nose region policy）再次按当前真实输出重录——rich 100/0 与
%   rich 100/15 因鼻孔软带抬升 texture/Fine 侧保护而变化（T20 旧值
%   分别为 fffa926c… 与 e981883d…）；rich 0/100、rich 50/25、
%   compact 100/15 未变化（T21 增量只落在非消费的零瑕疵参考快照上，
%   或未越过 uint8 量化；逐 Ticket 字段置零探针实测贡献 0 px）。
%   T22（ear region policy）对本文件全部 digest 零影响：两个 fixture 的
%   earStructure 恒为零、耳结构带恒零。
%   T30（region policy gate activation）把 T20/T21/T22 的分级保护从
%   "仅作用于折叠快照"改为真正注入消费侧算术（regionBand* → 各 stage
%   门控），两个 fixture 的 eye/lip/nostril/noseStructure 证据非零，
%   故全部 7 项 digest 按"当前真实输出重新录制"规则更新（新旧对照见
%   tests/beauty-regression-baseline.md 的 T30 章节）。compat Context
%   （无 evidence 层）仍走 T07 legacy 折叠。v3.3 完成颜色敏感退让、
%   高档 Fine 曲线与紧凑 Fine-first Repair 后，经真实图人工验收通过，
%   以下 digest 按已接受的 v3.3 视觉基线重录。
cases = struct( ...
    'fixture', {'rich', 'rich', 'rich', 'rich', 'compact'}, ...
    'smoothingStrength', {100, 0, 100, 50, 100}, ...
    'whiteningStrength', {0, 100, 15, 25, 15});
expectedDigests = { ...
    'e1a423be7b0f14f9b10711a30a19a3d7f428f8f8813f0fe798e11eca5d43333c'; ...
    '07b7734149e39a1703b304fce4c2aca47a6560a9af4028073a7efb9dcae8d9af'; ...
    '41833f37a36fa176005c23b9b98a29132c32f3abcaa84844d1901775e62597b8'; ...
    '68f6e1f137d6df357e368c2759a8ff1e0cb8760167f513c6333236c582179449'; ...
    '220bfd84b221e28498044b3f2fade6fc3cc722441875f251e6d67361d6cbfb35'};
end

function digest = recordedPreviewDigest
% v3.3 重录（紧凑 Fine-first Repair 与颜色敏感区退让）：
digest = '8c437297bf30d6e462343ccd5db4a575268eb401e14c7bff1f6a272f3794838c';
end

function digest = recordedOriginalSizeDigest
% v3.3 原尺寸路径重录：
digest = '3a2d99facac3429a7739ffe4bd43c16880c20d1451361058d7c678fed704d02c';
end

function digest = rgbDigest(image)
%RGBDIGEST 输出 RGB 的 SHA-256（uint8 列优先字节序）。
%   R2024a 无原生 sha256，使用 JVM MessageDigest（-batch 默认启用 JVM）。
bytes = uint8(image(:)).';
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
messageDigest.update(bytes);
digest = lower(reshape(dec2hex(typecast(messageDigest.digest(), ...
    'uint8'), 2).', 1, []));
end

function fixture = loadBaselineFixture(name)
switch name
    case 'rich'
        fixture = buildRichFixture();
    case 'compact'
        fixture = buildCompactFixture();
    otherwise
        error('testMaskSystemV4CompatibilityBaseline:UnknownFixture', ...
            '未知的基线 fixture：%s。', name);
end
end

function fixture = buildRichFixture
%BUILDRICHFIXTURE 180x260 确定性合成人像（复用 runBeautyRegression 的
%   合成样例公式）：皮肤/脖颈/鼻侧影/雀斑/硬保护眼部区域。
imageSize = [180, 260];
faceBox = [70, 24, 120, 128];
[xGrid, yGrid] = meshgrid(1:imageSize(2), 1:imageSize(1));
faceRegion = ((xGrid - 130) / 59) .^ 2 + ...
    ((yGrid - 86) / 63) .^ 2 <= 1;
neckRegion = xGrid >= 106 & xGrid <= 154 & yGrid >= 138 & yGrid <= 176;
skinRegion = faceRegion | neckRegion;
noseRegion = ((xGrid - 130) / 18) .^ 2 + ...
    ((yGrid - 91) / 35) .^ 2 <= 1;
noseShading = .055 * exp(-((xGrid - 130) / 13) .^ 2) - ...
    .035 * exp(-((xGrid - 114) / 11) .^ 2) - ...
    .035 * exp(-((xGrid - 146) / 11) .^ 2);
baseLuminance = .60 + .020 * sin(2 * pi * xGrid / 31) .* ...
    sin(2 * pi * yGrid / 27);
baseLuminance(faceRegion) = baseLuminance(faceRegion) + ...
    noseShading(faceRegion);
baseLuminance(neckRegion) = .58 + ...
    .012 * sin(2 * pi * yGrid(neckRegion) / 23);
sourceImage = zeros([imageSize, 3], 'uint8');
for channel = 1:3
    channelImage = uint8(round(48 + 16 * baseLuminance));
    channelImage(skinRegion) = uint8(round( ...
        255 * min(max(baseLuminance(skinRegion), 0), 1)));
    sourceImage(:, :, channel) = channelImage;
end
sourceImage(:, :, 1) = min(255, sourceImage(:, :, 1) + uint8(18 * skinRegion));
sourceImage(:, :, 2) = min(255, sourceImage(:, :, 2) + uint8(2 * skinRegion));
sourceImage(:, :, 3) = max(0, sourceImage(:, :, 3) - uint8(10 * skinRegion));

freckleCenters = [106, 65; 119, 87; 144, 74; 154, 101; ...
    93, 112; 166, 123; 130, 154];
for index = 1:size(freckleCenters, 1)
    spot = (xGrid - freckleCenters(index, 1)) .^ 2 + ...
        (yGrid - freckleCenters(index, 2)) .^ 2 <= 9;
    spot = spot & skinRegion;
    for channel = 1:3
        channelImage = sourceImage(:, :, channel);
        channelImage(spot) = max(0, channelImage(spot) - uint8(24));
        sourceImage(:, :, channel) = channelImage;
    end
end

parsing = emptyFaceParsing(imageSize);
parsing.regions.skin = double(skinRegion);
parsing.regionConfidence.skin = double(skinRegion);
parsing.regions.neck = double(neckRegion);
parsing.regionConfidence.neck = double(neckRegion);
parsing.regions.nose = double(noseRegion);
parsing.regionConfidence.nose = double(noseRegion);
hardFeature = ((xGrid - 108) / 12) .^ 2 + ...
    ((yGrid - 66) / 5) .^ 2 <= 1;
parsing.regions.leftEye = double(hardFeature);
parsing.regionConfidence.leftEye = double(hardFeature);
context = prepareBeautyContext(sourceImage, faceBox, parsing, ...
    emptyBodyParsing(imageSize));
fixture = struct('image', sourceImage, 'faceBox', faceBox, ...
    'parsing', parsing, 'context', context);
end

function fixture = buildCompactFixture
%BUILDCOMPACTFIXTURE 120x160 确定性合成人像（复用 testBeautyV3 的
%   合成样例公式）：正弦皮肤纹理、鼻部、眼部与唇部语义区域。
height = 120;
width = 160;
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
context = prepareBeautyContext(image, faceBox, parsing, ...
    emptyBodyParsing([height, width]));
fixture = struct('image', image, 'faceBox', faceBox, ...
    'parsing', parsing, 'context', context);
end

function parsing = resizeFixtureParsing(parsing, targetSize)
%RESIZEFIXTUREPARSING 用 bilinear 把注入语义缩放到预览尺寸。
names = fieldnames(parsing.regions);
for index = 1:numel(names)
    parsing.regions.(names{index}) = imresize( ...
        parsing.regions.(names{index}), targetSize, 'bilinear');
    parsing.regionConfidence.(names{index}) = imresize( ...
        parsing.regionConfidence.(names{index}), targetSize, 'bilinear');
end
end

function box = scaleFaceBox(box, scale, imageSize)
%SCALEFACEBOX 与 smokeIntegratedBeautyPipeline 相同的人脸框缩放规则。
box = round(double(box) * scale);
box(1) = max(1, min(box(1), imageSize(2)));
box(2) = max(1, min(box(2), imageSize(1)));
x2 = min(imageSize(2), box(1) + box(3) - 1);
y2 = min(imageSize(1), box(2) + box(4) - 1);
box(3:4) = max(1, [x2 - box(1) + 1, y2 - box(2) + 1]);
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
