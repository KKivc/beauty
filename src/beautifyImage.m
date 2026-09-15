function beautifiedImage = beautifyImage(inputImage, params, faceBox, beautyContext)
%BEAUTIFYIMAGE 对裸露皮肤执行结构保留的磨皮和美白。

if nargin < 1 || ~isValidRgbImage(inputImage)
    error('beautifyImage:InvalidImage', ...
        'inputImage must be a uint8 three-channel RGB image.');
end
if nargin < 2 || ~isstruct(params) || ~isscalar(params) || ...
        ~isfield(params, 'smoothingStrength') || ...
        ~isfield(params, 'whiteningStrength')
    error('beautifyImage:InvalidParams', ...
        'params must contain smoothingStrength and whiteningStrength.');
end
smoothingStrength = params.smoothingStrength;
whiteningStrength = params.whiteningStrength;
if ~isValidStrength(smoothingStrength) || ~isValidStrength(whiteningStrength)
    error('beautifyImage:InvalidParams', ...
        'Beauty strengths must be finite numeric scalars in the range 0 to 100.');
end
if nargin < 3
    error('beautifyImage:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));

% 零强度在 context 构建或验证前直接返回。
if smoothingStrength == 0 && whiteningStrength == 0
    beautifiedImage = inputImage;
    return;
end
ensureImageProcessingToolbox();
if nargin < 4
    beautyContext = normalizeBeautyContext(inputImage, faceBox);
else
    try
        beautyContext = normalizeBeautyContext(inputImage, faceBox, beautyContext);
    catch exception
        if startsWith(exception.identifier, 'normalizeBeautyContext:')
            error('beautifyImage:InvalidContext', ...
                'Beauty Context 无效：%s', exception.message);
        end
        rethrow(exception);
    end
end

inputDouble = im2double(inputImage);
ycbcrImage = rgb2ycbcr(inputDouble);
originalY = ycbcrImage(:, :, 1);
originalCb = ycbcrImage(:, :, 2);
originalCr = ycbcrImage(:, :, 3);
protectionMask = beautyContext.featureProtectionMask;
if isfield(beautyContext, 'hardProtectionMask')
    hardProtectionMask = beautyContext.hardProtectionMask;
else
    hardProtectionMask = protectionMask >= .999;
end
skinMask = min(max(beautyContext.skinMask, 0), 1);
faceSkinMask = min(max(beautyContext.faceSkinMask, 0), 1);
% 先把语义皮肤分成互斥的脸部与脸外区域，再各自合并一次软保护权重。
% 不再先乘 skinMask、再乘区域 mask、最后重复乘 effectMask，避免边界
% 权重被压窄后形成可见的皮肤块分界。
faceRegionMask = min(skinMask, faceSkinMask);
nonFaceRegionMask = max(skinMask - faceRegionMask, 0);
effectRegionMask = min(max(1 - protectionMask, 0), 1);
faceEffectMask = faceRegionMask .* effectRegionMask;
nonFaceEffectMask = nonFaceRegionMask .* effectRegionMask;
faceScale = min(faceBox(3:4));
profile = beautySmoothingProfile(smoothingStrength);

% 美白与分区中值校正在硬保护边界附近平滑退让，避免保护区内外
% 形成肉眼可见的亮度台阶。
featureSetback = ones(size(originalY));
hardCore = hardProtectionMask >= .999;
if any(hardCore(:))
    setbackRadius = min(10, max(5, round(.024 * faceScale)));
    setbackT = min(max(bwdist(hardCore) ./ (setbackRadius + 1), 0), 1);
    featureSetback = setbackT .^ 2 .* (3 - 2 * setbackT);
end

% 大尺度基底承载脸部立体结构，只衰减中尺度色斑和高频纹理。
fineSigma = min(4.5, max(0.9, 0.006 * faceScale));
% 固定分解尺度，确保同一图像上的滑块响应连续单调。
mediumSigma = min(32, max(5, 0.045 * faceScale));
if exist('imguidedfilter', 'file') ~= 0
    fineBase = imguidedfilter(originalY, 'NeighborhoodSize', ...
        max(3, 2 * floor(fineSigma) + 1), 'DegreeOfSmoothing', fineSigma ^ 2 / 8);
    lowFrequency = imguidedfilter(fineBase, 'NeighborhoodSize', ...
        max(5, 2 * floor(mediumSigma / 2) + 1), ...
        'DegreeOfSmoothing', mediumSigma ^ 2 / 10);
else
    fineBase = imbilatfilt(originalY, 0.08, max(1, fineSigma));
    lowFrequency = imbilatfilt(fineBase, 0.08, max(2, mediumSigma / 2));
end
fineDetail = originalY - fineBase;
mediumDetail = fineBase - lowFrequency;

% 低频梯度只保护真正的面部形状，不把孤立雀斑误判为结构。
[horizontalGradient, verticalGradient] = gradient(lowFrequency);
structureGradient = hypot(horizontalGradient, verticalGradient);
structureProtection = min(max((structureGradient - 0.009) / 0.055, 0), 1);
% 局部斑点也可能产生梯度，但不会形成达到脸部尺度的连续结构。
% 这条 mask 专门阻止稳健邻域参考跨越鼻梁、脸缘、手指等长边缘。
minimumStructureArea = max(12, round(.0015 * double(faceScale) ^ 2));
continuousStructureCore = bwareaopen( ...
    structureProtection >= .25, minimumStructureArea, 8);
structureRadius = min(4, max(1, round(.006 * faceScale)));
continuousStructureProtection = imgaussfilt( ...
    double(imdilate(continuousStructureCore, ...
    strel('disk', structureRadius, 0))), max(.8, structureRadius / 2), ...
    'Padding', 'replicate');
continuousStructureProtection = min(max( ...
    continuousStructureProtection, 0), 1);
% 分区独立估计局部基线，避免手臂、肩部等区域改变脸部的异常阈值。
faceSkinPixels = faceEffectMask > .25 & protectionMask < .35;
nonFaceSkinPixels = nonFaceEffectMask > .25 & protectionMask < .35;

% 普通皮肤只做轻度平滑，局部亮度异常处才提高修复权重。
[faceMediumBaseline, faceMediumScale] = robustResidualBaseline( ...
    mediumDetail, faceSkinPixels);
[nonFaceMediumBaseline, nonFaceMediumScale] = robustResidualBaseline( ...
    mediumDetail, nonFaceSkinPixels);
faceMediumAnomaly = residualAnomaly(abs(mediumDetail), ...
    faceMediumBaseline, faceMediumScale, .006, .025, 1.0);
nonFaceMediumAnomaly = residualAnomaly(abs(mediumDetail), ...
    nonFaceMediumBaseline, nonFaceMediumScale, .006, .025, 1.0);
% 中等偏离也应在高档逐步纳入瑕疵处理，避免斑点边缘残留。
mediumAnomaly = faceRegionMask .* sqrt(faceMediumAnomaly) + ...
    nonFaceRegionMask .* sqrt(nonFaceMediumAnomaly);

% 高频细节只作为辅助证据，避免把正常毛孔或细纹单独当作瑕疵。
[faceFineBaseline, faceFineScale] = robustResidualBaseline( ...
    fineDetail, faceSkinPixels);
[nonFaceFineBaseline, nonFaceFineScale] = robustResidualBaseline( ...
    fineDetail, nonFaceSkinPixels);
faceFineAnomaly = residualAnomaly(abs(fineDetail), faceFineBaseline, ...
    faceFineScale, .010, .030);
nonFaceFineAnomaly = residualAnomaly(abs(fineDetail), ...
    nonFaceFineBaseline, nonFaceFineScale, .010, .030);
fineAnomaly = faceRegionMask .* faceFineAnomaly + ...
    nonFaceRegionMask .* nonFaceFineAnomaly;

% 色度异常与亮度异常共同决定瑕疵权重，避免只按灰度抹平肤色。
localCb = originalCb;
localCr = originalCr;
chromaAnomaly = zeros(size(originalY));
if smoothingStrength > 0
    chromaSigma = min(12, max(2.5, 0.025 * faceScale));
    localCb = imgaussfilt(originalCb, chromaSigma, 'Padding', 'replicate');
    localCr = imgaussfilt(originalCr, chromaSigma, 'Padding', 'replicate');
    [faceCbBaseline, faceCbScale] = robustResidualBaseline( ...
        originalCb - localCb, faceSkinPixels);
    [nonFaceCbBaseline, nonFaceCbScale] = robustResidualBaseline( ...
        originalCb - localCb, nonFaceSkinPixels);
    [faceCrBaseline, faceCrScale] = robustResidualBaseline( ...
        originalCr - localCr, faceSkinPixels);
    [nonFaceCrBaseline, nonFaceCrScale] = robustResidualBaseline( ...
        originalCr - localCr, nonFaceSkinPixels);
    faceCbAnomaly = residualAnomaly(abs(originalCb - localCb), ...
        faceCbBaseline, faceCbScale, .010, .030);
    nonFaceCbAnomaly = residualAnomaly(abs(originalCb - localCb), ...
        nonFaceCbBaseline, nonFaceCbScale, .010, .030);
    faceCrAnomaly = residualAnomaly(abs(originalCr - localCr), ...
        faceCrBaseline, faceCrScale, .010, .030);
    nonFaceCrAnomaly = residualAnomaly(abs(originalCr - localCr), ...
        nonFaceCrBaseline, nonFaceCrScale, .010, .030);
    faceChromaAnomaly = max(faceCbAnomaly, faceCrAnomaly);
    nonFaceChromaAnomaly = max(nonFaceCbAnomaly, nonFaceCrAnomaly);
    chromaAnomaly = faceRegionMask .* faceChromaAnomaly + ...
        nonFaceRegionMask .* nonFaceChromaAnomaly;
end
blemishAnomaly = max(cat(3, mediumAnomaly, chromaAnomaly, ...
    .25 * fineAnomaly), [], 3);
% 高档区间只额外增强高置信瑕疵，不改变普通皮肤的封顶曲线。
extraBlemishRange = max((profile.ratio - .5) / .5, 0);
blemishBoost = min(1, profile.highBoost + .25 * extraBlemishRange);
% 孤立瑕疵可能在低频梯度中留下局部响应，不能因此被当作脸部结构保护。
% 只有缺少瑕疵证据的连续梯度才保持完整保护权重。
% 区域级软光影保护：鼻侧影、眼窝等大面积平缓明暗的逐像素梯度低于
% structureProtection 的起判阈值，直接放行会让高档磨皮抹平立体感。
% 用平滑后的区域梯度补充识别；真实光影是方向连贯的坡面，而雀斑场
% 的梯度方向各向同性、会在结构张量中互相抵消，因此叠加方向一致性
% 门控，并用瑕疵证据抑制，避免保护雀斑场。
softShadingSigma = max(2, mediumSigma / 3);
softShadingGradient = imgaussfilt(structureGradient, softShadingSigma, ...
    'Padding', 'replicate');
tensorXX = imgaussfilt(horizontalGradient .^ 2, softShadingSigma, ...
    'Padding', 'replicate');
tensorYY = imgaussfilt(verticalGradient .^ 2, softShadingSigma, ...
    'Padding', 'replicate');
tensorXY = imgaussfilt(horizontalGradient .* verticalGradient, ...
    softShadingSigma, 'Padding', 'replicate');
orientationCoherence = sqrt((tensorXX - tensorYY) .^ 2 + ...
    4 * tensorXY .^ 2) ./ (tensorXX + tensorYY + eps);
softShadingEvidence = min(max( ...
    (softShadingGradient - .0028) / .0072, 0), 1) .* ...
    min(max((orientationCoherence - .45) / .35, 0), 1) .* ...
    (1 - .85 * blemishAnomaly);
softShadingCore = bwareaopen(softShadingEvidence >= .30, ...
    max(80, round(.004 * double(faceScale) ^ 2)), 8);
softShadingProtection = zeros(size(originalY));
if any(softShadingCore(:))
    softShadingBand = imgaussfilt(double(softShadingCore), ...
        max(2, softShadingSigma / 2), 'Padding', 'replicate');
    bandPeak = max(softShadingBand(:));
    if bandPeak > 0
        softShadingProtection = min(1, softShadingBand ./ bandPeak) .* ...
            min(1, 1.25 * softShadingEvidence);
    end
end
detailStructureProtection = max(structureProtection .* ...
    (1 - .85 * blemishAnomaly), softShadingProtection);
% 用异常置信度抑制邻域中的离群像素，得到局部稳健肤色参考。
% 窗口按脸部尺度覆盖完整斑点，但只让非瑕疵像素贡献参考，因此不会
% 像普通大核模糊一样把鼻梁、眼窝或手指结构带入修复结果。
neighborhoodRadius = min(10, max(4, round(.024 * faceScale)));
neighborhoodSize = 2 * neighborhoodRadius + 1;
neighborhoodKernel = ones(neighborhoodSize, neighborhoodSize) / ...
    neighborhoodSize ^ 2;
reliableNeighborhood = max(1 - blemishAnomaly, .01);
referenceWeight = imfilter(reliableNeighborhood, neighborhoodKernel, ...
    'replicate');
robustLowFrequency = imfilter(lowFrequency .* reliableNeighborhood, ...
    neighborhoodKernel, 'replicate') ./ max(referenceWeight, eps);
% 脸部与脸外分别计算处理权重，后续可独立替换两套频率曲线。
faceProcessingWeight = profile.baseWeight + ...
    (1 - profile.baseWeight) .* blemishAnomaly;
nonFaceProcessingWeight = profile.baseWeight + ...
    (1 - profile.baseWeight) .* blemishAnomaly;
% 脸外效果随滑块非线性启用，最高档不超过脸部约一半。
nonFaceSmoothingWeight = nonFaceSmoothingEffectWeight(smoothingStrength);
nonFaceMediumWeight = .80 * nonFaceSmoothingWeight;
nonFaceChromaWeight = min(.55, .80 * nonFaceSmoothingWeight);
% 结构保护在 75-100 档不因整体强度而减弱；仅在瑕疵证据充分时放宽。
fineStructureCoefficient = .98 - .18 * profile.highBoost .* blemishAnomaly;
mediumStructureCoefficient = .98 - .60 * profile.highBoost .* blemishAnomaly;
% 两个区域的 alpha 在这里各自只组合一次，避免区域 mask 与效果 mask
% 的重复相乘压窄软边界。高频/中频仍共用同一结构保护带。
faceFineProcessingMask = min(faceEffectMask, faceEffectMask .* ...
    faceProcessingWeight .* (1 + .10 * profile.highBoost .* blemishAnomaly) .* ...
    (1 - fineStructureCoefficient .* detailStructureProtection));
nonFaceFineProcessingMask = min(nonFaceSmoothingWeight .* nonFaceEffectMask, ...
    nonFaceSmoothingWeight .* nonFaceEffectMask .* nonFaceProcessingWeight .* ...
    (1 - fineStructureCoefficient .* detailStructureProtection));
fineProcessingMask = min(1, faceFineProcessingMask + ...
    nonFaceFineProcessingMask);
faceMediumProcessingMask = min(faceEffectMask, faceEffectMask .* ...
    faceProcessingWeight .* (1 + .50 * profile.highBoost .* blemishAnomaly) .* ...
    (1 - mediumStructureCoefficient .* detailStructureProtection));
nonFaceMediumProcessingMask = min(nonFaceMediumWeight .* nonFaceEffectMask, ...
    nonFaceMediumWeight .* nonFaceEffectMask .* nonFaceProcessingWeight .* ...
    (1 - mediumStructureCoefficient .* detailStructureProtection));
mediumProcessingMask = min(1, faceMediumProcessingMask + ...
    nonFaceMediumProcessingMask);
faceChromaProcessingMask = min(faceEffectMask, faceEffectMask .* ...
    faceProcessingWeight .* (1 + .30 * profile.highBoost .* blemishAnomaly));
nonFaceChromaProcessingMask = min(nonFaceChromaWeight .* nonFaceEffectMask, ...
    nonFaceChromaWeight .* nonFaceEffectMask .* nonFaceProcessingWeight);
chromaProcessingMask = min(1, faceChromaProcessingMask + ...
    nonFaceChromaProcessingMask);

if smoothingStrength > 0
    % 高档只对已识别的异常区域进一步收敛，普通皮肤仍沿用基础保留率。
    % 斑点核心按原始异常度彻底清除，雀斑带的整体过渡按平滑异常场
    % 渐近收敛；两者叠加后仍保留最低纹理，避免形成苍白死斑。
    blemishField = imgaussfilt(blemishAnomaly, ...
        max(1.5, .006 * faceScale), 'Padding', 'replicate');
    coreConvergence = smoothStep( ...
        6.0 * blemishBoost .* blemishAnomaly, 0, 1);
    bandConvergence = smoothStep( ...
        2.2 * blemishBoost .* blemishField, 0, 1);
    anomalyConvergence = .45 * coreConvergence + .45 * bandConvergence;
    fineRetention = profile.fineRetention .* (1 - .90 * anomalyConvergence);
    mediumRetention = profile.mediumRetention .* ...
        (1 - .90 * anomalyConvergence);
    outputY = originalY + mediumProcessingMask .* ...
        (mediumRetention - 1) .* mediumDetail + ...
        fineProcessingMask .* (fineRetention - 1) .* fineDetail;
    % 斑点密集区（眉上方雀斑带等）的中频/高频删除不是零均值的：
    % 连带删掉整条带的平均色沉会让它比周围皮肤更苍白。把删除量中
    % 超过局部均值的部分沉淀回去，只保留零均值的斑点清除。
    toneCompensationSigma = max(10, 1.5 * mediumSigma);
    mediumRemoved = mediumProcessingMask .* (1 - mediumRetention) .* ...
        mediumDetail;
    fineRemoved = fineProcessingMask .* (1 - fineRetention) .* fineDetail;
    % 高斯均值补偿会渗出效果区边界，用效果 mask 门控，保证背景和
    % 硬保护特征处的补偿量严格为零。
    regionGate = min(1, faceEffectMask + nonFaceEffectMask);
    mediumRemovedMean = imgaussfilt(mediumRemoved, ...
        toneCompensationSigma, 'Padding', 'replicate') .* regionGate;
    fineRemovedMean = imgaussfilt(fineRemoved, ...
        toneCompensationSigma, 'Padding', 'replicate') .* regionGate;
    outputY = outputY + mediumRemovedMean + fineRemovedMean;

    localReferenceMask = min(1, max(fineProcessingMask, ...
        mediumProcessingMask)) .* profile.highBoost .* ...
        blemishBoost .* blemishAnomaly .^ 1.25 .* ...
        (1 - .55 * detailStructureProtection) .* ...
        (1 - .98 * continuousStructureProtection);
    localReferenceMask = min(1, 1.03 * localReferenceMask);
    outputY = outputY + localReferenceMask .* ...
        (robustLowFrequency - outputY);

    % 对仍未达到异常阈值、但明显低于邻域肤色的暗斑，只做正向抬升。
    % 不压低亮部，避免把鼻梁高光、眼窝和唇周结构拉平。
    toneRadius = min(8, max(3, round(.018 * faceScale)));
    toneWindow = 2 * toneRadius + 1;
    skinToneReference = medfilt2(originalY, [toneWindow, toneWindow], ...
        'symmetric');
    darkToneDelta = max(skinToneReference - outputY, 0);
    skinInterior = bwdist(skinMask < .35) > toneRadius;
    noseToneWeight = ones(size(originalY));
    if isfield(beautyContext, 'regions') && ...
            isfield(beautyContext.regions, 'nose')
        noseProbability = min(max(double(beautyContext.regions.nose), 0), 1);
        noseToneWeight = 1 - .90 * noseProbability;
    end
    toneStrength = min(1, .35 + 1.05 * blemishBoost);
    toneRegionMask = min(1, faceEffectMask + ...
        .80 * nonFaceSmoothingWeight .* nonFaceEffectMask);
    toneMask = toneRegionMask .* double(skinInterior) .* ...
        toneStrength .* max(blemishAnomaly, .40) .* ...
        (1 - .95 * continuousStructureProtection) .* ...
        (1 - .55 * structureProtection) .* noseToneWeight .* ...
        (1 - .90 * softShadingProtection);
    % 只抬升显著低于局部中值的残留斑点；平缓的带状明暗不再被整体
    % 提亮，避免雀斑带被抬成眉毛上方的苍白区块。
    deltaGate = smoothStep(darkToneDelta, .002, .020);
    outputY = outputY + .85 * toneMask .* deltaGate .* darkToneDelta;

    % 色度异常同步衰减，避免亮度处理后仍残留橙红色斑。
    % 75 档后普通皮肤色度处理封顶，仅高置信色斑继续增强。
    excessHighBoost = max(blemishBoost - .5, 0);
    chromaEffect = min(1, profile.chromaEffect + ...
        .15 * max(profile.highBoost - .5, 0) + ...
        .35 * excessHighBoost .* chromaAnomaly);
    % 色度删除同样不是零均值：雀斑带的棕色色沉会被整体删掉。
    % 补回局部均值，只清除斑点起伏，保留带状色沉。
    chromaRemovedCb = chromaProcessingMask .* chromaEffect .* ...
        (originalCb - localCb);
    chromaRemovedCr = chromaProcessingMask .* chromaEffect .* ...
        (originalCr - localCr);
    chromaMeanCb = imgaussfilt(chromaRemovedCb, toneCompensationSigma, ...
        'Padding', 'replicate') .* regionGate;
    chromaMeanCr = imgaussfilt(chromaRemovedCr, toneCompensationSigma, ...
        'Padding', 'replicate') .* regionGate;
    outputCb = originalCb - (chromaRemovedCb - chromaMeanCb);
    outputCr = originalCr - (chromaRemovedCr - chromaMeanCr);
    extraChromaRepair = .35 * max(blemishBoost - .5, 0) .* ...
        chromaAnomaly .* min(1, faceEffectMask + ...
        nonFaceSmoothingWeight .* nonFaceEffectMask) .* ...
        (1 - .25 * detailStructureProtection);
    outputCb = outputCb + extraChromaRepair .* (localCb - outputCb);
    outputCr = outputCr + extraChromaRepair .* (localCr - outputCr);
else
    outputY = originalY;
    outputCb = originalCb;
    outputCr = originalCr;
end

% 磨皮只改变局部变异，不应改变各分区自身的整体色调中位数。
% 脸部与脸外分别回补，避免一侧的肤色把另一侧带偏。
if smoothingStrength > 0
    if any(faceSkinPixels(:))
        faceMedianCorrection = [
            median(originalY(faceSkinPixels)) - median(outputY(faceSkinPixels)), ...
            median(originalCb(faceSkinPixels)) - median(outputCb(faceSkinPixels)), ...
            median(originalCr(faceSkinPixels)) - median(outputCr(faceSkinPixels))];
        outputY = outputY + faceEffectMask .* faceMedianCorrection(1) .* ...
            featureSetback;
        outputCb = outputCb + faceEffectMask .* faceMedianCorrection(2) .* ...
            featureSetback;
        outputCr = outputCr + faceEffectMask .* faceMedianCorrection(3) .* ...
            featureSetback;
    end
    if any(nonFaceSkinPixels(:))
        nonFaceMedianCorrection = [
            median(originalY(nonFaceSkinPixels)) - median(outputY(nonFaceSkinPixels)), ...
            median(originalCb(nonFaceSkinPixels)) - median(outputCb(nonFaceSkinPixels)), ...
            median(originalCr(nonFaceSkinPixels)) - median(outputCr(nonFaceSkinPixels))];
        outputY = outputY + nonFaceSmoothingWeight .* nonFaceEffectMask .* ...
            nonFaceMedianCorrection(1) .* featureSetback;
        outputCb = outputCb + nonFaceSmoothingWeight .* nonFaceEffectMask .* ...
            nonFaceMedianCorrection(2) .* featureSetback;
        outputCr = outputCr + nonFaceSmoothingWeight .* nonFaceEffectMask .* ...
            nonFaceMedianCorrection(3) .* featureSetback;
    end
end

if whiteningStrength > 0
    ratio = whiteningStrength / 100;
    faceTonePixels = faceRegionMask > .35 & protectionMask < .35;
    nonFaceTonePixels = nonFaceRegionMask > .35 & protectionMask < .35;
    faceMedianY = regionalMedian(originalY, faceTonePixels, .78);
    nonFaceMedianY = regionalMedian(originalY, nonFaceTonePixels, .78);
    faceWhiteningNeed = min(max((0.78 - faceMedianY) / .35, .25), 1);
    nonFaceWhiteningNeed = min(max((0.78 - nonFaceMedianY) / .35, .25), 1);
    % 有界单调中间调曲线，最大档仍保留亮度排序和高光层次。
    toneStrength = 0.27 * (1 - exp(-6 * ratio)) / ...
        (1 - exp(-6)) + 0.16 * ratio;
    nonFaceWhiteningWeight = nonFaceWhiteningEffectWeight(whiteningStrength);
    whiteningStrengthMap = faceWhiteningNeed .* faceEffectMask + ...
        nonFaceWhiteningNeed .* nonFaceWhiteningWeight .* nonFaceEffectMask;
    whiteningStrengthMap = toneStrength .* whiteningStrengthMap .* ...
        featureSetback;
    highlightProtection = min(max((0.97 - outputY) / 0.20, 0), 1);
    increase = whiteningStrengthMap .* highlightProtection .^ 2 .* ...
        outputY .* (1 - outputY);
    outputY = outputY + min(increase, max(0, 0.975 - outputY));
end

ycbcrImage(:, :, 1) = min(max(outputY, 0), 1);
ycbcrImage(:, :, 2) = min(max(outputCb, 0), 1);
ycbcrImage(:, :, 3) = min(max(outputCr, 0), 1);
outputDouble = min(max(ycbcr2rgb(ycbcrImage), 0), 1);
beautifiedImage = uint8(round(outputDouble * 255));
% 语义硬保护区逐像素复用原图，避免颜色空间往返造成任何改动。
hardPixels = hardProtectionMask >= 0.999;
for channel = 1:size(inputImage, 3)
    outputChannel = beautifiedImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(hardPixels) = sourceChannel(hardPixels);
    beautifiedImage(:, :, channel) = outputChannel;
end
if ~isequal(size(beautifiedImage), size(inputImage))
    error('beautifyImage:InvalidOutput', ...
        'The beautified image must preserve the input dimensions.');
end
end

function [baseline, scale] = robustResidualBaseline(residual, mask)
%ROBUSTRESIDUALBASELINE 用中位数和 MAD 估计局部纹理基线。
if any(mask(:))
    values = abs(residual(mask));
    baseline = median(values);
    madValue = median(abs(values - baseline));
    scale = 1.4826 * madValue;
else
    baseline = 0;
    scale = 0;
end
end

function anomaly = residualAnomaly(residual, baseline, scale, floorThreshold, ...
        span, scaleMultiplier)
%RESIDUALANOMALY 将超出局部基线的残差连续映射为 [0, 1] 权重。
if nargin < 6
    scaleMultiplier = 2;
end
onset = baseline + scaleMultiplier * scale + floorThreshold;
normalized = min(max((residual - onset) / max(span, 3 * scale), 0), 1);
anomaly = normalized .^ 2 .* (3 - 2 * normalized);
end

function alpha = smoothStep(value, low, high)
%SMOOTHSTEP 将数值从 low 到 high 平滑映射为 [0, 1]。
t = min(max((value - low) / max(high - low, eps), 0), 1);
alpha = t .^ 2 .* (3 - 2 * t);
end

function weight = nonFaceSmoothingEffectWeight(strength)
%NONFACESMOOTHINGEFFECTWEIGHT 身体皮肤参与均肤但弱于脸部，保留
% 手部关节和肢体本身的结构与纹理，避免乳化感。
ratio = min(max(strength / 100, 0), 1);
weight = 0.55 * ratio ^ 2 * (3 - 2 * ratio);
end

function weight = nonFaceWhiteningEffectWeight(strength)
%NONFACEWHITENINGEFFECTWEIGHT 身体提亮明显弱于脸部，保持肢体的
% 暖调与明暗，避免手背被提成苍白的一层膜。
ratio = min(max(strength / 100, 0), 1);
weight = 0.50 * ratio ^ .35;
end

function value = regionalMedian(imageChannel, mask, fallback)
%REGIONALMEDIAN 只从当前分区取色调统计，空分区使用固定参考值。
if any(mask(:))
    value = median(imageChannel(mask));
else
    value = fallback;
end
end

function isValid = isValidRgbImage(inputImage)
isValid = isa(inputImage, 'uint8') && isreal(inputImage) && ...
    ndims(inputImage) == 3 && size(inputImage, 3) == 3;
end

function isValid = isValidStrength(strength)
isValid = isnumeric(strength) && isreal(strength) && isscalar(strength) && ...
    isfinite(strength) && strength >= 0 && strength <= 100;
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ~isequal(size(faceBox), [1, 4]) || ...
        any(~isfinite(faceBox)) || faceBox(1) < 1 || faceBox(2) < 1 || ...
        faceBox(3) <= 0 || faceBox(4) <= 0 || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('beautifyImage:InvalidFaceBox', ...
        'faceBox must be one finite [x y width height] rectangle within the image.');
end
end

function ensureImageProcessingToolbox
requiredFunctions = {'rgb2ycbcr', 'ycbcr2rgb', 'imgaussfilt'};
if any(cellfun(@(name) exist(name, 'file') == 0, requiredFunctions))
    error('beautifyImage:MissingToolbox', ...
        'Image Processing Toolbox is required for beauty processing.');
end
end
