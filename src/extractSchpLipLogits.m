function logits = extractSchpLipLogits(rawOutput)
%EXTRACTSCHPLIPLOGITS 从多输出结果中提取任意常见维度排列的 LIP20 logits。
candidates = collectCandidates(rawOutput);
if isempty(candidates)
    error('extractSchpLipLogits:InvalidOutput', ...
        'SCHP output does not contain a numeric tensor with 20 classes.');
end
preferred = find(cellfun(@(value) isequal(size(value, 1), 119) && ...
    isequal(size(value, 2), 119), candidates), 1);
if isempty(preferred)
    preferred = 1;
end
logits = candidates{preferred};
if any(~isfinite(logits(:)))
    error('extractSchpLipLogits:InvalidOutput', ...
        'SCHP logits contain non-finite values.');
end
logits = single(logits);
end

function candidates = collectCandidates(value)
candidates = {};
if iscell(value)
    for index = 1:numel(value)
        candidates = [candidates, collectCandidates(value{index})]; %#ok<AGROW>
    end
    return;
end
if isstruct(value)
    names = fieldnames(value);
    for element = 1:numel(value)
        for index = 1:numel(names)
            candidates = [candidates, ...
                collectCandidates(value(element).(names{index}))]; %#ok<AGROW>
        end
    end
    return;
end
if isa(value, 'dlarray')
    value = extractdata(value);
end
if isa(value, 'gpuArray')
    value = gather(value);
end
if ~isnumeric(value) || ~isreal(value)
    return;
end
candidate = normalizeDimensions(value);
if ~isempty(candidate)
    candidates = {candidate};
end
end

function candidate = normalizeDimensions(value)
candidate = [];
shape = size(value);
if ndims(value) == 4
    if shape(1) == 1 && shape(2) == 20
        candidate = reshape(permute(value, [3, 4, 2, 1]), ...
            shape(3), shape(4), 20);
    elseif shape(1) == 1 && shape(4) == 20
        candidate = reshape(permute(value, [2, 3, 4, 1]), ...
            shape(2), shape(3), 20);
    elseif shape(4) == 1 && shape(1) == 20
        candidate = reshape(permute(value, [2, 3, 1, 4]), ...
            shape(2), shape(3), 20);
    elseif shape(4) == 1 && shape(3) == 20
        candidate = reshape(value, shape(1), shape(2), 20);
    end
elseif ndims(value) == 3
    if shape(3) == 20
        candidate = value;
    elseif shape(1) == 20
        candidate = permute(value, [2, 3, 1]);
    end
end
end
