function context = rebuildBeautyDerivedMasks(inputImage, context, faceBox)
%REBUILDBEAUTYDERIVEDMASKS 权威重建 Context 的 v3.1 派生保护与强度字段。
%   Context 构建（buildBeautyContextFromParsing）、准备
%   （prepareBeautyContext）和尺寸迁移（resizeBeautyContext）共用的
%   唯一桥接入口：先清掉可能残留的派生字段，再调用现有的
%   masks.buildBeautyMasks，一次性回填当前 v3.2 规范字段（texture/
%   structure/whitening/chroma 保护与强度图）及 tone/protectionMasks
%   兼容字段。缓存/非缓存与 preview/full-size 路径因此共享同一份
%   派生字段来源；后续 V4 分层字段的兼容生成也只在本桥接补齐，
%   各入口不得再自行拼装派生字段。

context = clearDerivedFields(context);
[beautyMasks, ~] = masks.buildBeautyMasks(inputImage, context, faceBox);
context.textureProtectionMask = beautyMasks.textureProtectionMask;
context.structureProtectionMask = beautyMasks.structureProtectionMask;
context.whiteningProtectionMask = beautyMasks.whiteningProtectionMask;
context.chromaProtectionMask = beautyMasks.chromaProtectionMask;
context.toneProtectionMask = context.chromaProtectionMask;
context.strengthMap = beautyMasks.strengthMap;
context.faceStrengthMap = beautyMasks.faceStrengthMap;
context.nonFaceStrengthMap = beautyMasks.nonFaceStrengthMap;
context.protectionMasks = struct( ...
    'texture', beautyMasks.textureProtectionMask, ...
    'structure', beautyMasks.structureProtectionMask, ...
    'whitening', beautyMasks.whiteningProtectionMask, ...
    'chroma', beautyMasks.chromaProtectionMask, ...
    'tone', context.chromaProtectionMask);
end

function context = clearDerivedFields(context)
% 清理入口侧可能残留的派生字段，保证重建只来自当前基础字段。
names = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks'};
names = names(isfield(context, names));
if ~isempty(names)
    context = rmfield(context, names);
end
end
