function [summary, diagnostics] = diagnoseLashOrientationCoherenceEvidence( ...
        imagePath, outputFolder, options)
%DIAGNOSELASHORIENTATIONCOHERENCEEVIDENCE 验证 Issue 08.8 连续方向证据。
%   本入口只做离线 feature-separability diagnostic，不修改生产
%   lashProtection、Repair、Smoothing、GUI、模型或公共 Context schema。
%   Structure Tensor 严格从当前 detectLashLines 使用的 lineImage 梯度
%   构造；manualLashMask 只参与离线统计，不参与特征计算或上游候选生成。
%
%   [summary, diagnostics] = diagnoseLashOrientationCoherenceEvidence( ...
%       'E:\image_beauty\人脸\人脸\77.png', tempdir, struct( ...
%       'productionRoot', 'E:\image_beauty', ...
%       'baselinePath', ...
%       'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat'));
%
%   Tensor smoothing 使用当前 detectLashLines 的 lineImage sigma：
%       lineSigma = min(1.35, max(.45, .002 * faceScale));
%       tensorSigma = lineSigma;
%   这是已有 lineImage 尺度语义，不新增绝对像素常数，也不扫描尺度。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
if nargin < 2
    outputFolder = [];
end
if nargin < 3
    options = [];
end
options = normalizeOptions(options, projectRoot);

productionRoot = resolveProductionRoot(options.productionRoot);
addpath(fullfile(productionRoot, 'src'), '-begin');
addpath(fileparts(mfilename('fullpath')), '-begin');

if nargin < 1 || isempty(imagePath)
    error('diagnoseLashOrientationCoherenceEvidence:MissingImage', ...
        '必须提供固定 77.png 的输入图像路径。');
end
imagePath = normalizeText(imagePath, 'imagePath');
inputImage = readInputImage(imagePath);
imageSize = [size(inputImage, 1), size(inputImage, 2)];
validateFixed77Fixture(inputImage, options);
outputFolder = normalizeOutputFolder(outputFolder);

% 08.6/08.7 的 support 和当前 detector evidence 由既有 08.7
% 离线阶段提供。若固定阶段产物不存在，则在临时目录重建 08.7；
% 本票不改变该阶段的生产候选。
[upstreamSummary, upstream] = obtainUpstreamStage( ...
    imagePath, options, imageSize);
validateUpstreamStage(upstreamSummary, upstream, imageSize, options);

manualLashMask = logical(upstream.manualLashMask);
fp08_6 = logical(upstream.candidate086Support) & ~manualLashMask;
fp08_7 = logical(upstream.candidate087Support) & ~manualLashMask;
eyeNeighborhood = logical(upstream.evidence.eyeNeighborhood);
lineSupport = logical(upstream.evidence.lineSupport);
browEye = makeRoiMask(options.browEyeRoi, imageSize);
browEyeNonLash = browEye & ~manualLashMask;
eyeNeighborhoodNonLash = eyeNeighborhood & ~manualLashMask;

% 只从当前 detector 的 lineImage 和 gradientX/gradientY 开始构造张量。
faceScale = double(upstream.evidence.faceScale);
lineSigma = existingLineSigma(faceScale);
lineImage = imgaussfilt(im2double(rgb2gray(inputImage)), lineSigma, ...
    'Padding', 'replicate');
[gradientX, gradientY] = gradient(lineImage);
gradientMagnitude = hypot(gradientX, gradientY);

% 唯一固定 tensor smoothing 尺度：复用 lineImage 的既有 sigma 语义。
tensorSigma = lineSigma;
Jxx = imgaussfilt(gradientX .^ 2, tensorSigma, ...
    'Padding', 'replicate');
Jyy = imgaussfilt(gradientY .^ 2, tensorSigma, ...
    'Padding', 'replicate');
Jxy = imgaussfilt(gradientX .* gradientY, tensorSigma, ...
    'Padding', 'replicate');
tensorEnergy = Jxx + Jyy;
orientation = 0.5 .* atan2(2 .* Jxy, Jxx - Jyy);
coherence = sqrt((Jxx - Jyy) .^ 2 + 4 .* Jxy .^ 2) ./ ...
    (tensorEnergy + eps);
% 公式理论上已位于 [0,1]；仅消除浮点舍入越界，不做阈值化。
coherence = min(max(coherence, 0), 1);
validTensorEnergy = isfinite(tensorEnergy) & tensorEnergy > 0 & ...
    isfinite(orientation) & isfinite(coherence);

validateTensorArrays(gradientX, gradientY, gradientMagnitude, Jxx, Jyy, ...
    Jxy, orientation, coherence, tensorEnergy, imageSize);

% 原始评价集合和 lineSupport == 1 内部集合均不参与特征计算，
% 这里只在特征完成后用于离线分组统计。
groupNames = { ...
    'manual_lash', ...
    'fp08_6', ...
    'fp08_7', ...
    'browEye_non_lash', ...
    'eyeNeighborhood_non_lash', ...
    'manual_lash_lineSupport', ...
    'fp08_6_lineSupport', ...
    'fp08_7_lineSupport'};
groupDescriptions = { ...
    '77-manual-lash-v1', ...
    'support_08_6 & ~manualLashMask', ...
    'support_08_7 & ~manualLashMask', ...
    'browEye & ~manualLashMask', ...
    'eyeNeighborhood & ~manualLashMask', ...
    'manualLashMask & lineSupport', ...
    'fp08_6 & lineSupport', ...
    'fp08_7 & lineSupport'};
groupMasks = { ...
    manualLashMask, ...
    fp08_6, ...
    fp08_7, ...
    browEyeNonLash, ...
    eyeNeighborhoodNonLash, ...
    manualLashMask & lineSupport, ...
    fp08_6 & lineSupport, ...
    fp08_7 & lineSupport};
groupStats = makeGroupStats(groupNames, groupDescriptions, groupMasks, ...
    coherence, tensorEnergy, validTensorEnergy);

comparisonNames = { ...
    'manual_vs_fp08_6', ...
    'manual_vs_fp08_7', ...
    'manual_vs_browEye_non_lash', ...
    'manual_vs_eyeNeighborhood_non_lash', ...
    'lineSupport_manual_vs_fp08_6', ...
    'lineSupport_manual_vs_fp08_7'};
positiveNames = { ...
    'manual_lash', 'manual_lash', 'manual_lash', 'manual_lash', ...
    'manual_lash_lineSupport', 'manual_lash_lineSupport'};
negativeNames = { ...
    'fp08_6', 'fp08_7', 'browEye_non_lash', ...
    'eyeNeighborhood_non_lash', 'fp08_6_lineSupport', ...
    'fp08_7_lineSupport'};
comparisonPositiveMasks = { ...
    manualLashMask, manualLashMask, manualLashMask, manualLashMask, ...
    manualLashMask & lineSupport, manualLashMask & lineSupport};
comparisonNegativeMasks = { ...
    fp08_6, fp08_7, browEyeNonLash, eyeNeighborhoodNonLash, ...
    fp08_6 & lineSupport, fp08_7 & lineSupport};

[gradientBinRows, gradientBinSummary] = makeGradientBinStats( ...
    coherence, gradientMagnitude, validTensorEnergy, ...
    manualLashMask, fp08_6, fp08_7);
comparisonStats = makeComparisonStats(comparisonNames, positiveNames, ...
    negativeNames, comparisonPositiveMasks, comparisonNegativeMasks, ...
    coherence, gradientMagnitude, validTensorEnergy, gradientBinSummary);

continuityNames = {'manual_lash', 'fp08_6', 'fp08_7'};
continuityMasks = {manualLashMask, fp08_6, fp08_7};
continuityStats = makeContinuityStats(continuityNames, continuityMasks, ...
    orientation, validTensorEnergy);

correlations = makeCorrelationStats(groupNames, groupMasks, ...
    coherence, gradientMagnitude, validTensorEnergy);
caseAssessment = assessFeatureSeparation(comparisonStats, continuityStats, ...
    gradientBinSummary);
