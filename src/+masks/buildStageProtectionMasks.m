function protection = buildStageProtectionMasks(beautyMasks)
%BUILDSTAGEPROTECTIONMASKS 从 v3.1 Beauty Masks 推导 V4 stage protection。
%   T07 兼容阶段：把当前 texture/structure/chroma/whitening/hard/nose
%   门控按各生产 stage 的真实组合方式映射为八个 stage 字段，只做行为
%   等价的 algebra 组合，不重新设计任何权重；后续 Region Policy Ticket
%   在此基础上逐 stage 改效果。
%
%   统一语义：protection 字段是"该 stage 施加的保护量"，取值 [0,1]，
%   消费侧用 gate = 1 - protection（或 1 - max(field, hard)）还原生产
%   门控。三个边界约定（与 T12--T19 的 consumer contract 一致）：
%     * hard identity 不并入任何 stage 字段：protection.hard 单独发布，
%       各 stage 按生产原位（max 合并或 (1-hard) 乘子）自行组合；
%     * strengthMap/effectStrengthMap 保持独立：profile.alphaCurve、
%       strengthMap 等强度侧标量一律不进入本层；
%     * runtime 证据（blemishMap 及其耦合的 structure gate 放宽）不进
%       入本层，字段记录其在零瑕疵参考点的快照（见 repairFine 说明）。
%
%   字段推导映射（production gate → stage 字段）：
%     smoothingFine
%       beauty.smoothSkinTexture 的 Fine 门控（fineProtection =
%       max(texture, hard) 与 fineStructureGate = max(0, 1-4*structure)，
%       alphaMap = effectStrength .* (1 - fineProtection) .*
%       fineStructureGate）：hard 走 max 合并，余下部分折叠为
%       smoothingFine = 1 - (1 - texture) .* max(0, 1 - 4*structure)。
%       重算 alphaMap = effectStrength .* (1 - max(smoothingFine, hard))
%       与生产逐像素等价。
%     smoothingMid
%       同函数 Mid 分支的额外门控（midStructureGate = fineStructureGate
%       与 noseMidGate = 1 - .50*nose.*profile.alphaCurve）：nose 项取
%       生产系数 .50 的满档快照（alphaCurve=1；alphaCurve 的强度插值
%       属 effect-strength 侧，见上），折叠为
%       smoothingMid = 1 - fineStructureGate .* (1 - .50*nose)。
%       重算 midAlphaMap = alphaMap .* (1 - smoothingMid) 在
%       alphaCurve=1 时与生产等价；alphaCurve<1 时生产 nose 门控为
%       1 与该快照的凸组合（快照即最强保护）。
%     repairFine
%       beauty.repairSkinBlemishes 的 fineWeight 门控（structureGate =
%       min(1 - structure.*(1-.90*blemish), 1 - .65*strongStructure)，
%       strongStructure = smoothStep(structure,.70,.90) .* (hard 特征
%       3px 带)；textureGate = 1 - texture 线性作用；allowed 中的
%       (1-hard) 单独保留）：记录零瑕疵参考点 structureGate0 =
%       min(1 - structure, 1 - .65*strongStructure)，折叠为
%       repairFine = 1 - structureGate0 .* (1 - texture)。runtime
%       blemish 证据只放宽 structureGate（≥ structureGate0），由
%       consumer 与 runtime evidence 一起消费。
%     repairMid
%       同函数 mediumWeight 门控：与 fine 共享 structureGate，另有
%       noseMidGate = 1 - .50*nose（repair 侧无 alphaCurve，完全静态）
%       与 textureGate：repairMid = 1 - structureGate0 .*
%       (1 - .50*nose) .* (1 - texture)。零瑕疵参考点重算与生产等价。
%     baseLuminance
%       beauty.evenSkinLuminance 的 supportMap 门控（structureGate =
%       1 - structure；featureProtection = max(texture, chroma)；
%       hardProtectionGate = 1 - hard 单独保留）：
%       baseLuminance = 1 - (1 - structure) .* (1 - max(texture, chroma))。
%       supportMap = baseWeightCurve .* regionalSkinWeight .* (1-hard) .*
%       (1 - baseLuminance) .* referenceCoverage 与生产逐像素等价。
%     tone
%       beauty.normalizeSkinTone 主 weight 分支（structureGate =
%       1 - structure；featureGate = 1 - .78*chroma；allowed 中的
%       (1-hard) 单独保留）：tone = 1 - (1 - structure) .*
%       (1 - .78*chroma)。已知残差：ratio>.50 的 uniform 分支使用
%       (1-structure).*(1-chroma)（比本字段更强），属 T17 迁移时的
%       消费侧课题。
%     whitening
%       beauty.applySkinWhitening 的 supportBase 门控（featureSetback =
%       1 - whitening；structureGate = 1 - structure，脸部（faceSkin
%       >= .5）浅退让为 1 - .10*structure；allowed 中的 (1-hard) 单独
%       保留）：whitening = 1 - structureGateWhitening .* (1 - whitening)。
%       supportBase 重算与生产逐像素等价。
%     hard
%       buildTextureProtectionMask 的 hardProtectionMask =
%       double(occluderHard | lipCore | nostrilCore | lashCore)，原样
%       拷贝（bit-exact，二值 identity）。nostrilCore 与 lashCore 的
%       hard identity 行为在本层原样保留，直至对应 Region Policy
%       Ticket 才允许改变。
%
%   输入参数：
%     beautyMasks — masks.buildBeautyMasks 的第一输出（含
%                   texture/structure/chroma/whitening/hardProtection、
%                   noseMask、faceSkinMask）；v3.1 顶层 Context 不直接
%                   作为输入，保证与生产门控共用同一份 mask 产物。

