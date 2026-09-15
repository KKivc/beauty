function model = loadFaceParsingModel(modelPath, expectedSha256)
%LOADFACEPARSINGMODEL 加载并校验本地 BiSeNet ONNX 模型。
% 不联网下载；模型缓存于 MATLAB 会话和本机磁盘。
persistent cachedPath cachedHash cachedModel cachedBytes cachedDatenum
if nargin < 1 || isempty(modelPath)
    modelPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'models', 'face_parsing_bisenet_resnet18.onnx');
end
if nargin < 2
    expectedSha256 = '0D9BD318E46987C3BDBFACAE9E2C0F461CAE1C6AC6EA6D43BBE541A91727E33F';
end
if ~ischar(modelPath) && ~isstring(modelPath)
    error('loadFaceParsingModel:InvalidPath', 'modelPath must be text.');
end
modelPath = char(modelPath);
if ~isfile(modelPath)
    error('loadFaceParsingModel:MissingModel', ...
        'Face parsing model is missing: %s', modelPath);
end
fileInfo = dir(modelPath);
expectedSha256 = char(expectedSha256);
fastMatch = ~isempty(cachedModel) && strcmp(cachedPath, modelPath) && ...
    cachedBytes == fileInfo.bytes && cachedDatenum == fileInfo.datenum;
if fastMatch
    actualHash = cachedHash;
else
    actualHash = sha256File(modelPath);
end
if isempty(expectedSha256) || ~strcmpi(actualHash, expectedSha256)
    error('loadFaceParsingModel:HashMismatch', ...
        'SHA-256 mismatch for face parsing model.');
end
if fastMatch && strcmpi(cachedHash, actualHash)
    model = cachedModel;
    return;
end

cachePath = fullfile(fileparts(modelPath), 'cache', ...
    ['face_parsing_bisenet_resnet18_', lower(actualHash), '.mat']);
metadata = cacheMetadata(actualHash);
if isfile(cachePath)
    try
        loaded = load(cachePath, 'network', 'metadata');
        if isfield(loaded, 'network') && isfield(loaded, 'metadata') && ...
                isCompatibleMetadata(loaded.metadata, metadata)
            model = struct('network', loaded.network, 'path', modelPath, ...
                'sha256', actualHash, 'classNames', {faceParsingClassNames()});
            cachedPath = modelPath;
            cachedHash = actualHash;
            cachedModel = model;
            cachedBytes = fileInfo.bytes;
            cachedDatenum = fileInfo.datenum;
            return;
        end
    catch
        % 缓存损坏或版本不符时安全回退到 ONNX 导入。
    end
end
try
    if exist('importNetworkFromONNX', 'file') ~= 0
        imported = importNetworkFromONNX(modelPath, InputDataFormats='BCSS');
        graph = layerGraph(imported);
        requiredLayers = {'Resize_To_ShapeLayer1023', 'outputOutput', ...
            'x414Output', 'x424Output'};
        layerNames = {graph.Layers.Name};
        if ~all(ismember(requiredLayers, layerNames))
            error('loadFaceParsingModel:ModelIncompatible', ...
                'Unexpected ONNX topology or missing known placeholder layers.');
        end
        graph = removeLayers(graph, requiredLayers);
        outputNames = {'x_conv_out_conv_Co_1', 'x_conv_out16_conv__1', ...
            'x_conv_out32_conv__1'};
        if ~all(ismember(outputNames, {graph.Layers.Name}))
            error('loadFaceParsingModel:ModelIncompatible', ...
                'Expected BiSeNet output layers were not found.');
        end
        network = dlnetwork(graph, OutputNames=outputNames);
        zeroInput = dlarray(zeros(1, 3, 512, 512, 'single'), 'BCSS');
        network = initialize(network, zeroInput);
    elseif exist('importONNXNetwork', 'file') ~= 0
        network = importONNXNetwork(modelPath, 'OutputLayerType', 'regression');
    else
        error('No ONNX import function is available.');
    end
catch exception
    if strcmp(exception.identifier, 'loadFaceParsingModel:ModelIncompatible')
        rethrow(exception);
    end
    if contains(exception.message, 'Converter for ONNX', 'IgnoreCase', true) || ...
            contains(exception.message, 'ONNX Model Format', 'IgnoreCase', true)
        error('loadFaceParsingModel:MissingOnnxConverter', ...
            'Deep Learning Toolbox Converter for ONNX Model Format is required.');
    end
    error('loadFaceParsingModel:ImportFailed', ...
        'Unable to import face parsing model: %s', exception.message);
end

model = struct('network', network, 'path', modelPath, ...
    'sha256', actualHash, 'classNames', {faceParsingClassNames()});
cachedPath = modelPath;
cachedHash = actualHash;
cachedModel = model;
cachedBytes = fileInfo.bytes;
cachedDatenum = fileInfo.datenum;
try
    cacheFolder = fileparts(cachePath);
    if ~isfolder(cacheFolder), mkdir(cacheFolder); end
    save(cachePath, 'network', 'metadata', '-v7.3');
catch
    % 磁盘缓存不可写时不影响当前会话中的模型。
end
end

function metadata = cacheMetadata(modelHash)
release = version('-release');
toolbox = ver('deep learning toolbox');
if isempty(toolbox)
    toolboxVersion = '';
else
    toolboxVersion = toolbox.Version;
end
metadata = struct('sha256', modelHash, 'matlabRelease', release, ...
    'deepLearningToolboxVersion', toolboxVersion);
end

function isCompatible = isCompatibleMetadata(actual, expected)
isCompatible = isstruct(actual) && all(isfield(actual, fieldnames(expected)));
if isCompatible
    names = fieldnames(expected);
    for index = 1:numel(names)
        isCompatible = isCompatible && strcmp(char(string(actual.(names{index}))), ...
            char(string(expected.(names{index}))));
    end
end
end

function digest = sha256File(filePath)
fileId = fopen(filePath, 'r');
if fileId < 0
    error('loadFaceParsingModel:ReadFailed', 'Unable to read model file.');
end
cleanup = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, '*uint8');
int8Digest = java.security.MessageDigest.getInstance('SHA-256').digest(bytes);
digestBytes = typecast(int8Digest, 'uint8');
digest = lower(reshape(dec2hex(digestBytes)', 1, []));
end
