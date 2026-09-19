function [summary, diagnostics] = diagnoseResidualEyelashCoverageAttribution( ...
        imagePath, outputFolder, options)
%DIAGNOSERESIDUALEYELASHCOVERAGEATTRIBUTION 验证 Issue 08.2 空间对应关系。
%   本入口固定复用 77.png、faceBox、browEye 和 lashRoi，先在不读取任何
%   保护结果或 Repair delta 的前提下加载固定 manualLashMask，再调用一次
%   Issue 08.1 生产诊断入口取得同一次运行的 frequency、Protection Mask、
%   Smoothing 和 Repair 产物。随后只做离线空间叠加与统计，不修改生产公式。
%
%   [summary, diagnostics] = diagnoseResidualEyelashCoverageAttribution( ...
%       'E:\image_beauty\人脸\人脸\77.png', tempdir, struct( ...
%       'lashRoi', [102 248 177 48]));
%
%   分类只使用 Issue 08.1 已存在的 nonzeroTolerance 区分严格零值，
%   再比较固定 manualLashMask 内的保护覆盖和 Repair Fine/Mid 作用量；
%   不新增高/中/低经验阈值，不把 delta 非零直接等同于视觉损伤。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
if nargin < 2
    outputFolder = [];
end
if nargin < 3
    options = [];
end
options = normalizeOptions(options, projectRoot);

if nargin < 1 || isempty(imagePath)
    error('diagnoseResidualEyelashCoverageAttribution:MissingImage', ...
        '必须提供固定 77.png 的输入图像路径。');
end
imagePath = normalizeText(imagePath, 'imagePath');
inputImage = readInputImage(imagePath);
imageSize = [size(inputImage, 1), size(inputImage, 2)];
validateFixed77Fixture(inputImage, options);

% 关键顺序：manualLashMask 先于任何 Protection Mask、Repair delta 或
% 诊断结果创建，并且 helper 本身只接收尺寸和人工 ROI。
[manualLashMask, annotation] = eyelashManualLashMask77( ...
    imageSize, options.lashRoi);
if ~annotation.diagnosticsIndependent || ~annotation.fixedAfterAnnotation
    error('diagnoseResidualEyelashCoverageAttribution:InvalidManualTruth', ...
        'manualLashMask 必须声明为独立且固定的人工真值。');
end

outputFolder = normalizeOutputFolder(outputFolder);
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
baseOutputFolder = fullfile(outputFolder, 'issue08_1_base');
baseOptions = options;
baseOptions.strictFixed77 = true;
[baseSummary, baseDiagnostics] = diagnoseResidualEyelashLoss( ...
    imagePath, baseOutputFolder, baseOptions);
validateBaseRun(baseSummary, baseDiagnostics, imageSize, options);

masks = baseDiagnostics.masks;
deltas = baseDiagnostics.deltas;
probes = baseDiagnostics.probes;
metrics = makeCoverageMetrics(manualLashMask, masks, deltas, ...
    baseSummary.nonzeroTolerance);
caseAssessment = classifyCoverageCase(metrics);
metrics.caseAssessment = caseAssessment;

paths = writeArtifacts(outputFolder, inputImage, manualLashMask, annotation, ...
    masks, deltas, metrics, options);
paths.baseOutputFolder = baseOutputFolder;
paths.data = fullfile(outputFolder, 'eyelash_coverage_attribution.mat');

summary = struct( ...
    'completed', true, ...
    'issue', '08.2', ...
    'case', caseAssessment.case, ...
    'caseAssessment', caseAssessment, ...
    'contract', baseSummary.contract, ...
    'imagePath', imagePath, ...
    'inputSize', size(inputImage), ...
    'faceBox', double(options.faceBox), ...
    'browEye', double(options.browEyeRoi), ...
    'lashRoi', double(options.lashRoi), ...
    'manualLashMaskId', annotation.annotationId, ...
    'manualLashMaskIndependent', annotation.diagnosticsIndependent, ...
    'manualLashMaskFixed', annotation.fixedAfterAnnotation, ...
    'manualLashMaskPixels', nnz(manualLashMask), ...
    'baseIssue', baseSummary.issue, ...
    'runtimeCacheReused', baseSummary.runtimeCacheReused, ...
    'sameMaskRun', baseSummary.sameMaskRun, ...
    'baseToneWhiteningDisabled', baseSummary.baseToneWhiteningDisabled, ...
    'originalReconstructionMaxError', ...
        baseSummary.originalReconstructionMaxError, ...
    'reconstructionTolerance', baseSummary.reconstructionTolerance, ...
    'nonzeroTolerance', baseSummary.nonzeroTolerance, ...
    'protectionStrongThreshold', baseSummary.protectionStrongThreshold, ...
    'metrics', metrics, ...
    'paths', paths);

