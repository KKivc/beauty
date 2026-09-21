function summary = generateVisualAcceptanceArtifacts()
%GENERATEVISUALACCEPTANCEARTIFACTS 生成 v3.3/v3.5/v3.6 真实图验收产物。
%   严格遵守任务 03 要求：
%   1. 样本：77.png, 80.jpg, face.jpg
%   2. 输出目录：系统临时目录 (tempdir/image_beauty_v36_manual_acceptance)
%   3. 77/face 五栏、80 六栏全图；80 额外包含 80r.jpg 精修目标。
%   4. ROI 特写同样包含原图、v3.3、v3.5、v3.6，80 额外加入 80r：
%      - eye (双眼)
%      - eyelash (睫毛)
%      - eyelid (眼皮)
%      - eyebrow (眉毛)
%      - forehead (额头)
%      - nose_bridge (鼻梁)
%      - nose_wing (鼻翼)
%      - nostril (鼻孔暗部)
%      - lip (嘴唇)
%      - ear (耳朵)
%      - cheek (脸颊纯皮肤)
%      - hair_clothes (头发/衣服边界)
%   5. 强度梯次对比：0, 30, 50, 60, 75, 85, 100
%   6. Smoothing/Dense/Compact Repair/Base/Tone/Whitening 阶段归因与热力图。
%   7. 客观指标汇总 CSV。所有产物只写入系统临时目录。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
v33Root = fullfile(tempdir, 'image_beauty_v33_src');
v35Root = fullfile(tempdir, 'image_beauty_v35_src');
targetDir = fullfile(tempdir, 'image_beauty_v36_real_parsing_acceptance');

% v3.3 基线由当前仓库 HEAD:src 生成，避免依赖可能为空的个人临时备份；
% v3.5 则从当前工作区复制后去除任务 03 的 Tone 收尾，仅写入临时目录。
ensureV33Source(projectRoot, v33Root);
prepareV35Source(projectRoot, v35Root);
if ~isfolder(targetDir)
    mkdir(targetDir);
end

fprintf('=================================================================\n');
fprintf('开始生成 Issue 02 真实图视觉验收产物\n');
fprintf('项目目录 (v3.6 当前): %s\n', projectRoot);
fprintf('参考目录 (v3.3 基线): %s\n', v33Root);
fprintf('参考目录 (v3.5 候选): %s\n', v35Root);
fprintf('产物输出目录: %s\n', targetDir);
fprintf('=================================================================\n\n');

% 定义 3 张代表性真实图配置
samples = struct();

% 样本 1: 77.png
samples(1).name = '77';
samples(1).path = fullfile(projectRoot, '人脸', '人脸', '77.png');
samples(1).faceBox = [95 79 286 372];
samples(1).rois = struct( ...
    'eye',          [120 235 145 70], ...
    'eyelash',      [125 245 135 45], ...
    'eyelid',       [135 235 120 40], ...
    'eyebrow',      [120 200 150 40], ...
    'forehead',     [145 120 150 75], ...
    'nose_bridge',  [180 255 70 75], ...
    'nose_wing',    [150 300 135 75], ...
    'nostril',      [180 320 70 50], ...
    'lip',          [185 350 110 65], ...
    'ear',          [335 100 85 130], ...
    'cheek',        [240 300 70 60], ...
    'hair_clothes', [40 300 80 120]);

% 样本 2: 80.jpg
samples(2).name = '80';
samples(2).path = fullfile(projectRoot, '人脸', '人脸', '80.jpg');
samples(2).targetPath = fullfile(projectRoot, '人脸', '人脸', '80r.jpg');
samples(2).faceBox = [220 180 300 360];
samples(2).rois = struct( ...
    'eye',          [180 175 340 85], ...
    'eyelash',      [200 190 300 50], ...
    'eyelid',       [200 175 300 45], ...
    'eyebrow',      [190 140 320 50], ...
    'forehead',     [270 230 200 75], ...
    'nose_bridge',  [320 230 95 95], ...
    'nose_wing',    [270 285 160 105], ...
    'nostril',      [295 325 110 55], ...
    'lip',          [255 405 185 110], ...
    'ear',          [1 150 80 210], ...
    'cheek',        [200 300 65 70], ...
    'hair_clothes', [50 400 100 120]);

% 样本 3: face.jpg
samples(3).name = 'face';
samples(3).path = fullfile(projectRoot, '人脸', '人脸2', 'face', 'face.jpg');
samples(3).faceBox = [48 124 301 301];
samples(3).rois = struct( ...
    'eye',          [90 195 215 70], ...
    'eyelash',      [100 210 195 45], ...
    'eyelid',       [100 195 195 40], ...
    'eyebrow',      [90 150 215 50], ...
    'forehead',     [100 135 200 60], ...
    'nose_bridge',  [160 225 80 75], ...
    'nose_wing',    [135 270 125 80], ...
    'nostril',      [165 295 70 45], ...
    'lip',          [155 350 130 70], ...
    'ear',          [400 180 65 130], ...
    'cheek',        [270 280 50 50], ...
    'hair_clothes', [450 250 100 100]);

% 档位测试配置: [smoothing, whitening]
strengthLevels = [
    0, 0;
    30, 10;
    50, 10;
    60, 15;
    75, 15;
    85, 20;
    100, 15
];

% 准备指标 CSV 表头
metricsCsvRows = {};
metricsCsvRows{end+1} = strjoin({ ...
    'Sample', 'SmoothStrength', 'WhiteStrength', ...
    'Entropy_Src', 'Entropy_V33', 'Entropy_V35', 'Entropy_V36', ...
    'StdDev_Src', 'StdDev_V33', 'StdDev_V35', 'StdDev_V36', ...
    'AvgGrad_Src', 'AvgGrad_V33', 'AvgGrad_V35', 'AvgGrad_V36', ...
    'CheekFine_Src', 'CheekFine_V33', 'CheekFine_V35', 'CheekFine_V36', ...
    'CheekFineReductPct_V33', 'CheekFineReductPct_V35', 'CheekFineReductPct_V36', ...
    'CheekFineBoostPct_V35', 'CheekFineBoostPct_V36', ...
    'EyeRetentionPct_V33', 'EyeRetentionPct_V35', 'EyeRetentionPct_V36', ...
    'MaxRgbDiff_V35_vs_V33', 'MaxRgbDiff_V36_vs_V35', 'MaxRgbDiff_V36_vs_V33', ...
    'ElapsedSec_V33', 'ElapsedSec_V35', 'ElapsedSec_V36' ...
}, ',');