metricsRow = makeMetricsRow(options, upstreamSummary, upstream, ...
    faceScale, lineSigma, tensorSigma, manualLashMask, fp08_6, fp08_7, ...
    browEyeNonLash, eyeNeighborhoodNonLash, groupStats, comparisonStats, ...
    continuityStats, correlations, gradientBinSummary, caseAssessment);

paths = writeArtifacts(outputFolder, lineImage, gradientMagnitude, ...
    coherence, orientation, tensorEnergy, validTensorEnergy, ...
    groupMasks, groupNames, groupDescriptions, coherence, ...
    gradientMagnitude, continuityNames, continuityMasks, ...
    orientation, options);
paths.metrics = fullfile(outputFolder, ...
    'lash_orientation_coherence_metrics.csv');
paths.groupStats = fullfile(outputFolder, ...
    'lash_orientation_coherence_group_stats.csv');
paths.continuityStats = fullfile(outputFolder, ...
    'lash_orientation_continuity_stats.csv');
paths.gradientBins = fullfile(outputFolder, ...
    'lash_orientation_coherence_gradient_bins.csv');
writeMetricsTable(paths.metrics, metricsRow);
writetable(struct2table(groupStats), paths.groupStats);
writetable(struct2table(continuityStats), paths.continuityStats);
writetable(struct2table(gradientBinRows), paths.gradientBins);
paths.data = fullfile(outputFolder, ...
    'lash_orientation_coherence_diagnostic.mat');

summary = struct( ...
    'completed', true, ...
    'issue', '08.8', ...
    'case', caseAssessment.case, ...
    'caseAssessment', caseAssessment, ...
    'imagePath', imagePath, ...
    'inputSize', size(inputImage), ...
    'faceBox', double(options.faceBox), ...
    'browEye', double(options.browEyeRoi), ...
    'lashRoi', double(options.lashRoi), ...
    'manualLashMaskId', upstream.annotation.annotationId, ...
    'manualLashMaskIndependent', upstream.annotation.diagnosticsIndependent, ...
    'manualLashMaskFixed', upstream.annotation.fixedAfterAnnotation, ...
    'manualLashMaskPixels', nnz(manualLashMask), ...
    'fp08_6Pixels', nnz(fp08_6), ...
    'fp08_7Pixels', nnz(fp08_7), ...
    'browEyeNonLashPixels', nnz(browEyeNonLash), ...
    'eyeNeighborhoodNonLashPixels', nnz(eyeNeighborhoodNonLash), ...
    'lineSupportPixels', nnz(lineSupport), ...
    'lineSupportRestricted', true, ...
    'lineSupportManualPixels', nnz(manualLashMask & lineSupport), ...
    'lineSupportFp08_6Pixels', nnz(fp08_6 & lineSupport), ...
    'lineSupportFp08_7Pixels', nnz(fp08_7 & lineSupport), ...
    'manualTruthUsedForFeature', false, ...
    'manualTruthUsedForGeneration', false, ...
    'productionModified', false, ...
    'coherenceThresholdUsed', false, ...
    'parameterScanUsed', false, ...
    'tensorEnergyThresholdUsed', false, ...
    'orientationAngularThresholdUsed', false, ...
    'faceScale', faceScale, ...
    'lineSigma', lineSigma, ...
    'tensorSigma', tensorSigma, ...
    'tensorSmoothingScaleSource', 'existing detectLashLines lineImage sigma', ...
    'tensorSigmaFormula', ...
        'tensorSigma = lineSigma = min(1.35,max(.45,.002*faceScale))', ...
    'sourceDiagnosticPath', upstreamSummary.sourceDiagnosticPath, ...
    'sourceStageRebuilt', upstreamSummary.sourceStageRebuilt, ...
    'gradientSource', ...
        'current detectLashLines lineImage gradientX/gradientY', ...
    'groupStats', groupStats, ...
    'comparisonStats', comparisonStats, ...
    'continuityStats', continuityStats, ...
    'correlations', correlations, ...
    'gradientBinSummary', gradientBinSummary, ...
    'metrics', metricsRow, ...
    'paths', paths);

diagnosticData = struct( ...
    'summary', summary, ...
    'inputImage', inputImage, ...
    'lineImage', lineImage, ...
    'gradientX', gradientX, ...
    'gradientY', gradientY, ...
    'gradientMagnitude', gradientMagnitude, ...
    'Jxx', Jxx, ...
    'Jyy', Jyy, ...
    'Jxy', Jxy, ...
    'tensorEnergy', tensorEnergy, ...
    'orientation', orientation, ...
    'coherence', coherence, ...
    'validTensorEnergy', validTensorEnergy, ...
    'manualLashMask', manualLashMask, ...
    'fp08_6', fp08_6, ...
    'fp08_7', fp08_7, ...
    'browEye', browEye, ...
    'browEyeNonLash', browEyeNonLash, ...
    'eyeNeighborhood', eyeNeighborhood, ...
    'eyeNeighborhoodNonLash', eyeNeighborhoodNonLash, ...
    'lineSupport', lineSupport, ...
    'upstreamSummary', upstreamSummary, ...
    'upstreamEvidence', upstream.evidence, ...
    'groupStats', groupStats, ...
    'comparisonStats', comparisonStats, ...
    'continuityStats', continuityStats, ...
    'correlations', correlations, ...
    'gradientBinRows', gradientBinRows, ...
    'gradientBinSummary', gradientBinSummary, ...
    'metrics', metricsRow);
save(paths.data, 'diagnosticData', '-v7.3');
summary.paths = paths;
diagnosticData.summary = summary;
diagnostics = diagnosticData;

fprintf('Issue 08.8 产物：%s\n', outputFolder);
fprintf('lineSigma/tensorSigma：%.17g / %.17g；tensor energy 有效像素：%d\n', ...
    lineSigma, tensorSigma, nnz(validTensorEnergy));
fprintf('Manual / 08.6 FP / 08.7 FP coherence AUC：%.6f / %.6f / %.6f\n', ...
    comparisonStats(1).auc, comparisonStats(2).auc, comparisonStats(3).auc);
fprintf('Case A 条件全部满足：%d；最终归因需结合 gradientMagnitude/lineSupport 复核。\n', ...
    caseAssessment.allCaseAConditions);
end

function options = normalizeOptions(options, projectRoot)
if nargin < 1 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('diagnoseLashOrientationCoherenceEvidence:InvalidOptions', ...
        'options 必须是标量结构。');
end
fixedFields = { ...
    'faceBox', [95, 79, 286, 372]; ...
    'browEyeRoi', [165, 205, 150, 100]; ...
    'lashRoi', [102, 248, 177, 48]};
for index = 1:size(fixedFields, 1)
    name = fixedFields{index, 1};
    defaultValue = fixedFields{index, 2};
    if ~isfield(options, name) || isempty(options.(name))
        options.(name) = defaultValue;
    end
    if ~isequal(double(options.(name)), double(defaultValue))
        error('diagnoseLashOrientationCoherenceEvidence:NonFixedFixture', ...
            '%s 必须复用 Issue 08.8 固定值。', name);
    end
end
options.faceBox = double(options.faceBox);
options.browEyeRoi = double(options.browEyeRoi);
options.lashRoi = double(options.lashRoi);
if ~isfield(options, 'productionRoot') || isempty(options.productionRoot)
    options.productionRoot = projectRoot;
end
options.productionRoot = normalizeText(options.productionRoot, ...
    'productionRoot');
if ~isfield(options, 'baselinePath') || isempty(options.baselinePath)
    options.baselinePath = ...
        'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat';
end
options.baselinePath = normalizeText(options.baselinePath, 'baselinePath');
if ~isfield(options, 'sourceDiagnosticPath') || ...
        isempty(options.sourceDiagnosticPath)
    options.sourceDiagnosticPath = fullfile(tempdir, ...
        'image_beauty_issue08_7_lash_angle_grouped_20260919', ...
        'lash_angle_grouped_diagnostic.mat');
end
options.sourceDiagnosticPath = normalizeText(options.sourceDiagnosticPath, ...
    'sourceDiagnosticPath');
