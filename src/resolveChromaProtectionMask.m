function [mask, hasMask] = resolveChromaProtectionMask( ...
        context, imageSize, invalidIdentifier, conflictIdentifier)
%RESOLVECHROMAPROTECTIONMASK 解析色度保护 Mask 及其兼容 alias。
%   chromaProtectionMask 是规范字段，toneProtectionMask 是兼容 alias。
%   两者同时存在时必须逐元素相等；两者都不存在时返回 hasMask=false。

if nargin < 3 || isempty(invalidIdentifier)
    invalidIdentifier = 'beautyContext:InvalidChromaProtectionMask';
end
if nargin < 4 || isempty(conflictIdentifier)
    conflictIdentifier = 'beautyContext:ConflictingChromaProtectionMask';
end

hasChroma = isfield(context, 'chromaProtectionMask');
hasTone = isfield(context, 'toneProtectionMask');
if ~hasChroma && ~hasTone
    mask = [];
    hasMask = false;
    return;
end

if hasChroma
    chromaMask = validateMask(context.chromaProtectionMask, imageSize, ...
        'chromaProtectionMask', invalidIdentifier);
else
    chromaMask = [];
end
if hasTone
    toneMask = validateMask(context.toneProtectionMask, imageSize, ...
        'toneProtectionMask', invalidIdentifier);
else
    toneMask = [];
end

if hasChroma && hasTone && ~isequal(chromaMask, toneMask)
    error(conflictIdentifier, ...
        'chromaProtectionMask 与 toneProtectionMask 必须逐元素完全一致。');
end

if hasChroma
    mask = chromaMask;
else
    mask = toneMask;
end
hasMask = true;
end

function value = validateMask(value, imageSize, name, invalidIdentifier)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error(invalidIdentifier, '字段 %s 的尺寸或取值范围无效。', name);
end
value = double(value);
end