stageCsvRows = {};
stageCsvRows{end+1} = strjoin({ ...
    'Sample', 'StageName', 'Region', ...
    'MeanRGBDiff_V33', 'MeanRGBDiff_V35', 'MeanRGBDiff_V36', ...
    'MaxRGBDiff_V33', 'MaxRGBDiff_V35', 'MaxRGBDiff_V36', ...
    'DeltaStageDiff_V35_vs_V33', 'DeltaStageDiff_V36_vs_V35' ...
}, ',');

semanticCsvRows = {};
semanticCsvRows{end+1} = strjoin({ ...
    'Sample', 'SemanticSource', 'BodySemanticSource', 'FallbackUsed', ...
    'CheekSkinCoverage', 'CheekFaceSkinCoverage', ...
    'CheekStrengthCoverage', 'BodySkinPixels', 'FaceSkinPixels' ...
}, ',');

% 预先加载全部 3 个样本，并且只在当前生产代码中执行一次真实的
% BiSeNet/SCHP 推理。后续 v3.3/v3.5/v3.6 只复用这里保存的证据。
try rmpath(v33Root); catch; end
try rmpath(v35Root); catch; end
addpath(fullfile(projectRoot, 'src'), '-begin');
clear functions;
for sIdx = 1:numel(samples)
    samples(sIdx).img = imread(samples(sIdx).path);
    imSize = size(samples(sIdx).img, 1:2);
    samples(sIdx).targetImage = [];
    if isfield(samples(sIdx), 'targetPath') && ...
            ~isempty(samples(sIdx).targetPath)
        samples(sIdx).targetImage = imread(samples(sIdx).targetPath);
        if ~isequal(size(samples(sIdx).targetImage), size(samples(sIdx).img))
            error('generateVisualAcceptanceArtifacts:TargetSizeMismatch', ...
                '精修目标尺寸必须与输入图一致: %s', samples(sIdx).targetPath);
        end
    end
    sName = samples(sIdx).name;
    fprintf('  [%s] 执行当前生产 BiSeNet 真实解析...\n', sName);
    try
        parsing = parseFaceRegions(samples(sIdx).img, samples(sIdx).faceBox);
    catch exception
        error('generateVisualAcceptanceArtifacts:SemanticInferenceFailed', ...
            '样本 %s 的真实 BiSeNet 解析失败，禁止生成验收图：%s', ...
            sName, exception.message);
    end
    if ~isstruct(parsing) || ~isfield(parsing, 'regions') || ...
            ~isfield(parsing, 'regionConfidence')
        error('generateVisualAcceptanceArtifacts:InvalidSemanticEvidence', ...
            '样本 %s 的 BiSeNet 结果缺少 regions/regionConfidence。', sName);
    end
    fprintf('  [%s] 执行当前生产 SCHP 真实身体解析...\n', sName);
    try
        probabilities = inferSchpLipProbabilities(samples(sIdx).img, struct());
    catch exception
        error('generateVisualAcceptanceArtifacts:SemanticInferenceFailed', ...
            '样本 %s 的真实 SCHP 解析失败，禁止生成验收图：%s', ...
            sName, exception.message);
    end
    if ~isequal(size(probabilities), [imSize, 20]) || ...
            any(~isfinite(probabilities(:))) || ...
            any(probabilities(:) < 0) || any(probabilities(:) > 1)
        error('generateVisualAcceptanceArtifacts:InvalidSemanticEvidence', ...
            '样本 %s 的 SCHP probabilities 尺寸或值域无效。', sName);
    end
    samples(sIdx).parsingStruct = parsing;
    samples(sIdx).bodyParsing = struct('probabilities', probabilities);
    samples(sIdx).semanticSource = '当前生产 BiSeNet';
    samples(sIdx).bodySemanticSource = '当前生产 SCHP';
    samples(sIdx).fallbackUsed = false;
    fprintf('  [%s] 语义证据已固定：BiSeNet + SCHP；不使用 probe 或几何 fallback。\n', sName);
end

% =========================================================================
% Pass 1: 在 v3.3 基线环境下计算全部输出
% =========================================================================
fprintf('\n>>> [Pass 1/3] 正在切换至 v3.3 基线环境运行全部样本...\n');
try rmpath(fullfile(projectRoot, 'src')); catch; end
addpath(v33Root, '-begin');
clear functions;

v33Data = struct();
for sIdx = 1:numel(samples)
    sName = samples(sIdx).name;
    img = samples(sIdx).img;
    fb = samples(sIdx).faceBox;
    pStruct = samples(sIdx).parsingStruct;
    bp = samples(sIdx).bodyParsing;
    
    fprintf('  [v3.3] 处理样本: %s ...\n', sName);
    ctx = prepareBeautyContext(img, fb, pStruct, bp);
    
    % 多档位运行
    numLvl = size(strengthLevels, 1);
    v33Data(sIdx).outputs = cell(numLvl, 1);
    v33Data(sIdx).elapsed = zeros(numLvl, 1);
    for lvlIdx = 1:numLvl
        p = struct('smoothingStrength', strengthLevels(lvlIdx, 1), ...
                   'whiteningStrength', strengthLevels(lvlIdx, 2));
        t = tic;
        v33Data(sIdx).outputs{lvlIdx} = beautifyImage(img, p, fb, ctx);
        v33Data(sIdx).elapsed(lvlIdx) = toc(t);
    end
    
    % 分阶段隔离运行 (sSmooth=100, sWhite=15)
    v33Data(sIdx).stages = executeIsolatedStages(img, fb, 100, 15, ctx);
end

% =========================================================================
% Pass 2: 在 v3.5 候选环境下计算全部输出
% =========================================================================
fprintf('\n>>> [Pass 2/3] 正在切换至 v3.5 候选环境运行全部样本...\n');
try rmpath(v33Root); catch; end
addpath(v35Root, '-begin');
clear functions;

v35Data = struct();
for sIdx = 1:numel(samples)
    sName = samples(sIdx).name;
    img = samples(sIdx).img;
    fb = samples(sIdx).faceBox;
    pStruct = samples(sIdx).parsingStruct;
    bp = samples(sIdx).bodyParsing;
    
    fprintf('  [v3.5] 处理样本: %s ...\n', sName);
    ctx = prepareBeautyContext(img, fb, pStruct, bp);
    
    % 多档位运行
    numLvl = size(strengthLevels, 1);
    v35Data(sIdx).outputs = cell(numLvl, 1);
    v35Data(sIdx).elapsed = zeros(numLvl, 1);
    for lvlIdx = 1:numLvl
        p = struct('smoothingStrength', strengthLevels(lvlIdx, 1), ...
                   'whiteningStrength', strengthLevels(lvlIdx, 2));
        t = tic;
        v35Data(sIdx).outputs{lvlIdx} = beautifyImage(img, p, fb, ctx);
        v35Data(sIdx).elapsed(lvlIdx) = toc(t);
    end
    
    % 分阶段隔离运行 (sSmooth=100, sWhite=15)
    v35Data(sIdx).stages = executeIsolatedStages(img, fb, 100, 15, ctx);
