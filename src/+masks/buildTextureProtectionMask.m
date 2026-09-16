function [textureProtectionMask, diagnostics] = ...
        buildTextureProtectionMask(inputImage, beautyContext, faceBox)
%BUILDTEXTUREPROTECTIONMASK 生成五官、眉毛和眼周细节的纹理保护 Mask。
%   硬保护和软保护都在本 package 内从语义概率与原图结构派生，Context
%   不再携带旧的通用 featureProtectionMask 或 hardProtectionMask。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    if isfield(beautyContext, 'faceBox')
        faceBox = beautyContext.faceBox;
    else
        error('masks:InvalidFaceBox', '必须提供人脸框。');
    end
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
regions = semanticRegions(beautyContext, imageSize);
confidence = semanticConfidence(beautyContext, imageSize);
reference = regions.skin;
faceScale = min(faceBox(3:4));
occluderNames = {'leftBrow', 'rightBrow', 'leftEye', 'rightEye', ...
    'eyeglass', 'cloth', 'hair', 'hat', 'earring', 'necklace'};
occluderEvidence = softUnion(regions, confidence, occluderNames, reference);
occluderHard = occluderEvidence >= .65;
occluderRadius = min(8, max(3, round(.020 * faceScale)));
occluderProtection = featherHardMask(occluderHard, occluderRadius, .85);

lipNames = {'mouth', 'upperLip', 'lowerLip'};
lipEvidence = softUnion(regions, confidence, lipNames, reference);
lipCore = lipEvidence >= .65;
lipAlpha = smoothStep(lipEvidence, .25, .65);
% 唇周过渡带过窄会让硬保护的唇体与被提亮的皮肤之间出现深色描边，
% 因此羽化半径与眉周同量级，并改用 smoothstep 衰减。
lipRadius = min(10, max(4, round(.030 * faceScale)));
if any(lipCore(:))
    lipDistance = bwdist(lipCore);
    lipRing = .90 * smoothStep( ...
        max(0, 1 - lipDistance ./ (lipRadius + 1)), 0, 1);
else
    lipRing = zeros(size(lipCore));
end
lipProtection = max(lipAlpha, lipRing);
lipProtection(lipCore) = 1;

noseEvidence = softUnion(regions, confidence, {'nose'}, reference);
noseRadius = min(5, max(4, round(.024 * faceScale)));
grayImage = im2double(rgb2gray(inputImage));
[gradientX, gradientY] = gradient(imgaussfilt(grayImage, ...
    noseLowFrequencySigma(faceScale), 'Padding', 'replicate'));
lowFrequencyGradient = hypot(gradientX, gradientY);
noseCore = noseEvidence >= .65;
noseBoundary = noseCore & ~imerode(noseCore, strel('disk', 1, 0));

% 鼻内只使用低通后的亮度梯度做软保护，避免把雀斑和毛孔逐点硬保护。
noseInterior = noseCore & ~noseBoundary;
gradientProtection = lowFrequencyStructureProtection( ...
    lowFrequencyGradient, noseInterior);
noseStructure = min(.45, .45 * gradientProtection) .* ...
    double(noseInterior);

% 鼻孔通常是鼻区内部连续的暗谷；仅保留经过面积和连续性筛选的候选，
% 鼻子的语义外轮廓不进入 hard，避免磨皮后出现一圈描边。
[nostrilCore, nostrilBoundary] = detectNostrilBoundary( ...
    grayImage, noseInterior, faceScale);
nostrilRadius = min(4, max(2, round(.006 * faceScale)));
nostrilProtection = featherSoftMask(nostrilCore, nostrilRadius, .95);

% 外轮廓只给低幅度、连续的软过渡；鼻梁和鼻翼的低频梯度单独保护。
noseEdgeBand = softBoundaryBand(noseBoundary, noseCore, ...
    noseRadius, .28);
noseProtection = max(noseStructure, noseEdgeBand);
noseProtection = max(noseProtection, nostrilProtection);
noseProtection(nostrilCore) = 1;

