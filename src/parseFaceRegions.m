function parsing = parseFaceRegions(inputImage, faceBox, injected)
%PARSEFACEREGIONS 推理并回映 BiSeNet 19 类结果。
if nargin >= 3 && ~isempty(injected)
    parsing = normalizeInjected(injected, size(inputImage));
    if ~isfield(parsing, 'roiBox')
        [~, transform] = prepareFaceParsingInput(inputImage, faceBox);
        parsing.roiBox = transform.roiBox;
    end
    return;
end
[networkInput, transform] = prepareFaceParsingInput(inputImage, faceBox);
model = loadFaceParsingModel();
inputData = dlarray(permute(networkInput, [4, 3, 1, 2]), 'BCSS');
try
    [rawOutput, ~, ~] = predict(model.network, inputData);
catch exception
    error('parseFaceRegions:InferenceFailed', ...
        'Face parsing inference failed: %s', exception.message);
end
logits = extractLogits(rawOutput);
[softMasks, confidence, hardLabels] = mapFaceParsingOutput(...
    logits, transform, size(inputImage));
names = faceParsingClassNames();
regions = struct();
regionConfidence = struct();
for index = 1:numel(names)
    regions.(names{index}) = softMasks(:, :, index);
    % 保留该类别的 softmax 概率，不用 argmax 标签截断边界置信度。
    regionConfidence.(names{index}) = softMasks(:, :, index);
end
parsing = struct('regions', regions, 'regionConfidence', regionConfidence, ...
    'hardLabels', hardLabels, 'confidence', confidence, ...
    'roiBox', transform.roiBox);
end

function logits = extractLogits(rawOutput)
if iscell(rawOutput)
    rawOutput = rawOutput{1};
end
if isa(rawOutput, 'dlarray')
    rawOutput = extractdata(rawOutput);
end
rawOutput = gather(rawOutput);
shape = size(rawOutput);
if numel(shape) == 4
    if shape(1) == 1 && shape(2) == 19
        rawOutput = permute(rawOutput, [3, 4, 2, 1]);
    elseif shape(4) == 19 && shape(1) == 1
        rawOutput = permute(rawOutput, [2, 3, 4, 1]);
    elseif shape(3) == 19 && shape(4) == 1
        rawOutput = rawOutput(:, :, :, 1);
    end
end
if ndims(rawOutput) ~= 3
    error('parseFaceRegions:InvalidOutput', 'Model output must contain 19 logits.');
end
if size(rawOutput, 3) == 19
    logits = rawOutput;
elseif size(rawOutput, 1) == 19
    logits = permute(rawOutput, [2, 3, 1]);
else
    error('parseFaceRegions:InvalidOutput', 'Model output does not contain 19 classes.');
end
if ~isequal(size(logits, 1), 512) || ~isequal(size(logits, 2), 512)
    logits = imresize(logits, [512, 512], 'bilinear');
end
end

function parsing = normalizeInjected(injected, imageSize)
if ~isstruct(injected) || ~isfield(injected, 'regions')
    error('parseFaceRegions:InvalidInjected', 'Injected parsing must contain regions.');
end
names = faceParsingClassNames();
parsing = injected;
for index = 1:numel(names)
    name = names{index};
    if ~isfield(parsing.regions, name)
        parsing.regions.(name) = zeros(imageSize(1), imageSize(2));
    end
    if ~isequal(size(parsing.regions.(name)), imageSize(1:2))
        error('parseFaceRegions:InvalidInjected', 'Injected mask size mismatch.');
    end
end
if ~isfield(parsing, 'regionConfidence')
    parsing.regionConfidence = parsing.regions;
end
end