end

% =========================================================================
% Pass 3: 在 v3.6 当前工作区环境下计算全部输出
% =========================================================================
fprintf('\n>>> [Pass 3/3] 正在切换至 v3.6 当前环境运行全部样本...\n');
try rmpath(v35Root); catch; end
addpath(fullfile(projectRoot, 'src'), '-begin');
clear functions;

v36Data = struct();
for sIdx = 1:numel(samples)
    sName = samples(sIdx).name;
    img = samples(sIdx).img;
    fb = samples(sIdx).faceBox;
    pStruct = samples(sIdx).parsingStruct;
    bp = samples(sIdx).bodyParsing;

    fprintf('  [v3.6] 处理样本: %s ...\n', sName);
    ctx = prepareBeautyContext(img, fb, pStruct, bp);

    numLvl = size(strengthLevels, 1);
    v36Data(sIdx).outputs = cell(numLvl, 1);
    v36Data(sIdx).elapsed = zeros(numLvl, 1);
    for lvlIdx = 1:numLvl
        p = struct('smoothingStrength', strengthLevels(lvlIdx, 1), ...
                   'whiteningStrength', strengthLevels(lvlIdx, 2));
        t = tic;
        [v36Data(sIdx).outputs{lvlIdx}, levelDiagnostics] = ...
            beautifyImage(img, p, fb, ctx);
        v36Data(sIdx).elapsed(lvlIdx) = toc(t);
        if strengthLevels(lvlIdx, 1) == 100
            v36Data(sIdx).finalDiagnostics = levelDiagnostics;
        end
    end

    v36Data(sIdx).semanticContext = ctx;
    v36Data(sIdx).stages = executeIsolatedStages(img, fb, 100, 15, ctx);
end

% =========================================================================
% Pass 4: 严格核验、客观指标统计与可视化验收产物生成
% =========================================================================
fprintf('\n>>> [Pass 4/4] 正在执行逐位核验、指标度量与产物输出...\n');
summary = struct();