% 眼睛语义区之外的睫毛和眼线由局部线结构补充保护。检测范围限定在
% 眼睑邻域，避免把全图高梯度和雀斑误认为五官细节。
eyeEvidence = softUnion(regions, confidence, ...
    {'leftEye', 'rightEye'}, reference);
leftEyeEvidence = softUnion(regions, confidence, {'leftEye'}, reference);
rightEyeEvidence = softUnion(regions, confidence, {'rightEye'}, reference);
browEvidence = softUnion(regions, confidence, ...
    {'leftBrow', 'rightBrow'}, reference);
% 浅色眉毛和眉尾的解析概率常落在 0.45--0.65 之间，只按 0.65 硬阈值
% 保护会让这部分眉毛被当作皮肤全强度美白磨皮，形成斑驳的缺皮块。
browProtection = smoothStep(browEvidence, .45, .65);
[eyeDetailProtection, lashCore, eyeNeighborhood, lashProtection, ...
    doubleEyelidCore, doubleEyelidProtection, periocularProtection] = ...
    detectEyeDetailProtection(grayImage, leftEyeEvidence, ...
    rightEyeEvidence, eyeEvidence, browEvidence, faceScale);

hardProtectionMask = double(occluderHard | lipCore | nostrilCore | lashCore);
textureProtectionMask = max(cat(3, occluderProtection, browProtection, ...
    lipProtection, noseProtection, eyeDetailProtection), [], 3);
textureProtectionMask = double(min(max(textureProtectionMask, 0), 1));
diagnostics = struct('occluderProtection', occluderProtection, ...
    'browProtection', browProtection, ...
    'lipProtection', lipProtection, 'noseProtection', noseProtection, ...
    'eyeDetailProtection', eyeDetailProtection, ...
    'lashProtection', lashProtection, ...
    'periocularProtection', periocularProtection, ...
    'doubleEyelidProtection', doubleEyelidProtection, ...
    'lipCore', lipCore, 'noseCore', noseCore, 'noseHard', nostrilCore, ...
    'noseBoundary', noseBoundary, 'nostrilBoundary', nostrilBoundary, ...
    'nostrilCore', nostrilCore, 'noseInterior', noseInterior, ...
    'noseStructureProtection', noseStructure, ...
    'lashCore', lashCore, 'eyeNeighborhood', eyeNeighborhood, ...
    'periocularBand', eyeNeighborhood, ...
    'doubleEyelidCore', doubleEyelidCore, ...
    'hardProtectionMask', hardProtectionMask, ...
    'skinExclusionEvidence', max(occluderEvidence, lipEvidence), ...
    'faceSkinMask', readOptionalMask(beautyContext, 'faceSkinMask', imageSize));
end

function evidence = softUnion(regions, confidence, names, reference)
evidence = zeros(size(reference));
for index = 1:numel(names)
    name = names{index};
    if ~isfield(regions, name) || ~isfield(confidence, name)
        error('masks:InvalidContext', ...
            '语义类别缺失。');
    end
    evidence = max(evidence, min(regions.(name), confidence.(name)));
end
evidence = min(max(double(evidence), 0), 1);
end

function alpha = smoothStep(value, low, high)
t = min(max((double(value) - low) / max(high - low, eps), 0), 1);
alpha = t .^ 2 .* (3 - 2 * t);
end

function feather = featherHardMask(core, radius, bandWeight)
if ~any(core(:))
    feather = zeros(size(core));
    return;
end
distance = bwdist(core);
feather = bandWeight * max(0, 1 - distance / (radius + 1));
feather(core) = 1;
end

function feather = featherSoftMask(core, radius, peak)
%FEATHERSOFTMASK 为高置信细节生成连续软过渡，不扩大硬保护区域。
if ~any(core(:))
    feather = zeros(size(core));
    return;
end
distance = bwdist(core);
feather = peak * max(0, 1 - distance / (radius + 1));
feather(core) = peak;
end

