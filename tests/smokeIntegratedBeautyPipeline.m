function [summary, diagnostics] = smokeIntegratedBeautyPipeline( ...
        imageFolder, outputFolder, imageNames)
%SMOKEINTEGRATEDBEAUTYPIPELINE 验收 v3.1 的组合、缓存和原尺寸链路。
%   该入口只接收调用方提供的真实图目录，不把真实图复制进仓库。每张图
%   分别在预览尺寸和原尺寸上执行 5×5 强度组合，并对照无缓存、运行时
%   缓存和显式历史迁移三条路径；输出表格和 PNG 对比图写入 outputFolder。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
if nargin < 1 || ~isfolder(imageFolder)
    error('smokeIntegratedBeautyPipeline:InvalidImageFolder', ...
        '必须提供包含真实人像的图像目录。');
end
if nargin < 2 || isempty(outputFolder)
    outputFolder = fullfile(tempdir, 'image_beauty_integrated_v31');
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end
if nargin < 3 || isempty(imageNames)
    imageNames = discoverSourceImages(imageFolder);
else
    imageNames = normalizeImageNames(imageNames);
end
if isempty(imageNames)
    error('smokeIntegratedBeautyPipeline:MissingImages', ...
        '图像目录中没有可用的真实人像输入。');
end

strengths = [0, 25, 50, 75, 100];
gridRows = repmat(emptyGridRow(), 0, 1);
imageRows = repmat(emptyImageRow(), 0, 1);
continuityRows = repmat(emptyContinuityRow(), 0, 1);
migrationRows = repmat(emptyMigrationRow(), 0, 1);
violations = {};

for imageIndex = 1:numel(imageNames)
    imageName = imageNames{imageIndex};
    imagePath = fullfile(imageFolder, imageName);
    if ~isfile(imagePath)
        error('smokeIntegratedBeautyPipeline:MissingImage', ...
            '输入图像不存在：%s。', imageName);
    end
    inputImage = imread(imagePath);
    validateRgbImage(inputImage, imageName);
    inputInfo = imfinfo(imagePath);

    [previewImage, previewScale] = makePreview(inputImage);
    [previewFaceBox, hasFace, detection] = detectSingleFace(previewImage);
    if ~hasFace
        error('smokeIntegratedBeautyPipeline:NoFace', ...
            '%s 未检测到可用的语义人脸。', imageName);
    end
    previewContext = normalizeBeautyContext(previewImage, ...
        previewFaceBox, prepareBeautyContext(previewImage, previewFaceBox, ...
        detection.selectedParsing, struct('rotationDegrees', ...
        detection.orientationDegrees)));
    fullFaceBox = scaleFaceBox(previewFaceBox, 1 / previewScale, ...
        size(inputImage));
    fullContext = resizeBeautyContext(previewContext, size(inputImage), ...
        fullFaceBox, inputImage);

    modes = { ...
        struct('name', 'preview', 'image', previewImage, ...
        'faceBox', previewFaceBox, 'context', previewContext), ...
        struct('name', 'original', 'image', inputImage, ...
        'faceBox', fullFaceBox, 'context', fullContext)};
    for modeIndex = 1:numel(modes)
        mode = modes{modeIndex};
        [modeGrid, modeImage, modeContinuity, modeMigration, ...
            modeViolations] = verifyMode(mode, imageName, strengths, ...
            outputFolder, inputInfo);
        gridRows = [gridRows; modeGrid]; %#ok<AGROW>
        imageRows = [imageRows; modeImage]; %#ok<AGROW>
        continuityRows = [continuityRows; modeContinuity]; %#ok<AGROW>
        migrationRows = [migrationRows; modeMigration]; %#ok<AGROW>
        violations = [violations, modeViolations]; %#ok<AGROW>
    end
end

gridSummary = struct2table(gridRows);
imageSummary = struct2table(imageRows);
continuitySummary = struct2table(continuityRows);
migrationSummary = struct2table(migrationRows);
writetable(gridSummary, fullfile(outputFolder, 'integrated-grid.csv'));
writetable(imageSummary, fullfile(outputFolder, 'integrated-image-metrics.csv'));
writetable(continuitySummary, ...
    fullfile(outputFolder, 'integrated-continuity-metrics.csv'));
writetable(migrationSummary, ...
    fullfile(outputFolder, 'integrated-cache-metrics.csv'));

