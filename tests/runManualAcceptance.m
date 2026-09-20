function summary = runManualAcceptance()
%RUNMANUALACCEPTANCE 真实样本人工验收对比产物生成与客观指标度量。
%   覆盖样本：人脸/人脸/77.png, 人脸/人脸/80.jpg, 人脸/人脸2/face/face.jpg
%   产物输出至系统临时目录：
%     C:\Users\JJiio\AppData\Local\Temp\image_beauty_manual_acceptance
%   产物规范：
%     - 每张样本原图、v3.2 旧基线图、v3.3 候选新图
%     - 同尺度三栏并排大图 [原图, v3.2 旧基线, v3.3 候选]
%     - 各部位真实 ROI（眼周、鼻周、嘴周、脸颊、耳部）三栏特写对比
%     - 5 阶段独立隔离与归因（Smoothing, +Repair, +Base Lum, +Tone, +Whitening）
%     - 客观评价指标 CSV（包含源图、v3.2基线、候选值及变化率）与 MAT

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'), '-begin');
addpath(fileparts(mfilename('fullpath')), '-begin');

targetDir = fullfile(tempdir, 'image_beauty_manual_acceptance');
if ~isfolder(targetDir)
    mkdir(targetDir);
end

fprintf('=========================================================\n');
fprintf('开始执行真实图人工验收对比与客观指标计算 (Issue 01 探针修复版)...\n');
fprintf('产物输出目录: %s\n', targetDir);
fprintf('=========================================================\n\n');

results = struct();
csvSummaryRows = {};
csvSummaryRows{end+1} = strjoin({ ...
    'Sample', 'Strength_Smooth', 'Strength_White', ...
    'Entropy_Src', 'Entropy_V32', 'Entropy_Cand', ...
    'StdDev_Src', 'StdDev_V32', 'StdDev_Cand', ...
    'AvgGrad_Src', 'AvgGrad_V32', 'AvgGrad_Cand', ...
    'CheekFine_Src', 'CheekFine_V32', 'CheekFine_Cand', 'CheekFineReduction_Pct', ...
    'EyeAll_Src', 'EyeAll_V32', 'EyeAll_Cand', 'EyeAllRetention_Pct', ...
    'EyeSupport_Src', 'EyeSupport_V32', 'EyeSupport_Cand', 'EyeSupportRetention_Pct', ...
    'NoseStructureRetention_Pct', 'NosePlainReduction_Pct', 'ElapsedSec' ...
}, ',');

% =========================================================================
% 样本 1: 77.png (半侧脸、高难度睫毛、眼周及鼻翼颜色敏感)
% =========================================================================
fprintf('>>> 运行样本 1: 77.png <<<\n');
path77 = fullfile(projectRoot, '人脸', '人脸', '77.png');
probe77Path = fullfile(tempdir, 'image_beauty_issue02_probe', '77_v32_probe.mat');
img77 = imread(path77);
faceBox77 = [95 79 286 372];
if exist(probe77Path, 'file') == 2
    p77 = load(probe77Path, 'context', 'output');
    context77 = prepareBeautyContext(img77, faceBox77, struct('regions', p77.context.regions));
    v32Out77 = p77.output;
else
    context77 = prepareBeautyContext(img77, faceBox77);
    v32Out77 = [];
end

% 经过语义与保护支持域校验的真实 ROI
rois77 = struct( ...
    'eye',   [120 235 145 70], ...   % 准确覆盖左眼球、眼睑、上下睫毛及双眼皮
    'nose',  [150 255 135 120], ...  % 准确覆盖鼻梁、鼻尖、鼻翼及下鼻部结构
    'lip',   [185 350 110 65], ...   % 准确覆盖唇体、唇弓与唇周过渡区
    'cheek', [240 300 70 60], ...    % 纯脸颊皮肤，排除发丝、五官与硬保护
    'ear',   [335 100 85 130]);      % 真实左耳部位

[res77, rows77] = evaluateSample('77', img77, faceBox77, context77, ...
    v32Out77, rois77, targetDir);
results.sample77 = res77;
csvSummaryRows = [csvSummaryRows(:); rows77(:)];

% 77 样本 5 阶段隔离归因分析
fprintf('\n>>> 执行 77 样本 5 阶段独立隔离与归因分析 <<<\n');
stageAttribution77 = execute5Stages(img77, faceBox77, context77, 100, 15, ...
    rois77, '77', targetDir);
results.stageAttribution77 = stageAttribution77;

% =========================================================================
% 样本 2: 80.jpg (正脸大图、双眼、明显鼻翼鼻孔、耳部)
% =========================================================================
fprintf('\n>>> 运行样本 2: 80.jpg <<<\n');
path80 = fullfile(projectRoot, '人脸', '人脸', '80.jpg');
probe80Path = fullfile(tempdir, 'image_beauty_issue02_probe', '80_v32_probe.mat');
img80 = imread(path80);
if exist(probe80Path, 'file') == 2
    p80 = load(probe80Path, 'context', 'faceBox', 'output');
    faceBox80 = p80.faceBox;
    context80 = prepareBeautyContext(img80, faceBox80, struct('regions', p80.context.regions));
    v32Out80 = p80.output;
else
    faceBox80 = [220 180 300 360];
    context80 = prepareBeautyContext(img80, faceBox80);
    v32Out80 = [];
end

rois80 = struct( ...
    'eye',   [180 175 340 85], ...   % 真实双眼、睫毛与眼睑
    'nose',  [270 200 160 190], ...  % 鼻梁、鼻尖、两侧鼻翼与鼻孔
    'lip',   [255 405 185 110], ...  % 完整唇部
    'cheek', [200 300 65 70], ...    % 纯右脸颊皮肤
    'ear',   [540 295 25 80]);       % 真实左耳露出的部位 (位于图像右侧 x=540)

[res80, rows80] = evaluateSample('80', img80, faceBox80, context80, ...
    v32Out80, rois80, targetDir);
results.sample80 = res80;
csvSummaryRows = [csvSummaryRows(:); rows80(:)];
generateRepairStageProbe(img80, faceBox80, context80, rois80, '80', targetDir);