diagnosticData = struct( ...
    'summary', summary, ...
    'baseSummary', baseSummary, ...
    'annotation', annotation, ...
    'inputImage', inputImage, ...
    'manualLashMask', manualLashMask, ...
    'masks', masks, ...
    'deltas', deltas, ...
    'metrics', metrics, ...
    'probes', probes, ...
    'baseDiagnostics', baseDiagnostics);
save(paths.data, 'diagnosticData', '-v7.3');
diagnostics = diagnosticData;

diagnostics.paths = paths;
summary.paths = paths;

fprintf('Issue 08.2 睫毛覆盖归因产物：%s\n', outputFolder);
fprintf('manualLashMask 像素：%d；soft support 覆盖：%.6f；空洞：%d\n', ...
    metrics.manualLashPixels, metrics.softSupportCoverageFraction, ...
    metrics.uncoveredPixels);
fprintf('Repair Fine 未覆盖/已覆盖绝对作用量：%.17g / %.17g\n', ...
    metrics.uncovered.repairFineMass, metrics.covered.repairFineMass);
fprintf('Repair Mid 未覆盖/已覆盖绝对作用量：%.17g / %.17g\n', ...
    metrics.uncovered.repairMidMass, metrics.covered.repairMidMass);
fprintf('空间归因：Case %s；%s\n', caseAssessment.case, ...
    caseAssessment.reason);
end