if ~isfield(options, 'forceRebuildSource') || isempty(options.forceRebuildSource)
    options.forceRebuildSource = false;
end
if ~isscalar(options.forceRebuildSource) || ...
        (~islogical(options.forceRebuildSource) && ...
        ~ismember(options.forceRebuildSource, [0, 1]))
    error('diagnoseLashOrientationCoherenceEvidence:InvalidOption', ...
        'forceRebuildSource 必须是逻辑标量。');
end
if ~isfield(options, 'formulaTolerance') || isempty(options.formulaTolerance)
    options.formulaTolerance = 1e-12;
end
if ~isscalar(options.formulaTolerance) || ...
        ~isfinite(options.formulaTolerance) || options.formulaTolerance <= 0
    error('diagnoseLashOrientationCoherenceEvidence:InvalidTolerance', ...
        'formulaTolerance 必须是正的有限标量。');
end
options.formulaTolerance = double(options.formulaTolerance);
end

function root = resolveProductionRoot(root)
if ~isfolder(root) || ~isfolder(fullfile(root, 'src'))
    error('diagnoseLashOrientationCoherenceEvidence:InvalidProductionRoot', ...
        '生产算法根目录或 src 目录不存在：%s。', root);
end
end

function [stageSummary, stage] = obtainUpstreamStage(imagePath, options, imageSize)
sourcePath = options.sourceDiagnosticPath;
if ~options.forceRebuildSource && isfile(sourcePath)
    loaded = load(sourcePath, 'diagnosticData');
    if isfield(loaded, 'diagnosticData') && ...
            isstruct(loaded.diagnosticData)
        stage = loaded.diagnosticData;
        stageSummary = stage.summary;
        stageSummary.sourceDiagnosticPath = sourcePath;
        stageSummary.sourceStageRebuilt = false;
        return;
    end
end
stageFolder = tempname;
mkdir(stageFolder);
[stageSummary, stage] = diagnoseLashAngleGroupedReconstruction( ...
    imagePath, stageFolder, options);
stageSummary.sourceDiagnosticPath = fullfile(stageFolder, ...
    'lash_angle_grouped_diagnostic.mat');
stageSummary.sourceStageRebuilt = true;
if ~isequal(size(stage.inputImage), [imageSize, 3])
    error('diagnoseLashOrientationCoherenceEvidence:UpstreamSizeMismatch', ...
        '重建的 08.7 阶段尺寸不一致。');
end
end

function validateUpstreamStage(stageSummary, stage, imageSize, options)
if ~isstruct(stageSummary) || ~stageSummary.completed || ...
        ~strcmp(stageSummary.issue, '08.7') || ...
        stageSummary.runtimeCacheReused || ...
        ~isstruct(stage) || ~isequal(size(stage.inputImage), [imageSize, 3])
    error('diagnoseLashOrientationCoherenceEvidence:InvalidUpstreamStage', ...
        '08.7 上游诊断未按固定、无缓存阶段完成。');
end
if ~isequal(stageSummary.faceBox, options.faceBox) || ...
        ~isequal(stageSummary.browEye, options.browEyeRoi) || ...
        ~isequal(stageSummary.lashRoi, options.lashRoi) || ...
        ~strcmp(stageSummary.manualLashMaskId, '77-manual-lash-v1') || ...
        stageSummary.manualLashMaskPixels ~= 576 || ...
        ~stageSummary.manualLashMaskIndependent || ...
        ~stageSummary.manualLashMaskFixed
    error('diagnoseLashOrientationCoherenceEvidence:InvalidUpstreamFixture', ...
        '08.7 上游诊断未使用固定 77 fixture 或固定人工真值。');
end
required = {'manualLashMask', 'candidate086Support', ...
    'candidate087Support', 'evidence', 'annotation'};
if ~all(isfield(stage, required))
    error('diagnoseLashOrientationCoherenceEvidence:MissingUpstreamField', ...
        '08.7 上游诊断缺少固定区域或 evidence。');
end
requiredEvidence = {'faceScale', 'eyeNeighborhood', 'lineSupport', ...
    'lineSupportFromAngleMaxError', 'lineResponse'};
if ~all(isfield(stage.evidence, requiredEvidence)) || ...
        stage.evidence.lineSupportFromAngleMaxError > options.formulaTolerance
    error('diagnoseLashOrientationCoherenceEvidence:InvalidUpstreamEvidence', ...
        '08.7 上游 lineSupport evidence 无效或逐 angle union 不一致。');
end
validateArray(stage.manualLashMask, imageSize, 'manualLashMask');
validateArray(stage.candidate086Support, imageSize, 'candidate086Support');
validateArray(stage.candidate087Support, imageSize, 'candidate087Support');
validateArray(stage.evidence.eyeNeighborhood, imageSize, 'eyeNeighborhood');
validateArray(stage.evidence.lineSupport, imageSize, 'lineSupport');
if ~isfinite(stage.evidence.faceScale) || stage.evidence.faceScale <= 0
    error('diagnoseLashOrientationCoherenceEvidence:InvalidFaceScale', ...
        '上游 faceScale 无效。');
end
end

function image = readInputImage(imagePath)
if ~isfile(imagePath)
    error('diagnoseLashOrientationCoherenceEvidence:MissingImage', ...
        '输入图像不存在：%s。', imagePath);