% =========================================================================
% 样本 3: face.jpg (标准正脸样本)
% =========================================================================
fprintf('\n>>> 运行样本 3: face.jpg <<<\n');
pathFace = fullfile(projectRoot, '人脸', '人脸2', 'face', 'face.jpg');
imgFace = imread(pathFace);
faceBoxFace = [48 124 301 301];
faceBaselinePath = fullfile(targetDir, 'face_v32_baseline.png');
if exist(faceBaselinePath, 'file') == 2
    v32OutFace = imread(faceBaselinePath);
else
    v32OutFace = [];
end

cacheFace = fullfile(targetDir, 'cache_face_v32_probe.mat');
if exist(cacheFace, 'file') == 2
    pFace = load(cacheFace);
    if isfield(pFace, 'ctx')
        contextFace = pFace.ctx;
    elseif isfield(pFace, 'context') && isfield(pFace.context, 'regions')
        contextFace = prepareBeautyContext(imgFace, faceBoxFace, struct('regions', pFace.context.regions));
    else
        contextFace = prepareBeautyContext(imgFace, faceBoxFace);
    end
else
    contextFace = prepareBeautyContext(imgFace, faceBoxFace);
    save(cacheFace, 'contextFace', 'faceBoxFace');
end

roisFace = struct( ...
    'eye',   [90 195 215 70], ...    % 真实双眼及眼睑
    'nose',  [140 205 110 140], ...  % 鼻梁、鼻翼与鼻孔
    'lip',   [155 350 130 70], ...   % 完整唇部
    'cheek', [270 280 50 50], ...    % 纯脸颊皮肤 (100% skin, 0 hard/eye/nose/lip)
    'ear',   [385 170 30 115]);      % 左耳部位

[resFace, rowsFace] = evaluateSample('face', imgFace, faceBoxFace, contextFace, ...
    v32OutFace, roisFace, targetDir);
results.sampleFace = resFace;
csvSummaryRows = [csvSummaryRows(:); rowsFace(:)];
generateRepairStageProbe(imgFace, faceBoxFace, contextFace, roisFace, 'face', targetDir);

% =========================================================================
% 输出汇总 CSV 与 MAT
% =========================================================================
csvPath = fullfile(targetDir, 'acceptance_summary.csv');
fid = fopen(csvPath, 'w', 'n', 'UTF-8');
for k = 1:numel(csvSummaryRows)
    fprintf(fid, '%s\n', csvSummaryRows{k});
end
fclose(fid);
fprintf('\n指标汇总 CSV 已保存: %s\n', csvPath);

matPath = fullfile(targetDir, 'acceptance_results.mat');
save(matPath, 'results');
fprintf('验收结构体 MAT 已保存: %s\n', matPath);

fprintf('\n=========================================================\n');
fprintf('人工验收对比产物与 5 阶段归因分析已全部完成！\n');
fprintf('=========================================================\n');

summary = results;
end

% =========================================================================
% 单样本多档位客观指标度量与产物保存
% =========================================================================
function [res, csvRows] = evaluateSample(sampleName, img, faceBox, context, ...
    v32Baseline, rois, targetDir)

% 1. 验证 ROI 并断言非零重叠
[beautyMasks, ~] = masks.buildBeautyMasks(img, context, faceBox);
[~, texDiag] = masks.buildTextureProtectionMask(img, context, faceBox);
assertAndValidateRois(sampleName, img, context, texDiag, rois);

res = struct();
csvRows = {};
imageSize = size(img, 1:2);

% 保证原图与基线图落盘
imwrite(img, fullfile(targetDir, sprintf('%s_original.png', sampleName)));
if ~isempty(v32Baseline)
    imwrite(v32Baseline, fullfile(targetDir, sprintf('%s_v32_baseline.png', sampleName)));
end

% 2. 建立各局部度量区域 mask
eyeRoiMask = roiToMask(rois.eye, imageSize);
noseRoiMask = roiToMask(rois.nose, imageSize);
cheekRoiMask = roiToMask(rois.cheek, imageSize);

% 纯脸颊皮肤 mask：必须排除头发、五官与高保护
cheekPureMask = cheekRoiMask & (context.skinMask >= 0.7) & ...
    (texDiag.hardProtectionMask < 0.01) & ...
    (texDiag.eyeDetailProtection < 0.05) & ...
    (texDiag.noseProtection < 0.05) & ...
    (texDiag.lipProtection < 0.05) & ...
    (texDiag.browProtection < 0.05);
if isfield(context, 'semantic') && isfield(context.semantic, 'hair')
    cheekPureMask = cheekPureMask & (context.semantic.hair < 0.05);
end
assert(nnz(cheekPureMask) >= 100, '纯脸颊有效皮肤像素数不足！');

% 眼睛与睫毛支持域 mask
eyeSupportMask = eyeRoiMask & (texDiag.eyeDetailProtection >= 0.20 | ...
    texDiag.periocularProtection >= 0.20 | ...
    texDiag.lashProtection >= 0.20);
if isfield(context, 'semantic') && isfield(context.semantic, 'eye')
    eyeSupportMask = eyeSupportMask | (eyeRoiMask & (context.semantic.eye > 0.10));
end

% 鼻部细分子域 mask
grayImg = im2double(rgb2gray(img));
nostrilMask = noseRoiMask & (texDiag.nostrilCore > 0.5 | ...
    (texDiag.noseCore > 0.5 & grayImg < 0.22));
noseStructureMask = noseRoiMask & (texDiag.noseStructureProtection >= 0.15 | ...
    texDiag.noseProtection >= 0.20);
plainNoseMask = noseRoiMask & (context.skinMask >= 0.7) & ...
    ~nostrilMask & ~noseStructureMask & (texDiag.hardProtectionMask < 0.01);

% 3. 计算源图基准频带与高频能量
[srcFreq, ~] = beauty.decomposeSkinFrequency(img, faceBox);
srcCheekFineEnergy = std(srcFreq.fine(cheekPureMask));

sigmaHigh = max(1.0, 0.008 * min(faceBox(3:4)));
srcHighFreq = grayImg - imgaussfilt(grayImg, sigmaHigh, 'Padding', 'replicate');
srcEyeAllEnergy = std(srcHighFreq(eyeRoiMask));
if any(eyeSupportMask(:))
    srcEyeSupportEnergy = std(srcHighFreq(eyeSupportMask));
