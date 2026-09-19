function runStructureGateProductionValidation()
%RUNSTRUCTUREGATEPRODUCTIONVALIDATION 在固定 77 Context 上重跑生产链。
%   该入口只复用已验证的 02 MAT 输入、Context 和基线输出；生产
%   Repair 从当前工作树调用，单独记录参考采样改变后的实际结果。
%   仅用于候选验证；候选失败后不应以当前入口宣称生产候选已保留。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'), '-begin');

baselinePath = 'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat';
inputPath = 'E:\image_beauty\人脸\人脸\77.png';
outputFolder = fullfile(tempdir, 'image_beauty_issue06_production');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
if ~isfile(baselinePath)
    error('runStructureGateProductionValidation:MissingBaseline', ...
        '固定 77 基线不存在：%s。', baselinePath);
end
loaded = load(baselinePath, 'diagnostics', 'context', 'output');
required = {'diagnostics', 'context', 'output'};
if ~all(isfield(loaded, required))
    error('runStructureGateProductionValidation:InvalidBaseline', ...
        '固定基线缺少 diagnostics/context/output。');
end
inputImage = imread(inputPath);
baseline = loaded.diagnostics;
context = loaded.context;
baselineImage = loaded.output;
faceBox = [95 79 286 372];
params = struct('smoothingStrength', 100, 'whiteningStrength', 15);

% 先核对保存基线的完整 Repair 重建，不能把候选输出误当作旧基线。
frequency = baseline.frequency;
frequency.sourceLuminance = rgb2ycbcr(im2double(inputImage));
frequency.sourceLuminance = frequency.sourceLuminance(:, :, 1);
frequency.imageSize = [size(inputImage, 1:2), 3];
frequency.faceBox = faceBox;
frequency.faceScale = min(faceBox(3:4));
frequency.reconstructedLuminance = double(frequency.base) + ...
    double(frequency.mid) + double(frequency.fine);
frequency.outputLuminance = frequency.reconstructedLuminance;
frequency.alphaMap = zeros(size(inputImage, 1:2));
processing = struct( ...
    'baseLuminance', baseline.baseLuminanceResult, ...
    'skinTone', baseline.skinToneResult, ...
    'whitening', baseline.whiteningResult);
[reconstructedBaseline, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, baseline.repairResult, baseline.beautyMasks, ...
    params.whiteningStrength, processing);
baselineReconstructionMaxRgbDifference = max(abs(double( ...
    reconstructedBaseline) - double(baselineImage)), [], 'all');
if baselineReconstructionMaxRgbDifference ~= 0
    error('runStructureGateProductionValidation:BaselineMismatch', ...
        '保存 v3.2 基线完整重建不一致，最大 RGB 差为 %.17g。', ...
        baselineReconstructionMaxRgbDifference);
end

% 这里调用真实生产入口，使 repairSkinBlemishes 重新生成权重、参考可靠度
% 和 Fine/Mid 输出；不使用离线缩放后的旧权重。
[productionOutput, productionDiagnostics] = beautifyImage( ...
    inputImage, params, faceBox, context);
uncachedContext = rmfield(context, 'runtimeCache');
[directProductionOutput, directProductionDiagnostics] = beautifyImage( ...
    inputImage, params, faceBox, uncachedContext);
cacheReuseMaxRgbDifference = max(abs(double(productionOutput) - ...
    double(directProductionOutput)), [], 'all');
if cacheReuseMaxRgbDifference ~= 0
    error('runStructureGateProductionValidation:CacheMismatch', ...
        '缓存复用与直接计算不一致，最大 RGB 差为 %.17g。', ...
        cacheReuseMaxRgbDifference);
end

outputDifference = max(abs(double(productionOutput) - double(baselineImage)), [], 3);
repair = productionDiagnostics.repair;
oldRepair = baseline.repair;
roiDefinitions = struct( ...
    'ear', [345 110 75 120], ...
    'nostril', [185 335 50 35], ...
    'browEye', [165 205 150 100], ...
    'noseBridge', [160 295 90 50], ...
    'noseWing', [155 325 80 45], ...
    'hair', [80 90 90 70], ...
    'background', [465 20 40 140]);
roiNames = fieldnames(roiDefinitions);
rows = repmat(emptyRow(), 0, 1);
for index = 1:numel(roiNames)
    name = roiNames{index};
    roiMask = makeRoiMask(roiDefinitions.(name), size(inputImage, 1:2));
    beforeEnergy = mean((abs(double(productionDiagnostics.smoothing.fineAfter(roiMask))) + ...
        abs(double(productionDiagnostics.smoothing.midAfter(roiMask)))) .* ...
        double(productionDiagnostics.blemishMap(roiMask)));
    afterEnergy = mean((abs(double(repair.fineAfter(roiMask))) + ...
        abs(double(repair.midAfter(roiMask)))) .* double(productionDiagnostics.blemishMap(roiMask)));
    base = double(productionDiagnostics.smoothingResult.base);
    [beforeX, beforeY] = gradient(base + ...
        double(productionDiagnostics.smoothingResult.mid));
    [afterX, afterY] = gradient(base + double(repair.midAfter));
    beforeGradient = mean(hypot(beforeX(roiMask), beforeY(roiMask)));
    afterGradient = mean(hypot(afterX(roiMask), afterY(roiMask)));
    outputChange = max(abs(double(productionOutput) - ...
        double(inputImage)), [], 3);
    row = emptyRow();
    row.name = name;
    row.pixels = nnz(roiMask);
    row.oldStructureGateMean = mean(double(oldRepair.structureGate(roiMask)));
    row.newStructureGateMean = mean(double(repair.structureGate(roiMask)));
    row.oldFineWeightMean = mean(double(oldRepair.fineWeight(roiMask)));
    row.newFineWeightMean = mean(double(repair.fineWeight(roiMask)));
    row.oldMediumWeightMean = mean(double(oldRepair.mediumWeight(roiMask)));
    row.newMediumWeightMean = mean(double(repair.mediumWeight(roiMask)));
    row.fineActionMean = mean(abs(double(repair.fineCorrection(roiMask))));
    row.mediumActionMean = mean(abs(double(repair.mediumCorrection(roiMask))));
    row.blemishEnergyBefore = beforeEnergy;
    row.blemishEnergyAfter = afterEnergy;
    row.blemishEnergyReductionRatio = (beforeEnergy - afterEnergy) / max(beforeEnergy, eps);
    row.lowFrequencyGradientRetentionRatio = afterGradient / max(beforeGradient, eps);
    row.outputDifferenceFromBaselineMean = mean(outputDifference(roiMask));
    row.outputDifferenceFromBaselineMax = max(outputDifference(roiMask));
    row.outputChangeFromInputMean = mean(outputChange(roiMask));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