for sIdx = 1:numel(samples)
    sConfig = samples(sIdx);
    sName = sConfig.name;
    img = sConfig.img;
    faceBox = sConfig.faceBox;
    rois = sConfig.rois;
    imSize = size(img, 1:2);
    
    fprintf('>>> 正在生成产物: %s (%dx%d) <<<\n', sName, imSize(1), imSize(2));
    
    % 原图落盘
    origFile = fullfile(targetDir, sprintf('%s_00_original.png', sName));
    imwrite(img, origFile);

    semanticRecord = writeSemanticDiagnostics(targetDir, sConfig, ...
        v36Data(sIdx).semanticContext, v36Data(sIdx).finalDiagnostics);
    semanticCsvRows{end+1} = sprintf( ...
        '%s,%s,%s,%d,%.4f,%.4f,%.4f,%d,%d', ...
        sName, sConfig.semanticSource, sConfig.bodySemanticSource, ...
        sConfig.fallbackUsed, semanticRecord.cheekSkinCoverage, ...
        semanticRecord.cheekFaceSkinCoverage, ...
        semanticRecord.cheekStrengthCoverage, semanticRecord.bodySkinPixels, ...
        semanticRecord.faceSkinPixels);
    
    cheekMask = roiToMask(rois.cheek, imSize);
    eyeMask = roiToMask(rois.eye, imSize);
    
    % 源图频带与高频度量
    [srcFreq, ~] = beauty.decomposeSkinFrequency(img, faceBox);
    srcCheekFine = std(srcFreq.fine(cheekMask));
    sigmaHigh = max(1.0, 0.008 * min(faceBox(3:4)));
    grayImg = im2double(rgb2gray(img));
    srcHighFreq = grayImg - imgaussfilt(grayImg, sigmaHigh, 'Padding', 'replicate');
    srcEyeHigh = std(srcHighFreq(eyeMask));
    
    mSrc = evaluateImage(img, img, 0);
    
    % 档位比对
    for lvlIdx = 1:size(strengthLevels, 1)
        sSmooth = strengthLevels(lvlIdx, 1);
        sWhite = strengthLevels(lvlIdx, 2);
        
        outV33 = v33Data(sIdx).outputs{lvlIdx};
        outV35 = v35Data(sIdx).outputs{lvlIdx};
        outV36 = v36Data(sIdx).outputs{lvlIdx};
        elV33 = v33Data(sIdx).elapsed(lvlIdx);
        elV35 = v35Data(sIdx).elapsed(lvlIdx);
        elV36 = v36Data(sIdx).elapsed(lvlIdx);
        
        maxDiff35 = max(abs(double(outV35(:)) - double(outV33(:))));
        maxDiff36 = max(abs(double(outV36(:)) - double(outV35(:))));
        maxDiff36From33 = max(abs(double(outV36(:)) - double(outV33(:))));
        
        % 任务03只对 v3.6 相对 v3.5 的 0--75 档逐位保持负责；
        % v3.5 相对 HEAD:v3.3 的历史差异保留为验收记录，不在此掩盖。
        if sSmooth <= 75
            if maxDiff35 ~= 0
                fprintf('  [记录] [%s s=%d] v3.5 相对 v3.3 的历史差异 maxDiff=%g。\n', ...
                    sName, sSmooth, maxDiff35);
            end
            assert(maxDiff36 == 0, ...
                '[%s s=%d] v3.6 相对 v3.5 存在非零差异 (maxDiff=%g)。', ...
                sName, sSmooth, maxDiff36);
        end
        
        mV33 = evaluateImage(img, outV33, elV33);
        mV35 = evaluateImage(img, outV35, elV35);
        mV36 = evaluateImage(img, outV36, elV36);
        
        [fV33, ~] = beauty.decomposeSkinFrequency(outV33, faceBox);
        [fV35, ~] = beauty.decomposeSkinFrequency(outV35, faceBox);
        [fV36, ~] = beauty.decomposeSkinFrequency(outV36, faceBox);
        cheekFineV33 = std(fV33.fine(cheekMask));
        cheekFineV35 = std(fV35.fine(cheekMask));
        cheekFineV36 = std(fV36.fine(cheekMask));
        
        reductV33 = max(0, (srcCheekFine - cheekFineV33) / max(srcCheekFine, eps)) * 100;
        reductV35 = max(0, (srcCheekFine - cheekFineV35) / max(srcCheekFine, eps)) * 100;
        reductV36 = max(0, (srcCheekFine - cheekFineV36) / max(srcCheekFine, eps)) * 100;
        boostPct35 = reductV35 - reductV33;
        boostPct36 = reductV36 - reductV35;
        
        grayV33 = im2double(rgb2gray(outV33));
        grayV35 = im2double(rgb2gray(outV35));
        grayV36 = im2double(rgb2gray(outV36));
        hfV33 = grayV33 - imgaussfilt(grayV33, sigmaHigh, 'Padding', 'replicate');
        hfV35 = grayV35 - imgaussfilt(grayV35, sigmaHigh, 'Padding', 'replicate');
        hfV36 = grayV36 - imgaussfilt(grayV36, sigmaHigh, 'Padding', 'replicate');
        eyeRetV33 = (std(hfV33(eyeMask)) / max(srcEyeHigh, eps)) * 100;
        eyeRetV35 = (std(hfV35(eyeMask)) / max(srcEyeHigh, eps)) * 100;
        eyeRetV36 = (std(hfV36(eyeMask)) / max(srcEyeHigh, eps)) * 100;
        
        metricsCsvRows{end+1} = sprintf( ...
            '%s,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f', ...
            sName, sSmooth, sWhite, ...
            mSrc.entropy, mV33.entropy, mV35.entropy, mV36.entropy, ...
            mSrc.standardDeviation, mV33.standardDeviation, ...
            mV35.standardDeviation, mV36.standardDeviation, ...
            mSrc.averageGradient, mV33.averageGradient, ...
            mV35.averageGradient, mV36.averageGradient, ...
            srcCheekFine, cheekFineV33, cheekFineV35, cheekFineV36, ...
            reductV33, reductV35, reductV36, boostPct35, boostPct36, ...
            eyeRetV33, eyeRetV35, eyeRetV36, ...
            maxDiff35, maxDiff36, maxDiff36From33, elV33, elV35, elV36);
    end
    
    % 保存 s=100 和 s=85 全图与带可见列名的对照图；80 额外加入 80r 精修目标。
    idx100 = find(strengthLevels(:, 1) == 100, 1);
    idx85 = find(strengthLevels(:, 1) == 85, 1);
    out100_V33 = v33Data(sIdx).outputs{idx100};
    out100_V35 = v35Data(sIdx).outputs{idx100};
    out100_V36 = v36Data(sIdx).outputs{idx100};
    out85_V33 = v33Data(sIdx).outputs{idx85};
    out85_V35 = v35Data(sIdx).outputs{idx85};
    out85_V36 = v36Data(sIdx).outputs{idx85};
    
    imwrite(out100_V33, fullfile(targetDir, sprintf('%s_v33_baseline_s100.png', sName)));
    imwrite(out100_V35, fullfile(targetDir, sprintf('%s_v35_candidate_s100.png', sName)));
    imwrite(out100_V36, fullfile(targetDir, sprintf('%s_v36_candidate_s100.png', sName)));

    comparisonImages = {img, out100_V33, out100_V35, out100_V36};
    comparisonLabels = {'原图', 'v3.3 基线', 'v3.5 候选（100档）', ...
        'v3.6 候选（100档）'};
    if ~isempty(sConfig.targetImage)
        imwrite(sConfig.targetImage, fullfile(targetDir, ...
            sprintf('%s_refined_target_80r.png', sName)));
        comparisonImages{end + 1} = sConfig.targetImage;
        comparisonLabels{end + 1} = '80r 精修目标';
    end
    writeLabeledComparison(comparisonImages, comparisonLabels, ...
        sprintf('%s 全图 100 档对照', sName), ...
        fullfile(targetDir, sprintf('%s_comparison_s100.png', sName)));

    writeLabeledComparison({img, out85_V33, out85_V35, out85_V36}, ...
        {'原图', 'v3.3 基线', 'v3.5 候选（85档）', 'v3.6 候选（85档）'}, ...
        sprintf('%s 全图 85 档对照', sName), ...
        fullfile(targetDir, sprintf('%s_comparison_s85.png', sName)));

    % ROI 三栏/四栏特写，80 与 80r 同步进入。
    roiFields = fieldnames(rois);
    for rfIdx = 1:numel(roiFields)
        rField = roiFields{rfIdx};
        roiRect = rois.(rField);
        cropSrc = cropRoi(img, roiRect);
        cropV33 = cropRoi(out100_V33, roiRect);
        cropV35 = cropRoi(out100_V35, roiRect);
        cropV36 = cropRoi(out100_V36, roiRect);
        roiImages = {cropSrc, cropV33, cropV35, cropV36};
        roiLabels = {'原图', 'v3.3 基线', 'v3.5 候选（100档）', ...
            'v3.6 候选（100档）'};
        if ~isempty(sConfig.targetImage)
            roiImages{end + 1} = cropRoi(sConfig.targetImage, roiRect);
            roiLabels{end + 1} = '80r 精修目标';
        end
        writeLabeledComparison(roiImages, roiLabels, ...
            sprintf('%s ROI：%s', sName, rField), ...
            fullfile(targetDir, sprintf('%s_roi_%s_s100.png', sName, rField)));
    end
    
    % 强度多档位对比，使用列名避免条带含义不可辨认。
    levelImages = [{img}; v36Data(sIdx).outputs(2:7)];
    levelLabels = {'原图', '30档', '50档', '60档', '75档', '85档', '100档'};
    writeLabeledComparison(levelImages, levelLabels, ...
        sprintf('%s 强度梯次', sName), ...
        fullfile(targetDir, sprintf('%s_strength_progression_v36.png', sName)));
    
    % 三组版本差异热力图（均为 s=100）。
    diff35 = max(abs(double(out100_V35) - double(out100_V33)), [], 3);
    diff36 = max(abs(double(out100_V36) - double(out100_V35)), [], 3);
    diff36From33 = max(abs(double(out100_V36) - double(out100_V33)), [], 3);
    imwrite(diffToHeatmap(diff35, 25), ...
        fullfile(targetDir, sprintf('%s_heatmap_v35_vs_v33_diff_s100.png', sName)));
    imwrite(diffToHeatmap(diff36, 25), ...
        fullfile(targetDir, sprintf('%s_heatmap_v36_vs_v35_diff_s100.png', sName)));
    imwrite(diffToHeatmap(diff36From33, 25), ...
        fullfile(targetDir, sprintf('%s_heatmap_v36_vs_v33_diff_s100.png', sName)));
    
    % Smoothing/Dense/Compact Repair/Base/Tone/Whitening 阶段演化与归因。
    stages33 = v33Data(sIdx).stages;
    stages35 = v35Data(sIdx).stages;
    stages36 = v36Data(sIdx).stages;

    stageLabels = {'Smoothing', 'Dense', 'Compact Repair', 'Base 均匀化', ...
        'Tone', 'Whitening'};
    writeLabeledComparison([{img}, stages36], stageLabelsWithOriginal(stageLabels), ...
        sprintf('%s 阶段演化（v3.6，100档）', sName), ...
        fullfile(targetDir, sprintf('%s_stage_progression_v36.png', sName)));

    stageNames = {'Stage1_Smoothing', 'Stage2_Dense', ...
        'Stage3_CompactRepair', 'Stage4_BaseLum', 'Stage5_Tone', ...
        'Stage6_Whitening'};
    for sK = 1:numel(stageNames)
        stgN = stageNames{sK};
        cur33 = stages33{sK};
        cur35 = stages35{sK};
        cur36 = stages36{sK};
        if sK == 1
            prv33 = img; prv35 = img; prv36 = img;
        else
            prv33 = stages33{sK-1}; prv35 = stages35{sK-1};
            prv36 = stages36{sK-1};
        end

        % 每个阶段单独输出 v3.6 相对 v3.5 的差异热力图，便于定位
        % v3.6 的新增影响是否只落在 Dense/Compact Repair/Tone。
        stageDiff36 = max(abs(double(cur36) - double(cur35)), [], 3);
        imwrite(diffToHeatmap(stageDiff36, 20), fullfile(targetDir, ...
            sprintf('%s_heatmap_%s_v36_vs_v35.png', sName, stgN)));
        
        for rK = 1:numel(roiFields)
            rf = roiFields{rK};
            rMask = roiToMask(rois.(rf), imSize);
            
            d33 = max(abs(double(cur33) - double(prv33)), [], 3);
            d35 = max(abs(double(cur35) - double(prv35)), [], 3);
            d36 = max(abs(double(cur36) - double(prv36)), [], 3);
            mDiff33 = mean(d33(rMask));
            mDiff35 = mean(d35(rMask));
            mDiff36 = mean(d36(rMask));
            mxDiff33 = max(d33(rMask));
            mxDiff35 = max(d35(rMask));
            mxDiff36 = max(d36(rMask));
            deltaDiff35 = abs(mDiff35 - mDiff33);
            deltaDiff36 = abs(mDiff36 - mDiff35);
            
            stageCsvRows{end+1} = sprintf( ...
                '%s,%s,%s,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.4f,%.4f', ...
                sName, stgN, rf, mDiff33, mDiff35, mDiff36, ...
                mxDiff33, mxDiff35, mxDiff36, deltaDiff35, deltaDiff36);
        end
    end
