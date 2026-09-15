function mapped = rotateFaceParsing(parsing, inverseDegrees, targetImageSize)
%ROTATEFACEPARSING 将正交旋转后的解析结果映射回原图方向。
if ~ismember(inverseDegrees, [0, -90, 90, 180]) || ...
        numel(targetImageSize) < 2
    error('rotateFaceParsing:InvalidTransform', ...
        'Only 0, +/-90 and 180 degree rotations are supported.');
end
if ~isstruct(parsing) || ~isfield(parsing, 'regions')
    error('rotateFaceParsing:InvalidParsing', ...
        'Parsing must contain regions.');
end
quarterTurns = inverseDegrees / 90;
mapped = parsing;
mapped.regions = rotateStructMasks(parsing.regions, quarterTurns);
if isfield(parsing, 'regionConfidence')
    mapped.regionConfidence = rotateStructMasks( ...
        parsing.regionConfidence, quarterTurns);
end
arrayFields = {'hardLabels', 'confidence'};
for index = 1:numel(arrayFields)
    name = arrayFields{index};
    if isfield(parsing, name) && ~isempty(parsing.(name))
        mapped.(name) = rot90(parsing.(name), quarterTurns);
    end
end
expectedSize = targetImageSize(1:2);
firstName = fieldnames(mapped.regions);
if ~isequal(size(mapped.regions.(firstName{1})), expectedSize)
    error('rotateFaceParsing:SizeMismatch', ...
        'Inverse rotation did not restore the original image size.');
end
mapped.roiBox = [1, 1, expectedSize(2), expectedSize(1)];
end

function output = rotateStructMasks(input, quarterTurns)
output = struct();
names = fieldnames(input);
for index = 1:numel(names)
    output.(names{index}) = rot90(input.(names{index}), quarterTurns);
end
end