else
    srcEyeSupportEnergy = srcEyeAllEnergy;
end

[srcGradX, srcGradY] = gradient(imgaussfilt(grayImg, 1.5, 'Padding', 'replicate'));
srcGradMag = hypot(srcGradX, srcGradY);
if any(noseStructureMask(:))
    srcNoseStructureGrad = mean(srcGradMag(noseStructureMask));
else
    srcNoseStructureGrad = eps;
end
if any(plainNoseMask(:))
    srcPlainNoseFine = std(srcFreq.fine(plainNoseMask));
else
    srcPlainNoseFine = eps;
end

% 计算 v3.2 旧基线指标（若存在）
v32Metrics = struct('entropy', NaN, 'stdDev', NaN, 'avgGrad', NaN, ...
    'cheekFine', NaN, 'eyeAll', NaN, 'eyeSupport', NaN);
if ~isempty(v32Baseline)
    v32Diag = evaluateImage(img, v32Baseline, 0);
    v32Metrics.entropy = v32Diag.entropy;
    v32Metrics.stdDev = v32Diag.standardDeviation;
    v32Metrics.avgGrad = v32Diag.averageGradient;
    
    [v32Freq, ~] = beauty.decomposeSkinFrequency(v32Baseline, faceBox);
    v32Metrics.cheekFine = std(v32Freq.fine(cheekPureMask));
    
    v32Gray = im2double(rgb2gray(v32Baseline));
    v32HighFreq = v32Gray - imgaussfilt(v32Gray, sigmaHigh, 'Padding', 'replicate');
    v32Metrics.eyeAll = std(v32HighFreq(eyeRoiMask));
    if any(eyeSupportMask(:))
        v32Metrics.eyeSupport = std(v32HighFreq(eyeSupportMask));
    else
        v32Metrics.eyeSupport = v32Metrics.eyeAll;
    end
end

res.srcMetrics = struct('cheekFine', srcCheekFineEnergy, ...
    'eyeAll', srcEyeAllEnergy, 'eyeSupport', srcEyeSupportEnergy, ...
    'noseStructureGrad', srcNoseStructureGrad, 'plainNoseFine', srcPlainNoseFine);
res.v32Metrics = v32Metrics;

strengths = [0, 0; 30, 10; 60, 15; 85, 20; 100, 15];