function band = softBoundaryBand(boundary, support, radius, peak)
%SOFTBOUNDARYBAND 仅在语义区域内部生成低幅度边界带。
band = zeros(size(support));
if ~any(boundary(:)) || ~any(support(:))
    return;
end
distance = bwdist(boundary);
band = peak * max(0, 1 - distance / (radius + 1));
band(~support) = 0;
band(boundary) = peak;
end

function [protection, lashCore, neighborhood, lashProtection, ...
        doubleEyelidCore, doubleEyelidProtection, periocularProtection] = ...
        detectEyeDetailProtection(grayImage, leftEyeEvidence, ...
        rightEyeEvidence, eyeEvidence, browEvidence, faceScale)
%DETECTEYEDETAILPROTECTION 保护眼睫毛、眼线和双眼皮褶皱。
% 检测始终限定在每只眼睛语义区的有限邻域内。睫毛要求暗色、细长、
% 方向连续和接近眼睑；双眼皮只生成局部软保护，不扩张为硬保护。
protection = zeros(size(eyeEvidence));
lashCore = false(size(eyeEvidence));
lashProtection = zeros(size(eyeEvidence));
doubleEyelidCore = false(size(eyeEvidence));
doubleEyelidProtection = zeros(size(eyeEvidence));
periocularProtection = zeros(size(eyeEvidence));
neighborhood = false(size(eyeEvidence));
eyeMasks = {leftEyeEvidence >= .45, rightEyeEvidence >= .45};
browCore = browEvidence >= .45;
if ~any(eyeEvidence(:) >= .45)
    return;
end

% 眼周带比原先的细线检测范围更宽，但每只眼睛独立膨胀，避免连接到
% 鼻梁、眼窝或另一只眼睛。外眼角的间断睫毛允许在带内寻找。
    periocularRadius = min(24, max(9, round(.040 * double(faceScale))));
softRadius = min(5, max(2, round(.008 * double(faceScale))));
for eyeIndex = 1:numel(eyeMasks)
    eyeCore = eyeMasks{eyeIndex};
    if ~any(eyeCore(:))
        continue;
    end
    currentBand = imdilate(eyeCore, strel('disk', periocularRadius, 0));
    neighborhood = neighborhood | currentBand;
    currentRing = currentBand & ~eyeCore;
    if any(browCore(:))
        browRadius = min(5, max(2, round(.010 * double(faceScale))));
        currentRing(imdilate(browCore, strel('disk', browRadius, 0))) = false;
    end

    % 软保护只覆盖眼睛外侧有限带，眼球核心仍由 occluderProtection 硬保护。
    % 紧邻眼睑的双眼皮、眼线尾部和细小睫毛即使未形成完整线组件，
    % 也需要足够的软保护；仍保持距离衰减，避免冻结整片眼窝皮肤。
    currentPeriocular = featherSoftMask(eyeCore, periocularRadius, .76);
    currentPeriocular(eyeCore) = 0;
    [eyeRows, ~] = find(eyeCore);
    topRow = min(eyeRows);
    [rowGrid, ~] = ndgrid(1:size(eyeCore, 1), 1:size(eyeCore, 2));
    upperAllowance = max(1, round(.004 * double(faceScale)));
    upperDetailBand = currentRing & rowGrid <= topRow + upperAllowance;
    eyeDistance = bwdist(eyeCore);
    upperCurve = .55 + .40 * max(0, 1 - ...
        (eyeDistance / (periocularRadius + 1)) .^ 2);
    outerFeather = min(max((periocularRadius + 1 - eyeDistance) / 4, 0), 1);
    upperProtection = upperCurve .* outerFeather;
    upperProtection(~upperDetailBand) = 0;
    currentPeriocular = max(currentPeriocular, upperProtection);
    periocularProtection = max(periocularProtection, currentPeriocular);

    [currentLash, currentLashProtection] = detectLashLines( ...
        grayImage, eyeCore, currentRing, faceScale, softRadius);
    lashCore = lashCore | currentLash;
    lashProtection = max(lashProtection, currentLashProtection);

    [currentFold, currentFoldProtection] = detectDoubleEyelidFold( ...
        grayImage, eyeCore, browCore, currentBand, faceScale);
    doubleEyelidCore = doubleEyelidCore | currentFold;
    doubleEyelidProtection = max(doubleEyelidProtection, currentFoldProtection);
