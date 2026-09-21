function [reference, coverage] = buildRobustSurfaceReference( ...
        value, reliability, faceScale, mode)
%BUILDROBUSTSURFACEREFERENCE 从安全皮肤参考构造有限尺度鲁棒曲面。
%   value 与 reliability 必须是同尺寸二维图。参考池只由调用方提供的
%   reliability 决定；本函数不读取语义字段，也不扩大任何保护区域。
%   luminance 模式用偏亮的局部分位统计拒绝暗色雀斑，median 模式对
%   色度使用截尾中值，mid 模式对有符号中频使用偏亮分位曲面；三者
%   都只在调用方提供的可靠域内取样，避免把 RGB 均值误当成肤色目标。

if nargin < 4 || isempty(mode)
    mode = 'median';
end
if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value) || ...
        any(~isfinite(value(:)))
    error('beauty:InvalidSurfaceReference', ...
        '鲁棒曲面参考值必须是有限二维数值图。');
end
if ~isnumeric(reliability) || ~isreal(reliability) || ...
        ~isequal(size(value), size(reliability)) || ...
        any(~isfinite(reliability(:))) || any(reliability(:) < 0) || ...
        any(reliability(:) > 1)
    error('beauty:InvalidSurfaceReference', ...
        '鲁棒曲面参考门必须是同尺寸 [0,1] 数值图。');
end
if ~isnumeric(faceScale) || ~isreal(faceScale) || ~isscalar(faceScale) || ...
        ~isfinite(faceScale) || faceScale <= 0
    error('beauty:InvalidSurfaceReference', ...
        '鲁棒曲面参考需要正的人脸尺度。');
end
if ~(ischar(mode) || (isstring(mode) && isscalar(mode)))
    error('beauty:InvalidSurfaceReference', '鲁棒曲面参考模式无效。');
end
mode = char(mode);
if ~ismember(mode, {'luminance', 'median', 'mid'})
    error('beauty:InvalidSurfaceReference', ...
        '鲁棒曲面参考模式必须是 luminance、median 或 mid。');
end

value = double(value);
reliability = min(max(double(reliability), 0), 1);
imageSize = size(value);
valid = reliability > .05;
if ~any(valid(:))
    reference = zeros(imageSize);
    coverage = zeros(imageSize);
    return;
end

globalReference = median(value(valid));
filledValue = value;
filledValue(~valid) = globalReference;

% 小尺度保留面部曲面，大尺度只用于局部安全参考不足时补足覆盖。
radii = unique(max(2, round(double(faceScale) .* [.022, .055, .100])));
radii = min(radii, 36);
scaleWeights = 1 ./ sqrt(double(radii));
weightedReference = zeros(imageSize);
weightedCoverage = zeros(imageSize);
totalScaleWeight = sum(scaleWeights);

for index = 1:numel(radii)
    radius = radii(index);
    kernel = ones(2 * radius + 1);
    kernelPixels = sum(kernel(:));
    localWeight = imfilter(reliability, kernel, 'replicate');
    localCoverage = min(max(localWeight ./ kernelPixels, 0), 1);
    localMean = imfilter(value .* reliability, kernel, 'replicate') ./ ...
        max(localWeight, eps);

    if strcmp(mode, 'luminance') || strcmp(mode, 'mid')
        % 约 72 分位抬起局部暗离群点；与局部均值混合以保留鼻梁、
        % 颊面和额头的慢变明暗曲面，不直接使用全局最大值。
        order = max(1, min(kernelPixels, ceil(.72 * kernelPixels)));
        robustValue = ordfilt2(filledValue, order, kernel, 'symmetric');
        if strcmp(mode, 'mid')
            % Mid 是有符号残差，不能像亮度一样截断到 [0,1]。偏亮
            % 分位只负责拒绝密集雀斑的暗离群点，局部均值保留面部
            % 曲率，最终仍由调用方的频带限幅控制。
            candidate = .32 * localMean + .68 * robustValue;
        else
            candidate = .56 * localMean + .44 * robustValue;
        end
    else
        % Cb/Cr 与频率使用中值参考，避免亮度偏置渗入色度目标。
        order = max(1, min(kernelPixels, ceil(.50 * kernelPixels)));
        robustValue = ordfilt2(filledValue, order, kernel, 'symmetric');
        candidate = .35 * localMean + .65 * robustValue;
    end

    candidate(~isfinite(candidate)) = globalReference;
    scaleContribution = scaleWeights(index) .* localCoverage .^ 1.15;
    weightedReference = weightedReference + ...
        scaleContribution .* candidate;
    weightedCoverage = weightedCoverage + scaleContribution;
end

reference = weightedReference ./ max(weightedCoverage, eps);
coverage = min(max(weightedCoverage ./ max(totalScaleWeight, eps), 0), 1);
reference(coverage <= eps) = 0;
if strcmp(mode, 'luminance')
    reference = min(max(reference, 0), 1);
end
end