end

% 保存指标 CSV
metricsCsvPath = fullfile(targetDir, 'visual_acceptance_metrics_summary.csv');
fid = fopen(metricsCsvPath, 'w', 'n', 'UTF-8');
for k = 1:numel(metricsCsvRows)
    fprintf(fid, '%s\n', metricsCsvRows{k});
end
fclose(fid);
fprintf('\n>>> 指标汇总 CSV 已保存: %s\n', metricsCsvPath);

% 保存阶段归因 CSV
stageCsvPath = fullfile(targetDir, 'visual_acceptance_stage_attribution.csv');
fid = fopen(stageCsvPath, 'w', 'n', 'UTF-8');
for k = 1:numel(stageCsvRows)
    fprintf(fid, '%s\n', stageCsvRows{k});
end
fclose(fid);
fprintf('>>> 阶段归因 CSV 已保存: %s\n', stageCsvPath);

semanticCsvPath = fullfile(targetDir, 'semantic_source_and_coverage.csv');
fid = fopen(semanticCsvPath, 'w', 'n', 'UTF-8');
if fid < 0
    error('generateVisualAcceptanceArtifacts:WriteFailure', ...
        '无法写入语义来源汇总：%s', semanticCsvPath);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
for k = 1:numel(semanticCsvRows)
    fprintf(fid, '%s\n', semanticCsvRows{k});
end
clear cleanup;
fprintf('>>> 语义来源与覆盖率 CSV 已保存: %s\n', semanticCsvPath);

fprintf('\n=================================================================\n');
fprintf('任务 03 真实图视觉验收产物生成完毕！\n');
fprintf('所有图片与 CSV 已存放至: %s\n', targetDir);
fprintf('=================================================================\n');

summary.targetDir = targetDir;
summary.metricsCsv = metricsCsvPath;
summary.stageCsv = stageCsvPath;
summary.semanticCsv = semanticCsvPath;
summary.v33Root = v33Root;
summary.v35Root = v35Root;
end

% =========================================================================
% 辅助函数：执行隔离阶段
% =========================================================================
function stages = executeIsolatedStages(img, faceBox, sSmooth, sWhite, ctx)
imSize = size(img, 1:2);
[beautyMasks, ~] = masks.buildBeautyMasks(img, ctx, faceBox);
[freq, ~] = beauty.decomposeSkinFrequency(img, faceBox);
[blemishMap, blemishDiagnostics] = buildRuntimeBlemishEvidence( ...
    img, freq, beautyMasks, ctx);
stageProt = buildStageProtectionForAcceptance(beautyMasks, ctx);
compContract = struct('hard', stageProt.hard);
zeroWhitening = struct('delta', zeros(imSize), 'supportMap', zeros(imSize));

% Stage 1: Smoothing only
[smFreq, ~] = beauty.smoothSkinTexture(freq, beautyMasks, sSmooth, blemishMap, stageProt);
stg1 = beauty.composeBeautyResult(img, freq, smFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 2: +Dense Repair。v3.3 没有 dense 证据时保持为 Stage 1，
% 这样版本间 CSV 的阶段语义仍然对齐。
repContract = beauty.repairStageContract(stageProt, blemishMap);
hasDense = isstruct(blemishDiagnostics) && ...
    isfield(blemishDiagnostics, 'denseBlemishField');
if hasDense
    denseInput = struct('blemishMap', zeros(imSize), ...
        'denseBlemishField', blemishDiagnostics.denseBlemishField);
    denseContract = beauty.repairStageContract(stageProt, zeros(imSize));
    [denseFreq, ~] = beauty.repairSkinBlemishes(smFreq, beautyMasks, ...
        denseInput, sSmooth, denseContract);
else
    denseFreq = smFreq;
end
stg2 = beauty.composeBeautyResult(img, freq, denseFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 3: +Compact Repair。dense 分支已在上一阶段执行，故这里仅传
% 原 compact blemish map，避免在验收图中重复应用 dense 重建。
if hasDense
    [repFreq, ~] = beauty.repairSkinBlemishes(denseFreq, beautyMasks, ...
        blemishMap, sSmooth, repContract);
else
    [repFreq, ~] = beauty.repairSkinBlemishes(smFreq, beautyMasks, ...
        blemishMap, sSmooth, repContract);
end
stg3 = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    struct('whitening', zeroWhitening), compContract);

% Stage 4: +Base Lum
baseContract = beauty.baseLuminanceStageContract(stageProt);
[baseLum, ~] = runBaseStage(freq, beautyMasks, sSmooth, baseContract, ...
    hasDense, blemishDiagnostics);
stg4 = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    struct('baseLuminance', baseLum, 'whitening', zeroWhitening), compContract);

