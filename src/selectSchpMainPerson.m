function personMask = selectSchpMainPerson(probabilities, faceRegion)
%SELECTSCHPMAINPERSON 选择与主脸区域重叠最多的 SCHP 前景连通域。
if ~isnumeric(probabilities) || ndims(probabilities) ~= 3 || ...
        size(probabilities, 3) ~= 20 || any(~isfinite(probabilities(:)))
    error('selectSchpMainPerson:InvalidProbabilities', ...
        'Expected finite HxWx20 SCHP probabilities.');
end
imageSize = size(probabilities, 1:2);
if ~isnumeric(faceRegion) && ~islogical(faceRegion)
    error('selectSchpMainPerson:InvalidFaceRegion', ...
        'faceRegion must be a numeric or logical mask.');
end
if ~isequal(size(faceRegion), imageSize) || any(~isfinite(faceRegion(:)))
    error('selectSchpMainPerson:InvalidFaceRegion', ...
        'faceRegion size must match SCHP probabilities.');
end

foreground = max(probabilities(:, :, 2:end), [], 3) >= .20;
components = bwconncomp(foreground, 8);
faceCore = faceRegion > .20;
personMask = false(imageSize);
bestOverlap = 0;
bestArea = 0;
bestPixels = [];
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    overlap = nnz(faceCore(pixels));
    area = numel(pixels);
    if overlap > bestOverlap || (overlap == bestOverlap && overlap > 0 && area > bestArea)
        bestOverlap = overlap;
        bestArea = area;
        bestPixels = pixels;
    end
end
if bestOverlap > 0
    personMask(bestPixels) = true;
else
    return;
end

% 手臂常被阴影或背景缝隙切成独立组件；按主体尺度和人体包围盒补回。
[baseRows, baseCols] = ind2sub(imageSize, bestPixels);
x1 = min(baseCols);
x2 = max(baseCols);
y1 = min(baseRows);
y2 = max(baseRows);
personWidth = x2 - x1 + 1;
personHeight = y2 - y1 + 1;
personScale = max(personWidth, personHeight);
gapRadius = max(4, round(.08 * personScale));
envelope = [max(1, x1 - round(.60 * personWidth)), ...
    max(1, y1 - round(.35 * personHeight)), ...
    min(imageSize(2), x2 + round(.60 * personWidth)), ...
    min(imageSize(1), y2 + round(1.00 * personHeight))];
distanceToPerson = bwdist(personMask);
names = schpLipClassNames();
limbNames = {'leftArm', 'rightArm', 'leftLeg', 'rightLeg'};
limbProbability = zeros(imageSize);
for index = 1:numel(limbNames)
    classIndex = find(strcmp(names, limbNames{index}), 1);
    limbProbability = max(limbProbability, probabilities(:, :, classIndex));
end
minimumArea = max(4, round(.00005 * prod(imageSize)));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    if any(personMask(pixels)) || numel(pixels) < minimumArea || ...
            nnz(limbProbability(pixels) >= .20) < max(4, round(.10 * numel(pixels)))
        continue;
    end
    [rows, cols] = ind2sub(imageSize, pixels);
    centroid = [mean(cols), mean(rows)];
    insideEnvelope = centroid(1) >= envelope(1) && ...
        centroid(1) <= envelope(3) && centroid(2) >= envelope(2) && ...
        centroid(2) <= envelope(4);
    if insideEnvelope && min(distanceToPerson(pixels)) <= gapRadius
        personMask(pixels) = true;
    end
end
end