function options = normalizeOptions(options, projectRoot)
if nargin < 1 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('diagnoseResidualEyelashCoverageAttribution:InvalidOptions', ...
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
        error('diagnoseResidualEyelashCoverageAttribution:NonFixedFixture', ...
            '%s 必须复用 Issue 08.1 固定值。', name);
    end
end
options.faceBox = double(options.faceBox);
options.browEyeRoi = double(options.browEyeRoi);
options.lashRoi = double(options.lashRoi);

if ~isfield(options, 'smoothingStrength') || isempty(options.smoothingStrength)
    options.smoothingStrength = 100;
end
if ~isfield(options, 'whiteningStrength') || isempty(options.whiteningStrength)
    options.whiteningStrength = 15;
end
if ~isValidStrength(options.smoothingStrength) || ...
        ~isValidStrength(options.whiteningStrength)
    error('diagnoseResidualEyelashCoverageAttribution:InvalidStrength', ...
        '强度必须是 0 到 100 的有限数值标量。');
end
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
if ~isfield(options, 'protectionStrongThreshold') || ...
        isempty(options.protectionStrongThreshold)
    options.protectionStrongThreshold = .50;
end
if ~isscalar(options.protectionStrongThreshold) || ...
        ~isfinite(options.protectionStrongThreshold) || ...
        options.protectionStrongThreshold <= 0 || ...
        options.protectionStrongThreshold > 1
    error('diagnoseResidualEyelashCoverageAttribution:InvalidOptions', ...
        'protectionStrongThreshold 必须是 (0, 1] 内的有限标量。');
end
options.protectionStrongThreshold = double(options.protectionStrongThreshold);
options.strictFixed77 = true;
end

function validateFixed77Fixture(inputImage, options)
if ~isequal(size(inputImage), [450, 512, 3])
    error('diagnoseResidualEyelashCoverageAttribution:UnexpectedFixture', ...
        'Issue 08.2 固定输入必须是 77.png 的 450x512x3。');
end
if ~isequal(options.faceBox, [95, 79, 286, 372]) || ...
        ~isequal(options.browEyeRoi, [165, 205, 150, 100]) || ...
        ~isequal(options.lashRoi, [102, 248, 177, 48])
    error('diagnoseResidualEyelashCoverageAttribution:NonFixedFixture', ...
        'Issue 08.2 必须复用 Issue 08.1 固定坐标。');
end
end

function validateBaseRun(baseSummary, baseDiagnostics, imageSize, options)
if ~baseSummary.completed || ~strcmp(baseSummary.issue, '08.1') || ...
        ~baseSummary.sameMaskRun || baseSummary.runtimeCacheReused || ...
        ~baseSummary.baseToneWhiteningDisabled
    error('diagnoseResidualEyelashCoverageAttribution:InvalidBaseRun', ...
        'Issue 08.2 未取得满足连续链路约束的 Issue 08.1 基线。');
end
if ~isequal(baseSummary.faceBox, options.faceBox) || ...
        ~isequal(baseSummary.browEye, options.browEyeRoi) || ...
        ~isequal(baseSummary.lashRoi, options.lashRoi)
    error('diagnoseResidualEyelashCoverageAttribution:BaseCoordinateMismatch', ...
        'Issue 08.1 基线坐标与本票固定坐标不一致。');
end
requiredMasks = {'textureProtectionMask', 'eyeDetailProtection', ...
    'lashProtection', 'doubleEyelidProtection', 'hardProtectionMask'};
if ~isstruct(baseDiagnostics) || ~isfield(baseDiagnostics, 'masks') || ...
        ~all(isfield(baseDiagnostics.masks, requiredMasks))
    error('diagnoseResidualEyelashCoverageAttribution:MissingBaseMasks', ...
        'Issue 08.1 基线缺少本票所需 Protection Mask。');
end
requiredDeltas = {'repairFine', 'repairMid', 'smoothFine', 'smoothMid'};
if ~isfield(baseDiagnostics, 'deltas') || ...
        ~all(isfield(baseDiagnostics.deltas, requiredDeltas))
    error('diagnoseResidualEyelashCoverageAttribution:MissingBaseDeltas', ...
        'Issue 08.1 基线缺少本票所需 Fine/Mid delta。');
end
for index = 1:numel(requiredMasks)
    value = baseDiagnostics.masks.(requiredMasks{index});
    if ~isequal(size(value), imageSize) || any(~isfinite(value(:)))
        error('diagnoseResidualEyelashCoverageAttribution:InvalidBaseArray', ...
            'Protection Mask 尺寸或取值无效：%s。', requiredMasks{index});
    end
end
for index = 1:numel(requiredDeltas)
    value = baseDiagnostics.deltas.(requiredDeltas{index});
    if ~isequal(size(value), imageSize) || any(~isfinite(value(:)))
        error('diagnoseResidualEyelashCoverageAttribution:InvalidBaseArray', ...
            'Fine/Mid delta 尺寸或取值无效：%s。', requiredDeltas{index});
    end
end
end

function metrics = makeCoverageMetrics(manualMask, masks, deltas, nonzeroTolerance)
softProtectionUnion = max(cat(3, ...
    double(masks.textureProtectionMask), ...
    double(masks.eyeDetailProtection), ...
    double(masks.lashProtection)), [], 3);
softSupported = softProtectionUnion > nonzeroTolerance;
coveredMask = manualMask & softSupported;
uncoveredMask = manualMask & ~softSupported;

repairFineAbs = abs(double(deltas.repairFine));
repairMidAbs = abs(double(deltas.repairMid));
repairActionAbs = repairFineAbs + repairMidAbs;
repairFineActionMask = repairFineAbs > nonzeroTolerance;
repairMidActionMask = repairMidAbs > nonzeroTolerance;
repairActionMask = repairFineActionMask | repairMidActionMask;

manualStats = makeScopeStats(manualMask, softProtectionUnion, ...
    masks, repairFineAbs, repairMidAbs, repairActionAbs, ...
    repairFineActionMask | repairMidActionMask);
coveredStats = makeScopeStats(coveredMask, softProtectionUnion, ...
    masks, repairFineAbs, repairMidAbs, repairActionAbs, ...
    repairFineActionMask | repairMidActionMask);
uncoveredStats = makeScopeStats(uncoveredMask, softProtectionUnion, ...
    masks, repairFineAbs, repairMidAbs, repairActionAbs, ...
    repairFineActionMask | repairMidActionMask);

% 逐阶段 action mask 单独保留，避免把 Fine/Mid 的存在直接压成一个
% "损伤" 分数；这里的统计只表示同一运行中的绝对频率作用量。
manualStats.repairFineActionPixels = nnz(manualMask & repairFineActionMask);
manualStats.repairMidActionPixels = nnz(manualMask & repairMidActionMask);
coveredStats.repairFineActionPixels = nnz(coveredMask & repairFineActionMask);
coveredStats.repairMidActionPixels = nnz(coveredMask & repairMidActionMask);
uncoveredStats.repairFineActionPixels = nnz(uncoveredMask & repairFineActionMask);
uncoveredStats.repairMidActionPixels = nnz(uncoveredMask & repairMidActionMask);

manualPixels = nnz(manualMask);
coveredPixels = nnz(coveredMask);
uncoveredPixels = nnz(uncoveredMask);
metrics = struct( ...
    'manualLashPixels', manualPixels, ...
    'coveredPixels', coveredPixels, ...
    'uncoveredPixels', uncoveredPixels, ...
    'softSupportCoverageFraction', safeFraction(coveredPixels, manualPixels), ...
    'softSupportHoleFraction', safeFraction(uncoveredPixels, manualPixels), ...
    'softProtectionUnion', softProtectionUnion, ...
    'softSupportedMask', softSupported, ...
    'coveredMask', coveredMask, ...
    'uncoveredMask', uncoveredMask, ...
    'repairFineAbs', repairFineAbs, ...
    'repairMidAbs', repairMidAbs, ...
    'repairActionAbs', repairActionAbs, ...
    'repairFineActionMask', repairFineActionMask, ...
    'repairMidActionMask', repairMidActionMask, ...
    'repairActionMask', repairActionMask, ...
    'manual', manualStats, ...
    'covered', coveredStats, ...
    'uncovered', uncoveredStats);
end

function stats = makeScopeStats(scopeMask, softUnion, masks, ...
        repairFineAbs, repairMidAbs, repairActionAbs, repairActionMask)
values = double(softUnion(scopeMask));
if isempty(values)
    softMean = NaN;
    softMin = NaN;
    softMax = NaN;
else
    softMean = mean(values);
    softMin = min(values);
    softMax = max(values);
end
stats = struct( ...
    'pixels', nnz(scopeMask), ...
    'softUnionMean', softMean, ...
    'softUnionMin', softMin, ...
    'softUnionMax', softMax, ...
    'textureMean', meanOn(masks.textureProtectionMask, scopeMask), ...
    'textureNonzeroFraction', fractionOfAny( ...
        masks.textureProtectionMask > 0, scopeMask), ...
    'eyeDetailMean', meanOn(masks.eyeDetailProtection, scopeMask), ...
    'eyeDetailNonzeroFraction', fractionOfAny( ...
        masks.eyeDetailProtection > 0, scopeMask), ...
    'lashMean', meanOn(masks.lashProtection, scopeMask), ...
    'lashNonzeroFraction', fractionOfAny( ...
        masks.lashProtection > 0, scopeMask), ...
    'doubleEyelidMean', meanOn(masks.doubleEyelidProtection, scopeMask), ...
    'doubleEyelidNonzeroFraction', fractionOfAny( ...
        masks.doubleEyelidProtection > 0, scopeMask), ...
    'hardProtectionFraction', fractionOfAny( ...
        masks.hardProtectionMask >= .999, scopeMask), ...
    'lashCoreFraction', fractionOfAny(masks.lashCore, scopeMask), ...
    'repairFineMeanAbs', meanOn(repairFineAbs, scopeMask), ...
    'repairFineMaxAbs', maxOn(repairFineAbs, scopeMask), ...
    'repairFineMass', sumOn(repairFineAbs, scopeMask), ...
    'repairMidMeanAbs', meanOn(repairMidAbs, scopeMask), ...
    'repairMidMaxAbs', maxOn(repairMidAbs, scopeMask), ...
    'repairMidMass', sumOn(repairMidAbs, scopeMask), ...
    'repairActionMeanAbs', meanOn(repairActionAbs, scopeMask), ...
    'repairActionMaxAbs', maxOn(repairActionAbs, scopeMask), ...
    'repairActionMass', sumOn(repairActionAbs, scopeMask), ...
    'repairActionNonzeroFraction', fractionOfAny(repairActionMask, scopeMask));
end

function assessment = classifyCoverageCase(metrics)
covered = metrics.covered;
uncovered = metrics.uncovered;

% 只用零值分流和直接空间量比较：不引入新的高/中/低经验阈值。
% "覆盖占多数"使用几何意义上的像素多数关系，Repair 作用量必须按
% Fine/Mid 分阶段比较；最终仍需结合输出图进行人工视觉核对。
uncoveredDominatesFine = uncovered.repairFineMass >= covered.repairFineMass;
uncoveredDominatesMid = uncovered.repairMidMass >= covered.repairMidMass;
coveredDominatesFine = covered.repairFineMass >= uncovered.repairFineMass;
coveredDominatesMid = covered.repairMidMass >= uncovered.repairMidMass;
coveredIsMajority = covered.pixels > uncovered.pixels;

% Fine 与 Mid 必须分别满足同一分流方向；不能用合计值掩盖一个阶段
% 落在空洞、另一个阶段落在已覆盖区域的混合情况。
if uncovered.pixels > 0 && uncoveredDominatesFine && uncoveredDominatesMid
    caseName = 'A';
    reason = ['真实睫毛存在保护空洞，且 Repair Fine 与 Repair Mid 的绝对 ', ...
        '作用量均不低于已覆盖区域；两阶段都指向未覆盖空间。'];
elseif coveredIsMajority && coveredDominatesFine && coveredDominatesMid
    caseName = 'B';
    reason = ['真实睫毛 soft support 覆盖占多数，且 Repair Fine 与 Repair Mid ', ...
        '的绝对作用量均主要落在已覆盖真实睫毛上。'];
else
    caseName = 'C';
    reason = ['Repair Fine 与 Repair Mid 没有同时指向同一类保护空间，或 ', ...
        '覆盖与作用量的对应关系不足以支持 Case A/Case B。'];
end

assessment = struct( ...
    'case', caseName, ...
    'reason', reason, ...
    'classificationBasis', ['固定 manualLashMask 内的 Protection Mask 连续值、', ...
        '严格非零支持和 Fine/Mid 绝对作用量；只复用 Issue 08.1 ', ...
        'nonzeroTolerance，不把 delta 非零直接定义为视觉损伤。'], ...
    'requiresVisualReview', true, ...
    'uncoveredRepairFineMass', uncovered.repairFineMass, ...
    'coveredRepairFineMass', covered.repairFineMass, ...
    'uncoveredRepairMidMass', uncovered.repairMidMass, ...
    'coveredRepairMidMass', covered.repairMidMass, ...
    'uncoveredRepairActionMass', uncovered.repairActionMass, ...
    'coveredRepairActionMass', covered.repairActionMass, ...
    'softSupportCoverageFraction', metrics.softSupportCoverageFraction, ...
    'softSupportHoleFraction', metrics.softSupportHoleFraction);
end

function paths = writeArtifacts(outputFolder, inputImage, manualMask, ...
        annotation, masks, deltas, metrics, options)
box = options.lashRoi;
originalCrop = cropImage(inputImage, box);
manualCrop = cropImage(manualMask, box);
paths = struct('outputFolder', outputFolder);

paths.manualMask = fullfile(outputFolder, 'eyelash_manual_lash_mask.png');
writePng(uint8(255 * double(manualCrop)), paths.manualMask);
paths.manualOverlay = fullfile(outputFolder, ...
    'eyelash_manual_lash_overlay.png');
writeManualOverlay(originalCrop, manualCrop, annotation, paths.manualOverlay);

protectionNames = {'textureProtectionMask', 'lashProtection', ...
    'eyeDetailProtection'};
protectionLabels = {'textureProtectionMask', 'lashProtection', ...
    'eyeDetailProtection'};
protectionFileNames = {'texture_protection', 'lash_protection', ...
    'eye_detail_protection'};
for index = 1:numel(protectionNames)
    name = protectionNames{index};
    path = fullfile(outputFolder, ...
        ['eyelash_manual_vs_' protectionFileNames{index} '.png']);
    writeMapOverlay(originalCrop, manualCrop, ...
        cropImage(masks.(name), box), protectionLabels{index}, ...
        options.protectionStrongThreshold, path);
    paths.(name) = path;
end

paths.repairFine = fullfile(outputFolder, ...
    'eyelash_manual_vs_repair_fine.png');
writeDeltaOverlay(originalCrop, manualCrop, ...
    cropImage(deltas.repairFine, box), 'Repair Fine delta', ...
    paths.repairFine);
paths.repairMid = fullfile(outputFolder, ...
    'eyelash_manual_vs_repair_mid.png');
writeDeltaOverlay(originalCrop, manualCrop, ...
    cropImage(deltas.repairMid, box), 'Repair Mid delta', ...
    paths.repairMid);

paths.coreOverlay = fullfile(outputFolder, ...
    'eyelash_manual_protection_repair_overlay.png');
writeCoreOverlay(originalCrop, manualCrop, masks, deltas, metrics, box, ...
    options, paths.coreOverlay);

rows = makeCsvRows(metrics);
paths.csv = fullfile(outputFolder, 'eyelash_coverage_attribution.csv');
writetable(struct2table(rows), paths.csv);

% 该文件明确保存人工真值与同一次生产运行的诊断量，便于后续候选
% 重复使用同一份 manualLashMask，而不重新标注。
paths.annotation = annotation;
end

function writeManualOverlay(originalCrop, manualCrop, annotation, outputPath)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1300, 520]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imshow(originalCrop);
hold on;
drawContourIfPresent(manualCrop, 'r', 1.8);
hold off;
title(['原图 + manualLashMask 边界；' annotation.annotationId], ...
    'Interpreter', 'none');
