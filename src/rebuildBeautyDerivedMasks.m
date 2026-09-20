function context = rebuildBeautyDerivedMasks(inputImage, context, faceBox)
%REBUILDBEAUTYDERIVEDMASKS 权威重建 Context 的 v3.1 派生保护与强度字段。
%   Context 构建（buildBeautyContextFromParsing）、准备
%   （prepareBeautyContext）和尺寸迁移（resizeBeautyContext）共用的
%   唯一桥接入口：先清掉可能残留的派生字段，再调用现有的
%   masks.buildBeautyMasks，一次性回填当前 v3.2 规范字段（texture/
%   structure/whitening/chroma 保护与强度图）及 tone/protectionMasks
%   兼容字段。缓存/非缓存与 preview/full-size 路径因此共享同一份
%   派生字段来源；后续 V4 分层字段的兼容生成也只在本桥接补齐，
%   各入口不得再自行拼装。
%
%   T06 起，policy-time evidence 层同样只在本桥接生成/回填：以
%   masks.buildBeautyMasks 的静态诊断（texture/structure）为来源调用
%   masks.buildBeautyPolicyEvidence，evidence 只读图像、语义与诊断，
%   不回写任何 protection 字段，也不包含 blemish/frequency 运行期
%   产物。evidence 的来源/版本元数据挂在 context.diagnostics.
%   policyEvidence（evidence 层本身按 V4 规范只允许 HxW mask 字段）。
%
%   T07 起，V4 protection 层同样只在本桥接生成/回填：以
%   masks.buildBeautyMasks 的 mask 产物为唯一来源调用
%   masks.buildStageProtectionMasks，按生产 stage 门控的静态组合推导
%   hard、target.{smoothingFine,smoothingMid,repairFine,repairMid,
%   baseLuminance}、support.{同五者} 与过渡扁平字段
%   noseMidProtection/tone/whitening、五条 regionBand*；hard identity 与
%   strengthMap/effectStrengthMap 保持独立，不并入 stage 字段。
%
%   T20 起，本桥接把 policy evidence 传入 stage protection 推导：
%   evidence 先于 protection 构建，并作为第二输入传给
%   masks.buildStageProtectionMasks（eye/lip identity policy 只消费
%   periocular/lip 两个语义字段；零带时 protection 与 T07 legacy 折叠
%   逐位相等）。evidence 的只读边界不变：它仍不回写任何 v3.1
%   protection mask，buildBeautyMasks 产物与 evidence 解耦；消费发生
%   在 V4 protection 层推导这一处，且只经由本桥接提供的 evidence，
%   各入口不得自行拼装。
%
%   T09 起，本桥接同时是 resize/recompute 契约的重算点：
%   resizeBeautyContext 的四参数路径在合并目标尺寸皮肤域后调用本桥
%   接，soft protection、二值 hard identity 与 image-dependent policy
%   evidence 全部在目标分辨率重新生成，任何 resize 流程都不得缩放预
%   览侧的这些产物（hard 缩放产生的灰边禁止进入 compose identity）；
%   三参数轻量路径不带目标原图，不得伪造这些分层（输出 v3.1 compat
%   形态）。semantic/processability 分层不归本桥接管：由各入口在皮
%   肤域最终确定后调用 buildBeautySemanticLayers 刷新。

context = clearDerivedFields(context);
[beautyMasks, maskDiagnostics] = masks.buildBeautyMasks(inputImage, ...
    context, faceBox);
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
[policyEvidence, evidenceMetadata] = masks.buildBeautyPolicyEvidence( ...
    inputImage, context, faceBox, maskDiagnostics);
context.evidence = policyEvidence;
context.protection = masks.buildStageProtectionMasks(beautyMasks, ...
    policyEvidence);
context = stampPolicyEvidenceMetadata(context, evidenceMetadata);
end

function context = clearDerivedFields(context)
% 清理入口侧可能残留的派生字段，保证重建只来自当前基础字段。
names = {'textureProtectionMask', 'structureProtectionMask', ...
    'whiteningProtectionMask', 'chromaProtectionMask', ...
    'toneProtectionMask', 'strengthMap', 'faceStrengthMap', ...
    'nonFaceStrengthMap', 'protectionMasks', 'protection', 'evidence'};
names = names(isfield(context, names));
if ~isempty(names)
    context = rmfield(context, names);
end
end

function context = stampPolicyEvidenceMetadata(context, metadata)
% 把 evidence 的来源/版本元数据写入 canonical diagnostics 层。
if ~isfield(context, 'diagnostics') || ...
        ~isstruct(context.diagnostics) || ~isscalar(context.diagnostics)
    context.diagnostics = struct();
end
context.diagnostics.policyEvidence = metadata;
end