% Stage 5: +Tone
toneContract = beauty.toneStageContract(stageProt);
toneInput = blemishMap;
if hasDense
    toneInput = buildRuntimeBlemishInput(blemishDiagnostics, blemishMap);
else
    toneInput = blemishMap;
end
[skinTone, ~] = beauty.normalizeSkinTone(img, freq, beautyMasks, ...
    toneInput, sSmooth, toneContract);
stg5 = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, 0, ...
    struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', zeroWhitening), compContract);

% Stage 6: +Whitening (Full pipeline)
whiteContract = beauty.whiteningStageContract(stageProt);
[whitening, ~] = beauty.applySkinWhitening(img, freq, beautyMasks, sWhite, whiteContract);
stg6 = beauty.composeBeautyResult(img, freq, repFreq, beautyMasks, sWhite, ...
    struct('baseLuminance', baseLum, 'skinTone', skinTone, 'whitening', whitening), compContract);

stages = {stg1, stg2, stg3, stg4, stg5, stg6};
end

function [blemishMap, diagnostics] = buildRuntimeBlemishEvidence( ...
        img, freq, beautyMasks, ctx)
%BUILDRUNTIMEBLEMISHEVIDENCE 兼容 v3.3 与 v3.5/v3.6 的 evidence 入口。
stageProtection = buildStageProtectionForAcceptance(beautyMasks, ctx);
if nargin('beauty.buildBlemishMap') >= 4
    [blemishMap, diagnostics] = beauty.buildBlemishMap( ...
        img, freq, beautyMasks, stageProtection);
else
    [blemishMap, diagnostics] = beauty.buildBlemishMap( ...
        img, freq, beautyMasks);
end
end

function stageProtection = buildStageProtectionForAcceptance(beautyMasks, ctx)
if isfield(ctx, 'evidence') && isstruct(ctx.evidence) && ...
        isscalar(ctx.evidence)
    stageProtection = masks.buildStageProtectionMasks(beautyMasks, ...
        ctx.evidence);
else
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
end
end

function [baseResult, diagnostics] = runBaseStage( ...
        freq, beautyMasks, strength, contract, hasDense, runtimeEvidence)
if hasDense && nargin('beauty.evenSkinLuminance') >= 5
    [baseResult, diagnostics] = beauty.evenSkinLuminance( ...
        freq, beautyMasks, strength, contract, runtimeEvidence);
else
    [baseResult, diagnostics] = beauty.evenSkinLuminance( ...
        freq, beautyMasks, strength, contract);
end
end

function value = buildRuntimeBlemishInput(diagnostics, blemishMap)
value = struct('blemishMap', blemishMap, ...
    'denseBlemishField', diagnostics.denseBlemishField);
end

function labels = stageLabelsWithOriginal(stageLabels)
labels = [{'原图'}, stageLabels];
end

function record = writeSemanticDiagnostics(targetDir, sample, context, diagnostics)
%WRITESEMANTICDIAGNOSTICS 输出真实语义 Mask 与覆盖率自检结果。
if ~isfield(sample, 'semanticSource') || ...
        ~strcmp(sample.semanticSource, '当前生产 BiSeNet') || ...
        ~isfield(sample, 'bodySemanticSource') || ...
        ~strcmp(sample.bodySemanticSource, '当前生产 SCHP') || ...
        ~isfield(sample, 'fallbackUsed') || sample.fallbackUsed
    error('generateVisualAcceptanceArtifacts:FallbackSemanticEvidence', ...
        '样本 %s 的语义来源不是当前生产 BiSeNet+SCHP，禁止继续。', ...
        sample.name);
end
if ~isstruct(context) || ~isscalar(context) || ...
        ~isfield(context, 'skinMask') || ...
        ~isfield(context, 'faceSkinMask') || ...
        ~isfield(context, 'bodySkinMask')
    error('generateVisualAcceptanceArtifacts:InvalidSemanticEvidence', ...
        '样本 %s 的 Context 缺少最终 skin/face/body 语义 Mask。', ...
        sample.name);
end
if ~isstruct(diagnostics) || ~isfield(diagnostics, 'beautyMasks') || ...
        ~isfield(diagnostics, 'blemish') || ...
        ~isfield(diagnostics.blemish, 'denseBlemishField') || ...
        ~isfield(diagnostics, 'compose') || ...
        ~isfield(diagnostics.compose, 'alphaMap')
    error('generateVisualAcceptanceArtifacts:InvalidSemanticDiagnostics', ...
        '样本 %s 的生产诊断缺少 denseBlemishField 或 alphaMap。', ...
        sample.name);
end

imageSize = size(context.skinMask);
skinMask = validateDiagnosticMap(context.skinMask, imageSize, 'skinMask');
faceSkinMask = validateDiagnosticMap(context.faceSkinMask, imageSize, ...
    'faceSkinMask');
bodySkinMask = validateDiagnosticMap(context.bodySkinMask, imageSize, ...
    'bodySkinMask');
beautyMasks = diagnostics.beautyMasks;
strengthMap = validateDiagnosticMap(beautyMasks.strengthMap, imageSize, ...
    'strengthMap');
hardProtection = validateDiagnosticMap(beautyMasks.hardProtectionMask, ...
    imageSize, 'hardProtection');
denseField = validateDiagnosticMap( ...
    diagnostics.blemish.denseBlemishField, imageSize, ...
    'denseBlemishField');
alphaMap = validateDiagnosticMap(diagnostics.compose.alphaMap, imageSize, ...
    'alphaMap');

cheekMask = roiToMask(sample.rois.cheek, imageSize);
roiPixels = nnz(cheekMask);
cheekSkinCoverage = nnz(cheekMask & skinMask >= .35) / max(roiPixels, 1);
cheekFaceSkinCoverage = nnz(cheekMask & faceSkinMask >= .35) / ...
    max(roiPixels, 1);
cheekStrengthCoverage = nnz(cheekMask & strengthMap > .05) / ...
    max(roiPixels, 1);
if cheekSkinCoverage < .25 || cheekFaceSkinCoverage < .25 || ...
        cheekStrengthCoverage < .25
    error('generateVisualAcceptanceArtifacts:InsufficientCheekCoverage', ...
        ['样本 %s 的脸颊 ROI 真实语义覆盖不足：skin=%.4f, ' ...
        'faceSkin=%.4f, strength=%.4f。'], sample.name, ...
        cheekSkinCoverage, cheekFaceSkinCoverage, cheekStrengthCoverage);
end

maps = {skinMask, faceSkinMask, bodySkinMask, strengthMap, ...
    hardProtection, denseField, alphaMap};