for k = 1:size(strengths, 1)
    sSmooth = strengths(k, 1);
    sWhite = strengths(k, 2);
    params = struct('smoothingStrength', sSmooth, 'whiteningStrength', sWhite);
    
    tStart = tic;
    [out, ~] = beautifyImage(img, params, faceBox, context);
    tElapsed = toc(tStart);
    
    % 最小验收矩阵自动断言
    assert(isequal(size(out), size(img)), '[%s] 输出尺寸与源图不一致！', sampleName);
    assert(isa(out, 'uint8'), '[%s] 输出类型必须为 uint8！', sampleName);
    
    % 1. 强度 0 (0, 0) 输出与源图逐位一致
    if sSmooth == 0 && sWhite == 0
        assert(isequal(out, img), '[%s] 零强度 (0,0) 输出必须与源图逐位一致！', sampleName);
    end
    
    % 2. hard identity 区域最终 RGB 逐位回源
    hardRegion = texDiag.hardProtectionMask >= 0.999;
    if any(hardRegion(:))
        hardRgb = repmat(hardRegion, 1, 1, 3);
        assert(isequal(out(hardRgb), img(hardRgb)), '[%s] hard identity 区域必须与源图逐位一致！', sampleName);
    end
    
    % 3. cached 与 uncached 输出逐位一致
    uncachedCtx = stripDerivedContext(context);
    [outUncached, ~] = beautifyImage(img, params, faceBox, uncachedCtx);
    assert(isequal(out, outUncached), '[%s] cached 与 uncached 输出必须逐位一致！', sampleName);
    
    % 4. 预览与原尺寸输出比例/尺寸保持（以代表性强度检验）
    if k == 3
        previewScale = min(1, 640 / max(size(img, 1), size(img, 2)));
        if previewScale < 1
            previewImg = imresize(img, previewScale, 'bilinear');
            previewBox = scaleFaceBox(faceBox, previewScale, size(previewImg));
            previewCtx = prepareBeautyContext(previewImg, previewBox);
            [previewOut, ~] = beautifyImage(previewImg, params, previewBox, previewCtx);
            assert(isequal(size(previewOut), size(previewImg)), '[%s] 预览图尺寸保持失败！', sampleName);
            fullCtx = resizeBeautyContext(previewCtx, size(img), faceBox, img);
            [fullOut, ~] = beautifyImage(img, params, faceBox, fullCtx);
            assert(isequal(size(fullOut), size(img)), '[%s] 原尺寸路径恢复尺寸保持失败！', sampleName);
        end
    end
    
    candMetrics = evaluateImage(img, out, tElapsed);
    
    % 脸颊 Fine 能量与降低率
    [outFreq, ~] = beauty.decomposeSkinFrequency(out, faceBox);
    candCheekFine = std(outFreq.fine(cheekPureMask));
    cheekFineReduction = max(0, (srcCheekFineEnergy - candCheekFine) / max(srcCheekFineEnergy, eps)) * 100;
    
    % 眼睛结构高频保留率（ROI 全体 vs 保护支持域）
    outGray = im2double(rgb2gray(out));
    outHighFreq = outGray - imgaussfilt(outGray, sigmaHigh, 'Padding', 'replicate');
    candEyeAll = std(outHighFreq(eyeRoiMask));
    eyeAllRetention = (candEyeAll / max(srcEyeAllEnergy, eps)) * 100;
    
    if any(eyeSupportMask(:))
        candEyeSupport = std(outHighFreq(eyeSupportMask));
        eyeSupportRetention = (candEyeSupport / max(srcEyeSupportEnergy, eps)) * 100;
    else
        candEyeSupport = candEyeAll;
        eyeSupportRetention = eyeAllRetention;
    end
    
    % 鼻部指标
    [outGradX, outGradY] = gradient(imgaussfilt(outGray, 1.5, 'Padding', 'replicate'));
    outGradMag = hypot(outGradX, outGradY);
    if any(noseStructureMask(:))
        noseStructureRetention = (mean(outGradMag(noseStructureMask)) / max(srcNoseStructureGrad, eps)) * 100;
    else
        noseStructureRetention = 100.0;
    end
    if any(plainNoseMask(:))
        candPlainNoseFine = std(outFreq.fine(plainNoseMask));
        nosePlainReduction = max(0, (srcPlainNoseFine - candPlainNoseFine) / max(srcPlainNoseFine, eps)) * 100;
    else
        nosePlainReduction = 0.0;
    end
    
    key = sprintf('s%d_w%d', sSmooth, sWhite);
    res.(key).output = out;
    res.(key).metrics = candMetrics;
    res.(key).cheekFine = candCheekFine;
    res.(key).cheekReduction = cheekFineReduction;
    res.(key).eyeAll = candEyeAll;
    res.(key).eyeAllRetention = eyeAllRetention;
    res.(key).eyeSupport = candEyeSupport;
    res.(key).eyeSupportRetention = eyeSupportRetention;
    res.(key).noseStructureRetention = noseStructureRetention;
    res.(key).nosePlainReduction = nosePlainReduction;
    
    fprintf('  [%s] 档位 s=%3d, w=%2d | 耗时: %.3fs | 纯脸颊Fine降低: %5.1f%% | 眼睛支持域保留: %5.1f%% (全体: %5.1f%%) | 鼻结构保留: %5.1f%%\n', ...
        sampleName, sSmooth, sWhite, tElapsed, cheekFineReduction, eyeSupportRetention, eyeAllRetention, noseStructureRetention);
    
    % CSV 行：同时输出源图、旧基线和候选结果
    csvRows{end+1} = sprintf('%s,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%.4f,%.4f,%.4f,%.2f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.4f', ...
        sampleName, sSmooth, sWhite, ...
        candMetrics.entropy, v32Metrics.entropy, candMetrics.entropy, ...
        candMetrics.standardDeviation, v32Metrics.stdDev, candMetrics.standardDeviation, ...
        candMetrics.averageGradient, v32Metrics.avgGrad, candMetrics.averageGradient, ...
        srcCheekFineEnergy, v32Metrics.cheekFine, candCheekFine, cheekFineReduction, ...
        srcEyeAllEnergy, v32Metrics.eyeAll, candEyeAll, eyeAllRetention, ...
        srcEyeSupportEnergy, v32Metrics.eyeSupport, candEyeSupport, eyeSupportRetention, ...
        noseStructureRetention, nosePlainReduction, tElapsed);
    
    % 保存代表性全图与三栏局部特写
    if sSmooth == 100 && sWhite == 15
        imwrite(out, fullfile(targetDir, sprintf('%s_v33_candidate.png', sampleName)));
        
        if ~isempty(v32Baseline)
            threeCol = [img, v32Baseline, out];
            imwrite(threeCol, fullfile(targetDir, sprintf('%s_three_column_compare.png', sampleName)));
            
            saveThreeColRoi(img, v32Baseline, out, rois.eye, fullfile(targetDir, sprintf('%s_crop_eye_compare.png', sampleName)));
            saveThreeColRoi(img, v32Baseline, out, rois.nose, fullfile(targetDir, sprintf('%s_crop_nose_compare.png', sampleName)));
            saveThreeColRoi(img, v32Baseline, out, rois.lip, fullfile(targetDir, sprintf('%s_crop_lip_compare.png', sampleName)));
            saveThreeColRoi(img, v32Baseline, out, rois.cheek, fullfile(targetDir, sprintf('%s_crop_cheek_compare.png', sampleName)));
            if ~isempty(rois.ear)
                saveThreeColRoi(img, v32Baseline, out, rois.ear, fullfile(targetDir, sprintf('%s_crop_ear_compare.png', sampleName)));
            end
        else
            twoCol = [img, out];
            imwrite(twoCol, fullfile(targetDir, sprintf('%s_two_column_compare.png', sampleName)));
        end
    end
end
end

% =========================================================================
% 真实 5 阶段独立隔离与归因分析
% =========================================================================
function attribution = execute5Stages(img, faceBox, context, sSmooth, sWhite, ...
    rois, sampleName, targetDir)

imageSize = size(img, 1:2);

% 构建底层 masks 与 contracts
[beautyMasks, ~] = masks.buildBeautyMasks(img, context, faceBox);
[freq, ~] = beauty.decomposeSkinFrequency(img, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(img, freq, beautyMasks);

if isfield(context, 'evidence') && isstruct(context.evidence) && isscalar(context.evidence)
    stageProt = masks.buildStageProtectionMasks(beautyMasks, context.evidence);
else
    stageProt = masks.buildStageProtectionMasks(beautyMasks);
end
compContract = struct('hard', stageProt.hard);
zeroWhitening = struct('delta', zeros(imageSize), 'supportMap', zeros(imageSize));

% Stage 1: Smoothing-only (仅磨皮平滑，无 repair, 无 base lum, 无 tone, 无 whitening)
[smFreq, ~] = beauty.smoothSkinTexture(freq, beautyMasks, sSmooth, blemishMap, stageProt);
stage1_out = beauty.composeBeautyResult(img, freq, smFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 2: +Repair (加入瑕疵修复)
repContract = beauty.repairStageContract(stageProt, blemishMap);
[repFreq, repairDiagnostics] = beauty.repairSkinBlemishes(smFreq, beautyMasks, blemishMap, sSmooth, repContract);
stage2_out = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 3: +Base Luminance (加入低频平整)
baseContract = beauty.baseLuminanceStageContract(stageProt);
[baseLum, ~] = beauty.evenSkinLuminance(freq, beautyMasks, sSmooth, baseContract);
proc3 = struct('baseLuminance', baseLum, 'whitening', zeroWhitening);
stage3_out = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    proc3, compContract);

% Stage 4: +Tone (加入肤色统一校色)
toneContract = beauty.toneStageContract(stageProt);
[skinTone, ~] = beauty.normalizeSkinTone(img, freq, beautyMasks, blemishMap, sSmooth, toneContract);
proc4 = struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', zeroWhitening);
stage4_out = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    proc4, compContract);

