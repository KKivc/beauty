function varargout = buildBeautyMasks(inputImage, beautyContext, faceBox)
%BUILDBEAUTYMASKS 聚合 v3 的三类保护 Mask、硬保护和连续强度图。
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

derivedNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap'};
hasDerivedMasks = all(isfield(beautyContext, derivedNames));
needsDerivedDiagnostics = nargout == 2 || nargout >= 5;
[generatedTexture, textureDiagnostics] = ...
    masks.buildTextureProtectionMask(inputImage, beautyContext, faceBox);
if ~hasDerivedMasks || needsDerivedDiagnostics
    [generatedStructure, structureDiagnostics] = ...
        masks.buildStructureProtectionMask(inputImage, beautyContext, faceBox);
    [generatedTone, toneDiagnostics] = ...
        masks.buildToneProtectionMask(inputImage, beautyContext, faceBox);
    [generatedStrength, strengthDiagnostics] = ...
        masks.buildBeautyStrengthMap(inputImage, beautyContext, faceBox);
else
    generatedStructure = [];
    generatedTone = [];
    generatedStrength = [];
    structureDiagnostics = struct('reusedDerivedMask', true);
    toneDiagnostics = struct('reusedDerivedMask', true);
    strengthDiagnostics = struct('reusedDerivedMask', true);
end
if hasDerivedMasks
    textureProtectionMask = readMask(beautyContext, ...
        'textureProtectionMask', size(inputImage, 1:2));
    structureProtectionMask = readMask(beautyContext, ...
        'structureProtectionMask', size(inputImage, 1:2));
    toneProtectionMask = readMask(beautyContext, ...
        'toneProtectionMask', size(inputImage, 1:2));
    strengthMap = readMask(beautyContext, ...
        'strengthMap', size(inputImage, 1:2));
    strengthDiagnostics.faceStrengthMap = readMask(beautyContext, ...
        'faceStrengthMap', size(inputImage, 1:2));
    strengthDiagnostics.nonFaceStrengthMap = readMask(beautyContext, ...
        'nonFaceStrengthMap', size(inputImage, 1:2));
else
    textureProtectionMask = generatedTexture;
    structureProtectionMask = generatedStructure;
    toneProtectionMask = generatedTone;
    strengthMap = generatedStrength;
end

hardProtectionMask = validateMask(textureDiagnostics.hardProtectionMask, ...
    size(inputImage, 1:2), 'hardProtectionMask');
skinMask = readMask(beautyContext, 'skinMask', size(inputImage, 1:2));
faceSkinMask = readMask(beautyContext, ...
    'faceSkinMask', size(inputImage, 1:2));
nonFaceSkinMask = readMask(beautyContext, ...
    'nonFaceSkinMask', size(inputImage, 1:2));

% 通用处理保护只合并纹理、结构和硬保护；色调保护仅约束色度
% 校正，不能把鼻部整块从磨皮和瑕疵统计中排除。
protectionMask = max(cat(3, textureProtectionMask, ...
    structureProtectionMask, hardProtectionMask), [], 3);
protectionMask = min(max(protectionMask, 0), 1);
beautyMasks = struct( ...
    'textureProtectionMask', textureProtectionMask, ...
    'structureProtectionMask', structureProtectionMask, ...
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
    'imageSize', [size(inputImage, 1:2), 3]);
diagnostics = struct( ...
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
