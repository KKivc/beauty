function [smoothedFrequency, diagnostics] = smoothSkinTexture( ...
        frequency, beautyMasks, smoothingStrength)
%SMOOTHSKINTEXTURE 以连续 Alpha Map 单调衰减 Fine 纹理。
%   Base 和 Mid 不被修改；最高档保留非零 Fine，结构保护只降低
%   局部 Alpha，不改变分解尺度。

if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'base', 'mid', 'fine', ...
        'sourceLuminance', 'imageSize', 'faceBox'}))
    error('beauty:InvalidFrequency', ...
        '必须提供完整的 Base/Mid/Fine 频率结构。');
end
if nargin < 2 || ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidMasks', '必须提供 v3 Beauty Masks。');
end
if nargin < 3 || ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

imageSize = frequency.imageSize(1:2);
validateBand(frequency.base, imageSize, 'base');
validateBand(frequency.mid, imageSize, 'mid');
validateBand(frequency.fine, imageSize, 'fine');
requiredMaskFields = {'strengthMap', 'textureProtectionMask', ...
    'structureProtectionMask', 'toneProtectionMask'};
if ~all(isfield(beautyMasks, requiredMaskFields))
    error('beauty:InvalidMasks', 'v3 Beauty Masks 缺少必需字段。');
end
strengthMap = validateMask(beautyMasks.strengthMap, imageSize, ...
    'strengthMap');
textureProtection = validateMask(beautyMasks.textureProtectionMask, ...
    imageSize, 'textureProtectionMask');
structureProtection = validateMask(beautyMasks.structureProtectionMask, ...
    imageSize, 'structureProtectionMask');
toneProtection = validateMask(beautyMasks.toneProtectionMask, ...
    imageSize, 'toneProtectionMask');
hardProtection = optionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);

protection = max(cat(3, textureProtection, ...
    structureProtection, toneProtection, hardProtection), [], 3);
ratio = double(smoothingStrength) / 100;
fineRetention = 1 - .65 * ratio ^ .85;
alphaMap = ratio .* strengthMap .* (1 - protection);
alphaMap = min(max(double(alphaMap), 0), 1);
retentionMap = 1 - alphaMap .* (1 - fineRetention);
smoothedFine = frequency.fine .* retentionMap;
outputLuminance = frequency.base + frequency.mid + smoothedFine;

smoothedFrequency = frequency;
smoothedFrequency.fine = smoothedFine;
smoothedFrequency.reconstructedLuminance = outputLuminance;
smoothedFrequency.outputLuminance = outputLuminance;
smoothedFrequency.alphaMap = alphaMap;
smoothedFrequency.fineRetention = fineRetention;
smoothedFrequency.retentionMap = retentionMap;
diagnostics = struct( ...
    'alphaMap', alphaMap, ...
    'fineRetention', fineRetention, ...
    'retentionMap', retentionMap, ...
    'protectionMask', protection, ...
    'fineBefore', frequency.fine, ...
    'fineAfter', smoothedFine, ...
    'fineEnergyBefore', mean(abs(frequency.fine(:))), ...
    'fineEnergyAfter', mean(abs(smoothedFine(:))), ...
    'baseUnchanged', true, ...
    'midUnchanged', true);
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function validateBand(value, imageSize, name)
if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
        any(~isfinite(value(:)))
    error('beauty:InvalidFrequency', '频率分量 %s 无效。', name);
end
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidMasks', 'Mask %s 无效。', name);
end
value = double(value);
end

function value = optionalMask(context, name, imageSize)
if isfield(context, name)
    value = validateMask(context.(name), imageSize, name);
else
    value = zeros(imageSize);
end
end

