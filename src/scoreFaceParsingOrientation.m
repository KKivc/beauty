function assessment = scoreFaceParsingOrientation(parsing)
%SCOREFACEPARSINGORIENTATION 评价一个方向下的脸部语义完整度。
if ~isstruct(parsing) || ~isfield(parsing, 'regions')
    error('scoreFaceParsingOrientation:InvalidParsing', ...
        'Parsing must contain face regions.');
end
fields = fieldnames(parsing.regions);
if isempty(fields)
    error('scoreFaceParsingOrientation:InvalidParsing', ...
        'Parsing regions cannot be empty.');
end
reference = parsing.regions.(fields{1});
pixelCount = numel(reference);
minimumArea = max(4, round(2e-5 * pixelCount));

featureNames = {'nose', 'leftEye', 'rightEye', 'leftBrow', ...
    'rightBrow', 'mouth', 'upperLip', 'lowerLip'};
present = false(1, numel(featureNames));
for index = 1:numel(featureNames)
    probability = regionProbability(parsing, featureNames{index}, reference);
    present(index) = nnz(probability > .35) >= minimumArea;
end
hasNose = present(1);
hasEyeBrow = any(present(2:5));
hasLipGroup = any(present(6:8));
featureCount = nnz(present);
skin = regionProbability(parsing, 'skin', reference);
skinCoverage = nnz(skin > .35) / pixelCount;
skinScore = min(1, skinCoverage / .05);
score = 2 * double(hasNose) + 2 * double(hasLipGroup) + ...
    nnz(present(2:5)) + skinScore;

assessment = struct('score', score, 'featureCount', featureCount, ...
    'hasNose', hasNose, 'hasLipGroup', hasLipGroup, ...
    'hasEyeBrow', hasEyeBrow, 'skinCoverage', skinCoverage, ...
    'needsFallback', featureCount < 3 || (~hasNose && ~hasLipGroup), ...
    'isStrong', score >= 6 && hasNose && hasLipGroup && hasEyeBrow);
end

function probability = regionProbability(parsing, name, reference)
if isfield(parsing, 'regionConfidence') && ...
        isfield(parsing.regionConfidence, name)
    probability = parsing.regionConfidence.(name);
elseif isfield(parsing.regions, name)
    probability = parsing.regions.(name);
else
    probability = zeros(size(reference));
end
if ~isnumeric(probability) || ~isreal(probability) || ...
        ~isequal(size(probability), size(reference)) || ...
        any(~isfinite(probability(:)))
    error('scoreFaceParsingOrientation:InvalidParsing', ...
        'Face region probabilities must be finite and share one size.');
end
end