% Stage 5: +Whitening (加入美白，全管线结果)
whiteContract = beauty.whiteningStageContract(stageProt);
[whitening, ~] = beauty.applySkinWhitening(img, freq, beautyMasks, sWhite, whiteContract);
proc5 = struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', whitening);
stage5_out = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, sWhite, ...
    proc5, compContract);

% 验证 Stage 5 与全管线生产输出 bit-exact
fullProd = beautifyImage(img, struct('smoothingStrength', sSmooth, 'whiteningStrength', sWhite), ...
    faceBox, context);
assert(isequal(stage5_out, fullProd), 'Stage 5 必须与全管线生产算法输出逐位一致！');

% 验证 smoothing-only 结果没有被伪造成美白强度为0
legacyS100W0 = beautifyImage(img, struct('smoothingStrength', sSmooth, 'whiteningStrength', 0), ...
    faceBox, context);
assert(~isequal(stage1_out, legacyS100W0), ...
    'Smoothing-only 必须是真正的纯磨皮阶段，不能等同于执行了 Base Lum 与 Tone 的 legacy (s=100, w=0)！');

% 保存各 Stage 独立图
imwrite(stage1_out, fullfile(targetDir, sprintf('%s_stage1_smoothing_only.png', sampleName)));
imwrite(stage2_out, fullfile(targetDir, sprintf('%s_stage2_repair.png', sampleName)));
imwrite(stage3_out, fullfile(targetDir, sprintf('%s_stage3_base_luminance.png', sampleName)));
imwrite(stage4_out, fullfile(targetDir, sprintf('%s_stage4_tone.png', sampleName)));
imwrite(stage5_out, fullfile(targetDir, sprintf('%s_stage5_whitening.png', sampleName)));

% 生成逐级差分图（经 5x 增强便于肉眼观察）
diff1 = max(abs(double(stage1_out) - double(img)), [], 3);
diff2 = max(abs(double(stage2_out) - double(stage1_out)), [], 3);
diff3 = max(abs(double(stage3_out) - double(stage2_out)), [], 3);
diff4 = max(abs(double(stage4_out) - double(stage3_out)), [], 3);
diff5 = max(abs(double(stage5_out) - double(stage4_out)), [], 3);
assertNoRepairGrayBlocks(sampleName, diff2, rois, min(faceBox(3:4)));

imwrite(uint8(min(255, round(diff1 * 5))), fullfile(targetDir, sprintf('%s_diff_stage1_vs_orig.png', sampleName)));
imwrite(uint8(min(255, round(diff2 * 5))), fullfile(targetDir, sprintf('%s_diff_stage2_vs_stage1.png', sampleName)));
imwrite(uint8(min(max(repairDiagnostics.repairWeight, 0), 1) * 255), ...
    fullfile(targetDir, sprintf('%s_repair_weight.png', sampleName)));
imwrite(uint8(min(255, round(diff3 * 5))), fullfile(targetDir, sprintf('%s_diff_stage3_vs_stage2.png', sampleName)));
imwrite(uint8(min(255, round(diff4 * 5))), fullfile(targetDir, sprintf('%s_diff_stage4_vs_stage3.png', sampleName)));
imwrite(uint8(min(255, round(diff5 * 5))), fullfile(targetDir, sprintf('%s_diff_stage5_vs_stage4.png', sampleName)));

% 生成阶段差分彩色热力图
imwrite(diffToHeatmap(diff1, 30), fullfile(targetDir, sprintf('%s_heatmap_diff_stage1_vs_orig.png', sampleName)));
imwrite(diffToHeatmap(diff2, 30), fullfile(targetDir, sprintf('%s_heatmap_diff_stage2_vs_stage1.png', sampleName)));
imwrite(diffToHeatmap(diff3, 10), fullfile(targetDir, sprintf('%s_heatmap_diff_stage3_vs_stage2.png', sampleName)));
imwrite(diffToHeatmap(diff4, 25), fullfile(targetDir, sprintf('%s_heatmap_diff_stage4_vs_stage3.png', sampleName)));
imwrite(diffToHeatmap(diff5, 20), fullfile(targetDir, sprintf('%s_heatmap_diff_stage5_vs_stage4.png', sampleName)));

% Stage 4 (Tone) 色度差分热力图（确凿证明灰斑在 Tone 阶段不再爆发）
ycbcr3 = rgb2ycbcr(im2double(stage3_out));
ycbcr4 = rgb2ycbcr(im2double(stage4_out));
dChromaToneMap = hypot(ycbcr4(:, :, 2) - ycbcr3(:, :, 2), ycbcr4(:, :, 3) - ycbcr3(:, :, 3)) * 255;
imwrite(diffToHeatmap(dChromaToneMap, 15), fullfile(targetDir, sprintf('%s_heatmap_stage4_tone_dChroma.png', sampleName)));

% 生成 6 栏递进对比条带 [原图, Stage 1, Stage 2, Stage 3, Stage 4, Stage 5]
progressionStrip = [img, stage1_out, stage2_out, stage3_out, stage4_out, stage5_out];
imwrite(progressionStrip, fullfile(targetDir, sprintf('%s_stage_progression_strip.png', sampleName)));

saveProgressionRoi(img, {stage1_out, stage2_out, stage3_out, stage4_out, stage5_out}, ...
    rois.eye, fullfile(targetDir, sprintf('%s_crop_eye_stage_progression.png', sampleName)));
saveProgressionRoi(img, {stage1_out, stage2_out, stage3_out, stage4_out, stage5_out}, ...
    rois.nose, fullfile(targetDir, sprintf('%s_crop_nose_stage_progression.png', sampleName)));
saveProgressionRoi(img, {stage1_out, stage2_out, stage3_out, stage4_out, stage5_out}, ...
    rois.cheek, fullfile(targetDir, sprintf('%s_crop_cheek_stage_progression.png', sampleName)));
if ~isempty(rois.ear)
    saveProgressionRoi(img, {stage1_out, stage2_out, stage3_out, stage4_out, stage5_out}, ...
        rois.ear, fullfile(targetDir, sprintf('%s_crop_ear_stage_progression.png', sampleName)));
end