nexttile;
imagesc(manualCrop);
axis image off;
colormap(gca, gray(256));
clim([0, 1]);
colorbar;
title('固定人工真值 mask', 'Interpreter', 'none');
exportgraphics(figureHandle, outputPath, 'Resolution', 170);
close(figureHandle);
end

function writeMapOverlay(originalCrop, manualCrop, mapCrop, label, ...
        contourThreshold, outputPath)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1300, 520]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imshow(originalCrop);
hold on;
drawContourIfPresent(manualCrop, 'r', 1.8);
drawContourIfPresent(mapCrop >= contourThreshold, 'c', 1.2);
hold off;
title(['原图 + manual 红边界 + ' label ' 青边界'], ...
    'Interpreter', 'none');
nexttile;
imagesc(mapCrop);
axis image off;
clim([0, 1]);
colorbar;
hold on;
drawContourIfPresent(manualCrop, 'r', 1.5);
hold off;
title([label '；连续值，边界复用 Issue 08.1 .50'], ...
    'Interpreter', 'none');
exportgraphics(figureHandle, outputPath, 'Resolution', 170);
close(figureHandle);
end

function writeDeltaOverlay(originalCrop, manualCrop, deltaCrop, label, outputPath)
absoluteDelta = abs(double(deltaCrop));
deltaScale = max([1e-6; absoluteDelta(:)]);
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1300, 520]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile;
imshow(originalCrop);
hold on;
drawContourIfPresent(manualCrop, 'r', 1.8);
hold off;
title(['原图 + manual 红边界 + ' label ''], 'Interpreter', 'none');
nexttile;
imagesc(absoluteDelta);
axis image off;
clim([0, deltaScale]);
colorbar;
hold on;
drawContourIfPresent(manualCrop, 'r', 1.5);
hold off;
title([label '；连续绝对作用量'], 'Interpreter', 'none');
exportgraphics(figureHandle, outputPath, 'Resolution', 170);
close(figureHandle);
end