end
image = imread(imagePath);
if ~isa(image, 'uint8') || ~isreal(image) || ndims(image) ~= 3 || ...
        size(image, 3) ~= 3
    error('diagnoseLashOrientationCoherenceEvidence:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFixed77Fixture(inputImage, options)
if ~isequal(size(inputImage), [450, 512, 3]) || ...
        ~isequal(options.faceBox, [95, 79, 286, 372]) || ...
        ~isequal(options.browEyeRoi, [165, 205, 150, 100]) || ...
        ~isequal(options.lashRoi, [102, 248, 177, 48])
    error('diagnoseLashOrientationCoherenceEvidence:UnexpectedFixture', ...
        'Issue 08.8 必须使用 77.png 的 450x512x3 和固定坐标。');
end
end

function sigma = existingLineSigma(faceScale)
sigma = min(1.35, max(.45, .002 * double(faceScale)));
end

function validateTensorArrays(gradientX, gradientY, gradientMagnitude, ...
        Jxx, Jyy, Jxy, orientation, coherence, tensorEnergy, imageSize)
values = {gradientX, gradientY, gradientMagnitude, Jxx, Jyy, Jxy, ...
    orientation, coherence, tensorEnergy};
names = {'gradientX', 'gradientY', 'gradientMagnitude', 'Jxx', ...
    'Jyy', 'Jxy', 'orientation', 'coherence', 'tensorEnergy'};
for index = 1:numel(values)
    validateArray(values{index}, imageSize, names{index});
end
if any(coherence(:) < 0) || any(coherence(:) > 1) || ...
        any(orientation(:) < -pi / 2 - 1e-12) || ...
        any(orientation(:) > pi / 2 + 1e-12)
    error('diagnoseLashOrientationCoherenceEvidence:InvalidTensorRange', ...
        'coherence 或 orientation 超出理论范围。');
end
end

function groupStats = makeGroupStats(names, descriptions, masks, ...
        coherence, tensorEnergy, validTensorEnergy)
empty = emptyGroupStats();
groupStats = repmat(empty, 0, 1);
for index = 1:numel(names)
    mask = logical(masks{index});
    valid = mask & validTensorEnergy;
    values = double(coherence(valid));
    energy = double(tensorEnergy(valid));
    row = empty;
    row.group = names{index};
    row.description = descriptions{index};
    row.groupPixels = nnz(mask);
    row.validEnergyPixels = nnz(valid);
    row.count = numel(values);
    row.mean = meanOrNaN(values);
    row.median = medianOrNaN(values);
    row.std = stdOrNaN(values);
    row.p10 = percentileOrNaN(values, .10);
    row.p25 = percentileOrNaN(values, .25);
    row.p50 = percentileOrNaN(values, .50);
    row.p75 = percentileOrNaN(values, .75);
    row.p90 = percentileOrNaN(values, .90);
    row.tensorEnergyMean = meanOrNaN(energy);
    row.tensorEnergyMedian = medianOrNaN(energy);
    groupStats(end + 1, 1) = row; %#ok<AGROW>
end
end

function row = emptyGroupStats()
row = struct('group', '', 'description', '', 'groupPixels', 0, ...
    'validEnergyPixels', 0, 'count', 0, 'mean', NaN, 'median', NaN, ...
    'std', NaN, 'p10', NaN, 'p25', NaN, 'p50', NaN, 'p75', NaN, ...
    'p90', NaN, 'tensorEnergyMean', NaN, 'tensorEnergyMedian', NaN);
end

function comparisonStats = makeComparisonStats(names, positiveNames, ...
        negativeNames, positiveMasks, negativeMasks, coherence, ...
        gradientMagnitude, validTensorEnergy, gradientBinSummary)
empty = emptyComparisonStats();
comparisonStats = repmat(empty, 0, 1);
for index = 1:numel(names)
    positive = double(coherence(positiveMasks{index} & validTensorEnergy));
    negative = double(coherence(negativeMasks{index} & validTensorEnergy));
    [auc, u] = rankAuc(positive, negative);
    row = empty;
    row.comparison = names{index};
    row.positiveGroup = positiveNames{index};
    row.negativeGroup = negativeNames{index};
    row.positiveCount = numel(positive);
    row.negativeCount = numel(negative);
    row.positiveMean = meanOrNaN(positive);
    row.negativeMean = meanOrNaN(negative);
    row.positiveMedian = medianOrNaN(positive);
    row.negativeMedian = medianOrNaN(negative);
    row.auc = auc;
    row.mannWhitneyU = u;
    row.rankBiserial = safeTransform(auc, @(value) 2 * value - 1);
    row.positivePearsonGradientCoherence = correlationCoefficient( ...
        gradientMagnitude(positiveMasks{index} & validTensorEnergy), positive);
    row.negativePearsonGradientCoherence = correlationCoefficient( ...
        gradientMagnitude(negativeMasks{index} & validTensorEnergy), negative);
    row.matchedGradientBinCount = NaN;
    row.matchedGradientBinWeightedDelta = NaN;
    row.matchedGradientBinMedianDelta = NaN;
    row.matchedGradientBinPositiveFraction = NaN;
    binSummary = findGradientPairSummary(gradientBinSummary, names{index});
    if ~isempty(binSummary)
        row.matchedGradientBinCount = binSummary.matchedBinCount;
        row.matchedGradientBinWeightedDelta = binSummary.weightedMeanDelta;
        row.matchedGradientBinMedianDelta = binSummary.medianDelta;
        row.matchedGradientBinPositiveFraction = binSummary.positiveFraction;
    end
    comparisonStats(end + 1, 1) = row; %#ok<AGROW>
end
end

function row = emptyComparisonStats()
row = struct('comparison', '', 'positiveGroup', '', 'negativeGroup', '', ...
    'positiveCount', 0, 'negativeCount', 0, 'positiveMean', NaN, ...
    'negativeMean', NaN, 'positiveMedian', NaN, 'negativeMedian', NaN, ...
    'auc', NaN, 'mannWhitneyU', NaN, 'rankBiserial', NaN, ...
    'positivePearsonGradientCoherence', NaN, ...
    'negativePearsonGradientCoherence', NaN, ...
    'matchedGradientBinCount', NaN, ...
    'matchedGradientBinWeightedDelta', NaN, ...
    'matchedGradientBinMedianDelta', NaN, ...
    'matchedGradientBinPositiveFraction', NaN);
end

function [rows, summary] = makeGradientBinStats(coherence, gradientMagnitude, ...
        validTensorEnergy, manualMask, fp086Mask, fp087Mask)
validGradient = validTensorEnergy & isfinite(gradientMagnitude);
if any(validGradient(:))
    maxGradient = max(double(gradientMagnitude(validGradient)));
else
    maxGradient = 1;
end
if ~isfinite(maxGradient) || maxGradient <= 0
    maxGradient = 1;
end
binCount = 10;
edges = linspace(0, maxGradient, binCount + 1);
if numel(unique(edges)) ~= numel(edges)
    edges = linspace(0, 1, binCount + 1);
end
names = {'manual_lash', 'fp08_6', 'fp08_7'};
masks = {manualMask, fp086Mask, fp087Mask};
empty = emptyGradientBinRow();
rows = repmat(empty, 0, 1);
counts = zeros(numel(names), binCount);
means = NaN(numel(names), binCount);
for groupIndex = 1:numel(names)
    for binIndex = 1:binCount
        if binIndex < binCount
            inBin = gradientMagnitude >= edges(binIndex) & ...
                gradientMagnitude < edges(binIndex + 1);
        else
            inBin = gradientMagnitude >= edges(binIndex) & ...
                gradientMagnitude <= edges(binIndex + 1);
        end
        selected = masks{groupIndex} & validTensorEnergy & inBin;
        values = double(coherence(selected));
        counts(groupIndex, binIndex) = numel(values);
        means(groupIndex, binIndex) = meanOrNaN(values);
        row = empty;
        row.group = names{groupIndex};
        row.binIndex = binIndex;
        row.gradientLower = edges(binIndex);
        row.gradientUpper = edges(binIndex + 1);
        row.count = numel(values);
        row.meanCoherence = meanOrNaN(values);
        row.medianCoherence = medianOrNaN(values);
        row.p25Coherence = percentileOrNaN(values, .25);
        row.p75Coherence = percentileOrNaN(values, .75);
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
end
summary = struct( ...
    'gradientMaximum', maxGradient, ...
    'binCount', binCount, ...
    'edges', edges, ...
    'manualVsFp086', summarizeGradientPair(counts(1, :), means(1, :), ...
        counts(2, :), means(2, :), 'manual_vs_fp08_6'), ...
    'manualVsFp087', summarizeGradientPair(counts(1, :), means(1, :), ...
        counts(3, :), means(3, :), 'manual_vs_fp08_7'));
end

function row = emptyGradientBinRow()
row = struct('group', '', 'binIndex', 0, 'gradientLower', NaN, ...
    'gradientUpper', NaN, 'count', 0, 'meanCoherence', NaN, ...
    'medianCoherence', NaN, 'p25Coherence', NaN, 'p75Coherence', NaN);
end

function summary = summarizeGradientPair(posCounts, posMeans, negCounts, ...
        negMeans, name)
matched = posCounts > 0 & negCounts > 0 & ...
    isfinite(posMeans) & isfinite(negMeans);
delta = posMeans(matched) - negMeans(matched);
weights = min(posCounts(matched), negCounts(matched));
if isempty(delta)
    weightedMean = NaN;
    medianDelta = NaN;
    positiveFraction = NaN;
else
    weightedMean = sum(weights .* delta) / sum(weights);
    medianDelta = median(delta);
    positiveFraction = mean(delta > 0);
end
summary = struct('comparison', name, 'matchedBinCount', nnz(matched), ...
    'weightedMeanDelta', weightedMean, 'medianDelta', medianDelta, ...
    'positiveFraction', positiveFraction, 'deltas', delta, ...
    'weights', weights);
end

function summary = findGradientPairSummary(gradientSummary, name)
summary = [];
if strcmp(name, 'manual_vs_fp08_6') || ...
        strcmp(name, 'lineSupport_manual_vs_fp08_6')
    summary = gradientSummary.manualVsFp086;
elseif strcmp(name, 'manual_vs_fp08_7') || ...
        strcmp(name, 'lineSupport_manual_vs_fp08_7')
    summary = gradientSummary.manualVsFp087;
end
end

function continuityStats = makeContinuityStats(names, masks, orientation, valid)
empty = emptyContinuityStats();
continuityStats = repmat(empty, 0, 1);
for index = 1:numel(names)
    differences = collectAxialDifferences(orientation, masks{index}, valid);
    row = empty;
    row.group = names{index};
    row.validPairCount = numel(differences);
    row.meanAxialAngularDifference = meanOrNaN(differences);
    row.medianAxialAngularDifference = medianOrNaN(differences);
    row.p75AxialAngularDifference = percentileOrNaN(differences, .75);
    row.p90AxialAngularDifference = percentileOrNaN(differences, .90);
    row.minAxialAngularDifference = minOrNaN(differences);
    row.maxAxialAngularDifference = maxOrNaN(differences);
    continuityStats(end + 1, 1) = row; %#ok<AGROW>
end
end

function row = emptyContinuityStats()
row = struct('group', '', 'validPairCount', 0, ...
    'meanAxialAngularDifference', NaN, ...
    'medianAxialAngularDifference', NaN, ...
    'p75AxialAngularDifference', NaN, ...
    'p90AxialAngularDifference', NaN, ...
    'minAxialAngularDifference', NaN, ...
    'maxAxialAngularDifference', NaN);
end

function differences = collectAxialDifferences(orientation, mask, valid)
mask = logical(mask) & logical(valid);
left = mask(:, 1:end - 1) & mask(:, 2:end);
differenceHorizontal = axialAngleDifference( ...
    orientation(:, 1:end - 1), orientation(:, 2:end));
differenceHorizontal = differenceHorizontal(left);
up = mask(1:end - 1, :) & mask(2:end, :);
differenceVertical = axialAngleDifference( ...
    orientation(1:end - 1, :), orientation(2:end, :));
differenceVertical = differenceVertical(up);
differences = [double(differenceHorizontal(:)); double(differenceVertical(:))];
end

function difference = axialAngleDifference(first, second)
difference = abs(double(first) - double(second));
difference = mod(difference, pi);
difference = min(difference, pi - difference);
end

function correlations = makeCorrelationStats(names, masks, coherence, ...
        gradientMagnitude, valid)
empty = struct('group', '', 'count', 0, 'pearson', NaN, ...
    'coherenceMean', NaN, 'gradientMagnitudeMean', NaN);
correlations = repmat(empty, 0, 1);
allValues = coherence(valid);
allGradient = gradientMagnitude(valid);
row = empty;
row.group = 'all_valid_tensor_energy';
row.count = numel(allValues);
row.pearson = correlationCoefficient(allGradient, allValues);
row.coherenceMean = meanOrNaN(allValues);
row.gradientMagnitudeMean = meanOrNaN(allGradient);
correlations(end + 1, 1) = row; %#ok<AGROW>
for index = 1:numel(names)
    selected = masks{index} & valid;
    values = coherence(selected);
    gradients = gradientMagnitude(selected);
    row = empty;
    row.group = names{index};
    row.count = numel(values);
    row.pearson = correlationCoefficient(gradients, values);
    row.coherenceMean = meanOrNaN(values);
    row.gradientMagnitudeMean = meanOrNaN(gradients);
    correlations(end + 1, 1) = row; %#ok<AGROW>
end
end

function assessment = assessFeatureSeparation(comparisons, continuity, gradientSummary)
main = comparisons(1:4);
line = comparisons(5:6);
mainAucAboveRandom = [main.auc] > .5;
mainEffectPositive = [main.rankBiserial] > 0;
lineAucAboveRandom = [line.auc] > .5;
coreFalsePositiveAuc = [main(1:2).auc, line.auc];
coreFalsePositiveEffect = [main(1:2).rankBiserial, line.rankBiserial];
continuityManual = continuity(strcmp({continuity.group}, 'manual_lash'));
continuityFp086 = continuity(strcmp({continuity.group}, 'fp08_6'));
continuityFp087 = continuity(strcmp({continuity.group}, 'fp08_7'));
manualContinuityLower = continuityManual.meanAxialAngularDifference < ...
    [continuityFp086.meanAxialAngularDifference, ...
    continuityFp087.meanAxialAngularDifference];
matchedGradientPositive = [ ...
    gradientSummary.manualVsFp086.weightedMeanDelta, ...
    gradientSummary.manualVsFp087.weightedMeanDelta] > 0;
allConditions = all(mainAucAboveRandom) && all(mainEffectPositive) && ...
    all(lineAucAboveRandom) && all(manualContinuityLower) && ...
    all(matchedGradientPositive);
coreCaseAConditions = all(coreFalsePositiveAuc > .5) && ...
    all(coreFalsePositiveEffect > 0) && all(manualContinuityLower) && ...
    all(matchedGradientPositive);
caseCWrongDirection = all(coreFalsePositiveAuc < .5) && ...
    all(coreFalsePositiveEffect < 0) && all(~manualContinuityLower) && ...
    all(~matchedGradientPositive);
if allConditions
    caseName = 'caseA_candidate';
elseif caseCWrongDirection
    caseName = 'caseC_notSeparable';
else
    caseName = 'notCaseA_directionalEvidence';
end
assessment = struct( ...
    'case', caseName, ...
    'mainAucAboveRandom', mainAucAboveRandom, ...
    'mainRankEffectPositive', mainEffectPositive, ...
    'lineSupportAucAboveRandom', lineAucAboveRandom, ...
    'coreFalsePositiveAuc', coreFalsePositiveAuc, ...
    'coreFalsePositiveEffect', coreFalsePositiveEffect, ...
    'coreCaseAConditions', coreCaseAConditions, ...
    'manualContinuityLowerThanFp', manualContinuityLower, ...
    'matchedGradientManualHigherThanFp', matchedGradientPositive, ...
    'caseCWrongDirection', caseCWrongDirection, ...
    'allCaseAConditions', allConditions, ...
    'interpretationBoundary', ...
        '以上仅为离线方向性描述，不产生 production threshold。');
end

function row = makeMetricsRow(options, upstreamSummary, upstream, faceScale, ...
        lineSigma, tensorSigma, manualMask, fp086, fp087, browNonLash, ...
        neighborhoodNonLash, ~, comparisons, continuity, ...
        correlations, gradientSummary, caseAssessment)
row = struct();
row.issue = '08.8';
row.caseName = caseAssessment.case;
row.caseAssessment = caseAssessment.case;
row.faceScale = faceScale;
row.lineSigma = lineSigma;
row.tensorSigma = tensorSigma;
row.manualLashPixels = nnz(manualMask);
row.fp08_6Pixels = nnz(fp086);
row.fp08_7Pixels = nnz(fp087);
row.browEyeNonLashPixels = nnz(browNonLash);
row.eyeNeighborhoodNonLashPixels = nnz(neighborhoodNonLash);
row.lineSupportPixels = nnz(upstream.evidence.lineSupport);
row.lineSupportManualPixels = nnz(manualMask & upstream.evidence.lineSupport);
row.lineSupportFp08_6Pixels = nnz(fp086 & upstream.evidence.lineSupport);
row.lineSupportFp08_7Pixels = nnz(fp087 & upstream.evidence.lineSupport);
row.sourceStageRebuilt = upstreamSummary.sourceStageRebuilt;
row.manualTruthUsedForFeature = false;
row.coherenceThresholdUsed = false;
row.parameterScanUsed = false;
row.tensorEnergyThresholdUsed = false;
row.orientationAngularThresholdUsed = false;
row.manualVsFp086Auc = comparisons(1).auc;
row.manualVsFp087Auc = comparisons(2).auc;
row.manualVsBrowEyeNonLashAuc = comparisons(3).auc;
row.manualVsEyeNeighborhoodNonLashAuc = comparisons(4).auc;
row.lineSupportManualVsFp086Auc = comparisons(5).auc;
row.lineSupportManualVsFp087Auc = comparisons(6).auc;
row.manualVsFp086RankBiserial = comparisons(1).rankBiserial;
row.manualVsFp087RankBiserial = comparisons(2).rankBiserial;
row.manualVsBrowEyeNonLashRankBiserial = comparisons(3).rankBiserial;
row.manualVsEyeNeighborhoodNonLashRankBiserial = comparisons(4).rankBiserial;
row.lineSupportManualVsFp086RankBiserial = comparisons(5).rankBiserial;
row.lineSupportManualVsFp087RankBiserial = comparisons(6).rankBiserial;
row.manualVsFp086MatchedGradientBins = comparisons(1).matchedGradientBinCount;
row.manualVsFp087MatchedGradientBins = comparisons(2).matchedGradientBinCount;
row.manualVsFp086GradientWeightedDelta = comparisons(1).matchedGradientBinWeightedDelta;
row.manualVsFp087GradientWeightedDelta = comparisons(2).matchedGradientBinWeightedDelta;
row.manualVsFp086GradientPositiveFraction = comparisons(1).matchedGradientBinPositiveFraction;
row.manualVsFp087GradientPositiveFraction = comparisons(2).matchedGradientBinPositiveFraction;
row.gradientCoherencePearsonAll = correlations(1).pearson;
row.gradientCoherencePearsonManual = findCorrelation(correlations, 'manual_lash');
row.gradientCoherencePearsonFp086 = findCorrelation(correlations, 'fp08_6');
row.gradientCoherencePearsonFp087 = findCorrelation(correlations, 'fp08_7');
manualContinuity = findContinuity(continuity, 'manual_lash');
fp086Continuity = findContinuity(continuity, 'fp08_6');
fp087Continuity = findContinuity(continuity, 'fp08_7');
row.manualOrientationPairCount = manualContinuity.validPairCount;
row.fp08_6OrientationPairCount = fp086Continuity.validPairCount;
row.fp08_7OrientationPairCount = fp087Continuity.validPairCount;
row.manualOrientationMeanAxialDifference = ...
    manualContinuity.meanAxialAngularDifference;
row.fp08_6OrientationMeanAxialDifference = ...
    fp086Continuity.meanAxialAngularDifference;
row.fp08_7OrientationMeanAxialDifference = ...
    fp087Continuity.meanAxialAngularDifference;
row.manualOrientationMedianAxialDifference = ...
    manualContinuity.medianAxialAngularDifference;
row.fp08_6OrientationMedianAxialDifference = ...
    fp086Continuity.medianAxialAngularDifference;
row.fp08_7OrientationMedianAxialDifference = ...
    fp087Continuity.medianAxialAngularDifference;
row.manualOrientationP75AxialDifference = ...
    manualContinuity.p75AxialAngularDifference;
row.fp08_6OrientationP75AxialDifference = ...
    fp086Continuity.p75AxialAngularDifference;
row.fp08_7OrientationP75AxialDifference = ...
    fp087Continuity.p75AxialAngularDifference;
row.manualOrientationP90AxialDifference = ...
    manualContinuity.p90AxialAngularDifference;
row.fp08_6OrientationP90AxialDifference = ...
    fp086Continuity.p90AxialAngularDifference;
row.fp08_7OrientationP90AxialDifference = ...
    fp087Continuity.p90AxialAngularDifference;
row.gradientBinCount = gradientSummary.binCount;
row.gradientMaximum = gradientSummary.gradientMaximum;
row.caseAConditionsAll = caseAssessment.allCaseAConditions;
row.productionModified = false;
row.upstreamLineSupportUnionMaxError = ...
    upstream.evidence.lineSupportFromAngleMaxError;
row.manualLashMaskAnnotationPixels = upstream.annotation.manualPixelCount;
row.tensorSmoothingScaleSource = ...
    'existing detectLashLines lineImage sigma';
row.outputRequiresNoCandidateSupport = true;
row.outputRequiresNoProductionMask = true;
row.fixedFaceBox = mat2str(options.faceBox);
row.fixedBrowEyeRoi = mat2str(options.browEyeRoi);
row.fixedLashRoi = mat2str(options.lashRoi);
row.fixedManualLashId = '77-manual-lash-v1';
row.sourceDiagnosticPath = upstreamSummary.sourceDiagnosticPath;
end

function value = findCorrelation(rows, name)
index = find(strcmp({rows.group}, name), 1);
if isempty(index)
    value = NaN;
else
    value = rows(index).pearson;
end
end

function row = findContinuity(rows, name)
index = find(strcmp({rows.group}, name), 1);
if isempty(index)
    row = emptyContinuityStats();
else
    row = rows(index);
end
end

function paths = writeArtifacts(outputFolder, lineImage, gradientMagnitude, ...
        coherence, orientation, tensorEnergy, validTensorEnergy, ...
        groupMasks, groupNames, groupDescriptions, coherenceForPlot, ...
        gradientForPlot, continuityNames, continuityMasks, ...
        orientationForPlot, ~)
paths = struct('outputFolder', outputFolder);
paths.lineImage = fullfile(outputFolder, 'line_image.png');
writeScalarMap(lineImage, 'lineImage', paths.lineImage, gray(256), ...
    [min(lineImage(:)), max(lineImage(:))]);
paths.gradientMagnitude = fullfile(outputFolder, 'gradient_magnitude.png');
gradientMax = max(gradientMagnitude(:));
if ~isfinite(gradientMax) || gradientMax <= 0
    gradientMax = 1;
end
writeScalarMap(gradientMagnitude, 'gradientMagnitude', ...
    paths.gradientMagnitude, parula(256), [0, gradientMax]);
paths.tensorCoherence = fullfile(outputFolder, 'tensor_coherence.png');
writeScalarMap(coherence, 'tensor coherence [0,1]', ...
    paths.tensorCoherence, parula(256), [0, 1]);
paths.tensorOrientation = fullfile(outputFolder, 'tensor_orientation.png');
writeOrientationBaseFigure(orientation, coherence, tensorEnergy, ...
    validTensorEnergy, paths.tensorOrientation);

manualIndex = find(strcmp(groupNames, 'manual_lash'), 1);
fp086Index = find(strcmp(groupNames, 'fp08_6'), 1);
fp087Index = find(strcmp(groupNames, 'fp08_7'), 1);
selectedIndices = [manualIndex, fp086Index, fp087Index];
selectedColors = {[1, 0, 0], [1, 0, 1], [0, 1, 1]};
for index = 1:numel(selectedIndices)
    groupIndex = selectedIndices(index);
    groupName = groupNames{groupIndex};
    safeName = strrep(groupName, '_', '_');
    paths.(['coherence_' safeName '_overlay']) = fullfile( ...
        outputFolder, ['coherence_' safeName '_overlay.png']);
    writeCoherenceOverlay(coherence, lineImage, groupMasks{groupIndex}, ...
        groupDescriptions{groupIndex}, selectedColors{index}, ...
        paths.(['coherence_' safeName '_overlay']));
    paths.(['orientation_' safeName '_overlay']) = fullfile( ...
        outputFolder, ['orientation_' safeName '_overlay.png']);
    writeOrientationOverlay(orientation, coherence, tensorEnergy, ...
        validTensorEnergy, groupMasks{groupIndex}, ...
        groupDescriptions{groupIndex}, selectedColors{index}, ...
        paths.(['orientation_' safeName '_overlay']));
end
% 使用 evidence 中规定的精确文件名作为主产物别名。
paths.coherenceManualOverlay = fullfile(outputFolder, ...
    'coherence_manual_overlay.png');
paths.coherence086FpOverlay = fullfile(outputFolder, ...
    'coherence_08_6_fp_overlay.png');
paths.coherence087FpOverlay = fullfile(outputFolder, ...
    'coherence_08_7_fp_overlay.png');
paths.orientationManualOverlay = fullfile(outputFolder, ...
    'orientation_manual_overlay.png');
paths.orientation086FpOverlay = fullfile(outputFolder, ...
    'orientation_08_6_fp_overlay.png');
paths.orientation087FpOverlay = fullfile(outputFolder, ...
    'orientation_08_7_fp_overlay.png');
writeCoherenceOverlay(coherence, lineImage, groupMasks{manualIndex}, ...
    groupDescriptions{manualIndex}, selectedColors{1}, ...
    paths.coherenceManualOverlay);
writeCoherenceOverlay(coherence, lineImage, groupMasks{fp086Index}, ...
    groupDescriptions{fp086Index}, selectedColors{2}, ...
    paths.coherence086FpOverlay);
writeCoherenceOverlay(coherence, lineImage, groupMasks{fp087Index}, ...
    groupDescriptions{fp087Index}, selectedColors{3}, ...
    paths.coherence087FpOverlay);
writeOrientationOverlay(orientation, coherence, tensorEnergy, ...
    validTensorEnergy, groupMasks{manualIndex}, groupDescriptions{manualIndex}, ...
    selectedColors{1}, paths.orientationManualOverlay);
writeOrientationOverlay(orientation, coherence, tensorEnergy, ...
    validTensorEnergy, groupMasks{fp086Index}, groupDescriptions{fp086Index}, ...
    selectedColors{2}, paths.orientation086FpOverlay);
writeOrientationOverlay(orientation, coherence, tensorEnergy, ...
    validTensorEnergy, groupMasks{fp087Index}, groupDescriptions{fp087Index}, ...
    selectedColors{3}, paths.orientation087FpOverlay);

paths.coherenceHistogram = fullfile(outputFolder, ...
    'coherence_histogram.png');
writeCoherenceHistogram(coherenceForPlot, validTensorEnergy, ...
    groupMasks, groupNames, paths.coherenceHistogram);
paths.coherenceEcdf = fullfile(outputFolder, 'coherence_ecdf.png');
writeCoherenceEcdf(coherenceForPlot, validTensorEnergy, groupMasks, ...
    groupNames, paths.coherenceEcdf);
paths.coherenceBoxplot = fullfile(outputFolder, ...
    'coherence_boxplot.png');
writeCoherenceBoxplot(coherenceForPlot, validTensorEnergy, groupMasks, ...
    groupNames, paths.coherenceBoxplot);
paths.coherenceGradientJoint = fullfile(outputFolder, ...
    'coherence_gradient_joint.png');
writeGradientJointFigure(coherenceForPlot, gradientForPlot, ...
    validTensorEnergy, groupMasks, groupNames, paths.coherenceGradientJoint);
paths.coherenceGradientBins = fullfile(outputFolder, ...
    'coherence_by_gradient_bin.png');
writeGradientBinFigure(coherenceForPlot, gradientForPlot, ...
    validTensorEnergy, groupMasks, groupNames, paths.coherenceGradientBins);
paths.orientationContinuityDistribution = fullfile(outputFolder, ...
    'orientation_continuity_distribution.png');
writeContinuityDistribution(orientationForPlot, validTensorEnergy, ...
    continuityMasks, continuityNames, paths.orientationContinuityDistribution);
end

function writeScalarMap(value, titleText, path, colorMap, limits)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1000, 780]);
imagesc(double(value));
axis image off;
caxis(limits);
colormap(colorMap);
colorbar;
title(titleText, 'Interpreter', 'none');
exportgraphics(figureHandle, path, 'Resolution', 160);
close(figureHandle);
end