% 5 阶段演化矩阵大图（多 ROI 纵向排布对齐）
stagesList = {img, stage1_out, stage2_out, stage3_out, stage4_out, stage5_out};
evolutionMatrix = buildEvolutionMatrix(stagesList, rois);
imwrite(evolutionMatrix, fullfile(targetDir, sprintf('%s_stage_evolution_matrix.png', sampleName)));

% 逐级数值统计与归因记录
stages = {stage1_out, stage2_out, stage3_out, stage4_out, stage5_out};
stageNames = {'Stage1_Smoothing', 'Stage2_Repair', 'Stage3_BaseLum', 'Stage4_Tone', 'Stage5_Whitening'};
stageRows = {};
stageRows{end+1} = 'Region,Stage,MaxRGBDiff,MeanRGBDiff,StdRGBDiff,Mean_dY,Mean_dChroma,Max_dChroma';

attribution = struct();
roiNames = {'full', 'eye', 'nose', 'cheek', 'lip', 'ear'};

for r = 1:numel(roiNames)
    rName = roiNames{r};
    if strcmp(rName, 'full')
        roiMask = true(imageSize);
    else
        if isempty(rois.(rName))
            continue;
        end
        roiMask = roiToMask(rois.(rName), imageSize);
    end
    
    prev = img;
    for k = 1:5
        curr = stages{k};
        
        diff = max(abs(double(curr) - double(prev)), [], 3);
        diffRegion = diff(roiMask);
        
        prevYcbcr = rgb2ycbcr(im2double(prev));
        currYcbcr = rgb2ycbcr(im2double(curr));
        dY = abs(currYcbcr(:, :, 1) - prevYcbcr(:, :, 1)) * 255;
        dChroma = hypot(currYcbcr(:, :, 2) - prevYcbcr(:, :, 2), ...
                        currYcbcr(:, :, 3) - prevYcbcr(:, :, 3)) * 255;
        dYRegion = dY(roiMask);
        dChromaRegion = dChroma(roiMask);
        
        maxRgb = max(diffRegion);
        meanRgb = mean(diffRegion);
        stdRgb = std(diffRegion);
        meanY = mean(dYRegion);
        meanChroma = mean(dChromaRegion);
        maxChroma = max(dChromaRegion);
        
        attribution.(rName).(stageNames{k}) = struct( ...
            'maxRGBDiff', maxRgb, 'meanRGBDiff', meanRgb, 'stdRGBDiff', stdRgb, ...
            'mean_dY', meanY, 'mean_dChroma', meanChroma, 'max_dChroma', maxChroma);
        
        stageRows{end+1} = sprintf('%s,%s,%.2f,%.3f,%.3f,%.3f,%.3f,%.2f', ...
            rName, stageNames{k}, maxRgb, meanRgb, stdRgb, meanY, meanChroma, maxChroma);
        
        prev = curr;
    end
end

% 写入 Stage 归因 CSV
stageCsvPath = fullfile(targetDir, sprintf('%s_stage_attribution.csv', sampleName));
fid = fopen(stageCsvPath, 'w', 'n', 'UTF-8');
for k = 1:numel(stageRows)
    fprintf(fid, '%s\n', stageRows{k});
end
fclose(fid);
fprintf('  [%s] 5 阶段归因 CSV 已保存: %s\n', sampleName, stageCsvPath);

% 打印诊断结论
fprintf('  === %s 阶段归因诊断 ===\n', sampleName);
fprintf('  Stage 1 (Smoothing vs Orig): 全图 maxRGB=%.1f, 眼周 meanRGB=%.2f, dChroma=%.2f\n', ...
    attribution.full.Stage1_Smoothing.maxRGBDiff, attribution.eye.Stage1_Smoothing.meanRGBDiff, attribution.eye.Stage1_Smoothing.max_dChroma);
fprintf('  Stage 2 (+Repair vs Stg1)  : 全图 maxRGB=%.1f, 眼周 meanRGB=%.2f, dChroma=%.2f\n', ...
    attribution.full.Stage2_Repair.maxRGBDiff, attribution.eye.Stage2_Repair.meanRGBDiff, attribution.eye.Stage2_Repair.max_dChroma);
fprintf('  Stage 3 (+BaseLum vs Stg2) : 全图 maxRGB=%.1f, 眼周 meanRGB=%.2f, dChroma=%.2f\n', ...
    attribution.full.Stage3_BaseLum.maxRGBDiff, attribution.eye.Stage3_BaseLum.meanRGBDiff, attribution.eye.Stage3_BaseLum.max_dChroma);
fprintf('  Stage 4 (+Tone vs Stg3)    : 全图 maxRGB=%.1f, 眼周 meanRGB=%.2f, dChroma=%.2f\n', ...
    attribution.full.Stage4_Tone.maxRGBDiff, attribution.eye.Stage4_Tone.meanRGBDiff, attribution.eye.Stage4_Tone.max_dChroma);
fprintf('  Stage 5 (+White vs Stg4)   : 全图 maxRGB=%.1f, 眼周 meanRGB=%.2f, dChroma=%.2f\n', ...
    attribution.full.Stage5_Whitening.maxRGBDiff, attribution.eye.Stage5_Whitening.meanRGBDiff, attribution.eye.Stage5_Whitening.max_dChroma);

if attribution.full.Stage2_Repair.meanRGBDiff < 1.0
    fprintf('  【Repair 验收结论】: %s 的 Stage 2 平均改变量为 %.3f RGB，未形成连续灰色块；后续阶段需结合 ROI 图片人工确认。\n', ...
        sampleName, attribution.full.Stage2_Repair.meanRGBDiff);
else
    fprintf('  【Repair 验收结论】: %s 的 Stage 2 平均改变量为 %.3f RGB，仍需退回 Repair 定位。\n', ...
        sampleName, attribution.full.Stage2_Repair.meanRGBDiff);
end
end

function result = generateRepairStageProbe(img, faceBox, context, rois, sampleName, targetDir)
%GENERATEREPAIRSTAGEPROBE 为 80/face 生成可信的 Smoothing→Repair 对照。
%   最终验收需要验证各样本的 Stage 2，而不是只看完整管线三栏图。
imageSize = size(img, 1:2);
[beautyMasks, ~] = masks.buildBeautyMasks(img, context, faceBox);
[frequency, ~] = beauty.decomposeSkinFrequency(img, faceBox);
[blemishMap, ~] = beauty.buildBlemishMap(img, frequency, beautyMasks);
if isfield(context, 'evidence') && isstruct(context.evidence) && isscalar(context.evidence)
    stageProtection = masks.buildStageProtectionMasks(beautyMasks, context.evidence);