requiredFields = {'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'whiteningProtectionMask', ...
    'hardProtectionMask', 'noseMask', 'faceSkinMask'};
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks) || ...
        ~all(isfield(beautyMasks, requiredFields))
    error('masks:InvalidMasks', ...
        'stage protection 需要完整的 v3.1 Beauty Masks 产物。');
end

texture = readMask(beautyMasks, 'textureProtectionMask');
structure = readMask(beautyMasks, 'structureProtectionMask');
chroma = readMask(beautyMasks, 'chromaProtectionMask');
whitening = readMask(beautyMasks, 'whiteningProtectionMask');
hard = readMask(beautyMasks, 'hardProtectionMask');
nose = readMask(beautyMasks, 'noseMask');
faceSkin = readMask(beautyMasks, 'faceSkinMask');
maskNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'whiteningProtectionMask', ...
    'hardProtectionMask', 'noseMask', 'faceSkinMask'};
maskValues = {texture, structure, chroma, whitening, hard, nose, faceSkin};
for index = 2:numel(maskValues)
    if ~isequal(size(maskValues{index}), size(texture))
        error('masks:InvalidMasks', ...
            'Beauty Masks 字段 %s 与 textureProtectionMask 尺寸不一致。', ...
            maskNames{index});
    end
end

% smoothSkinTexture L98：fineStructureGate = max(0, 1 - 4*structure)。
fineStructureGate = max(0, 1 - 4 * structure);
% Fine：hard 走生产原位的 max 合并，texture×structure 折叠进本字段。
smoothingFine = 1 - (1 - texture) .* fineStructureGate;
% Mid：midStructureGate（=fineStructureGate）与 noseMidGate 的静态满档
% 快照（生产 noseMidGate = 1 - .50*nose.*alphaCurve，alphaCurve 归
% effect-strength 侧）。
smoothingMid = 1 - fineStructureGate .* (1 - .50 * nose);

% repairSkinBlemishes L48-51：strongStructure 与 structureGate 上限，
% 零瑕疵参考点为 min(1 - structure, 1 - .65*strongStructure)。
strongStructure = smoothStep(structure, .70, .90) .* ...
    double(bwdist(hard >= .999) <= 3);
structureGateRepair = min(1 - structure, 1 - .65 * strongStructure);
% repairSkinBlemishes L97-100：textureGate = 1 - texture 线性作用于
% fineWeight/mediumWeight/chromaWeight。
textureGate = 1 - texture;
% repair 侧 noseMidGate = 1 - .50*nose（L78，无 alphaCurve，纯静态）。
repairNoseGate = 1 - .50 * nose;
repairFine = 1 - structureGateRepair .* textureGate;
repairMid = 1 - structureGateRepair .* repairNoseGate .* textureGate;

% evenSkinLuminance L42/L88-93：featureProtection = max(texture, chroma)。
baseFeatureGate = 1 - max(texture, chroma);
baseLuminance = 1 - (1 - structure) .* baseFeatureGate;

% normalizeSkinTone L77-78：featureGate = 1 - .78*chroma（主分支）。
toneFeatureGate = 1 - .78 * chroma;
tone = 1 - (1 - structure) .* toneFeatureGate;

% applySkinWhitening L53-57/L61：脸部浅退让 1 - .10*structure 与
% featureSetback = 1 - whitening。
structureGateWhitening = 1 - structure;
faceSkinSupport = faceSkin >= .5;
structureGateWhitening(faceSkinSupport) = ...
    1 - .10 * structure(faceSkinSupport);
whiteningField = 1 - structureGateWhitening .* (1 - whitening);

protection = struct( ...
    'smoothingFine', clamp01(smoothingFine), ...
    'smoothingMid', clamp01(smoothingMid), ...
    'repairFine', clamp01(repairFine), ...
    'repairMid', clamp01(repairMid), ...
    'baseLuminance', clamp01(baseLuminance), ...
    'tone', clamp01(tone), ...
    'whitening', clamp01(whiteningField), ...
    'hard', hard);
end

function value = readMask(beautyMasks, name)
value = beautyMasks.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidMasks', ...
        'Beauty Masks 字段 %s 的类型、尺寸或取值无效。', name);
end
value = double(value);
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function value = clamp01(value)
value = min(max(double(value), 0), 1);
end