function writeCoreOverlay(originalCrop, manualCrop, masks, deltas, ...
        metrics, box, options, outputPath)
textureCrop = cropImage(masks.textureProtectionMask, box);
eyeCrop = cropImage(masks.eyeDetailProtection, box);
lashCrop = cropImage(masks.lashProtection, box);
hardCrop = cropImage(masks.hardProtectionMask, box);
fineCrop = abs(cropImage(deltas.repairFine, box));
midCrop = abs(cropImage(deltas.repairMid, box));
uncoveredCrop = cropImage(metrics.uncoveredMask, box);
coveredCrop = cropImage(metrics.coveredMask, box);
repairActionCrop = cropImage(metrics.repairActionMask, box);

figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [80, 80, 1700, 1050]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imshow(originalCrop);
hold on;
drawContourIfPresent(manualCrop, 'r', 1.8);
drawContourIfPresent(textureCrop >= options.protectionStrongThreshold, 'b', 1.1);
drawContourIfPresent(eyeCrop >= options.protectionStrongThreshold, 'g', 1.1);
drawContourIfPresent(lashCrop >= options.protectionStrongThreshold, 'c', 1.1);
drawContourIfPresent(hardCrop >= .999, 'm', 1.1);
hold off;
title('原图：manual / texture / eye-detail / lash / hard 边界');