summary = struct( ...
    'passed', isempty(violations), ...
    'images', {imageNames}, ...
    'strengths', strengths, ...
    'grid', gridSummary, ...
    'imageMetrics', imageSummary, ...
    'continuity', continuitySummary, ...
    'cache', migrationSummary, ...
    'violations', {violations}, ...
    'outputFolder', outputFolder);
diagnostics = struct( ...
    'gridRows', height(gridSummary), ...
    'imageRows', height(imageSummary), ...
    'continuityRows', height(continuitySummary), ...
    'cacheRows', height(migrationSummary), ...
    'violations', {violations});
diagnostics.previewScaleByImage = readPreviewScales(imageNames, imageFolder);
if ~summary.passed
    error('smokeIntegratedBeautyPipeline:VerificationFailed', ...
        'v3.1 集成验收失败：%s。', strjoin(violations, '；'));
end
end

function [gridRows, imageRows, continuityRow, migrationRow, violations] = ...
        verifyMode(mode, imageName, strengths, outputFolder, inputInfo)
image = mode.image;
faceBox = mode.faceBox;
cacheContext = mode.context;
regeneratedContext = normalizeBeautyContext(image, faceBox, ...
    stripDerivedArtifacts(cacheContext));
[beautyMasks, ~] = masks.buildBeautyMasks(image, ...
    regeneratedContext, faceBox);
verifyAliasEquality(cacheContext, [imageName, '/', mode.name]);
verifyAliasEquality(regeneratedContext, [imageName, '/', mode.name]);

gridRows = repmat(emptyGridRow(), 0, 1);
violations = {};
smoothingOutputs = cell(1, numel(strengths));
defaultOutput = [];
whiteningOutput = [];
combinedOutput = [];
maximumOutput = [];
whiteningTargetLuminance = [];
combinedTargetLuminance = [];
caseElapsed = NaN(1, 4);

for smoothingIndex = 1:numel(strengths)
    for whiteningIndex = 1:numel(strengths)
        smoothingStrength = strengths(smoothingIndex);
        whiteningStrength = strengths(whiteningIndex);
        params = struct('smoothingStrength', smoothingStrength, ...
            'whiteningStrength', whiteningStrength);
        startTime = tic;
        [regeneratedOutput, regeneratedDiagnostics] = beautifyImage( ...
            image, params, faceBox, regeneratedContext);
        regeneratedElapsed = toc(startTime);
        startTime = tic;
        [cachedOutput, cachedDiagnostics] = beautifyImage( ...
            image, params, faceBox, cacheContext);
        cachedElapsed = toc(startTime);

        exact = isequal(regeneratedOutput, cachedOutput);
        isZero = smoothingStrength == 0 && whiteningStrength == 0;
        zeroIdentity = isZero && regeneratedDiagnostics.identity && ...
            cachedDiagnostics.identity && isequal(regeneratedOutput, image);
        cacheStateValid = isZero || ...
            (~regeneratedDiagnostics.reusedRuntimeCache && ...
            cachedDiagnostics.reusedRuntimeCache);
        [backgroundChange, hardChange] = protectedChanges( ...
            image, regeneratedOutput, cacheContext, beautyMasks);
        outputValid = isa(regeneratedOutput, 'uint8') && ...
            isequal(size(regeneratedOutput), size(image)) && ...
            ndims(regeneratedOutput) == 3 && size(regeneratedOutput, 3) == 3;

        row = emptyGridRow();
        row.image = imageName;
        row.mode = mode.name;
        row.smoothingStrength = smoothingStrength;
        row.whiteningStrength = whiteningStrength;
        row.regeneratedElapsedSeconds = regeneratedElapsed;
        row.cachedElapsedSeconds = cachedElapsed;
        row.cacheReused = hasRuntimeCacheReuse(cachedDiagnostics);
        row.outputsExactlyEqual = exact;
        row.zeroIdentity = zeroIdentity;
        row.outputValid = outputValid;
        row.backgroundMaxChange = backgroundChange;
        row.hardProtectionMaxChange = hardChange;
        row.outputHeight = size(regeneratedOutput, 1);
        row.outputWidth = size(regeneratedOutput, 2);
        row.outputClass = class(regeneratedOutput);
        gridRows(end + 1, 1) = row; %#ok<AGROW>

        if ~exact
            violations = appendViolation(violations, sprintf( ...
                '%s/%s %d/%d 缓存与重新生成 RGB 不一致', ...
                imageName, mode.name, smoothingStrength, whiteningStrength));
        end
        if ~cacheStateValid
            violations = appendViolation(violations, sprintf( ...
                '%s/%s %d/%d 缓存状态不符合预期', ...
                imageName, mode.name, smoothingStrength, whiteningStrength));
        end
        if isZero && ~zeroIdentity
            violations = appendViolation(violations, sprintf( ...
                '%s/%s 零强度没有严格返回原图', imageName, mode.name));
        end
        if ~outputValid
            violations = appendViolation(violations, sprintf( ...
                '%s/%s %d/%d 输出尺寸或 uint8 RGB 类型不正确', ...
                imageName, mode.name, smoothingStrength, whiteningStrength));
        end
        if backgroundChange > 1
            violations = appendViolation(violations, sprintf( ...
                '%s/%s %d/%d 改变了背景像素', ...
                imageName, mode.name, smoothingStrength, whiteningStrength));
        end
        if hardChange > 0
            violations = appendViolation(violations, sprintf( ...
                '%s/%s %d/%d 改变了硬保护像素', ...
                imageName, mode.name, smoothingStrength, whiteningStrength));
        end

        if whiteningStrength == 0
            smoothingOutputs{smoothingIndex} = regeneratedOutput;
        end
        if smoothingStrength == 25 && whiteningStrength == 15
            defaultOutput = regeneratedOutput;
            caseElapsed(1) = regeneratedElapsed;
        elseif smoothingStrength == 0 && whiteningStrength == 100
            whiteningOutput = regeneratedOutput;
            whiteningTargetLuminance = regeneratedDiagnostics.compose.targetLuminance;
            caseElapsed(2) = regeneratedElapsed;
        elseif smoothingStrength == 100 && whiteningStrength == 100
            maximumOutput = regeneratedOutput;
            caseElapsed(4) = regeneratedElapsed;
        elseif smoothingStrength == 50 && whiteningStrength == 50
            combinedOutput = regeneratedOutput;
            combinedTargetLuminance = regeneratedDiagnostics.compose.targetLuminance;
            caseElapsed(3) = regeneratedElapsed;
        end
    end