end

protection = max(cat(3, periocularProtection, lashProtection, ...
    doubleEyelidProtection), [], 3);
end

function [lashCore, protection] = detectLashLines( ...
        grayImage, eyeCore, ring, faceScale, softRadius)
%DETECTLASHLINES 检测允许小间断的外眼角睫毛和眼线。
lashCore = false(size(eyeCore));
protection = zeros(size(eyeCore));
if ~any(ring(:))
    return;
end

darkSigma = min(2.4, max(.7, .004 * double(faceScale)));
lineSigma = min(1.35, max(.45, .002 * double(faceScale)));
smoothed = imgaussfilt(grayImage, darkSigma, 'Padding', 'replicate');
lineImage = imgaussfilt(grayImage, lineSigma, 'Padding', 'replicate');
[gradientX, gradientY] = gradient(lineImage);
gradientMagnitude = hypot(gradientX, gradientY);
darkResidual = smoothed - grayImage;
darkValues = sort(darkResidual(ring));
gradientValues = sort(gradientMagnitude(ring));
darkThreshold = max(.010, percentileValue(darkValues, .62));
gradientThreshold = max(.012, percentileValue(gradientValues, .65));
darkCandidate = ring & darkResidual >= darkThreshold;
edgeCandidate = darkCandidate & gradientMagnitude >= gradientThreshold;
if ~any(darkCandidate(:))
    return;
end

% 先沿多方向闭合 1--数像素间隙，再用短线开运算保留细长结构。
% 只把原始 darkCandidate 像素写入 hard，闭合产生的像素仅用于连续性判定。
lineLength = min(6, max(3, round(.007 * double(faceScale))));
gapLength = min(5, max(2, round(.006 * double(faceScale))));
lineSupport = false(size(darkCandidate));
for angle = 0:15:165
    closingElement = strel('line', gapLength, angle);
    openingElement = strel('line', lineLength, angle);
    closed = imclose(darkCandidate, closingElement);
    lineSupport = lineSupport | imdilate(imopen(closed, openingElement), ...
        strel('disk', 1, 0));
end

candidate = darkCandidate & (edgeCandidate | lineSupport);
% 允许外眼角与眼 core 之间存在数像素间隙，但仍限制在眼周带内。
lashDistance = min(9, max(4, round(.014 * double(faceScale))));
nearEye = bwdist(eyeCore) <= lashDistance;
% 只有显著深色的细线进入 hard；低对比双眼皮即使具有线形，也只由
% periocular/doubleEyelidProtection 软保护，避免制造新的硬边界。
hardDarkThreshold = max(.045, percentileValue(darkValues, .80));
hardGradientThreshold = max(.018, percentileValue(gradientValues, .75));
lashCore = candidate & nearEye & darkResidual >= hardDarkThreshold & ...
    (gradientMagnitude >= hardGradientThreshold | lineSupport);
if any(lashCore(:))
    protection = featherSoftMask(lashCore, softRadius, .99);
    protection(lashCore) = .99;
end
end

function [foldCore, protection] = detectDoubleEyelidFold( ...
        grayImage, eyeCore, browCore, band, faceScale)
%DETECTDOUBLEEYELIDFOLD 检测眼睛上方连续的低对比双眼皮褶皱。
foldCore = false(size(eyeCore));
protection = zeros(size(eyeCore));
[rows, ~] = find(eyeCore);
if isempty(rows)
    return;
end