nexttile;
imagesc(fineCrop);
axis image off;
clim([0, max([1e-6; fineCrop(:)])]);
colorbar;
hold on;
drawContourIfPresent(manualCrop, 'r', 1.6);
drawContourIfPresent(uncoveredCrop, 'w', 1.1);
hold off;
title('Repair Fine 绝对作用量；红=真值，白=soft 空洞');

nexttile;
imagesc(midCrop);
axis image off;
clim([0, max([1e-6; midCrop(:)])]);
colorbar;
hold on;
drawContourIfPresent(manualCrop, 'r', 1.6);
drawContourIfPresent(uncoveredCrop, 'w', 1.1);
hold off;
title('Repair Mid 绝对作用量；红=真值，白=soft 空洞');

nexttile;
base = im2double(originalCrop);
base = blendMask(base, uncoveredCrop, [1, 0, 0], .75);
base = blendMask(base, coveredCrop, [0, 1, 0], .45);
base = blendMask(base, repairActionCrop, [1, 1, 0], .70);
imshow(base);
hold on;
drawContourIfPresent(manualCrop, 'r', 1.5);
drawContourIfPresent(repairActionCrop, 'y', 1.2);
hold off;
title('核心空间叠加：红=空洞真值，绿=已有 soft，黄=Repair Fine/Mid');

