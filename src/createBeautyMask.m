function beautyMask = createBeautyMask(inputDouble, faceBox)
%CREATEBEAUTYMASK 根据人脸框和肤色生成椭圆软 mask。

imageHeight = size(inputDouble, 1);
imageWidth = size(inputDouble, 2);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
centerX = faceBox(1) + faceBox(3) / 2;
centerY = faceBox(2) + faceBox(4) / 2;
radiusX = max(faceBox(3) / 2, 1);
radiusY = max(faceBox(4) / 2, 1);
radialDistance = sqrt(((xGrid - centerX) / radiusX) .^ 2 + ...
    ((yGrid - centerY) / radiusY) .^ 2);

% 椭圆边缘使用 smoothstep 羽化，框外区域保持为零。
featherStart = 0.80;
featherPosition = min(max((radialDistance - featherStart) / ...
    (1 - featherStart), 0), 1);
ellipseMask = 1 - featherPosition .^ 2 .* (3 - 2 * featherPosition);
ellipseCore = radialDistance <= 0.72;

% 使用适度放宽的 YCbCr 范围覆盖不同肤色，并排除明显高光。
ycbcrImage = rgb2ycbcr(inputDouble);
luminance = ycbcrImage(:, :, 1);
skinCandidate = ycbcrImage(:, :, 2) >= 0.30 & ...
    ycbcrImage(:, :, 2) <= 0.58 & ycbcrImage(:, :, 3) >= 0.46 & ...
    ycbcrImage(:, :, 3) <= 0.72 & luminance >= 0.06 & ...
    luminance <= 0.97 & radialDistance <= 1;

% 以人脸核心区的稳健亮度为基准，避免低可靠性时由少量头发主导。
referenceLuminance = median(luminance(ellipseCore));
shadowStart = max(0.025, 0.32 * referenceLuminance);
shadowEnd = max(shadowStart + 0.02, 0.72 * referenceLuminance);
shadowPosition = min(max((luminance - shadowStart) / ...
    (shadowEnd - shadowStart), 0), 1);
shadowProtection = shadowPosition .^ 2 .* (3 - 2 * shadowPosition);
skinWeight = double(skinCandidate) .* shadowProtection;

faceScale = min(faceBox(3), faceBox(4));
maskSigma = min(6, max(1.2, 0.008 * faceScale));
softSkinMask = imgaussfilt(skinWeight, maskSigma, ...
    'Padding', 'replicate');
softSkinMask = min(1, 1.7 * softSkinMask);

% 覆盖不足时混入椭圆先验，但回退同样避开相对过暗的头发和背景。
coreCount = max(nnz(ellipseCore), 1);
skinCoverage = sum(skinWeight(ellipseCore)) / coreCount;
supportCoverage = nnz(softSkinMask > 0.20 & ellipseCore) / coreCount;
densityReliability = min(max((skinCoverage - 0.10) / 0.30, 0), 1);
supportReliability = min(max(supportCoverage / 0.45, 0), 1);
maskReliability = densityReliability * supportReliability;
fallbackWeight = 0.72 * (1 - maskReliability);
fallbackPosition = min(max((radialDistance - 0.58) / 0.26, 0), 1);
fallbackSpatialMask = 1 - fallbackPosition .^ 2 .* ...
    (3 - 2 * fallbackPosition);
beautyMask = ellipseMask .* (fallbackWeight .* fallbackSpatialMask .* ...
    shadowProtection + (1 - fallbackWeight) .* softSkinMask);
% 再次施加阴影保护，阻止 Gaussian 羽化泄漏到深色头发内部。
beautyMask = beautyMask .* shadowProtection;
beautyMask = min(max(beautyMask, 0), 1);
end