foldDistance = min(20, max(6, round(.035 * double(faceScale))));
[rowGrid, ~] = ndgrid(1:size(eyeCore, 1), 1:size(eyeCore, 2));
top = min(rows);
foldBand = band & rowGrid < top & rowGrid >= top - foldDistance;
if any(browCore(:))
    browRadius = min(5, max(2, round(.010 * double(faceScale))));
    foldBand(imdilate(browCore, strel('disk', browRadius, 0))) = false;
end
if ~any(foldBand(:))
    return;
end

foldSigma = min(3.2, max(.9, .005 * double(faceScale)));
foldImage = imgaussfilt(grayImage, foldSigma, 'Padding', 'replicate');
broadImage = imgaussfilt(grayImage, min(8, 2.4 * foldSigma), ...
    'Padding', 'replicate');
[gradientX, gradientY] = gradient(foldImage);
gradientMagnitude = hypot(gradientX, gradientY);
darkRidge = broadImage - foldImage;
gradientValues = sort(gradientMagnitude(foldBand));
darkValues = sort(darkRidge(foldBand));
gradientThreshold = max(.0045, percentileValue(gradientValues, .58));
darkThreshold = max(.0035, percentileValue(darkValues, .55));
seed = foldBand & ((gradientMagnitude >= gradientThreshold & ...
    darkRidge >= darkThreshold) | darkRidge >= 1.25 * darkThreshold);
if ~any(seed(:))
    return;
end

% 褶皱允许小弧度，因此用水平和 ±15 度方向确认连续性，避免圆形斑点通过。
arcLength = min(14, max(5, round(.018 * double(faceScale))));
shortLength = min(8, max(3, round(.010 * double(faceScale))));
arcSupport = false(size(seed));
for angle = [-15, 0, 15]
    closeElement = strel('line', arcLength, angle);
    openElement = strel('line', shortLength, angle);
    closed = imclose(seed, closeElement);
    arcSupport = arcSupport | imdilate(imopen(closed, openElement), ...
        strel('disk', 1, 0));
end
foldCore = seed & arcSupport;
if any(foldCore(:))
    foldRadius = min(5, max(2, round(.008 * double(faceScale))));
    protection = featherSoftMask(foldCore, foldRadius, .92);
    protection(foldCore) = .92;
end
end

function value = percentileValue(sortedValues, fraction)
index = 1 + round(fraction * (numel(sortedValues) - 1));
value = sortedValues(index);
end

function sigma = noseLowFrequencySigma(faceScale)
%NOSELOWFREQUENCYSIGMA 按脸部尺度抑制鼻内毛孔和雀斑高频。
sigma = min(8, max(1.25, .018 * double(faceScale)));
end

function protection = lowFrequencyStructureProtection(gradient, interior)
%LOWFREQUENCYSTRUCTUREPROTECTION 将鼻内低频梯度映射为连续软保护。
protection = zeros(size(gradient));
if nnz(interior) < 4
    return;
end
values = sort(gradient(interior));
low = percentileValue(values, .65);
high = max(percentileValue(values, .95), low + 1e-6);
protection(interior) = smoothStep(gradient(interior), low, high);
end

function [core, boundary] = detectNostrilBoundary(grayImage, interior, faceScale)
%DETECTNOSTRILBOUNDARY 只识别有连续尺度的鼻孔暗谷及其边界。
core = false(size(interior));
boundary = false(size(interior));
if nnz(interior) < 12
    return;
end

lowSigma = noseLowFrequencySigma(faceScale);
lowFrequency = imgaussfilt(grayImage, lowSigma, 'Padding', 'replicate');
surrounding = imgaussfilt(lowFrequency, min(12, max(2.5, ...
    2.2 * lowSigma)), 'Padding', 'replicate');
darkValley = surrounding - lowFrequency;
[gradientX, gradientY] = gradient(lowFrequency);
gradientMagnitude = hypot(gradientX, gradientY);

gradientValues = sort(gradientMagnitude(interior));
darkValues = sort(darkValley(interior));
gradientThreshold = max(.012, percentileValue(gradientValues, .92));
darkThreshold = max(.018, percentileValue(darkValues, .90));
seed = interior & gradientMagnitude >= gradientThreshold & ...
    darkValley >= darkThreshold;