end

if isempty(combinedOutput)
    [combinedOutput, combinedDiagnostics] = beautifyImage(image, struct( ...
        'smoothingStrength', 50, 'whiteningStrength', 50), faceBox, ...
        regeneratedContext);
    combinedTargetLuminance = combinedDiagnostics.compose.targetLuminance;
end
if isempty(maximumOutput)
    maximumOutput = beautifyImage(image, struct( ...
        'smoothingStrength', 100, 'whiteningStrength', 100), faceBox, ...
        regeneratedContext);
end
if isempty(defaultOutput)
    startTime = tic;
    defaultOutput = beautifyImage(image, struct( ...
        'smoothingStrength', 25, 'whiteningStrength', 15), faceBox, ...
        regeneratedContext);
    caseElapsed(1) = toc(startTime);
end
if isempty(whiteningOutput)
    [whiteningOutput, whiteningDiagnostics] = beautifyImage(image, struct( ...
        'smoothingStrength', 0, 'whiteningStrength', 100), faceBox, ...
        regeneratedContext);
    whiteningTargetLuminance = whiteningDiagnostics.compose.targetLuminance;
end

imageRows = makeImageMetricRows(image, imageName, mode, inputInfo, ...
    defaultOutput, whiteningOutput, combinedOutput, maximumOutput, ...
    caseElapsed, cacheContext, faceBox);
[continuityRow, continuityViolations] = measureContinuity( ...
    image, imageName, mode.name, whiteningOutput, combinedOutput, ...
    whiteningTargetLuminance, combinedTargetLuminance, smoothingOutputs, ...
    cacheContext, beautyMasks, faceBox);
violations = [violations, continuityViolations]; %#ok<AGROW>

[migrationRow, migrationViolations] = verifyCacheLifecycle( ...
    image, imageName, mode.name, cacheContext, beautyMasks, faceBox, ...
    defaultOutput);
violations = [violations, migrationViolations]; %#ok<AGROW>

if strcmp(mode.name, 'preview')
    maskVisual = repmat(uint8(round(255 * cacheContext.skinMask)), ...
        [1, 1, 3]);
    visual = [image, defaultOutput, combinedOutput, maximumOutput, maskVisual];
    visualName = sprintf('%s_%s_compare.png', safeFileStem(imageName), ...
        mode.name);
    imwrite(visual, fullfile(outputFolder, visualName), 'png');
end
end

