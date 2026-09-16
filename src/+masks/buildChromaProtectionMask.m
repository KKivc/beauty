function [chromaProtectionMask, diagnostics] = ...
        buildChromaProtectionMask(inputImage, beautyContext, faceBox)
%BUILDCHROMAPROTECTIONMASK 生成五官颜色和鼻孔色调保护 Mask。
%   旧的 buildToneProtectionMask 入口仍保留为兼容 alias。

[chromaProtectionMask, diagnostics] = masks.buildToneProtectionMask( ...
    inputImage, beautyContext, faceBox);
diagnostics.chromaProtectionMask = chromaProtectionMask;
diagnostics.toneProtectionMask = chromaProtectionMask;
end