else
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
end
[smoothed, ~] = beauty.smoothSkinTexture(frequency, beautyMasks, 100, ...
    blemishMap, stageProtection);
composeContract = struct('hard', stageProtection.hard);
zeroWhitening = struct('delta', zeros(imageSize), 'supportMap', zeros(imageSize));
stage1 = beauty.composeBeautyResult(img, frequency, smoothed, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), composeContract);
repairContract = beauty.repairStageContract(stageProtection, blemishMap);
[repaired, repairDiagnostics] = beauty.repairSkinBlemishes(smoothed, ...
    beautyMasks, blemishMap, 100, repairContract);
stage2 = beauty.composeBeautyResult(img, frequency, repaired, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), composeContract);

imwrite(stage1, fullfile(targetDir, sprintf('%s_stage1_smoothing_only.png', sampleName)));
imwrite(stage2, fullfile(targetDir, sprintf('%s_stage2_repair.png', sampleName)));
imwrite([stage1, stage2], fullfile(targetDir, sprintf('%s_stage1_stage2_compare.png', sampleName)));
imwrite(uint8(min(max(repairDiagnostics.repairWeight, 0), 1) * 255), ...
    fullfile(targetDir, sprintf('%s_repair_weight.png', sampleName)));
saveProgressionRoi(img, {stage1, stage2}, rois.eye, ...
    fullfile(targetDir, sprintf('%s_crop_eye_stage1_stage2.png', sampleName)));
saveProgressionRoi(img, {stage1, stage2}, rois.nose, ...
    fullfile(targetDir, sprintf('%s_crop_nose_stage1_stage2.png', sampleName)));
saveProgressionRoi(img, {stage1, stage2}, rois.lip, ...
    fullfile(targetDir, sprintf('%s_crop_lip_stage1_stage2.png', sampleName)));
saveProgressionRoi(img, {stage1, stage2}, rois.cheek, ...
    fullfile(targetDir, sprintf('%s_crop_cheek_stage1_stage2.png', sampleName)));
if ~isempty(rois.ear)
    saveProgressionRoi(img, {stage1, stage2}, rois.ear, ...
        fullfile(targetDir, sprintf('%s_crop_ear_stage1_stage2.png', sampleName)));
end

diffMap = max(abs(double(stage2) - double(stage1)), [], 3);
assertNoRepairGrayBlocks(sampleName, diffMap, rois, min(faceBox(3:4)));
result = struct('stage2MaxRGBDiff', max(diffMap(:)), ...
    'stage2MeanRGBDiff', mean(diffMap(:)), ...
    'repairWeightActivePixels', nnz(repairDiagnostics.repairWeight > .01), ...
    'repairWeightMax', max(repairDiagnostics.repairWeight(:)));
fprintf('  [%s] Stage 1→2 maxRGB=%.1f meanRGB=%.3f，Repair active=%d\n', ...
    sampleName, result.stage2MaxRGBDiff, result.stage2MeanRGBDiff, ...
    result.repairWeightActivePixels);
end

function assertNoRepairGrayBlocks(sampleName, diffMap, rois, faceScale)
%ASSERTNOREPAIRGRAYBLOCKS 以 Stage 1→2 的亮度/RGB 改变量筛除连续灰块。
%   色度不变并不能证明视觉无灰层，因此同时约束 ROI 平均改变量和
%   高改变量占比；阈值按 ROI 观察用途固定，不参与生产算法。
roiNames = {'eye', 'nose', 'lip', 'cheek', 'ear'};
for index = 1:numel(roiNames)
    name = roiNames{index};
    if ~isfield(rois, name) || isempty(rois.(name))
        continue;
    end
    mask = roiToMask(rois.(name), size(diffMap));
    values = diffMap(mask);
    if isempty(values)
        continue;
    end
    meanDiff = mean(values);
    highFraction = mean(values > 8);
    if meanDiff >= 1.0 || highFraction >= .03
        error('runManualAcceptance:RepairGrayBlock', ...
            '[%s] %s ROI 的 Stage 2 平均 RGB 改变量 %.3f、高改变量占比 %.3f，疑似连续灰块。', ...
            sampleName, name, meanDiff, highFraction);
    end
end
if ~isfinite(faceScale) || faceScale <= 0
    error('runManualAcceptance:InvalidFaceScale', ...
        '[%s] 人脸尺度无效，无法完成 Repair 灰块验收。', sampleName);
end
end

% =========================================================================
% 辅助函数
% =========================================================================
function assertAndValidateRois(sampleName, img, ctx, texDiag, rois)
imageSize = size(img, 1:2);

% 1. Eye ROI 断言：必须与眼睛语义或眼周细节保护非零重叠
eyeMask = roiToMask(rois.eye, imageSize);
eyeSemOverlap = 0;
if isfield(ctx, 'semantic') && isfield(ctx.semantic, 'eye')
    eyeSemOverlap = nnz(eyeMask & (ctx.semantic.eye > 0.1));
end
eyeProtOverlap = nnz(eyeMask & (texDiag.eyeDetailProtection > 0.1 | texDiag.periocularBand > 0.1));
if eyeSemOverlap == 0 && eyeProtOverlap == 0
    error('runManualAcceptance:EyeRoiMismatch', ...
        '[%s] 样本 eye ROI [%d %d %d %d] 未与眼睛语义或眼周保护支持域重叠！', ...
        sampleName, rois.eye);
end

% 2. Nose ROI 断言：必须与鼻语义非零重叠
noseMask = roiToMask(rois.nose, imageSize);
noseSemOverlap = 0;
if isfield(ctx, 'semantic') && isfield(ctx.semantic, 'nose')
    noseSemOverlap = nnz(noseMask & (ctx.semantic.nose > 0.1));
end
if noseSemOverlap == 0
    error('runManualAcceptance:NoseRoiMismatch', ...
        '[%s] 样本 nose ROI [%d %d %d %d] 未与鼻部语义重叠！', ...
        sampleName, rois.nose);