function rows = makeImageMetricRows(image, imageName, mode, inputInfo, ...
        defaultOutput, whiteningOutput, combinedOutput, maximumOutput, ...
        caseElapsed, context, faceBox)
outputs = {defaultOutput, whiteningOutput, combinedOutput, maximumOutput};
names = {'default_25_15', 'whitening_0_100', ...
    'combined_50_50', 'maximum_100_100'};
rows = repmat(emptyImageRow(), numel(outputs), 1);
for index = 1:numel(outputs)
    output = outputs{index};
    metrics = evaluateImage(image, output, caseElapsed(index));
    regression = measureBeautyRegression(image, output, context, faceBox, ...
        caseElapsed(index));
    row = emptyImageRow();
    row.image = imageName;
    row.mode = mode.name;
    row.caseName = names{index};
    row.inputWidth = size(image, 2);
    row.inputHeight = size(image, 1);
    row.outputWidth = size(output, 2);
    row.outputHeight = size(output, 1);
    row.outputClass = class(output);
    row.inputXResolution = resolutionValue(inputInfo, 'XResolution');
    row.inputYResolution = resolutionValue(inputInfo, 'YResolution');
    row.entropy = metrics.entropy;
    row.standardDeviation = metrics.standardDeviation;
    row.averageGradient = metrics.averageGradient;
    row.elapsedSeconds = caseElapsed(index);
    row.textureEnergy = regression.textureEnergy;
    row.blemishEnergy = regression.blemishEnergy;
    row.noseStructure = regression.noseStructure;
    row.noseStructureInput = regression.noseStructureInput;
    row.outsideStructure = regression.outsideStructure;
    row.outsideStructureInput = regression.outsideStructureInput;
    row.backgroundMaxChange = regression.backgroundMaxChange;
    row.hardProtectionMaxChange = regression.hardProtectionMaxChange;
    rows(index) = row;
end
end

function [row, violations] = measureContinuity(inputImage, imageName, ...
        modeName, whiteningOutput, combinedOutput, whiteningTargetLuminance, ...
        combinedTargetLuminance, smoothingOutputs, context, beautyMasks, faceBox)
violations = {};
sourceYCbCr = rgb2ycbcr(im2double(inputImage));
whiteningYCbCr = rgb2ycbcr(im2double(whiteningOutput));
combinedYCbCr = rgb2ycbcr(im2double(combinedOutput));
sourceY = sourceYCbCr(:, :, 1);
if isempty(whiteningTargetLuminance)
    whiteningY = whiteningYCbCr(:, :, 1);
else
    whiteningY = whiteningTargetLuminance;
end
if isempty(combinedTargetLuminance)
    combinedY = combinedYCbCr(:, :, 1);
else
    combinedY = combinedTargetLuminance;
end
skin = context.skinMask >= .50;
hard = beautyMasks.hardProtectionMask >= .999;
frequency = beauty.decomposeSkinFrequency(inputImage, faceBox);
blemishMap = beauty.buildBlemishMap(inputImage, frequency, beautyMasks);
valid = skin & ~hard & frequency.base < .90 & ...
    beautyMasks.whiteningProtectionMask < .999;
scale = min(faceBox(3:4));

noseEvidence = min(context.regions.nose, context.regionConfidence.nose);
noseCore = valid & noseEvidence >= .60;
noseDistance = bwdist(noseCore);
noseReference = valid & noseDistance >= .02 * scale & ...
    noseDistance <= .10 * scale;
[noseRatio, noseStatus, nosePass] = liftRatio( ...
    whiteningY - sourceY, noseCore, noseReference, .75);

browEvidence = max(min(context.regions.leftBrow, ...
    context.regionConfidence.leftBrow), min(context.regions.rightBrow, ...
    context.regionConfidence.rightBrow));
% 眉毛本体不是皮肤，核心先按语义置信度确定；近/远对照区
% 再用 valid 限制为合格皮肤，避免把眉毛自身误判为“不适用”。
browCore = browEvidence >= .60;
browDistance = bwdist(browCore);
browNear = valid & browDistance > 0 & browDistance <= .01 * scale;
browFar = valid & browDistance >= .03 * scale & ...
    browDistance <= .06 * scale;
[browRatio, browStatus, browPass] = liftRatio( ...
    whiteningY - sourceY, browNear, browFar, .80);

% 结构口径使用输入 Base 的上下四分位固定亮/暗区，而不是把
% 美白后的整体梯度分位数误当成鼻梁/鼻侧对比。
[whiteningStructure, whiteningStatus, whiteningPass] = ...
    contrastRetention(sourceY, whiteningY, noseCore, frequency.base, ...
    frequency.scales.mediumSigma, .90);
