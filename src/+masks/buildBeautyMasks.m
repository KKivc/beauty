function varargout = buildBeautyMasks(inputImage, beautyContext, faceBox)
%BUILDBEAUTYMASKS 聚合 v3.1 的三类保护 Mask、硬保护和连续强度图。
%   两个输出返回 [beautyMasks, diagnostics]；需要拆分时可请求
%   [texture, structure, tone, strength, diagnostics]。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    if isfield(beautyContext, 'faceBox')
        faceBox = beautyContext.faceBox;
    else
        error('masks:InvalidFaceBox', '必须提供人脸框。');
    end
end

imageSize = size(inputImage, 1:2);
[chromaProtectionMask, hasChromaProtectionMask] = ...
    resolveChromaProtectionMask(beautyContext, imageSize, ...
    'masks:InvalidContext', 'masks:ChromaProtectionConflict');
hasTexture = isfield(beautyContext, 'textureProtectionMask');
hasStructure = isfield(beautyContext, 'structureProtectionMask');
hasStrength = isfield(beautyContext, 'strengthMap');
hasFaceStrength = isfield(beautyContext, 'faceStrengthMap');
hasNonFaceStrength = isfield(beautyContext, 'nonFaceStrengthMap');
needsDerivedDiagnostics = nargout == 2 || nargout >= 5;
[generatedTexture, textureDiagnostics] = ...
    masks.buildTextureProtectionMask(inputImage, beautyContext, faceBox);
if ~hasStructure || needsDerivedDiagnostics
    [generatedStructure, structureDiagnostics] = ...
        masks.buildStructureProtectionMask(inputImage, beautyContext, faceBox);
else
    generatedStructure = [];
    structureDiagnostics = struct('reusedDerivedMask', true);
end
if ~hasChromaProtectionMask || needsDerivedDiagnostics
    [generatedTone, toneDiagnostics] = ...
        masks.buildToneProtectionMask(inputImage, beautyContext, faceBox);
else
    generatedTone = [];
    toneDiagnostics = struct('reusedDerivedMask', true);
end
if ~hasStrength || ~hasFaceStrength || ~hasNonFaceStrength || ...
        needsDerivedDiagnostics
    [generatedStrength, strengthDiagnostics] = ...
        masks.buildBeautyStrengthMap(inputImage, beautyContext, faceBox);
else
    generatedStrength = [];
    strengthDiagnostics = struct('reusedDerivedMask', true);
end
if hasTexture
    textureProtectionMask = readMask(beautyContext, ...
        'textureProtectionMask', imageSize);
else
    textureProtectionMask = generatedTexture;
end
if hasStructure
    structureProtectionMask = readMask(beautyContext, ...
        'structureProtectionMask', imageSize);
else
    structureProtectionMask = generatedStructure;
end
if hasChromaProtectionMask
    toneProtectionMask = chromaProtectionMask;
else
    toneProtectionMask = generatedTone;
    chromaProtectionMask = toneProtectionMask;
end
if hasStrength
    strengthMap = readMask(beautyContext, ...
        'strengthMap', imageSize);
else
    strengthMap = generatedStrength;
end
if hasFaceStrength
    strengthDiagnostics.faceStrengthMap = readMask(beautyContext, ...
        'faceStrengthMap', imageSize);
elseif isempty(generatedStrength)
    strengthDiagnostics.faceStrengthMap = zeros(imageSize);
end
if hasNonFaceStrength
    strengthDiagnostics.nonFaceStrengthMap = readMask(beautyContext, ...
        'nonFaceStrengthMap', imageSize);
elseif isempty(generatedStrength)
    strengthDiagnostics.nonFaceStrengthMap = zeros(imageSize);
end

hardProtectionMask = validateMask(textureDiagnostics.hardProtectionMask, ...
    imageSize, 'hardProtectionMask');
skinMask = readMask(beautyContext, 'skinMask', imageSize);
faceSkinMask = readMask(beautyContext, ...
    'faceSkinMask', imageSize);
nonFaceSkinMask = readMask(beautyContext, ...
    'nonFaceSkinMask', imageSize);

% 通用处理保护只合并纹理、结构和硬保护；色调保护仅约束色度
% 校正，不能把鼻部整块从磨皮和瑕疵统计中排除。
protectionMask = max(cat(3, textureProtectionMask, ...
    structureProtectionMask, hardProtectionMask), [], 3);
protectionMask = min(max(protectionMask, 0), 1);
beautyMasks = struct( ...
    'textureProtectionMask', textureProtectionMask, ...
    'structureProtectionMask', structureProtectionMask, ...
    'chromaProtectionMask', chromaProtectionMask, ...
    'toneProtectionMask', toneProtectionMask, ...
    'protectionMask', protectionMask, ...
    'strengthMap', strengthMap, ...
    'faceStrengthMap', strengthDiagnostics.faceStrengthMap, ...
    'nonFaceStrengthMap', strengthDiagnostics.nonFaceStrengthMap, ...
    'skinMask', skinMask, ...
    'faceSkinMask', faceSkinMask, ...
    'nonFaceSkinMask', nonFaceSkinMask, ...
    'noseMask', double(textureDiagnostics.noseInterior), ...
    'hardProtectionMask', hardProtectionMask, ...
    'faceBox', double(faceBox), ...
    'imageSize', [imageSize, 3], ...
    'schemaVersion', '3.1');
diagnostics = struct( ...
    'schemaVersion', '3.1', ...
    'chromaProtectionMask', chromaProtectionMask, ...
    'toneProtectionMask', toneProtectionMask, ...
    'texture', textureDiagnostics, ...
    'structure', structureDiagnostics, ...
    'tone', toneDiagnostics, ...
    'strength', strengthDiagnostics, ...
    'hardProtectionMask', hardProtectionMask, ...
    'protectionMask', protectionMask);

if nargout <= 2
    if nargout >= 1
        varargout{1} = beautyMasks;
    end
    if nargout == 2
        varargout{2} = diagnostics;
    end
else
    varargout{1} = textureProtectionMask;
    varargout{2} = structureProtectionMask;
    varargout{3} = toneProtectionMask;
    varargout{4} = strengthMap;
    varargout{5} = diagnostics;
    if nargout > 5
        varargout{6} = beautyMasks;
    end
end
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('masks:InvalidContext', 'Context 缺少字段 %s。', name);
end
value = validateMask(context.(name), imageSize, name);
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 %s 无效。', name);
end
value = double(value);
end