function writeOrientationBaseFigure(orientation, coherence, tensorEnergy, ...
        valid, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [80, 80, 1900, 800]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imageHandle = imagesc(orientation);
axis image off;
caxis([-pi / 2, pi / 2]);
energyAlpha = double(tensorEnergy ./ max(max(tensorEnergy(:)), eps));
set(imageHandle, 'AlphaData', energyAlpha .* double(valid));
colormap(gca, hsv(256));
colorbar;
title('tensor orientation; alpha=tensor energy');
nexttile;
imagesc(coherence);
axis image off;
caxis([0, 1]);
colormap(gca, parula(256));
colorbar;
title('tensor coherence [0,1]');
exportgraphics(figureHandle, path, 'Resolution', 160);
close(figureHandle);
end

function writeCoherenceOverlay(coherence, lineImage, groupMask, ...
        description, color, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [80, 80, 1800, 760]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imagesc(coherence);
axis image off;
caxis([0, 1]);
colormap(gca, parula(256));
colorbar;
hold on;
drawContourIfPresent(groupMask, color, 1.5);
hold off;
title(['coherence + ' description], 'Interpreter', 'none');
nexttile;
imagesc(lineImage);
axis image off;
caxis([min(lineImage(:)), max(lineImage(:))]);
colormap(gca, gray(256));
hold on;
drawContourIfPresent(groupMask, color, 1.5);
hold off;
title('lineImage + group contour', 'Interpreter', 'none');
exportgraphics(figureHandle, path, 'Resolution', 160);
close(figureHandle);
end

function writeOrientationOverlay(orientation, coherence, tensorEnergy, ...
        valid, groupMask, description, color, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [80, 80, 1800, 760]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imageHandle = imagesc(orientation);
axis image off;
caxis([-pi / 2, pi / 2]);
energyAlpha = double(tensorEnergy ./ max(max(tensorEnergy(:)), eps));
set(imageHandle, 'AlphaData', energyAlpha .* double(valid));
colormap(gca, hsv(256));
colorbar;
hold on;
drawContourIfPresent(groupMask, color, 1.5);
hold off;
title(['orientation + ' description], 'Interpreter', 'none');
nexttile;
imagesc(coherence);
axis image off;
caxis([0, 1]);
colormap(gca, parula(256));
colorbar;
hold on;
drawContourIfPresent(groupMask, color, 1.5);
hold off;
title('coherence and same group contour', 'Interpreter', 'none');
exportgraphics(figureHandle, path, 'Resolution', 160);
close(figureHandle);
end

function writeCoherenceHistogram(coherence, valid, masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1100, 780]);
edges = linspace(0, 1, 41);
centers = (edges(1:end - 1) + edges(2:end)) / 2;
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
selected = {'manual_lash', 'fp08_6', 'fp08_7'};
maxHeight = 0;
hold on;
for index = 1:numel(selected)
    groupIndex = find(strcmp(names, selected{index}), 1);
    values = coherence(masks{groupIndex} & valid);
    counts = histcounts(values, edges);
    if ~isempty(values)
        counts = counts / numel(values);
    end
    maxHeight = max(maxHeight, max(counts));
    plot(centers, counts, 'LineWidth', 2, 'Color', colors(index, :));
end
hold off;
xlim([0, 1]);
ylim([0, max(0.01, maxHeight * 1.10)]);
xlabel('coherence');
ylabel('probability per bin');
legend(labels, 'Location', 'best');
title('coherence histogram; common [0,1] range');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeCoherenceEcdf(coherence, valid, masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1100, 780]);
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
selected = {'manual_lash', 'fp08_6', 'fp08_7'};
hold on;
for index = 1:numel(selected)
    groupIndex = find(strcmp(names, selected{index}), 1);
    values = sort(double(coherence(masks{groupIndex} & valid)));
    if isempty(values)
        continue;
    end
    [uniqueValues, ~, groupIndexValues] = unique(values);
    counts = accumarray(groupIndexValues, 1);
    cumulative = cumsum(counts) / numel(values);
    plot(uniqueValues, cumulative, 'LineWidth', 2, ...
        'Color', colors(index, :));
end
hold off;
xlim([0, 1]);
ylim([0, 1]);
xlabel('coherence');
ylabel('ECDF');
legend(labels, 'Location', 'best');
title('coherence ECDF; common [0,1] range');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeCoherenceBoxplot(coherence, valid, masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1000, 780]);
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
selected = {'manual_lash', 'fp08_6', 'fp08_7'};
hold on;
for index = 1:numel(selected)
    groupIndex = find(strcmp(names, selected{index}), 1);
    values = double(coherence(masks{groupIndex} & valid));
    if isempty(values)
        continue;
    end
    q1 = percentileOrNaN(values, .25);
    q2 = percentileOrNaN(values, .50);
    q3 = percentileOrNaN(values, .75);
    low = min(values);
    high = max(values);
    rectangle('Position', [index - .25, q1, .5, q3 - q1], ...
        'FaceColor', colors(index, :), 'EdgeColor', colors(index, :), ...
        'FaceAlpha', .35, 'LineWidth', 1.5);
    plot([index - .25, index + .25], [q2, q2], ...
        'Color', colors(index, :), 'LineWidth', 2.5);
    plot([index, index], [low, q1], 'Color', colors(index, :), ...
        'LineWidth', 1.5);
    plot([index, index], [q3, high], 'Color', colors(index, :), ...
        'LineWidth', 1.5);
    plot([index - .12, index + .12], [low, low], ...
        'Color', colors(index, :), 'LineWidth', 1.5);
    plot([index - .12, index + .12], [high, high], ...
        'Color', colors(index, :), 'LineWidth', 1.5);