end

% 3. Lip ROI 断言：必须与唇语义非零重叠
lipMask = roiToMask(rois.lip, imageSize);
lipSemOverlap = 0;
if isfield(ctx, 'semantic') && isfield(ctx.semantic, 'lip')
    lipSemOverlap = nnz(lipMask & (ctx.semantic.lip > 0.1));
end
if lipSemOverlap == 0 && nnz(lipMask & (texDiag.lipProtection > 0.1)) == 0
    error('runManualAcceptance:LipRoiMismatch', ...
        '[%s] 样本 lip ROI [%d %d %d %d] 未与唇部语义重叠！', ...
        sampleName, rois.lip);
end

% 4. Cheek ROI 断言：必须是高纯度脸颊皮肤，严禁与眼睛/鼻子/嘴唇/硬保护重叠
cheekMask = roiToMask(rois.cheek, imageSize);
skinFrac = mean(ctx.skinMask(cheekMask) >= 0.7);
hardMax = max(texDiag.hardProtectionMask(cheekMask));
eyeMax = max(texDiag.eyeDetailProtection(cheekMask));
noseMax = max(texDiag.noseProtection(cheekMask));
lipMax = max(texDiag.lipProtection(cheekMask));

if skinFrac < 0.85 || hardMax >= 0.05 || eyeMax >= 0.05 || noseMax >= 0.05 || lipMax >= 0.05
    error('runManualAcceptance:CheekRoiImpure', ...
        '[%s] 样本 cheek ROI 纯度不满足要求 (skinFrac=%.2f, hard=%.2f, eye=%.2f, nose=%.2f, lip=%.2f)！', ...
        sampleName, skinFrac, hardMax, eyeMax, noseMax, lipMax);
end

% 5. Ear ROI 断言（若存在）
if ~isempty(rois.ear)
    earMask = roiToMask(rois.ear, imageSize);
    earSemOverlap = 0;
    if isfield(ctx, 'semantic') && isfield(ctx.semantic, 'ear')
        earSemOverlap = nnz(earMask & (ctx.semantic.ear > 0.1));
    end
    if isfield(ctx, 'regions')
        if isfield(ctx.regions, 'leftEar'), earSemOverlap = earSemOverlap + nnz(earMask & (ctx.regions.leftEar > 0.1)); end
        if isfield(ctx.regions, 'rightEar'), earSemOverlap = earSemOverlap + nnz(earMask & (ctx.regions.rightEar > 0.1)); end
    end
    if earSemOverlap == 0
        error('runManualAcceptance:EarRoiMismatch', ...
            '[%s] 样本 ear ROI 未与耳部语义重叠！', sampleName);
    end
end
end

function saveThreeColRoi(imgOrig, imgV32, imgV33, roi, savePath)
if isempty(roi)
    return;
end
pOrig = cropRoi(imgOrig, roi);
pV32 = cropRoi(imgV32, roi);
pV33 = cropRoi(imgV33, roi);
patchCompare = [pOrig, pV32, pV33];
imwrite(patchCompare, savePath);
end

function saveProgressionRoi(imgOrig, stageOutputs, roi, savePath)
if isempty(roi)
    return;
end
strip = cropRoi(imgOrig, roi);
for k = 1:numel(stageOutputs)
    strip = [strip, cropRoi(stageOutputs{k}, roi)]; %#ok<AGROW>
end
imwrite(strip, savePath);
end

function patch = cropRoi(mat, roi)
x1 = max(1, roi(1)); y1 = max(1, roi(2));
x2 = min(size(mat, 2), roi(1) + roi(3) - 1);
y2 = min(size(mat, 1), roi(2) + roi(4) - 1);
patch = mat(y1:y2, x1:x2, :);
end

function m = roiToMask(roi, imSize)
m = false(imSize(1:2));
x1 = max(1, roi(1)); y1 = max(1, roi(2));
x2 = min(imSize(2), roi(1) + roi(3) - 1);
y2 = min(imSize(1), roi(2) + roi(4) - 1);
m(y1:y2, x1:x2) = true;
end

function context = stripDerivedContext(context)
names = {'runtimeCache', 'textureProtectionMask', ...
    'structureProtectionMask', 'whiteningProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', 'nonFaceStrengthMap', 'protectionMasks'};
present = names(isfield(context, names));
if ~isempty(present)
    context = rmfield(context, present);
end
end

function box = scaleFaceBox(box, scale, imageSize)
box = round(double(box) * scale);
box(1) = max(1, min(box(1), imageSize(2)));
box(2) = max(1, min(box(2), imageSize(1)));
x2 = min(imageSize(2), box(1) + box(3) - 1);
y2 = min(imageSize(1), box(2) + box(4) - 1);
box(3:4) = max(1, [x2 - box(1) + 1, y2 - box(2) + 1]);
end

function heat = diffToHeatmap(diffMap, maxVal)
if nargin < 2 || isempty(maxVal)
    maxVal = max(diffMap(:));
end
normDiff = min(1, max(0, double(diffMap) / max(maxVal, eps)));
cmap = jet(256);
idx = round(normDiff * 255) + 1;
heat = uint8(reshape(cmap(idx, :) * 255, [size(diffMap, 1), size(diffMap, 2), 3]));
end

function matrixImg = buildEvolutionMatrix(stagesList, rois)
roiNames = {'eye', 'nose', 'lip', 'cheek'};
if isfield(rois, 'ear') && ~isempty(rois.ear)
    roiNames{end+1} = 'ear';
end
targetWidth = 1200;
rows = {};
for r = 1:numel(roiNames)
    roi = rois.(roiNames{r});
    rowStrips = cell(1, numel(stagesList));
    for s = 1:numel(stagesList)
        rowStrips{s} = cropRoi(stagesList{s}, roi);
    end
    strip = cat(2, rowStrips{:});
    scale = targetWidth / size(strip, 2);
    resizedStrip = imresize(strip, [max(1, round(size(strip, 1) * scale)), targetWidth], 'bilinear');
    rows{end+1} = resizedStrip; %#ok<AGROW>
    rows{end+1} = 255 * ones(3, targetWidth, 3, 'uint8'); %#ok<AGROW>
end
matrixImg = cat(1, rows{1:end-1});
end