mapNames = {'skinMask', 'faceSkinMask', 'bodySkinMask', 'strengthMap', ...
    'hardProtection', 'denseBlemishField', 'alphaMap'};
mapLabels = {'skinMask（真实）', 'faceSkinMask（真实）', ...
    'bodySkinMask（真实 SCHP）', 'strengthMap', ...
    'hardProtection', 'denseBlemishField', '最终 alphaMap'};
mapImages = cell(size(maps));
record = struct( ...
    'cheekSkinCoverage', cheekSkinCoverage, ...
    'cheekFaceSkinCoverage', cheekFaceSkinCoverage, ...
    'cheekStrengthCoverage', cheekStrengthCoverage, ...
    'bodySkinPixels', nnz(bodySkinMask > .35), ...
    'faceSkinPixels', nnz(faceSkinMask > .35));
for index = 1:numel(maps)
    mapImages{index} = diagnosticMapImage(maps{index});
    mapPath = fullfile(targetDir, sprintf('%s_semantic_%s.png', ...
        sample.name, mapNames{index}));
    imwrite(mapImages{index}, mapPath);
    fprintf('>>> 语义 Mask 产物已保存: %s\n', mapPath);
end
montagePath = fullfile(targetDir, sprintf('%s_semantic_masks.png', ...
    sample.name));
writeLabeledComparison(mapImages, mapLabels, ...
    sprintf('%s 真实语义 Mask 诊断', sample.name), montagePath);
fprintf('>>> 语义 Mask 拼图已保存: %s\n', montagePath);

overlay = semanticOverlay(sample.img, skinMask, faceSkinMask, ...
    bodySkinMask, sample.faceBox);
overlayPath = fullfile(targetDir, sprintf('%s_semantic_overlay.png', ...
    sample.name));
imwrite(overlay, overlayPath);
fprintf('>>> 语义覆盖叠加图已保存: %s\n', overlayPath);

sourcePath = fullfile(targetDir, sprintf('%s_semantic_source.txt', ...
    sample.name));
writeUtf8File(sourcePath, sprintf([ ...
    '语义来源：%s\n', ...
    '身体语义来源：%s\n', ...
    'fallbackUsed：%d\n', ...
    '脸颊 skinMask 覆盖率：%.6f\n', ...
    '脸颊 faceSkinMask 覆盖率：%.6f\n', ...
    '脸颊 strengthMap 覆盖率：%.6f\n', ...
    'bodySkinMask 有效像素：%d\n', ...
    'faceSkinMask 有效像素：%d\n'], ...
    sample.semanticSource, sample.bodySemanticSource, ...
    sample.fallbackUsed, cheekSkinCoverage, cheekFaceSkinCoverage, ...
    cheekStrengthCoverage, record.bodySkinPixels, record.faceSkinPixels));
fprintf('>>> 语义来源记录已保存: %s\n', sourcePath);
end

