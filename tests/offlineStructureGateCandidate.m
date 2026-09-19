function offlineStructureGateCandidate()
%OFFLINESTRUCTUREGATECANDIDATE 离线验证独立结构门控候选。
%   加载 02 保存基线，用候选公式 structureGate = 1 - structureProtection
%   冻结磨皮结果、参考目标和其他阶段，仅重新计算修复权重与输出。

testRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(testRoot);
addpath(fullfile(projectRoot, 'src'), '-begin');

outputFolder = fullfile(tempdir, 'image_beauty_issue06_offline_frozen');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

matPath = 'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat';
if ~isfile(matPath)
    error('offlineStructureGateCandidate:MissingBaseline', ...
        '02 基线 MAT 不存在：%s。', matPath);
end
loaded = load(matPath, 'diagnostics', 'context', 'output');
baseline = loaded.diagnostics;
baselineImage = loaded.output;
context = loaded.context;

inputImagePath = 'E:\image_beauty\人脸\人脸\77.png';
inputImage = imread(inputImagePath);

imageSize = baseline.beautyMasks.imageSize(1:2);
structureProtection = double(baseline.beautyMasks.structureProtectionMask);
textureProtection = double(baseline.beautyMasks.textureProtectionMask);
hardProtection = double(baseline.beautyMasks.hardProtectionMask);
skinMask = double(baseline.beautyMasks.skinMask);
strengthMap = double(baseline.beautyMasks.strengthMap);
blemishMap = double(baseline.blemishMap);

frequency = baseline.frequency;
if ~isfield(frequency, 'sourceLuminance')
    sourceYcbcr = rgb2ycbcr(im2double(inputImage));
    frequency.sourceLuminance = sourceYcbcr(:, :, 1);
end
if ~isfield(frequency, 'imageSize')
    frequency.imageSize = [imageSize, 3];
end
if ~isfield(frequency, 'faceBox')
    frequency.faceBox = [95 79 286 372];
end
if ~isfield(frequency, 'faceScale')
    frequency.faceScale = min(double(frequency.faceBox(3:4)));
end
if ~isfield(frequency, 'reconstructedLuminance')
    frequency.reconstructedLuminance = double(frequency.base) + ...
        double(frequency.mid) + double(frequency.fine);
end
if ~isfield(frequency, 'outputLuminance')
    frequency.outputLuminance = frequency.reconstructedLuminance;
end
if ~isfield(frequency, 'alphaMap')
    frequency.alphaMap = zeros(imageSize);
end
smoothingResult = baseline.smoothingResult;
repairDiag = baseline.repair;
requiredFields = {'fineBefore', 'midBefore', 'fineTarget', 'midTarget', ...
    'fineReference', 'midReference', 'referenceReliability'};
if ~all(isfield(repairDiag, requiredFields))
    error('offlineStructureGateCandidate:IncompleteBaseline', ...
        '固定基线缺少冻结修复输入和参考目标所需的字段。');
end
fine = double(smoothingResult.fine);
mid = double(smoothingResult.mid);
base = double(smoothingResult.base);
if ~isequal(fine, double(repairDiag.fineBefore)) || ...
        ~isequal(mid, double(repairDiag.midBefore))
    error('offlineStructureGateCandidate:RepairInputMismatch', ...
        '磨皮结果与保存的 Repair 输入不一致。');
end
fineTarget = double(repairDiag.fineTarget);
midTarget = double(repairDiag.midTarget);
referenceReliability = repairDiag.referenceReliability;
fineReference = repairDiag.fineReference;
midReference = repairDiag.midReference;

allowed = repairDiag.allowed;
textureGate = repairDiag.textureGate;
repairEvidence = repairDiag.repairEvidence;
mediumConfidence = repairDiag.mediumConfidence;
highConfidence = repairDiag.highConfidence;
highEndConfidence = repairDiag.highEndConfidence;
noseMask = repairDiag.noseMask;
noseMidGate = repairDiag.noseMidGate;
normalRepairCurve = repairDiag.normalRepairCurve;
highEndRepairCurve = repairDiag.highEndRepairCurve;
repairCurveMap = repairDiag.repairCurveMap;

oldStructureGate = repairDiag.structureGate;

newStructureGate = 1 - structureProtection;