[combinedStructure, ~, ~] = ...
    contrastRetention(sourceY, combinedY, noseCore, frequency.base, ...
    frequency.scales.mediumSigma, .90);
% 鼻部结构门槛与提亮比属于独立美白连续性口径；组合结果中的
% 磨皮会有意改变中频阴影，组合本身由 5×5 RGB/保护和频带单调性验收。
structurePass = whiteningPass;
if strcmp(whiteningStatus, '不适用')
    structureStatus = '不适用';
else
    structureStatus = '适用';
end

ordinary = valid & blemishMap < .60;
inputFrequency = frequency;
fineEnergy = NaN(size(smoothingOutputs));
midEnergy = NaN(size(smoothingOutputs));
fineRetention = NaN(size(smoothingOutputs));
midRetention = NaN(size(smoothingOutputs));
inputFineEnergy = meanAbsolute(inputFrequency.fine, ordinary);
inputMidEnergy = meanAbsolute(inputFrequency.mid, ordinary);
for index = 1:numel(smoothingOutputs)
    if isempty(smoothingOutputs{index})
        continue;
    end
    outputFrequency = beauty.decomposeSkinFrequency( ...
        smoothingOutputs{index}, faceBox);
    fineEnergy(index) = meanAbsolute(outputFrequency.fine, ordinary);
    midEnergy(index) = meanAbsolute(outputFrequency.mid, ordinary);
    fineRetention(index) = fineEnergy(index) / max(inputFineEnergy, eps);
    midRetention(index) = midEnergy(index) / max(inputMidEnergy, eps);
end
energyPass = isNonIncreasing(fineEnergy, 1e-12) && ...
    isNonIncreasing(midEnergy, 1e-12) && ...
    isNonIncreasing(fineRetention, 1e-12) && ...
    isNonIncreasing(midRetention, 1e-12);
if ~energyPass
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 重分解 Fine/Mid 能量未按磨皮强度单调下降', ...
        imageName, modeName));
end
if nosePass == false
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 鼻部提亮比或低增量绝对差未达标', imageName, modeName));
end
if browPass == false
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 眉周提亮比或低增量绝对差未达标', imageName, modeName));
end
if ~structurePass
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 鼻部结构对比保留率低于 0.90', imageName, modeName));
end
[baseResult, ~] = beauty.evenSkinLuminance(frequency, beautyMasks, 50);
correction = correctionGradientMetric(inputImage, baseResult.baseDelta, ...
    ordinary, faceBox);
if correction.applicable && ~correction.passed
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 非瑕疵校正梯度 P95 超过定义上限', imageName, modeName));
end

row = emptyContinuityRow();
row.image = imageName;
row.mode = modeName;
row.noseStatus = noseStatus;
row.noseLiftRatio = noseRatio;
row.browStatus = browStatus;
row.browLiftRatio = browRatio;
row.whiteningNoseStructureRetention = whiteningStructure;
row.combinedNoseStructureRetention = combinedStructure;
row.structureStatus = structureStatus;
row.correctionStatus = correction.status;
row.originalGradientP95 = correction.originalP95;
row.correctionGradientP95 = correction.correctionP95;
row.correctionGradientLimit = correction.limit;
row.fineEnergy0 = fineEnergy(1);
row.fineEnergy25 = fineEnergy(2);
row.fineEnergy50 = fineEnergy(3);
row.fineEnergy75 = fineEnergy(4);
row.fineEnergy100 = fineEnergy(5);
row.midEnergy0 = midEnergy(1);
row.midEnergy25 = midEnergy(2);
row.midEnergy50 = midEnergy(3);
row.midEnergy75 = midEnergy(4);
row.midEnergy100 = midEnergy(5);
row.fineRetention100 = fineRetention(end);
row.midRetention100 = midRetention(end);
row.energyMonotonic = energyPass;
row.passed = nosePass && browPass && structurePass && energyPass && ...
    (~correction.applicable || correction.passed);
end

function [row, violations] = verifyCacheLifecycle(image, imageName, ...
        modeName, cacheContext, beautyMasks, ...
        faceBox, expectedOutput)
violations = {};
params = struct('smoothingStrength', 25, 'whiteningStrength', 15);
changedImage = image;
changedValue = changedImage(1, 1, 1);
if changedValue == 255
    changedImage(1, 1, 1) = uint8(254);
