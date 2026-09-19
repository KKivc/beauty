function tests = testMaskSystemV4CompatibilityBaseline
%TESTMASKSYSTEMV4COMPATIBILITYBASELINE 冻结 v3.2 生产输出的 V4 兼容性 oracle。
%   Oracle commit：e889f31ab04de3d10f21be3c3a6f1b09df19dd80（main）。
%   契约版本：schemaVersion=3.1、algorithmVersion=v3.2、artifactVersion=v3.1。
%   记录时间：2026-09-19（MATLAB R2024a，Windows）。
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

tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
end

function testFrozenPipelineContract(testCase)
contract = beautyPipelineContract();
verifyEqual(testCase, contract.schemaVersion, '3.1');
verifyEqual(testCase, contract.algorithmVersion, 'v3.2');
verifyEqual(testCase, contract.artifactVersion, 'v3.1');

fixture = buildRichFixture();
cache = fixture.context.runtimeCache;
verifyEqual(testCase, cache.schemaVersion, '3.1');
verifyEqual(testCase, cache.algorithmVersion, 'v3.2');
verifyEqual(testCase, cache.artifactVersion, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.beautyMasks, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.frequency, 'v3.1');
verifyEqual(testCase, cache.artifactInfo.blemishMap, 'v3.1');
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
% 最终 RGB oracle：SHA-256（uint8 列优先字节序），在 e889f31 上录制。
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
        sprintf('fixture=%s, smoothing=%d, whitening=%d 的最终 RGB 偏离 e889f31 基线。', ...
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
% 路径的最终 RGB 均在 e889f31 上录制为 SHA-256 oracle。
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
    '预览路径最终 RGB 偏离 e889f31 基线。');

fullContext = resizeBeautyContext(previewContext, ...
    [size(fixture.image, 1), size(fixture.image, 2), 3], ...
    fixture.faceBox, fixture.image);
fullOutput = beautifyImage(fixture.image, params, fixture.faceBox, ...
    fullContext);
verifySize(testCase, fullOutput, size(fixture.image));
verifyEqual(testCase, rgbDigest(fullOutput), recordedOriginalSizeDigest(), ...
    '原尺寸路径最终 RGB 偏离 e889f31 基线。');

uncachedFullContext = rmfield(fullContext, 'runtimeCache');
uncachedFullOutput = beautifyImage(fixture.image, params, ...
    fixture.faceBox, uncachedFullContext);
verifyEqual(testCase, uncachedFullOutput, fullOutput);
end

%% Oracle 表与辅助函数

function [cases, expectedDigests] = recordedRgbBaseline
%RECORDEDRGBBASELINE e889f31 冻结的最终 RGB oracle（SHA-256）。
cases = struct( ...
    'fixture', {'rich', 'rich', 'rich', 'rich', 'compact'}, ...
    'smoothingStrength', {100, 0, 100, 50, 100}, ...
    'whiteningStrength', {0, 100, 15, 25, 15});
expectedDigests = { ...
    '8ef2bf0ec01c681a2ee1d649220581ff7bf3dbb9cb650b5a37db9cab78682dc6'; ...
    '58ab2f354176fb258dcef67e01ff65d5c4c2b98f0085902cfe16c604281bfe80'; ...
    '6716ed9ef1db1c9a3f91c5c1aa877732a92398e2452abdacd6d3aefc9fac21f9'; ...
    'b18986f62ffa6952b2252160dc79264448d2fac9c16b935cf6b4e966104dc6fe'; ...
    '012175a4b7b63b06bd73dd8a3dd638c811d4fcde24d544047e4b154b6e4b6304'};
end

function digest = recordedPreviewDigest
digest = 'dc6539302f6c001509f0cb69a95ae87691d852e551ba915b83ba98e10e3b89b2';
end

function digest = recordedOriginalSizeDigest
digest = '31e9168c9dc1d74d3a0c40104c64eb40bd1d74ce6e1eb57e4f748db96c7a1ef7';
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