metrics = struct2table(rows);

save(fullfile(outputFolder, 'productionValidation.mat'), ...
    'productionOutput', 'baselineImage', 'inputImage', ...
    'productionDiagnostics', 'baseline', 'outputDifference', ...
    'baselineReconstructionMaxRgbDifference', ...
    'cacheReuseMaxRgbDifference', 'directProductionDiagnostics', ...
    'metrics', '-v7.3');
writetable(metrics, fullfile(outputFolder, 'productionStructureGateMetrics.csv'));
writeComparisonFigure(inputImage, baselineImage, productionOutput, ...
    outputDifference, roiDefinitions, outputFolder);

fprintf('生产链验证完成。\n');
fprintf('输出目录：%s\n', outputFolder);
fprintf('旧基线完整重建最大 RGB 差：%.17g\n', ...
    baselineReconstructionMaxRgbDifference);
fprintf('生产候选 vs 旧基线 RGB 最大差：%.6f，均值差：%.6f\n', ...
    max(outputDifference(:)), mean(outputDifference(:)));
fprintf('缓存复用：%d；与直接计算最大 RGB 差：%.17g\n', ...
    productionDiagnostics.reusedRuntimeCache, cacheReuseMaxRgbDifference);
for index = 1:height(metrics)
    fprintf('%-10s oldGate=%.6f newGate=%.6f oldFine=%.6f newFine=%.6f oldMid=%.6f newMid=%.6f energy=%.6f->%.6f grad=%.6f rgb=%.6f/%g\n', ...
        metrics.name{index}, metrics.oldStructureGateMean(index), ...
        metrics.newStructureGateMean(index), metrics.oldFineWeightMean(index), ...
        metrics.newFineWeightMean(index), metrics.oldMediumWeightMean(index), ...
        metrics.newMediumWeightMean(index), metrics.blemishEnergyBefore(index), ...
        metrics.blemishEnergyAfter(index), metrics.lowFrequencyGradientRetentionRatio(index), ...
        metrics.outputDifferenceFromBaselineMean(index), metrics.outputDifferenceFromBaselineMax(index));
end
end

function row = emptyRow()
row = struct('name', '', 'pixels', 0, ...
    'oldStructureGateMean', 0, 'newStructureGateMean', 0, ...
    'oldFineWeightMean', 0, 'newFineWeightMean', 0, ...
    'oldMediumWeightMean', 0, 'newMediumWeightMean', 0, ...
    'fineActionMean', 0, 'mediumActionMean', 0, ...
    'blemishEnergyBefore', 0, 'blemishEnergyAfter', 0, ...
    'blemishEnergyReductionRatio', 0, ...
    'lowFrequencyGradientRetentionRatio', 0, ...
    'outputDifferenceFromBaselineMean', 0, ...
    'outputDifferenceFromBaselineMax', 0, ...
    'outputChangeFromInputMean', 0);
end

function mask = makeRoiMask(roi, imageSize)
mask = false(imageSize);
x1 = max(1, roi(1));
y1 = max(1, roi(2));
x2 = min(imageSize(2), roi(1) + roi(3) - 1);
y2 = min(imageSize(1), roi(2) + roi(4) - 1);
mask(y1:y2, x1:x2) = true;
end

function writeComparisonFigure(inputImage, baselineImage, candidateImage, ...
        outputDifference, roiDefinitions, outputFolder)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 2200, 1200]);
tiledlayout(2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; imshow(inputImage); title('77 输入');
nexttile; imshow(baselineImage); title('v3.2 旧基线');
nexttile; imshow(candidateImage); title('Repair 结构门控候选');
nexttile; imagesc(outputDifference); axis image off; colorbar; clim([0, 32]); title('候选-基线 RGB差(0-32)');
featureNames = {'ear', 'nostril', 'browEye', 'noseBridge'};
for index = 1:numel(featureNames)
    name = featureNames{index};
    roi = roiDefinitions.(name);
    nexttile;
    imshow(crop(inputImage, roi)); hold on;
    rectangle('Position', [1, 1, size(crop(inputImage, roi), 2) - 1, ...
        size(crop(inputImage, roi), 1) - 1], 'EdgeColor', 'r');
    title([name ' 输入']);
end
exportgraphics(figureHandle, fullfile(outputFolder, ...
    'productionStructureGateComparison.png'), 'Resolution', 140);
close(figureHandle);
end

function value = crop(image, roi)
x1 = max(1, roi(1)); y1 = max(1, roi(2));
x2 = min(size(image, 2), roi(1) + roi(3) - 1);
y2 = min(size(image, 1), roi(2) + roi(4) - 1);
value = image(y1:y2, x1:x2, :);
end