hardFeatureBand = bwdist(hardProtection >= .999) <= 3;
strongStructure = smoothStep(structureProtection, .70, .90) .* ...
    double(hardFeatureBand);
newStructureGate = min(newStructureGate, 1 - .65 * strongStructure);
newStructureGate = max(min(newStructureGate, 1), 0);

fprintf('结构门控统计：\n');
fprintf('  旧 structureGate 均值: %.6f\n', mean(oldStructureGate(:)));
fprintf('  新 structureGate 均值: %.6f\n', mean(newStructureGate(:)));
fprintf('  差值 均值: %.6f, 最大: %.6f\n', ...
    mean(abs(newStructureGate(:) - oldStructureGate(:))), ...
    max(abs(newStructureGate(:) - oldStructureGate(:))));

newFineWeight = repairCurveMap .* (repairEvidence + .25 * highConfidence) .* ...
    allowed .* newStructureGate + (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* newStructureGate;
newMediumWeight = repairCurveMap .* (.95 * mediumConfidence + ...
    .40 * highConfidence) .* allowed .* newStructureGate + ...
    (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* newStructureGate;
newMediumWeight = min(max(newMediumWeight, 0), 1);
newMediumWeight = newMediumWeight .* noseMidGate;
newChromaWeight = .16 * repairCurveMap .* highConfidence .* allowed .* ...
    newStructureGate;
newFineWeight = min(max(newFineWeight, 0), 1);
newChromaWeight = min(max(newChromaWeight, 0), 1);

newFineWeight = newFineWeight .* textureGate;
newMediumWeight = newMediumWeight .* textureGate;
newChromaWeight = newChromaWeight .* textureGate;

% 第一阶段只验证门控；参考采样和目标均沿用同一次基线。
newFineCorrection = newFineWeight .* (fineTarget - fine);
newMediumCorrection = newMediumWeight .* (midTarget - mid);

newRepairedFine = fine + newFineCorrection;
newRepairedMid = mid + newMediumCorrection;
newReconstructedLuminance = base + newRepairedMid + newRepairedFine;

processing = struct( ...
    'baseLuminance', baseline.baseLuminanceResult, ...
    'skinTone', baseline.skinToneResult, ...
    'whitening', baseline.whiteningResult);

repairedFrequency = smoothingResult;
repairedFrequency.fine = newRepairedFine;
repairedFrequency.mid = newRepairedMid;
repairedFrequency.reconstructedLuminance = newReconstructedLuminance;
repairedFrequency.outputLuminance = newReconstructedLuminance;
alphaMap = double(smoothingResult.alphaMap);
repairedFrequency.alphaMap = min(1, max(alphaMap, ...
    newFineWeight + newMediumWeight));

[newOutput, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, repairedFrequency, ...
    baseline.beautyMasks, 15, processing);

% 用同一冻结目标还原旧校正，确保候选对照没有更换修复输入。
oldRepairedFrequency = smoothingResult;
oldRepairedFrequency.fine = fine + double(repairDiag.fineWeight) .* ...
    (fineTarget - fine);
oldRepairedFrequency.mid = mid + double(repairDiag.mediumWeight) .* ...
    (midTarget - mid);
oldRepairedFrequency.outputLuminance = base + ...
    oldRepairedFrequency.mid + oldRepairedFrequency.fine;
oldRepairedFrequency.reconstructedLuminance = ...
    oldRepairedFrequency.outputLuminance;
oldRepairedFrequency.alphaMap = min(1, max(alphaMap, ...
    double(repairDiag.fineWeight) + double(repairDiag.mediumWeight)));
[reconstructedBaseline, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, oldRepairedFrequency, baseline.beautyMasks, ...
    15, processing);
baselineReconstructionMaxRgbDifference = max(abs( ...
    double(reconstructedBaseline) - double(baselineImage)), [], 'all');
if baselineReconstructionMaxRgbDifference ~= 0
    error('offlineStructureGateCandidate:BaselineMismatch', ...
        '冻结输入和参考目标的旧基线重建失败，最大 RGB 差为 %.17g。', ...
        baselineReconstructionMaxRgbDifference);
end
if any(newFineWeight(:) > double(repairDiag.fineWeight(:)) + 1e-12) || ...
        any(newMediumWeight(:) > double(repairDiag.mediumWeight(:)) + 1e-12)
    error('offlineStructureGateCandidate:UnexpectedWeightIncrease', ...
        '独立结构门控候选不应增大原有修复权重。');
end
fprintf('冻结旧基线重建最大 RGB 差：%.17g\n', ...
    baselineReconstructionMaxRgbDifference);

outputDifference = max(abs(double(newOutput) - double(baselineImage)), [], 3);
fprintf('\n输出比较：\n');
fprintf('  候选 vs 基线 RGB 最大差: %.6f\n', max(outputDifference(:)));
fprintf('  候选 vs 基线 RGB 均值差: %.6f\n', mean(outputDifference(:)));

weightDifference = max(abs(newFineWeight - double(repairDiag.fineWeight)), [], 'all');
fprintf('  fineWeight 最大差: %.6f\n', weightDifference);
weightDifference = max(abs(newMediumWeight - double(repairDiag.mediumWeight)), [], 'all');
fprintf('  mediumWeight 最大差: %.6f\n', weightDifference);

% 为离线冻结口径补齐无 Repair、修复能量和低频结构量化；Base、肤色、
% 美白以及 Fine/Mid 参考目标均保持同一保存基线，不把参考采样变化混入。
noRepairFrequency = smoothingResult;
noRepairFrequency.fine = fine;
noRepairFrequency.mid = mid;
noRepairFrequency.reconstructedLuminance = base + mid + fine;
noRepairFrequency.outputLuminance = noRepairFrequency.reconstructedLuminance;
noRepairFrequency.alphaMap = double(smoothingResult.alphaMap);
[noRepairOutput, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, noRepairFrequency, baseline.beautyMasks, ...
    15, processing);
noRepairDifference = max(abs(double(noRepairOutput) - ...
    double(baselineImage)), [], 3);
candidateNoRepairDifference = max(abs(double(newOutput) - ...
    double(noRepairOutput)), [], 3);

weightOnlyFrequency = repairedFrequency;
weightOnlyFrequency.fine = fine + newFineWeight .* (fineTarget - fine);
weightOnlyFrequency.mid = mid + newMediumWeight .* (midTarget - mid);
weightOnlyFrequency.reconstructedLuminance = base + ...
    weightOnlyFrequency.mid + weightOnlyFrequency.fine;
weightOnlyFrequency.outputLuminance = weightOnlyFrequency.reconstructedLuminance;
weightOnlyFrequency.alphaMap = min(1, max(double(smoothingResult.alphaMap), ...
    newFineWeight + newMediumWeight));
[weightOnlyOutput, ~] = beauty.composeBeautyResult( ...
    inputImage, frequency, weightOnlyFrequency, baseline.beautyMasks, ...
    15, processing);
weightOnlyDifference = max(abs(double(weightOnlyOutput) - ...
    double(baselineImage)), [], 3);

earRoi = [345 110 75 120];
nostrilRoi = [185 335 50 35];
browEyeRoi = [165 205 150 100];
noseBridgeRoi = [160 295 90 50];
noseWingRoi = [155 325 80 45];
hairRoi = [80 90 90 70];
backgroundRoi = [465 20 40 140];

rois = struct('ear', earRoi, 'nostril', nostrilRoi, 'browEye', browEyeRoi, ...
    'noseBridge', noseBridgeRoi, 'noseWing', noseWingRoi, ...
    'hair', hairRoi, 'background', backgroundRoi);

roiNames = fieldnames(rois);
offlineMetricRows = repmat(emptyOfflineMetricRow(), 0, 1);
fprintf('\n区域指标：\n');
fprintf('%-15s %-12s %-12s %-12s %-12s\n', 'ROI', '旧Gate均值', '新Gate均值', '旧Weight均值', '新Weight均值');
for i = 1:numel(roiNames)
    name = roiNames{i};
    roi = rois.(name);
    roiMask = false(imageSize);
    x1 = max(1, roi(1)); y1 = max(1, roi(2));
    x2 = min(imageSize(2), roi(1)+roi(3)-1);
    y2 = min(imageSize(1), roi(2)+roi(4)-1);
    roiMask(y1:y2, x1:x2) = true;
    
    oldGateMean = mean(oldStructureGate(roiMask));
    newGateMean = mean(newStructureGate(roiMask));
    oldWeightMean = mean(double(repairDiag.fineWeight(roiMask)));
    newWeightMean = mean(newFineWeight(roiMask));
    beforeEnergy = mean((abs(fine(roiMask)) + abs(mid(roiMask))) .* ...
        blemishMap(roiMask));
    afterEnergy = mean((abs(newRepairedFine(roiMask)) + ...
        abs(newRepairedMid(roiMask))) .* blemishMap(roiMask));
    beforeGradient = lowFrequencyGradient(base + mid, roiMask);
    afterGradient = lowFrequencyGradient(base + newRepairedMid, roiMask);
    row = emptyOfflineMetricRow();
    row.roi = name;
    row.pixels = nnz(roiMask);
    row.oldStructureGateMean = oldGateMean;
    row.newStructureGateMean = newGateMean;
    row.oldFineWeightMean = oldWeightMean;
    row.newFineWeightMean = newWeightMean;
    row.oldMediumWeightMean = mean(double(repairDiag.mediumWeight(roiMask)));
    row.newMediumWeightMean = mean(newMediumWeight(roiMask));
    row.fineActionMean = mean(abs(newFineCorrection(roiMask)));
    row.mediumActionMean = mean(abs(newMediumCorrection(roiMask)));
    row.repairActionNonzeroFraction = mean((abs(newFineCorrection(roiMask)) + ...
        abs(newMediumCorrection(roiMask))) > 1e-12);
    row.blemishEnergyBefore = beforeEnergy;
    row.blemishEnergyAfter = afterEnergy;
    row.blemishEnergyReductionRatio = (beforeEnergy - afterEnergy) / ...
        max(beforeEnergy, eps);
    row.lowFrequencyGradientRetentionRatio = afterGradient / ...
        max(beforeGradient, eps);
    row.outputDifferenceFromBaselineMean = mean(outputDifference(roiMask));
    row.outputDifferenceFromBaselineMax = max(outputDifference(roiMask));
    row.noRepairDifferenceFromBaselineMean = mean(noRepairDifference(roiMask));
    row.noRepairDifferenceFromBaselineMax = max(noRepairDifference(roiMask));
    row.candidateDifferenceFromNoRepairMean = ...
        mean(candidateNoRepairDifference(roiMask));
    row.candidateDifferenceFromNoRepairMax = ...
        max(candidateNoRepairDifference(roiMask));
    row.weightOnlyDifferenceFromBaselineMean = ...
        mean(weightOnlyDifference(roiMask));
    row.referenceSamplingFrozen = true;
    offlineMetricRows(end + 1, 1) = row; %#ok<AGROW>
    fprintf('%-15s %-12.4f %-12.4f %-12.6f %-12.6f\n', ...
        name, oldGateMean, newGateMean, oldWeightMean, newWeightMean);
end
offlineMetrics = struct2table(offlineMetricRows);
writetable(offlineMetrics, fullfile(outputFolder, ...
    'offlineStructureGateMetrics.csv'));

save(fullfile(outputFolder, 'offlineStructureGateCandidate.mat'), ...
    'newOutput', 'baselineImage', 'inputImage', ...
    'newStructureGate', 'oldStructureGate', ...
    'newFineWeight', 'newMediumWeight', 'newChromaWeight', ...
    'referenceReliability', 'fineReference', 'midReference', ...
    'fineTarget', 'midTarget', 'baselineReconstructionMaxRgbDifference', ...
    'newFineCorrection', 'newMediumCorrection', ...
    'newRepairedFine', 'newRepairedMid', 'noRepairOutput', ...
    'offlineMetrics', 'repairDiag', 'baseline', 'outputDifference', '-v7.3');

writeLocalComparisonImages(inputImage, baselineImage, newOutput, ...
    newStructureGate, oldStructureGate, ...
    newFineWeight, repairDiag.fineWeight, ...
    rois, imageSize, outputFolder);

fprintf('\n离线候选验证完成。产物目录：%s\n', outputFolder);
end

function writeLocalComparisonImages(inputImage, baselineImage, newOutput, ...
    newStructureGate, oldStructureGate, ...
    newFineWeight, oldFineWeight, ...
    rois, imageSize, outputFolder)

featureNames = {'ear', 'nostril', 'browEye'};
featureRois = [rois.ear; rois.nostril; rois.browEye];

figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 2400, 600 * numel(featureNames)]);
tiledlayout(numel(featureNames), 6, ...
    'Padding', 'compact', 'TileSpacing', 'compact');

