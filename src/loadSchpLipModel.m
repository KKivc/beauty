function model = loadSchpLipModel(modelPath, expectedSha256)
%LOADSCHPLIPMODEL 校验并缓存固定静态 SCHP LIP ONNX 模型。
persistent cachedPath cachedHash cachedModel cachedBytes cachedDatenum
if nargin < 1 || isempty(modelPath)
    modelPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        'models', 'schp_lip_resnet101.onnx');
end
if nargin < 2 || isempty(expectedSha256)
    expectedSha256 = ...
        '92E0A10000073B6B6AF4FDE567944ED0F91B52F7D4D79715425B0A13B82AFF54';
end
if ~ischar(modelPath) && ~isstring(modelPath)
    error('loadSchpLipModel:InvalidPath', 'SCHP modelPath must be text.');
end
modelPath = char(modelPath);
if ~isfile(modelPath)
    error('loadSchpLipModel:MissingModel', ...
        'SCHP LIP model is missing: %s', modelPath);
end
[resolved, attributes] = fileattrib(modelPath);
if resolved
    modelPath = attributes.Name;
end
fileInfo = dir(modelPath);
fastMatch = ~isempty(cachedModel) && strcmp(cachedPath, modelPath) && ...
    cachedBytes == fileInfo.bytes && cachedDatenum == fileInfo.datenum;
if fastMatch
    actualHash = cachedHash;
else
    actualHash = sha256File(modelPath);
end
if ~strcmpi(actualHash, char(expectedSha256))
    error('loadSchpLipModel:HashMismatch', ...
        'SHA-256 mismatch for SCHP LIP model: %s', modelPath);
end
if fastMatch
    model = cachedModel;
    return;
end

cacheFolder = fullfile(fileparts(modelPath), 'cache');
if ~isfolder(cacheFolder)
    mkdir(cacheFolder);
end
addpath(cacheFolder);
cachePath = fullfile(cacheFolder, ...
    ['schp_lip_resnet101_', lower(actualHash), '.mat']);
metadata = cacheMetadata(actualHash);
if isfile(cachePath)
    try
        loaded = load(cachePath, 'network', 'metadata');
        if isfield(loaded, 'network') && isfield(loaded, 'metadata') && ...
                isCompatibleMetadata(loaded.metadata, metadata)
            model = makeModel(loaded.network, modelPath, actualHash);
            [cachedPath, cachedHash, cachedModel, cachedBytes, cachedDatenum] = ...
                cacheSession(model, fileInfo);
            return;
        end
    catch
        % 缓存损坏或版本不符时重新导入固定 ONNX。
    end
end

try
    previousFolder = pwd;
    folderCleanup = onCleanup(@() cd(previousFolder));
    cd(cacheFolder);
    if exist('importNetworkFromONNX', 'file') ~= 0
        network = importNetworkFromONNX(modelPath, ...
            InputDataFormats='BCSS', OutputDataFormats='BCSS');
    elseif exist('importONNXNetwork', 'file') ~= 0
        network = importONNXNetwork(modelPath, 'OutputLayerType', 'regression');
    else
        error('No ONNX import function is available.');
    end
    clear folderCleanup;
catch exception
    if contains(exception.message, 'Converter for ONNX', 'IgnoreCase', true) || ...
            contains(exception.message, 'ONNX Model Format', 'IgnoreCase', true)
        error('loadSchpLipModel:MissingOnnxConverter', ...
            ['SCHP requires Deep Learning Toolbox Converter for ONNX ', ...
            'Model Format.']);
    end
    error('loadSchpLipModel:ImportFailed', ...
        'Unable to import SCHP LIP model: %s', exception.message);
end

model = makeModel(network, modelPath, actualHash);
[cachedPath, cachedHash, cachedModel, cachedBytes, cachedDatenum] = ...
    cacheSession(model, fileInfo);
try
    save(cachePath, 'network', 'metadata', '-v7.3');
catch
    % 磁盘缓存不可写时仍保留当前 MATLAB 会话缓存。
end
end

function model = makeModel(network, modelPath, actualHash)
model = struct('network', network, 'path', modelPath, ...
    'sha256', actualHash, 'inputSize', [473, 473], ...
    'outputSize', [119, 119], 'classNames', {schpLipClassNames()});
end

function [path, hash, model, bytes, datenumValue] = cacheSession(value, fileInfo)
path = value.path;
hash = value.sha256;
model = value;
bytes = fileInfo.bytes;
datenumValue = fileInfo.datenum;
end

function metadata = cacheMetadata(modelHash)
toolbox = ver('deep learning toolbox');
if isempty(toolbox)
    toolboxVersion = '';
else
    toolboxVersion = toolbox.Version;
end
metadata = struct('sha256', modelHash, 'matlabRelease', version('-release'), ...
    'deepLearningToolboxVersion', toolboxVersion, ...
    'inputSize', [473, 473], 'outputSize', [119, 119]);
end

function compatible = isCompatibleMetadata(actual, expected)
compatible = isstruct(actual) && all(isfield(actual, fieldnames(expected)));
if ~compatible
    return;
end
names = fieldnames(expected);
for index = 1:numel(names)
    compatible = compatible && isequal(actual.(names{index}), expected.(names{index}));
end
end

function digest = sha256File(filePath)
fileId = fopen(filePath, 'r');
if fileId < 0
    error('loadSchpLipModel:ReadFailed', 'Unable to read SCHP model file.');
end
cleanup = onCleanup(@() fclose(fileId));
messageDigest = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fileId, 8 * 1024 * 1024, '*uint8');
    if isempty(bytes)
        break;
    end
    messageDigest.update(bytes);
end
digestBytes = typecast(messageDigest.digest(), 'uint8');
digest = lower(reshape(dec2hex(digestBytes)', 1, []));
clear cleanup;
end