end
hold off;
xlim([.4, 3.6]);
ylim([0, 1]);
set(gca, 'XTick', 1:3, 'XTickLabel', labels);
ylabel('coherence');
title('coherence boxplot; common [0,1] range');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeGradientJointFigure(coherence, gradientMagnitude, valid, ...
        masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1100, 780]);
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
selected = {'manual_lash', 'fp08_6', 'fp08_7'};
gradientMax = max(gradientMagnitude(valid));
if ~isfinite(gradientMax) || gradientMax <= 0
    gradientMax = 1;
end
hold on;
for index = 1:numel(selected)
    groupIndex = find(strcmp(names, selected{index}), 1);
    selectedIndices = find(masks{groupIndex} & valid);
    selectedIndices = deterministicSample(selectedIndices, 4000);
    scatter(gradientMagnitude(selectedIndices), coherence(selectedIndices), ...
        9, colors(index, :), 'filled', 'MarkerFaceAlpha', .25, ...
        'DisplayName', labels{index});
end
hold off;
xlim([0, gradientMax]);
ylim([0, 1]);
xlabel('gradientMagnitude');
ylabel('coherence');
legend('Location', 'best');
title('coherence vs gradientMagnitude; deterministic downsample');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeGradientBinFigure(coherence, gradientMagnitude, valid, ...
        masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1100, 780]);