% 只接受达到脸部尺度的连续区域；单个斑点即使梯度很高也会被滤掉。
closeRadius = min(3, max(1, round(.006 * faceScale)));
closedSeed = imclose(seed, strel('disk', closeRadius, 0));
% 鼻孔占脸部面积很小，阈值过高会在高分辨率照片中漏掉真实鼻孔。
% 同时由组件跨度和填充率过滤孤立雀斑，保持尺度自适应。
minimumArea = max(8, round(.0003 * double(faceScale) ^ 2));
nostrilRegion = keepNostrilComponents(closedSeed, minimumArea, faceScale);
if ~any(nostrilRegion(:))
    return;
end
core = nostrilRegion & interior;
boundary = core & ~imerode(core, strel('disk', 1, 0));
boundary = boundary & interior;
end

function output = keepNostrilComponents(seed, minimumArea, faceScale)
%KEEPNOSTRILCOMPONENTS 过滤面积过小、没有细长尺度的孤立斑点。
output = false(size(seed));
if ~any(seed(:))
    return;
end
components = bwconncomp(seed, 8);
minimumSpan = max(3, round(.01 * double(faceScale)));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    if numel(pixels) < minimumArea
        continue;
    end
    [rows, columns] = ind2sub(size(seed), pixels);
    span = max(max(rows) - min(rows) + 1, max(columns) - min(columns) + 1);
    fillRatio = numel(pixels) / max(1, ...
        (max(rows) - min(rows) + 1) * (max(columns) - min(columns) + 1));
    if span >= minimumSpan && fillRatio >= .18
        output(pixels) = true;
    end
end
end

function semantics = semanticRegions(context, imageSize)
if isfield(context, 'regions')
    semantics = context.regions;
else
    semantics = unstackSemantics(context.semanticProbabilities, imageSize);
end
semantics = validateSemantics(semantics, imageSize);
end

function semantics = semanticConfidence(context, imageSize)
if isfield(context, 'regionConfidence')
    semantics = context.regionConfidence;
elseif isfield(context, 'semanticConfidence')
    semantics = unstackSemantics(context.semanticConfidence, imageSize);
else
    semantics = semanticRegions(context, imageSize);
end
semantics = validateSemantics(semantics, imageSize);
end

function semantics = unstackSemantics(values, imageSize)
names = faceParsingClassNames();
if ~isnumeric(values) || ~isreal(values) || ndims(values) ~= 3 || ...
        ~isequal(size(values), [imageSize, numel(names)]) || ...
        any(~isfinite(values(:))) || any(values(:) < 0) || ...
        any(values(:) > 1)
    error('masks:InvalidContext', '语义概率堆栈无效。');
end
semantics = struct();
for index = 1:numel(names)
    semantics.(names{index}) = double(values(:, :, index));
end
end

function semantics = validateSemantics(semantics, imageSize)
names = faceParsingClassNames();
if ~isstruct(semantics) || ~isscalar(semantics)
    error('masks:InvalidContext', '语义概率必须是标量结构体。');
end
for index = 1:numel(names)
    name = names{index};
    if ~isfield(semantics, name)
        error('masks:InvalidContext', '语义类别 %s 缺失。', name);
    end
    value = semantics.(name);
    if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
            ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:))) || any(value(:) < 0) || ...
            any(value(:) > 1)
        error('masks:InvalidContext', '语义类别 %s 无效。', name);
    end
    semantics.(name) = double(value);
end
end

function value = readOptionalMask(context, name, imageSize)
if ~isfield(context, name)
    value = zeros(imageSize);
    return;
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 %s 无效。', name);
end
value = double(value);
end

function validateImageAndFace(inputImage, faceBox)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('masks:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > size(inputImage, 2) || ...
        faceBox(2) + faceBox(4) - 1 > size(inputImage, 1)
    error('masks:InvalidFaceBox', '人脸框超出图像范围。');
end
end