else
    changedImage(1, 1, 1) = changedValue + uint8(1);
end
[~, changedDiagnostics] = beautifyImage(changedImage, params, faceBox, ...
    cacheContext);
changedRejected = ~changedDiagnostics.reusedRuntimeCache;
if ~changedRejected
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 换图后仍复用了旧 runtime cache', imageName, modeName));
end

legacy = makeLegacyContext(cacheContext);
migrated = migrateBeautyContext(legacy);
[migratedOutput, migratedDiagnostics] = beautifyImage( ...
    image, params, faceBox, migrated);
migrationValid = isfield(migrated, 'migrationDiagnostics') && ...
    strcmp(migrated.migrationDiagnostics.status, 'regenerated') && ...
    isfield(migrated, 'runtimeCache') && ...
    strcmp(migrated.runtimeCache.schemaVersion, '3.1') && ...
    isequal(migratedOutput, expectedOutput);
if ~migrationValid
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 历史 Context 迁移后结果或版本不正确', imageName, modeName));
end

aliasValid = isequal(cacheContext.chromaProtectionMask, ...
    cacheContext.toneProtectionMask) && ...
    isequal(beautyMasks.chromaProtectionMask, ...
    beautyMasks.toneProtectionMask) && ...
    isfield(migrated, 'chromaProtectionMask') && ...
    isequal(migrated.chromaProtectionMask, migrated.toneProtectionMask);
if ~aliasValid
    violations = appendViolation(violations, sprintf( ...
        '%s/%s 兼容 alias 未保持同值', imageName, modeName));
end

row = emptyMigrationRow();
row.image = imageName;
row.mode = modeName;
row.changedInputRejected = changedRejected;
row.migrationStatus = migrated.migrationDiagnostics.status;
row.migratedSchemaVersion = migrated.schemaVersion;
row.migratedCacheSchemaVersion = migrated.runtimeCache.schemaVersion;
row.migratedOutputExact = isequal(migratedOutput, expectedOutput);
row.migratedCacheReused = migratedDiagnostics.reusedRuntimeCache;
row.aliasEqual = aliasValid;
row.passed = changedRejected && migrationValid && aliasValid;
end

function context = makeLegacyContext(context)
removeNames = {'chromaProtectionMask', 'whiteningProtectionMask'};
removeNames = removeNames(isfield(context, removeNames));
if ~isempty(removeNames)
    context = rmfield(context, removeNames);
end
context.schemaVersion = '3.0';
if isfield(context, 'runtimeCache') && isstruct(context.runtimeCache)
    context.runtimeCache.schemaVersion = '3.0';
end
end

function context = stripDerivedArtifacts(context)
removeNames = {'runtimeCache', 'textureProtectionMask', ...
    'structureProtectionMask', 'whiteningProtectionMask', ...
    'chromaProtectionMask', 'toneProtectionMask', 'strengthMap', ...
    'faceStrengthMap', 'nonFaceStrengthMap', 'protectionMasks'};
removeNames = removeNames(isfield(context, removeNames));
if ~isempty(removeNames)
    context = rmfield(context, removeNames);
end
end

function verifyAliasEquality(context, label)
if ~isfield(context, 'chromaProtectionMask') || ...
        ~isfield(context, 'toneProtectionMask') || ...
        ~isequal(context.chromaProtectionMask, context.toneProtectionMask)
    error('smokeIntegratedBeautyPipeline:AliasConflict', ...
        '%s 的 chromaProtectionMask 与 toneProtectionMask 不同值。', label);
end
end

function reused = hasRuntimeCacheReuse(diagnostics)
reused = isstruct(diagnostics) && isscalar(diagnostics) && ...
    isfield(diagnostics, 'reusedRuntimeCache') && ...
    diagnostics.reusedRuntimeCache;
end

function [backgroundChange, hardChange] = protectedChanges( ...
        inputImage, outputImage, context, beautyMasks)
difference = max(abs(double(outputImage) - double(inputImage)), [], 3);
background = context.skinMask < .01;
hard = beautyMasks.hardProtectionMask >= .999;
backgroundChange = maskedMaximum(difference, background);
hardChange = maskedMaximum(difference, hard);
end

function value = maskedMaximum(data, mask)
if any(mask(:))
    value = max(data(mask));
else
    value = 0;
end
end

function values = appendViolation(values, message)
values{end + 1} = message; %#ok<AGROW>
end

