function [bodySkinMask, personMask, limbMask] = buildBodySkinMaskFromSchp( ...
        probabilities, faceAndNeckMask, inputImage)
%BUILDBODYSKINMASKFROMSCHP 构建主人物身体皮肤的连续软掩膜。
%   掩膜先用 SCHP 的软概率和主人物连通性确定候选区域，再用可靠的
%   脸/颈肤色参考排除衣物和异色区域。边界只在图像边缘允许的位置羽化，
%   不用无条件 Gaussian 扩散，以免手指间隙和衣物边界被填平。
if ~isnumeric(probabilities) || ~isreal(probabilities) || ...
        ndims(probabilities) ~= 3 || size(probabilities, 3) ~= 20 || ...
        any(~isfinite(probabilities(:))) || any(probabilities(:) < 0) || ...
        any(probabilities(:) > 1)
    error('buildBodySkinMaskFromSchp:InvalidProbabilities', ...
        'Expected finite HxWx20 probabilities in [0, 1].');
end
imageSize = size(probabilities, 1:2);
if (~isnumeric(faceAndNeckMask) && ~islogical(faceAndNeckMask)) || ...
        ~isequal(size(faceAndNeckMask), imageSize) || ...
        any(~isfinite(faceAndNeckMask(:)))
    error('buildBodySkinMaskFromSchp:InvalidReferenceMask', ...
        'Face/neck reference mask size must match SCHP probabilities.');
end
if ~isa(inputImage, 'uint8') || ~isequal(size(inputImage), [imageSize, 3])
    error('buildBodySkinMaskFromSchp:InvalidImage', ...
        'inputImage must be a matching uint8 RGB image.');
end

names = schpLipClassNames();
personMask = selectSchpMainPerson(probabilities, faceAndNeckMask);
limbProbability = max(cat(3, classProbability('leftArm'), ...
    classProbability('rightArm'), classProbability('leftLeg'), ...
    classProbability('rightLeg')), [], 3);

% 这些类别是明确的非皮肤区域。保留概率而不是立刻二值化，便于在
% 后续边界处让高置信排除区域优先于软羽化结果。
excludeProbability = zeros(imageSize);
excludeNames = {'glove', 'upperClothes', 'dress', 'coat', 'socks', ...
    'pants', 'jumpsuits', 'scarf', 'skirt', 'hair', 'hat', ...
    'leftShoe', 'rightShoe'};
for index = 1:numel(excludeNames)
    excludeProbability = max(excludeProbability, ...
        classProbability(excludeNames{index}));
end
exclude = excludeProbability >= .35;

% 以主脸/颈区域建立颜色参考；若参考区域过小，才使用高置信四肢，
% 防止旁人的颜色或衣物颜色污染肤色中心。
reference = faceAndNeckMask > .35 & personMask & ~exclude;
if nnz(reference) < 3
    reference = faceAndNeckMask > .35;
end
colorMatch = matchesReferenceSkin(inputImage, reference);

% 高置信区域提供连通种子；中等置信区域必须同时通过肤色检查，避免
% 将与人体相邻的衣物、头发和背景纳入候选。
strong = limbProbability >= .55 & personMask & ~exclude;
weak = limbProbability >= .16 & limbProbability < .55 & ...
    personMask & ~exclude & colorMatch;
candidate = strong | weak;

% 只补全候选区域内部的小封闭孔洞。imfill 不会填充通向外部的空隙，
% 因而手指之间的开口不会被当成孔洞；面积和跨度上限则防止填平大结构。
candidate = fillSmallCandidateHoles(candidate, exclude, imageSize);

% 只有与高置信种子相连的候选才进入最终掩膜，避免孤立异色弱区被误处理。
if any(strong(:))
    connected = imreconstruct(uint8(strong), uint8(candidate), 8) > 0;
else
    connected = false(imageSize);
end
limbMask = connected & ~exclude;

% 其他人物的前景不属于主人的身体皮肤，即使颜色碰巧接近也要排除。
otherForeground = max(probabilities(:, :, 2:end), [], 3) >= .20 & ~personMask;
limbMask(otherForeground) = false;

% 将软概率作为初始 alpha，再用原图亮度引导局部滤波。imguidedfilter
% 会沿真实亮度边缘保留跃迁，同时只在 limbMask 内提供连续软边。
support = min(max((double(limbProbability) - .16) / (.58 - .16), 0), 1);
support = support .* double(limbMask);
guidance = im2double(rgb2gray(inputImage));
featherRadius = min(8, max(2, round(min(imageSize) * .004)));
filterSize = 2 * featherRadius + 1;
insideDistance = bwdist(~limbMask);
% 一旦低置信小孔洞通过主人物连通和面积约束被补回，就不能再次因
% 原始 SCHP 概率低而把 alpha 压成黑点。内部随距离恢复为连续高权重，
% 边界仍保留模型概率和图像引导信息。
interiorWeight = .92 * min(insideDistance / featherRadius, 1);
support = max(support, interiorWeight .* double(limbMask));
guidedSupport = imguidedfilter(support, guidance, ...
    'NeighborhoodSize', [filterSize, filterSize], ...
    'DegreeOfSmoothing', .02 ^ 2);

% 让掩膜在边界内保留一个可控的软过渡，避免处理效果在皮肤边缘
% 突然截止；不过不把 alpha 扩散到 limbMask 外，保证没有光晕渗漏。
edgeWeight = min(insideDistance / featherRadius, 1);
bodySkinMask = double(min(max(guidedSupport .* edgeWeight .* double(limbMask), 0), 1));
bodySkinMask(exclude | otherForeground) = 0;

    function value = classProbability(className)
        classIndex = find(strcmp(names, className), 1);
        value = double(probabilities(:, :, classIndex));
    end
end

function mask = fillSmallCandidateHoles(mask, exclude, imageSize)
if ~any(mask(:))
    return;
end
filled = imfill(mask, 'holes');
holes = filled & ~mask & ~exclude;
components = bwconncomp(holes, 8);
areaLimit = max(4, min(400, round(.0008 * prod(imageSize))));
spanLimit = max(3, round(.04 * min(imageSize)));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    [rows, columns] = ind2sub(imageSize, pixels);
    span = max(max(rows) - min(rows) + 1, max(columns) - min(columns) + 1);
    if numel(pixels) <= areaLimit && span <= spanLimit
        mask(pixels) = true;
    end
end
mask(exclude) = false;
end

function colorMatch = matchesReferenceSkin(inputImage, referenceMask)
reference = logical(referenceMask) & isfinite(referenceMask);
colorMatch = false(size(reference));
if nnz(reference) < 3
    return;
end

lab = rgb2lab(inputImage);
normalizedLab = cat(3, lab(:, :, 1) / 100, ...
    (lab(:, :, 2) + 128) / 255, (lab(:, :, 3) + 128) / 255);
referenceValues = reshape(normalizedLab(repmat(reference, [1, 1, 3])), [], 3);
center = median(referenceValues, 1);
deviation = median(abs(referenceValues - center), 1);
% 颜色参考允许自然光照下的适度变化，但对亮度/色度都设最低容差，
% 避免均匀参考图因为 MAD 为零而拒绝所有身体像素。
minimumTolerance = [12 / 100, 6 / 255, 6 / 255];
tolerance = max(4 * deviation, minimumTolerance);
distance = zeros(size(reference));
for channel = 1:3
    distance = distance + ((normalizedLab(:, :, channel) - center(channel)) ...
        / tolerance(channel)) .^ 2;
end
colorMatch = sqrt(distance) <= 1.35;
end