exportgraphics(figureHandle, outputPath, 'Resolution', 170);
close(figureHandle);
end

function rows = makeCsvRows(metrics)
scopes = {'manualLash', 'coveredBySoftSupport', 'uncoveredProtectionHole'};
values = {metrics.manual, metrics.covered, metrics.uncovered};
rows = repmat(emptyCsvRow(), numel(scopes), 1);
for index = 1:numel(scopes)
    value = values{index};
    row = emptyCsvRow();
    row.scope = scopes{index};
    row.pixels = value.pixels;
    row.pixelFractionOfManual = safeFraction(value.pixels, ...
        metrics.manualLashPixels);
    row.softUnionMean = value.softUnionMean;
    row.softUnionMin = value.softUnionMin;
    row.softUnionMax = value.softUnionMax;
    row.textureMean = value.textureMean;
    row.textureNonzeroFraction = value.textureNonzeroFraction;
    row.eyeDetailMean = value.eyeDetailMean;
    row.eyeDetailNonzeroFraction = value.eyeDetailNonzeroFraction;
    row.lashMean = value.lashMean;
    row.lashNonzeroFraction = value.lashNonzeroFraction;
    row.doubleEyelidMean = value.doubleEyelidMean;
    row.doubleEyelidNonzeroFraction = value.doubleEyelidNonzeroFraction;
    row.hardProtectionFraction = value.hardProtectionFraction;
    row.lashCoreFraction = value.lashCoreFraction;
    row.repairFineMeanAbs = value.repairFineMeanAbs;
    row.repairFineMaxAbs = value.repairFineMaxAbs;
    row.repairFineMass = value.repairFineMass;
    row.repairFineActionPixels = value.repairFineActionPixels;
    row.repairMidMeanAbs = value.repairMidMeanAbs;
    row.repairMidMaxAbs = value.repairMidMaxAbs;
    row.repairMidMass = value.repairMidMass;
    row.repairMidActionPixels = value.repairMidActionPixels;
    row.repairActionMeanAbs = value.repairActionMeanAbs;
    row.repairActionMaxAbs = value.repairActionMaxAbs;
    row.repairActionMass = value.repairActionMass;
    row.repairActionNonzeroFraction = value.repairActionNonzeroFraction;
    rows(index) = row;