function [ratio, status, passed] = liftRatio(delta, core, reference, threshold)
ratio = NaN;
status = '不适用';
passed = true;
if nnz(core) < 16 || nnz(reference) < 16
    return;
end
coreLift = median(delta(core));
referenceLift = median(delta(reference));
status = '比值';
if abs(referenceLift) <= 2 / 255
    ratio = coreLift / max(referenceLift, eps);
    status = '低增量绝对差';
    passed = abs(coreLift - referenceLift) <= 2 / 255;
else
    ratio = coreLift / referenceLift;
    passed = ratio >= threshold;
end
end

function [ratio, status, passed] = contrastRetention(inputY, outputY, ...
        roi, base, sigma, minimumRetention)
ratio = NaN;
status = '不适用';
passed = true;
if nnz(roi) < 16
    return;
end
baseValues = base(roi);
lowBase = percentileValue(baseValues, .25);
highBase = percentileValue(baseValues, .75);
light = roi & base >= highBase;
dark = roi & base <= lowBase;
if nnz(light) < 8 || nnz(dark) < 8
    return;
end
inputLow = imgaussfilt(inputY, sigma, 'Padding', 'replicate');
outputLow = imgaussfilt(outputY, sigma, 'Padding', 'replicate');
inputContrast = mean(inputLow(light)) - mean(inputLow(dark));
outputContrast = mean(outputLow(light)) - mean(outputLow(dark));
status = '比值';
if abs(inputContrast) <= 2 / 255
    status = '低对比绝对差';
    passed = abs(outputContrast - inputContrast) <= 2 / 255;
    ratio = outputContrast / max(inputContrast, eps);
else
    ratio = abs(outputContrast) / abs(inputContrast);
    passed = inputContrast * outputContrast > 0 && ...
        ratio >= minimumRetention;
end
end

function result = correctionGradientMetric(inputImage, correctionDelta, ...
        mask, faceBox)
config = metricConfig(faceBox);
inputYCbCr = rgb2ycbcr(im2double(inputImage));
inputY = imgaussfilt(inputYCbCr(:, :, 1), config.lowPassSigma, ...
    'Padding', 'replicate');
correctionY = imgaussfilt(double(correctionDelta), ...
    config.lowPassSigma, 'Padding', 'replicate');
[inputX, inputYGradient] = gradient(inputY);
[correctionX, correctionYGradient] = gradient(correctionY);
inputGradient = hypot(inputX, inputYGradient);
correctionGradient = hypot(correctionX, correctionYGradient);
result = struct('applicable', false, 'passed', true, 'status', '不适用', ...
    'originalP95', NaN, 'correctionP95', NaN, 'limit', NaN);
if nnz(mask) < 16
    return;
end
result.applicable = true;
result.status = '适用';
result.originalP95 = percentileValue(inputGradient(mask), .95);
result.correctionP95 = percentileValue(correctionGradient(mask), .95);
faceScale = min(faceBox(3:4));
result.limit = .10 * max(result.originalP95, 2 / (255 * faceScale));
result.passed = result.correctionP95 <= result.limit + 1e-12;
end

function config = metricConfig(faceBox)
faceScale = min(faceBox(3:4));
config = struct('lowPassSigma', min(8, max(1.25, .018 * faceScale)));
end

function value = meanAbsolute(data, mask)
if nnz(mask) < 16
    value = NaN;
else
    value = mean(abs(data(mask)));
end
end

function valid = isNonIncreasing(values, tolerance)
values = values(isfinite(values));
valid = numel(values) < 2 || all(diff(values) <= tolerance);
end