for idx = 1:numel(featureNames)
    name = featureNames{idx};
    roi = featureRois(idx, :);
    
    inputCrop = cropRoi(inputImage, roi, imageSize);
    baselineCrop = cropRoi(baselineImage, roi, imageSize);
    newCrop = cropRoi(newOutput, roi, imageSize);
    
    oldGateRoi = cropRoi(oldStructureGate, roi, imageSize);
    newGateRoi = cropRoi(newStructureGate, roi, imageSize);
    gateDiff = abs(newGateRoi - oldGateRoi);
    
    nexttile;
    imshow(inputCrop);
    title([name ' - 输入']);
    
    nexttile;
    imshow(baselineCrop);
    title([name ' - 基线']);
    
    nexttile;
    imshow(newCrop);
    title([name ' - 候选']);
    
    nexttile;
    diffImg = max(abs(double(newCrop) - double(baselineCrop)), [], 3);
    imagesc(diffImg);
    axis image off;
    colorbar;
    clim([0, 16]);
    title([name ' - RGB差(0-16)']);
    
    nexttile;
    imagesc(gateDiff);
    axis image off;
    colorbar;
    clim([0, 0.3]);
    title([name ' - 门控差(0-0.3)']);
    
    nexttile;
    oldWeightRoi = cropRoi(double(oldFineWeight), roi, imageSize);
    newWeightRoi = cropRoi(double(newFineWeight), roi, imageSize);
    imagesc(cat(2, oldWeightRoi, newWeightRoi));
    axis image off;
    colorbar;
    clim([0, 0.5]);
    title([name ' - 旧/新权重']);