end
end

function row = emptyCsvRow()
row = struct( ...
    'scope', '', 'pixels', 0, 'pixelFractionOfManual', NaN, ...
    'softUnionMean', NaN, 'softUnionMin', NaN, 'softUnionMax', NaN, ...
    'textureMean', NaN, 'textureNonzeroFraction', NaN, ...
    'eyeDetailMean', NaN, 'eyeDetailNonzeroFraction', NaN, ...
    'lashMean', NaN, 'lashNonzeroFraction', NaN, ...
    'doubleEyelidMean', NaN, 'doubleEyelidNonzeroFraction', NaN, ...
    'hardProtectionFraction', NaN, 'lashCoreFraction', NaN, ...
    'repairFineMeanAbs', NaN, 'repairFineMaxAbs', NaN, ...
    'repairFineMass', NaN, 'repairFineActionPixels', 0, ...
    'repairMidMeanAbs', NaN, 'repairMidMaxAbs', NaN, ...
    'repairMidMass', NaN, 'repairMidActionPixels', 0, ...
    'repairActionMeanAbs', NaN, 'repairActionMaxAbs', NaN, ...
    'repairActionMass', NaN, 'repairActionNonzeroFraction', NaN);
end

function mask = cropImage(image, box)
x1 = box(1);
y1 = box(2);
x2 = min(size(image, 2), x1 + box(3) - 1);
y2 = min(size(image, 1), y1 + box(4) - 1);
if ismatrix(image)
    mask = image(y1:y2, x1:x2);
else
    mask = image(y1:y2, x1:x2, :);
end
end

function drawContourIfPresent(mask, color, lineWidth)
if any(mask(:))
    contour(mask, [0.5, 0.5], color, 'LineWidth', lineWidth);
end
end

function image = blendMask(image, mask, color, alpha)
mask = logical(mask);
for channel = 1:3
    plane = image(:, :, channel);
    plane(mask) = (1 - alpha) * plane(mask) + alpha * color(channel);
    image(:, :, channel) = plane;
end
end

function value = meanOn(data, mask)
values = double(data(mask));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = maxOn(data, mask)
values = double(data(mask));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function value = sumOn(data, mask)
values = double(data(mask));
if isempty(values)
    value = 0;
else
    value = sum(values);
end
end

function value = fractionOfAny(data, mask)
values = logical(data(mask));
if isempty(values)
    value = NaN;
else
    value = nnz(values) / numel(values);
end
end

function value = safeFraction(numerator, denominator)
if denominator <= 0
    value = NaN;
else
    value = numerator / denominator;
end
end

function image = readInputImage(imagePath)
if ~isfile(imagePath)
    error('diagnoseResidualEyelashCoverageAttribution:MissingImage', ...
        '输入图像不存在：%s。', imagePath);
end
image = imread(imagePath);
if ~isa(image, 'uint8') || ~isreal(image) || ndims(image) ~= 3 || ...
        size(image, 3) ~= 3
    error('diagnoseResidualEyelashCoverageAttribution:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function folder = normalizeOutputFolder(folder)
if nargin < 1 || isempty(folder)
    folder = fullfile(tempdir, ...
        'image_beauty_issue08_2_eyelash_20260918');
end
folder = normalizeText(folder, 'outputFolder');
parent = fileparts(folder);
if ~isempty(parent) && ~isfolder(parent)
    mkdir(parent);
end
end

function value = normalizeText(value, name)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || size(value, 1) ~= 1
    error('diagnoseResidualEyelashCoverageAttribution:InvalidText', ...
        '%s 必须是单行文本。', name);
end
end

function value = isValidStrength(value)
value = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function writePng(image, path)
if ~isa(image, 'uint8')
    image = uint8(min(max(round(double(image)), 0), 255));
end
imwrite(image, path);
end