function value = percentileValue(values, fraction)
values = sort(double(values(:)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + (numel(values) - 1) * fraction;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    weight = position - lower;
    value = (1 - weight) * values(lower) + weight * values(upper);
end
end

function imageNames = discoverSourceImages(imageFolder)
extensions = {'.jpg', '.jpeg', '.png'};
files = dir(imageFolder);
imageNames = {};
for index = 1:numel(files)
    if files(index).isdir
        continue;
    end
    [~, baseName, extension] = fileparts(files(index).name);
    if ismember(lower(extension), extensions) && ...
            (numel(baseName) < 1 || lower(baseName(end)) ~= 'r')
        imageNames{end + 1} = files(index).name; %#ok<AGROW>
    end
end
imageNames = sort(imageNames);
end

function imageNames = normalizeImageNames(values)
if ischar(values) && size(values, 1) == 1
    values = {values};
elseif isstring(values)
    values = cellstr(values(:));
elseif iscell(values)
    values = values(:)';
else
    error('smokeIntegratedBeautyPipeline:InvalidImageNames', ...
        'imageNames 必须是字符向量、字符串数组或元胞数组。');
end
if ~all(cellfun(@(value) ischar(value) || ...
        (isstring(value) && isscalar(value)), values))
    error('smokeIntegratedBeautyPipeline:InvalidImageNames', ...
        'imageNames 中包含无效名称。');
end
imageNames = cellfun(@char, values, 'UniformOutput', false);
end

function [preview, scale] = makePreview(image)
scale = min(1, 640 / max(size(image, 1), size(image, 2)));
if scale < 1
    preview = imresize(image, scale, 'bilinear');
else
    preview = image;
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

function value = safeFileStem(name)
[~, value, ~] = fileparts(name);
value = regexprep(value, '[^A-Za-z0-9_-]', '_');
if isempty(value)
    value = 'image';
end
end

function value = resolutionValue(info, name)
if isstruct(info) && isscalar(info) && isfield(info, name) && ...
        isnumeric(info.(name)) && isscalar(info.(name)) && ...
        isfinite(info.(name))
    value = double(info.(name));
else
    value = NaN;
end
end

function scales = readPreviewScales(imageNames, imageFolder)
scales = zeros(size(imageNames));
for index = 1:numel(imageNames)
    image = imread(fullfile(imageFolder, imageNames{index}));
    scales(index) = min(1, 640 / max(size(image, 1), size(image, 2)));
end
end

function validateRgbImage(image, name)
if ~isa(image, 'uint8') || ~isreal(image) || ndims(image) ~= 3 || ...
        size(image, 3) ~= 3
    error('smokeIntegratedBeautyPipeline:InvalidImage', ...
        '%s 必须是 uint8 三通道 RGB 图像。', name);
end
end

function row = emptyGridRow
row = struct('image', '', 'mode', '', 'smoothingStrength', 0, ...
    'whiteningStrength', 0, 'regeneratedElapsedSeconds', NaN, ...
    'cachedElapsedSeconds', NaN, 'cacheReused', false, ...
    'outputsExactlyEqual', false, 'zeroIdentity', false, ...
    'outputValid', false, 'backgroundMaxChange', 0, ...
    'hardProtectionMaxChange', 0, 'outputHeight', 0, 'outputWidth', 0, ...
    'outputClass', '');
end

function row = emptyImageRow
row = struct('image', '', 'mode', '', 'caseName', '', ...
    'inputWidth', 0, 'inputHeight', 0, 'outputWidth', 0, ...
    'outputHeight', 0, 'outputClass', '', 'inputXResolution', NaN, ...
    'inputYResolution', NaN, 'entropy', NaN, 'standardDeviation', NaN, ...
    'averageGradient', NaN, 'elapsedSeconds', NaN, ...
    'textureEnergy', NaN, 'blemishEnergy', NaN, 'noseStructure', NaN, ...
    'noseStructureInput', NaN, 'outsideStructure', NaN, ...
    'outsideStructureInput', NaN, 'backgroundMaxChange', NaN, ...
    'hardProtectionMaxChange', NaN);
end

function row = emptyContinuityRow
row = struct('image', '', 'mode', '', 'noseStatus', '', ...
    'noseLiftRatio', NaN, 'browStatus', '', 'browLiftRatio', NaN, ...
    'whiteningNoseStructureRetention', NaN, ...
    'combinedNoseStructureRetention', NaN, 'structureStatus', '', ...
    'correctionStatus', '', 'originalGradientP95', NaN, ...
    'correctionGradientP95', NaN, 'correctionGradientLimit', NaN, ...
    'fineEnergy0', NaN, 'fineEnergy25', NaN, 'fineEnergy50', NaN, ...
    'fineEnergy75', NaN, 'fineEnergy100', NaN, 'midEnergy0', NaN, ...
    'midEnergy25', NaN, 'midEnergy50', NaN, 'midEnergy75', NaN, ...
    'midEnergy100', NaN, 'fineRetention100', NaN, ...
    'midRetention100', NaN, 'energyMonotonic', false, 'passed', false);
end

function row = emptyMigrationRow
row = struct('image', '', 'mode', '', 'changedInputRejected', false, ...
    'migrationStatus', '', 'migratedSchemaVersion', '', ...
    'migratedCacheSchemaVersion', '', 'migratedOutputExact', false, ...
    'migratedCacheReused', false, 'aliasEqual', false, 'passed', false);
end
