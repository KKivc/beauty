function tests = testAcceptanceProbes
%TESTACCEPTANCEPROBES 验证真实图验收探针与 5 阶段归因隔离契约。
%   1. 验证 77、80 和 face 样本的各部位 ROI 满足语义与支持域非零重叠断言。
%   2. 验证 5 阶段独立隔离（Smoothing, Repair, BaseLum, Tone, Whitening）：
%      - Stage 1 (Smoothing-only) 未执行 Repair、Base Lum、Tone 与 Whitening；
%      - Stage 5 与全管线生产输出 bit-exact；
%      - 77 样本灰斑首次出现于 Stage 4 (Tone)。
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
addpath(fullfile(projectRoot, 'tests'));
end

function testRoisOverlapAssertions77(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
path77 = fullfile(projectRoot, '人脸', '人脸', '77.png');
probe77Path = fullfile(tempdir, 'image_beauty_issue02_probe', '77_v32_probe.mat');
img77 = imread(path77);
faceBox77 = [95 79 286 372];
if exist(probe77Path, 'file') == 2
    p77 = load(probe77Path, 'context');
    context77 = prepareBeautyContext(img77, faceBox77, struct('regions', p77.context.regions));
else
    context77 = prepareBeautyContext(img77, faceBox77);
end
[~, texDiag] = masks.buildTextureProtectionMask(img77, context77, faceBox77);

% 77 ROI 验证
rois77 = struct( ...
    'eye',   [120 235 145 70], ...
    'nose',  [150 255 135 120], ...
    'lip',   [185 350 110 65], ...
    'cheek', [240 300 70 60], ...
    'ear',   [335 100 85 130]);

imageSize = size(img77, 1:2);
eyeMask = roiToMask(rois77.eye, imageSize);
noseMask = roiToMask(rois77.nose, imageSize);
lipMask = roiToMask(rois77.lip, imageSize);
cheekMask = roiToMask(rois77.cheek, imageSize);
earMask = roiToMask(rois77.ear, imageSize);

% 断言 eye 覆盖眼球语义或眼周细节
eyeSemOverlap = nnz(eyeMask & (context77.semantic.eye > 0.1));
eyeProtOverlap = nnz(eyeMask & (texDiag.eyeDetailProtection > 0.1));
verifyGreaterThan(testCase, eyeSemOverlap + eyeProtOverlap, 0, '77 Eye ROI 必须有非零语义或保护重叠');

% 断言 nose 覆盖鼻语义与鼻孔/鼻结构
noseSemOverlap = nnz(noseMask & (context77.semantic.nose > 0.1));
verifyGreaterThan(testCase, noseSemOverlap, 1000, '77 Nose ROI 必须包含大量鼻部语义');

% 断言 lip 覆盖唇部语义
lipSemOverlap = nnz(lipMask & (context77.semantic.lip > 0.1));
verifyGreaterThan(testCase, lipSemOverlap, 500, '77 Lip ROI 必须包含唇部语义');

% 断言 cheek 为纯皮肤
skinFrac = mean(context77.skinMask(cheekMask) >= 0.7);
hardMax = max(texDiag.hardProtectionMask(cheekMask));
verifyGreaterThan(testCase, skinFrac, 0.90, '77 Cheek ROI 皮肤占比须 >= 90%');
verifyLessThan(testCase, hardMax, 0.05, '77 Cheek ROI 不得包含硬保护结构');

% 断言 ear 覆盖耳语义
earSemOverlap = nnz(earMask & (context77.semantic.ear > 0.1));
verifyGreaterThan(testCase, earSemOverlap, 1000, '77 Ear ROI 必须包含耳部语义');
end

function testRoisOverlapAssertions80(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
path80 = fullfile(projectRoot, '人脸', '人脸', '80.jpg');
probe80Path = fullfile(tempdir, 'image_beauty_issue02_probe', '80_v32_probe.mat');
img80 = imread(path80);
if exist(probe80Path, 'file') == 2
    p80 = load(probe80Path, 'context', 'faceBox');
    faceBox80 = p80.faceBox;
    context80 = prepareBeautyContext(img80, faceBox80, struct('regions', p80.context.regions));
else
    faceBox80 = [220 180 300 360];
    context80 = prepareBeautyContext(img80, faceBox80);
end
[~, texDiag] = masks.buildTextureProtectionMask(img80, context80, faceBox80);

rois80 = struct( ...
    'eye',   [180 175 340 85], ...
    'nose',  [270 200 160 190], ...
    'lip',   [255 405 185 110], ...
    'cheek', [200 300 65 70], ...
    'ear',   [540 295 25 80]);

imageSize = size(img80, 1:2);
eyeMask = roiToMask(rois80.eye, imageSize);
noseMask = roiToMask(rois80.nose, imageSize);
lipMask = roiToMask(rois80.lip, imageSize);
cheekMask = roiToMask(rois80.cheek, imageSize);
earMask = roiToMask(rois80.ear, imageSize);

eyeSemOverlap = nnz(eyeMask & (context80.semantic.eye > 0.1));
verifyGreaterThan(testCase, eyeSemOverlap, 1000, '80 Eye ROI 必须覆盖眼部语义');

noseSemOverlap = nnz(noseMask & (context80.semantic.nose > 0.1));
verifyGreaterThan(testCase, noseSemOverlap, 2000, '80 Nose ROI 必须包含大量鼻部语义');

lipSemOverlap = nnz(lipMask & (context80.semantic.lip > 0.1));
verifyGreaterThan(testCase, lipSemOverlap, 1000, '80 Lip ROI 必须包含唇部语义');

skinFrac = mean(context80.skinMask(cheekMask) >= 0.7);
verifyGreaterThan(testCase, skinFrac, 0.90, '80 Cheek ROI 皮肤占比须 >= 90%');

earSemOverlap = nnz(earMask & (context80.semantic.ear > 0.1 | context80.regions.leftEar > 0.1));
verifyGreaterThan(testCase, earSemOverlap, 100, '80 Ear ROI 必须包含耳部语义');
end

function testRoisOverlapAssertionsFace(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
pathFace = fullfile(projectRoot, '人脸', '人脸2', 'face', 'face.jpg');
targetDir = fullfile(tempdir, 'image_beauty_manual_acceptance');
cacheFace = fullfile(targetDir, 'cache_face_v32_probe.mat');
imgFace = imread(pathFace);
faceBoxFace = [48 124 301 301];
if exist(cacheFace, 'file') == 2
    pFace = load(cacheFace);
    if isfield(pFace, 'ctx')
        contextFace = pFace.ctx;
    elseif isfield(pFace, 'contextFace')
        contextFace = pFace.contextFace;
    else
        contextFace = prepareBeautyContext(imgFace, faceBoxFace);
    end
else
    contextFace = prepareBeautyContext(imgFace, faceBoxFace);
end
[~, texDiag] = masks.buildTextureProtectionMask(imgFace, contextFace, faceBoxFace);

roisFace = struct( ...
    'eye',   [90 195 215 70], ...    % 真实双眼及眼睑
    'nose',  [140 205 110 140], ...  % 鼻梁、鼻翼与鼻孔
    'lip',   [155 350 130 70], ...   % 完整唇部
    'cheek', [270 280 50 50], ...    % 纯右脸颊皮肤
    'ear',   [385 170 30 115]);      % 左耳部位

imageSize = size(imgFace, 1:2);
eyeMask = roiToMask(roisFace.eye, imageSize);
noseMask = roiToMask(roisFace.nose, imageSize);
lipMask = roiToMask(roisFace.lip, imageSize);
cheekMask = roiToMask(roisFace.cheek, imageSize);
earMask = roiToMask(roisFace.ear, imageSize);

eyeSemOverlap = nnz(eyeMask & (contextFace.semantic.eye > 0.1));
verifyGreaterThan(testCase, eyeSemOverlap, 1000, 'face Eye ROI 必须覆盖眼部语义');

noseSemOverlap = nnz(noseMask & (contextFace.semantic.nose > 0.1));
verifyGreaterThan(testCase, noseSemOverlap, 1000, 'face Nose ROI 必须覆盖鼻部语义');

lipSemOverlap = nnz(lipMask & (contextFace.semantic.lip > 0.1));
verifyGreaterThan(testCase, lipSemOverlap, 500, 'face Lip ROI 必须覆盖唇部语义');

skinFrac = mean(contextFace.skinMask(cheekMask) >= 0.7);
hardMax = max(texDiag.hardProtectionMask(cheekMask));
eyeMax = max(texDiag.eyeDetailProtection(cheekMask));
verifyGreaterThan(testCase, skinFrac, 0.90, 'face Cheek ROI 皮肤占比须 >= 90%');
verifyLessThan(testCase, hardMax, 0.05, 'face Cheek ROI 不得包含硬保护');
verifyLessThan(testCase, eyeMax, 0.05, 'face Cheek ROI 不得包含眼部保护');

earSemOverlap = nnz(earMask & (contextFace.semantic.ear > 0.1));
verifyGreaterThan(testCase, earSemOverlap, 50, 'face Ear ROI 必须覆盖耳部语义');
end

function testFiveStagesIsolationAndAttribution77(testCase)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
path77 = fullfile(projectRoot, '人脸', '人脸', '77.png');
probe77Path = fullfile(tempdir, 'image_beauty_issue02_probe', '77_v32_probe.mat');
img77 = imread(path77);
faceBox77 = [95 79 286 372];
if exist(probe77Path, 'file') == 2
    p77 = load(probe77Path, 'context');
    context77 = prepareBeautyContext(img77, faceBox77, struct('regions', p77.context.regions));
else
    context77 = prepareBeautyContext(img77, faceBox77);
end

sSmooth = 100;
sWhite = 15;
imageSize = size(img77, 1:2);

% 构建 stage 组件
[beautyMasks, ~] = masks.buildBeautyMasks(img77, context77, faceBox77);
[freq, ~] = beauty.decomposeSkinFrequency(img77, faceBox77);
[blemishMap, ~] = beauty.buildBlemishMap(img77, freq, beautyMasks);
stageProt = masks.buildStageProtectionMasks(beautyMasks, context77.evidence);
compContract = struct('hard', stageProt.hard);
zeroWhitening = struct('delta', zeros(imageSize), 'supportMap', zeros(imageSize));

% Stage 1: Smoothing only
[smFreq, ~] = beauty.smoothSkinTexture(freq, beautyMasks, sSmooth, blemishMap, stageProt);
stage1_out = beauty.composeBeautyResult(img77, freq, smFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 2: +Repair
repContract = beauty.repairStageContract(stageProt, blemishMap);
[repFreq, ~] = beauty.repairSkinBlemishes(smFreq, beautyMasks, blemishMap, sSmooth, repContract);
stage2_out = beauty.composeBeautyResult(img77, freq, repFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 3: +Base Luminance
baseContract = beauty.baseLuminanceStageContract(stageProt);
[baseLum, ~] = beauty.evenSkinLuminance(freq, beautyMasks, sSmooth, baseContract);
stage3_out = beauty.composeBeautyResult(img77, freq, repFreq, beautyMasks, 0, ...
    struct('baseLuminance', baseLum, 'whitening', zeroWhitening), compContract);

% Stage 4: +Tone
toneContract = beauty.toneStageContract(stageProt);
[skinTone, ~] = beauty.normalizeSkinTone(img77, freq, beautyMasks, blemishMap, sSmooth, toneContract);
stage4_out = beauty.composeBeautyResult(img77, freq, repFreq, beautyMasks, 0, ...
    struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', zeroWhitening), compContract);

% Stage 5: +Whitening
whiteContract = beauty.whiteningStageContract(stageProt);
[whitening, ~] = beauty.applySkinWhitening(img77, freq, beautyMasks, sWhite, whiteContract);
stage5_out = beauty.composeBeautyResult(img77, freq, repFreq, beautyMasks, sWhite, ...
    struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', whitening), compContract);

% 1. 断言 Stage 5 与全管线 bit-exact
fullProd = beautifyImage(img77, struct('smoothingStrength', sSmooth, 'whiteningStrength', sWhite), ...
    faceBox77, context77);
verifyEqual(testCase, stage5_out, fullProd, 'Stage 5 必须与全管线生产输出逐位一致');

% 2. 断言 Stage 1 不等于包含 Base/Tone 的伪纯磨皮 (s=100, w=0)
legacyS100W0 = beautifyImage(img77, struct('smoothingStrength', sSmooth, 'whiteningStrength', 0), ...
    faceBox77, context77);
verifyFalse(testCase, isequal(stage1_out, legacyS100W0), ...
    'Stage 1 (Smoothing-only) 不得等同于执行了 Base Lum 与 Tone 的 legacy(s=100, w=0)');

% 3. 断言 Stage 1 与 Stage 2 无色度偏移
ycbcrOrig = rgb2ycbcr(im2double(img77));
ycbcr1 = rgb2ycbcr(im2double(stage1_out));
ycbcr2 = rgb2ycbcr(im2double(stage2_out));
ycbcr3 = rgb2ycbcr(im2double(stage3_out));
ycbcr4 = rgb2ycbcr(im2double(stage4_out));

verifyLessThan(testCase, max(abs(ycbcr1(:,:,2:3) - ycbcrOrig(:,:,2:3)), [], 'all'), 1e-12, ...
    'Smoothing-only 色度必须与原图逐位一致');
verifyLessThan(testCase, max(abs(ycbcr2(:,:,2:3) - ycbcrOrig(:,:,2:3)), [], 'all'), 1e-12, ...
    'Repair 色度必须与原图逐位一致');
verifyLessThan(testCase, max(abs(ycbcr3(:,:,2:3) - ycbcrOrig(:,:,2:3)), [], 'all'), 1e-12, ...
    'Base Luminance 色度必须与原图逐位一致');

% 4. 断言 Stage 3 (Base Luminance) 变化幅度微小 (<= 2.0 RGB)
diffBase = max(abs(double(stage3_out) - double(stage2_out)), [], 3);
verifyLessThanOrEqual(testCase, max(diffBase(:)), 2.0, ...
    '77 样本 Base Luminance 改变幅度极微，不是灰斑来源');

% 5. 断言 Stage 4 (Tone) 首次引入显著色度偏移 (dChroma > 5.0)
eyeMask = roiToMask([120 235 145 70], imageSize);
dChromaTone = hypot(ycbcr4(:,:,2) - ycbcr3(:,:,2), ycbcr4(:,:,3) - ycbcr3(:,:,3)) * 255;
verifyGreaterThan(testCase, max(dChromaTone(eyeMask)), 5.0, ...
    '77 样本灰斑首次出现于 Stage 4 (Tone)，产生显著色度偏移');
end

function m = roiToMask(roi, imSize)
m = false(imSize(1:2));
x1 = max(1, roi(1)); y1 = max(1, roi(2));
x2 = min(imSize(2), roi(1) + roi(3) - 1);
y2 = min(imSize(1), roi(2) + roi(4) - 1);
m(y1:y2, x1:x2) = true;
end