end

exportgraphics(figureHandle, fullfile(outputFolder, 'offlineStructureGateComparison.png'), ...
    'Resolution', 140);
close(figureHandle);

figureHandle2 = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1800, 400]);
tiledlayout(1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imagesc(oldStructureGate);
axis image off;
colorbar;
clim([0, 1]);
title('旧结构门控');

nexttile;
imagesc(newStructureGate);
axis image off;
colorbar;
clim([0, 1]);
title('新结构门控');

nexttile;
imagesc(abs(newStructureGate - oldStructureGate));
axis image off;
colorbar;
clim([0, 0.3]);
title('门控差值(0-0.3)');

exportgraphics(figureHandle2, fullfile(outputFolder, 'offlineStructureGateMaps.png'), ...
    'Resolution', 140);
close(figureHandle2);
end

function row = emptyOfflineMetricRow()
row = struct('roi', '', 'pixels', 0, ...
    'oldStructureGateMean', 0, 'newStructureGateMean', 0, ...
    'oldFineWeightMean', 0, 'newFineWeightMean', 0, ...
    'oldMediumWeightMean', 0, 'newMediumWeightMean', 0, ...
    'fineActionMean', 0, 'mediumActionMean', 0, ...
    'repairActionNonzeroFraction', 0, ...
    'blemishEnergyBefore', 0, 'blemishEnergyAfter', 0, ...
    'blemishEnergyReductionRatio', 0, ...
    'lowFrequencyGradientRetentionRatio', 0, ...
    'outputDifferenceFromBaselineMean', 0, ...
    'outputDifferenceFromBaselineMax', 0, ...
    'noRepairDifferenceFromBaselineMean', 0, ...
    'noRepairDifferenceFromBaselineMax', 0, ...
    'candidateDifferenceFromNoRepairMean', 0, ...
    'candidateDifferenceFromNoRepairMax', 0, ...
    'weightOnlyDifferenceFromBaselineMean', 0, ...
    'referenceSamplingFrozen', false);
end

function value = lowFrequencyGradient(image, roiMask)
[xGradient, yGradient] = gradient(double(image));
value = mean(hypot(xGradient(roiMask), yGradient(roiMask)));
end

function cropped = cropRoi(data, roi, imageSize)
x1 = max(1, roi(1));
y1 = max(1, roi(2));
x2 = min(imageSize(2), roi(1) + roi(3) - 1);
y2 = min(imageSize(1), roi(2) + roi(4) - 1);
if ndims(data) == 3
    cropped = data(y1:y2, x1:x2, :);
else
    cropped = data(y1:y2, x1:x2);
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end