gradientMax = max(gradientMagnitude(valid));
if ~isfinite(gradientMax) || gradientMax <= 0
    gradientMax = 1;
end
edges = linspace(0, gradientMax, 11);
centers = (edges(1:end - 1) + edges(2:end)) / 2;
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
selected = {'manual_lash', 'fp08_6', 'fp08_7'};
hold on;
for groupIndex = 1:numel(selected)
    sourceIndex = find(strcmp(names, selected{groupIndex}), 1);
    means = NaN(1, numel(centers));
    for binIndex = 1:numel(centers)
        if binIndex < numel(centers)
            inBin = gradientMagnitude >= edges(binIndex) & ...
                gradientMagnitude < edges(binIndex + 1);
        else
            inBin = gradientMagnitude >= edges(binIndex) & ...
                gradientMagnitude <= edges(binIndex + 1);
        end
        values = coherence(masks{sourceIndex} & valid & inBin);
        means(binIndex) = meanOrNaN(values);
    end
    plot(centers, means, '-o', 'LineWidth', 1.8, 'MarkerSize', 5, ...
        'Color', colors(groupIndex, :), 'DisplayName', labels{groupIndex});
end
hold off;
xlim([0, gradientMax]);
ylim([0, 1]);
xlabel('gradientMagnitude bin center');
ylabel('mean coherence within bin');
legend('Location', 'best');
title('coherence within matched gradientMagnitude bins');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeContinuityDistribution(orientation, valid, masks, names, path)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1100, 780]);
edges = linspace(0, pi / 2, 31);
centers = (edges(1:end - 1) + edges(2:end)) / 2;
colors = [0.85, 0.10, 0.10; 0.80, 0.10, 0.80; 0.05, 0.65, 0.75];
labels = {'Manual Lash', '08.6 FP', '08.7 FP'};
hold on;
for index = 1:numel(names)
    values = collectAxialDifferences(orientation, masks{index}, valid);
    counts = histcounts(values, edges);
    if ~isempty(values)
        counts = counts / numel(values);
    end
    plot(centers, counts, 'LineWidth', 2, 'Color', colors(index, :));
