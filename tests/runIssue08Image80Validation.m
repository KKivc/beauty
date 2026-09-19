function summary = runIssue08Image80Validation()
%RUNISSUE08IMAGE80VALIDATION 验证 issue 08 对 80.jpg 既有回归无退化。
%   复用已验证的 80 v3.2 MAT，只移除派生 Mask 和 runtimeCache，
%   让候选生产链重新构建当前保护；输出写入系统临时目录。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'), '-begin');
outputFolder = fullfile(tempdir, 'image_beauty_issue08_validation_20260918');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
inputPath = 'E:\image_beauty\人脸\人脸\80.jpg';
baselinePath = 'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\80_v32_probe.mat';
loaded = load(baselinePath, 'context', 'diagnostics', 'output', 'faceBox');
inputImage = imread(inputPath);
faceBox = loaded.faceBox;
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);

baseDiagnostics = loaded.diagnostics;
frequency = baseDiagnostics.frequency;
frequency.sourceLuminance = rgb2ycbcr(im2double(inputImage));
frequency.sourceLuminance = frequency.sourceLuminance(:, :, 1);
frequency.imageSize = [size(inputImage, 1:2), 3];
frequency.faceBox = faceBox;
frequency.faceScale = min(faceBox(3:4));
frequency.reconstructedLuminance = double(frequency.base) + ...
    double(frequency.mid) + double(frequency.fine);
frequency.outputLuminance = frequency.reconstructedLuminance;
frequency.alphaMap = zeros(size(inputImage, 1:2));
processing = struct('baseLuminance', baseDiagnostics.baseLuminanceResult, ...
    'skinTone', baseDiagnostics.skinToneResult, ...
    'whitening', baseDiagnostics.whiteningResult);
[reconstructedBaseline, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, baseDiagnostics.repairResult, ...
    baseDiagnostics.beautyMasks, params.whiteningStrength, processing);
baselineReconstructionMaxRgbDifference = max(abs(double( ...
    reconstructedBaseline) - double(loaded.output)), [], 'all');
if baselineReconstructionMaxRgbDifference ~= 0
    error('runIssue08Image80Validation:BaselineMismatch', ...
        '保存 80 v3.2 基线重建不一致：%.17g。', ...
        baselineReconstructionMaxRgbDifference);
end

context = stripDerivedContext(loaded.context);
[candidateOutput, candidateDiagnostics] = beautifyImage( ...
    inputImage, params, faceBox, context);
[directOutput, ~] = beautifyImage(inputImage, params, faceBox, context);
recomputeMaxRgbDifference = max(abs(double(candidateOutput) - ...
    double(directOutput)), [], 'all');
if recomputeMaxRgbDifference ~= 0
    error('runIssue08Image80Validation:RecomputeMismatch', ...
        '两次无缓存 80 候选计算不一致：%.17g。', ...
        recomputeMaxRgbDifference);
end

roiDefinitions = struct( ...
    'nostril', [300 330 125 80], ...
    'noseBridge', [320 245 80 90], ...
    'noseWing', [295 320 140 90], ...
    'normalSkin', [200 330 100 100], ...
    'freckle', [200 180 100 100], ...
    'hair', [60 60 40 50], ...
    'background', [1 100 50 200]);
roiNames = fieldnames(roiDefinitions);
rows = repmat(emptyRow(), 0, 1);
for index = 1:numel(roiNames)
    name = roiNames{index};
    roi = makeRoiMask(roiDefinitions.(name), size(inputImage, 1:2));
    baselineDifference = max(abs(double(loaded.output) - ...
        double(inputImage)), [], 3);
    candidateDifference = max(abs(double(candidateOutput) - ...
        double(inputImage)), [], 3);
    candidateVsBaseline = max(abs(double(candidateOutput) - ...
        double(loaded.output)), [], 3);
    row = emptyRow();
    row.name = name;
    row.pixels = nnz(roi);
    row.baselineChangeMean = mean(baselineDifference(roi));
    row.candidateChangeMean = mean(candidateDifference(roi));
    row.baselineChangeMax = max(baselineDifference(roi));
    row.candidateChangeMax = max(candidateDifference(roi));
    row.candidateVsBaselineMean = mean(candidateVsBaseline(roi));
    row.candidateVsBaselineMax = max(candidateVsBaseline(roi));
    row.baselineRepairFineMean = mean(abs(baseDiagnostics.repair.fineCorrection(roi)));
    row.candidateRepairFineMean = mean(abs(candidateDiagnostics.repair.fineCorrection(roi)));
    row.baselineRepairMidMean = mean(abs(baseDiagnostics.repair.mediumCorrection(roi)));
    row.candidateRepairMidMean = mean(abs(candidateDiagnostics.repair.mediumCorrection(roi)));
    row.candidateTextureProtectionMean = mean( ...
        candidateDiagnostics.beautyMasks.textureProtectionMask(roi));
    row.candidateHardProtectionFraction = mean( ...
        candidateDiagnostics.beautyMasks.hardProtectionMask(roi) >= .999);
    rows(end + 1, 1) = row; %#ok<AGROW>
end
metrics = struct2table(rows);
summary = struct('baselineReconstructionMaxRgbDifference', ...
    baselineReconstructionMaxRgbDifference, ...
    'recomputeMaxRgbDifference', recomputeMaxRgbDifference, ...
    'metrics', metrics, 'outputFolder', outputFolder, ...
    'candidateOutputPath', fullfile(outputFolder, '80_issue08_candidate.png'));
imwrite(candidateOutput, summary.candidateOutputPath);
imwrite(loaded.output, fullfile(outputFolder, '80_v32_baseline.png'));
imwrite(inputImage, fullfile(outputFolder, '80_original.png'));
writetable(metrics, fullfile(outputFolder, '80_issue08_metrics.csv'));
save(fullfile(outputFolder, '80_issue08_validation.mat'), ...
    'summary', 'candidateDiagnostics', '-v7.3');
fprintf('80 issue 08 验证产物：%s\n', outputFolder);
fprintf('80 基线重建最大 RGB 差：%.17g\n', ...
    baselineReconstructionMaxRgbDifference);
fprintf('两次无缓存 80 候选计算最大 RGB 差：%.17g\n', ...
    recomputeMaxRgbDifference);
for index = 1:height(metrics)
    fprintf('%-10s baseline/candidate change %.6f/%.6f, candidate-vs-baseline %.6f/%g, texture %.6f\n', ...
        metrics.name{index}, metrics.baselineChangeMean(index), ...
        metrics.candidateChangeMean(index), metrics.candidateVsBaselineMean(index), ...
        metrics.candidateVsBaselineMax(index), metrics.candidateTextureProtectionMean(index));
end
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

function row = emptyRow()
row = struct('name', '', 'pixels', 0, ...
    'baselineChangeMean', 0, 'candidateChangeMean', 0, ...
    'baselineChangeMax', 0, 'candidateChangeMax', 0, ...
    'candidateVsBaselineMean', 0, 'candidateVsBaselineMax', 0, ...
    'baselineRepairFineMean', 0, 'candidateRepairFineMean', 0, ...
    'baselineRepairMidMean', 0, 'candidateRepairMidMean', 0, ...
    'candidateTextureProtectionMean', 0, ...
    'candidateHardProtectionFraction', 0);
end

function mask = makeRoiMask(roi, imageSize)
mask = false(imageSize);
x1 = max(1, roi(1)); y1 = max(1, roi(2));
x2 = min(imageSize(2), roi(1) + roi(3) - 1);
y2 = min(imageSize(1), roi(2) + roi(4) - 1);
mask(y1:y2, x1:x2) = true;
end