function value = validateDiagnosticMap(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('generateVisualAcceptanceArtifacts:InvalidSemanticDiagnostics', ...
        '诊断字段 %s 的尺寸或值域无效。', name);
end
value = double(value);
end

function image = diagnosticMapImage(value)
image = uint8(round(min(max(double(value), 0), 1) * 255));
end

function overlay = semanticOverlay(inputImage, skinMask, faceSkinMask, ...
        bodySkinMask, faceBox)
base = im2double(inputImage);
overlayDouble = base;
overlayDouble(:, :, 1) = max(overlayDouble(:, :, 1), .72 * bodySkinMask);
overlayDouble(:, :, 2) = max(overlayDouble(:, :, 2), .72 * skinMask);
overlayDouble(:, :, 3) = max(overlayDouble(:, :, 3), .72 * faceSkinMask);
row1 = max(1, round(faceBox(2)));
row2 = min(size(base, 1), round(faceBox(2) + faceBox(4) - 1));
col1 = max(1, round(faceBox(1)));
col2 = min(size(base, 2), round(faceBox(1) + faceBox(3) - 1));
overlayDouble([row1, row2], col1:col2, :) = 1;
overlayDouble(row1:row2, [col1, col2], :) = 1;
overlay = uint8(round(min(max(overlayDouble, 0), 1) * 255));
end

function ensureV33Source(projectRoot, v33Root)
%ENSUREV33SOURCE 从 HEAD:src 生成可复现的 v3.3 临时基线。
requiredFile = fullfile(v33Root, 'beautyPipelineContract.m');
if isfile(requiredFile)
    return;
end

if ~isfolder(v33Root)
    mkdir(v33Root);
end
archivePath = fullfile(tempdir, 'image_beauty_v33_src.zip');
extractRoot = fullfile(tempdir, 'image_beauty_v33_extract');
if ~isfolder(extractRoot)
    mkdir(extractRoot);
end
command = sprintf('git -C "%s" archive --format=zip --output="%s" HEAD src', ...
    projectRoot, archivePath);
[status, commandOutput] = system(command);
if status ~= 0
    error('generateVisualAcceptanceArtifacts:MissingV33Backup', ...
        '无法从 HEAD 生成 v3.3 源码副本：%s', commandOutput);
end
unzip(archivePath, extractRoot);
sourceRoot = fullfile(extractRoot, 'src');
if ~isfolder(sourceRoot)
    error('generateVisualAcceptanceArtifacts:MissingV33Backup', ...
        'HEAD 归档中没有 src 目录：%s', sourceRoot);
end
copyfile(sourceRoot, v33Root, 'f');
if ~isfile(requiredFile)
    error('generateVisualAcceptanceArtifacts:MissingV33Backup', ...
        'v3.3 临时源码副本生成不完整：%s', v33Root);
end
end

function prepareV35Source(projectRoot, v35Root)
%PREPAREV35SOURCE 从当前工作区派生任务02的 v3.5 候选。
sourceRoot = fullfile(projectRoot, 'src');
if ~isfolder(v35Root)
    mkdir(v35Root);
end
copyfile(sourceRoot, v35Root, 'f');

tonePath = fullfile(v35Root, '+beauty', 'normalizeSkinTone.m');
toneText = fileread(tonePath);
toneText = strrep(toneText, sprintf('\r\n'), sprintf('\n'));
newlineChar = sprintf('\n');
startMarker = '% v3.6：dense 重建之后做轻量 Tone 收尾。';
if ~contains(toneText, startMarker)
    startMarker = '% v3.6：dense 重建之后只做轻量 Tone 收尾。';
end
candidateMarker = 'candidateDeltaCb = candidateCb - localCb;';
startIndex = strfind(toneText, startMarker);
candidateIndex = strfind(toneText, candidateMarker);
if isempty(startIndex) || isempty(candidateIndex) || ...
        candidateIndex(1) <= startIndex(1)
    error('generateVisualAcceptanceArtifacts:InvalidV35Source', ...
        '无法从当前 Tone 实现派生 v3.5 快照。');
end
v35Diagnostics = [ ...
    'redResidualEvidence = zeros(imageSize);\n' ...
    'brownResidualEvidence = zeros(imageSize);\n' ...
    'toneResidualEvidence = zeros(imageSize);\n' ...
    'toneResidualGate = zeros(imageSize);\n' ...
    'darkStructureEvidence = zeros(imageSize);\n' ...
    'darkStructureGate = ones(imageSize);\n' ...
    'edgeHaloGate = ones(imageSize);\n' ...
    'toneChromaDeltaLimit = Inf;\n\n'];
v35Diagnostics = strrep(v35Diagnostics, '\n', newlineChar);
toneText = [toneText(1:startIndex(1) - 1), v35Diagnostics, ...
    toneText(candidateIndex(1):end)];

oldLocalBlend = [ ...
    'if highEndToneGate > eps\n' ...
    '    denseToneBlendMap = denseToneEvidence .* double(denseToneWeight > eps);\n' ...
    '    localBlend = max(localChromaEvidence, denseToneBlendMap);\n' ...
    '    localBlend = max(localBlend, .50 * brownResidualEvidence);\n' ...
    'elseif uniformToneCurve > eps\n' ...
    '    localBlend = max(localChromaEvidence, double( ...\n' ...
    '        uniformToneSupport > eps));\n' ...
    'else\n' ...
    '    localBlend = localChromaEvidence;\n' ...
    'end\n' ...
    'if highEndToneGate <= eps\n' ...
    '    denseToneBlendMap = denseToneEvidence .* double(denseToneWeight > eps);\n' ...
    '    localBlend = max(localBlend, denseToneBlendMap);\n' ...
    'end\n'];
newLocalBlend = [ ...
    'if uniformToneCurve > eps\n' ...
    '    localBlend = max(localChromaEvidence, double( ...\n' ...
    '        uniformToneSupport > eps));\n' ...
    'else\n' ...
    '    localBlend = localChromaEvidence;\n' ...
    'end\n' ...
    'denseToneBlend = denseToneEvidence .* double(denseToneWeight > eps);\n' ...
    'localBlend = max(localBlend, denseToneBlend);\n'];
oldLocalBlend = strrep(oldLocalBlend, '\n', newlineChar);
newLocalBlend = strrep(newLocalBlend, '\n', newlineChar);
if ~contains(toneText, oldLocalBlend)
    error('generateVisualAcceptanceArtifacts:InvalidV35Source', ...
        'v3.5 Tone 快照缺少 localBlend 迁移片段。');
end
toneText = strrep(toneText, oldLocalBlend, newLocalBlend);

oldDeltaLimit = [ ...
    'rawDeltaCb = deltaCb;\n' ...
    'rawDeltaCr = deltaCr;\n' ...
    'if highEndToneGate > eps\n' ...
    '    deltaCb = min(max(deltaCb, -toneChromaDeltaLimit), ...\n' ...
    '        toneChromaDeltaLimit);\n' ...
    '    deltaCr = min(max(deltaCr, -toneChromaDeltaLimit), ...\n' ...
    '        toneChromaDeltaLimit);\n' ...
    'end\n'];
oldDeltaLimit = strrep(oldDeltaLimit, '\n', newlineChar);
if ~contains(toneText, oldDeltaLimit)
    error('generateVisualAcceptanceArtifacts:InvalidV35Source', ...
        'v3.5 Tone 快照缺少 delta 限幅迁移片段。');
end
toneText = strrep(toneText, oldDeltaLimit, ...
    ['rawDeltaCb = deltaCb;', newlineChar, ...
    'rawDeltaCr = deltaCr;', newlineChar]);
writeUtf8File(tonePath, toneText);
contractPath = fullfile(v35Root, 'beautyPipelineContract.m');
contractText = fileread(contractPath);
contractText = strrep(contractText, 'v3.6', 'v3.5');
writeUtf8File(contractPath, contractText);
end

function writeUtf8File(path, text)
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid < 0
    error('generateVisualAcceptanceArtifacts:WriteFailure', ...
        '无法写入临时源码：%s', path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s', text);
end

% =========================================================================
% 图像拼合与辅助工具
% =========================================================================
function writeLabeledComparison(images, labels, heading, outputPath)
%WRITELABELEDCOMPARISON 用标题和列名输出可辨认的三栏/四栏对照图。
if numel(images) ~= numel(labels) || isempty(images)
    error('generateVisualAcceptanceArtifacts:InvalidComparison', ...
        '对照图的图像与列名数量必须一致且非空。');
end
figureWidth = max(900, 360 * numel(images));
fig = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, figureWidth, 520]);
layout = tiledlayout(fig, 1, numel(images), ...
    'TileSpacing', 'compact', 'Padding', 'compact');
for index = 1:numel(images)
    ax = nexttile(layout, index);
    imshow(images{index}, 'Parent', ax);
    title(ax, labels{index}, 'Interpreter', 'none', ...
        'FontWeight', 'bold', 'FontSize', 11);
    axis(ax, 'image');
    axis(ax, 'off');
end
if ~isempty(heading)
    title(layout, heading, 'Interpreter', 'none', 'FontWeight', 'bold');
end
exportgraphics(fig, outputPath, 'Resolution', 120);
close(fig);
end

function crop = cropRoi(img, roi)
rows = size(img, 1);
cols = size(img, 2);
x1 = max(1, round(roi(1)));
y1 = max(1, round(roi(2)));
x2 = min(cols, round(roi(1) + roi(3) - 1));
y2 = min(rows, round(roi(2) + roi(4) - 1));
crop = img(y1:y2, x1:x2, :);
end

function m = roiToMask(roi, imSize)
m = false(imSize(1:2));
x1 = max(1, round(roi(1))); y1 = max(1, round(roi(2)));
x2 = min(imSize(2), round(roi(1) + roi(3) - 1));
y2 = min(imSize(1), round(roi(2) + roi(4) - 1));
m(y1:y2, x1:x2) = true;
end

function heat = diffToHeatmap(diffMap, maxVal)
normVal = min(max(diffMap / maxVal, 0), 1);
% 简易喷射色图转换 (Jet-like: 0=Blue, 0.35=Cyan, 0.5=Green, 0.75=Yellow, 1=Red)
r = min(max(1.5 - abs(normVal * 4 - 3), 0), 1);
g = min(max(1.5 - abs(normVal * 4 - 2), 0), 1);
b = min(max(1.5 - abs(normVal * 4 - 1), 0), 1);
heat = uint8(round(cat(3, r, g, b) * 255));
end
