function probabilities = inferSchpLipProbabilities(inputImage, options)
%INFERSCHPLIPPROBABILITIES 独立执行 SCHP 预处理、推理和原图回映。
if nargin < 2 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('inferSchpLipProbabilities:InvalidOptions', ...
        'SCHP options must be a scalar struct.');
end
if isfield(options, 'probabilities')
    probabilities = validateProbabilities(options.probabilities, size(inputImage));
    return;
end
rotationDegrees = readRotation(options);
workingImage = inputImage;
if rotationDegrees ~= 0
    workingImage = rot90(inputImage, rotationDegrees / 90);
end

[networkInput, transform] = prepareSchpLipInput(workingImage);
try
    if isfield(options, 'runner') && ~isempty(options.runner)
        if ~isa(options.runner, 'function_handle')
            error('inferSchpLipProbabilities:InvalidRunner', ...
                'SCHP runner must be a function handle.');
        end
        rawOutput = options.runner(networkInput);
    else
        if isfield(options, 'model') && ~isempty(options.model)
            model = options.model;
        else
            model = loadSchpLipModel();
        end
        rawOutput = runModel(model, networkInput);
    end
catch exception
    if startsWith(exception.identifier, 'loadSchpLipModel:') || ...
            startsWith(exception.identifier, 'inferSchpLipProbabilities:')
        rethrow(exception);
    end
    error('inferSchpLipProbabilities:InferenceFailed', ...
        'SCHP LIP inference failed: %s', exception.message);
end
try
    logits = extractSchpLipLogits(rawOutput);
    probabilities = mapSchpLipOutput(logits, transform, size(workingImage));
    if rotationDegrees ~= 0
        probabilities = rot90(probabilities, -rotationDegrees / 90);
        if ~isequal(size(probabilities, 1:2), size(inputImage, 1:2))
            error('inferSchpLipProbabilities:RotationSizeMismatch', ...
                'SCHP inverse rotation did not restore the input size.');
        end
    end
catch exception
    error('inferSchpLipProbabilities:InvalidOutput', ...
        'SCHP LIP output is incompatible: %s', exception.message);
end

function rotationDegrees = readRotation(options)
rotationDegrees = 0;
if isfield(options, 'rotationDegrees')
    rotationDegrees = options.rotationDegrees;
end
if ~isnumeric(rotationDegrees) || ~isreal(rotationDegrees) || ...
        ~isscalar(rotationDegrees) || ...
        ~ismember(rotationDegrees, [0, -90, 90, 180])
    error('inferSchpLipProbabilities:InvalidRotation', ...
        'rotationDegrees must be 0, -90, 90 or 180.');
end
end
end

function rawOutput = runModel(model, networkInput)
if isstruct(model) && isfield(model, 'network')
    network = model.network;
else
    network = model;
end
if isempty(network)
    error('inferSchpLipProbabilities:InvalidModel', ...
        'SCHP model does not contain a network.');
end
if isa(network, 'dlnetwork')
    inputData = dlarray(reshape(networkInput, [1, 3, 473, 473]), 'BCSS');
    rawOutput = predict(network, inputData);
else
    rawOutput = predict(network, permute(networkInput, [2, 3, 1]));
end
end

function probabilities = validateProbabilities(value, imageSize)
if ~isnumeric(value) || ~isreal(value) || ndims(value) ~= 3 || ...
        size(value, 3) ~= 20 || ~isequal(size(value, 1), imageSize(1)) || ...
        ~isequal(size(value, 2), imageSize(2)) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('inferSchpLipProbabilities:InvalidProbabilities', ...
        'Injected SCHP probabilities must be finite HxWx20 values in [0, 1].');
end
probabilities = single(value);
end