end
hold off;
xlim([0, pi / 2]);
yMax = ylim;
if yMax(2) <= 0
    ylim([0, .01]);
end
xlabel('axial angular difference (radians)');
ylabel('probability per pair bin');
legend(labels, 'Location', 'best');
title('orientation continuity; 4-neighbor axial differences');
exportgraphics(figureHandle, path, 'Resolution', 170);
close(figureHandle);
end

function writeMetricsTable(path, row)
writetable(struct2table(row), path);
end

function mask = makeRoiMask(roi, imageSize)
mask = false(imageSize);
x1 = max(1, roi(1));
y1 = max(1, roi(2));
x2 = min(imageSize(2), roi(1) + roi(3) - 1);
y2 = min(imageSize(1), roi(2) + roi(4) - 1);
mask(y1:y2, x1:x2) = true;
end

function drawContourIfPresent(mask, color, lineWidth)
if any(mask(:))
    contour(mask, [0.5, 0.5], 'Color', color, 'LineWidth', lineWidth);
end
end

function values = deterministicSample(indices, maximum)
indices = indices(:);
if numel(indices) <= maximum
    values = indices;
    return;
end
positions = round(linspace(1, numel(indices), maximum));
positions = unique(positions);
values = indices(positions);
end

function [auc, u] = rankAuc(positive, negative)
positive = double(positive(:));
negative = double(negative(:));
if isempty(positive) || isempty(negative)
    auc = NaN;
    u = NaN;
    return;
end
scores = [positive; negative];
[sortedScores, order] = sort(scores, 'ascend');
ranks = zeros(size(scores));
startIndex = 1;
while startIndex <= numel(sortedScores)
    endIndex = startIndex;
    while endIndex < numel(sortedScores) && ...
            sortedScores(endIndex + 1) == sortedScores(startIndex)
        endIndex = endIndex + 1;
    end
    ranks(order(startIndex:endIndex)) = (startIndex + endIndex) / 2;
    startIndex = endIndex + 1;
end
positiveRankSum = sum(ranks(1:numel(positive)));
u = positiveRankSum - numel(positive) * (numel(positive) + 1) / 2;
auc = u / (numel(positive) * numel(negative));
end

function value = correlationCoefficient(first, second)
first = double(first(:));
second = double(second(:));
if numel(first) ~= numel(second) || numel(first) < 2 || ...
        any(~isfinite(first)) || any(~isfinite(second))
    value = NaN;
    return;
end
first = first - mean(first);
second = second - mean(second);
denominator = sqrt(sum(first .^ 2) * sum(second .^ 2));
if denominator <= 0 || ~isfinite(denominator)
    value = NaN;
else
    value = sum(first .* second) / denominator;
end
end

function value = meanOrNaN(values)
values = double(values(:));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = medianOrNaN(values)
values = double(values(:));
if isempty(values)
    value = NaN;
else
    value = median(values);
end
end

function value = stdOrNaN(values)
values = double(values(:));
if numel(values) < 2
    value = NaN;
else
    value = std(values);
end
end

function value = minOrNaN(values)
values = double(values(:));
if isempty(values)
    value = NaN;
else
    value = min(values);
end
end

function value = maxOrNaN(values)
values = double(values(:));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function value = percentileOrNaN(values, fraction)
values = sort(double(values(:)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + fraction * (numel(values) - 1);
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    value = values(lower) + (position - lower) * ...
        (values(upper) - values(lower));
end
end

function value = safeTransform(value, transform)
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = NaN;
else
    value = transform(value);
end
end

function outputFolder = normalizeOutputFolder(value)
if nargin < 1 || isempty(value)
    value = fullfile(tempdir, ...
        'image_beauty_issue08_8_lash_orientation_coherence_20260919');
end
outputFolder = normalizeText(value, 'outputFolder');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
end

function value = normalizeText(value, name)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || size(value, 1) ~= 1
    error('diagnoseLashOrientationCoherenceEvidence:InvalidText', ...
        '%s 必须是单行文本。', name);
end
end

function validateArray(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(double(value(:))))
    error('diagnoseLashOrientationCoherenceEvidence:InvalidArray', ...
        '%s 尺寸或取值无效。', name);
end
end
