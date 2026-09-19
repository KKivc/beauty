function protection = buildStageProtectionMasks(beautyMasks, policyEvidence)
%BUILDSTAGEPROTECTIONMASKS 从 v3.1 Beauty Masks 推导 V4 stage protection。
%   T07 兼容阶段：把当前 texture/structure/chroma/whitening/hard/nose
%   门控按各生产 stage 的真实组合方式映射为八个 stage 字段，只做行为
%   等价的 algebra 组合，不重新设计任何权重。
%
%   T20（eye/lip identity policy）：本函数新增可选第二输入
%   policyEvidence（masks.buildBeautyPolicyEvidence 的第一输出，经
%   rebuildBeautyDerivedMasks 桥接传入；生产调用点 beautifyImage 从
%   normalized Context 的 evidence 层转发）。提供且包含 periocular/lip
%   字段时，对眼周/唇周执行三带分级保护 policy：
%
%     identity core —— 眼语义（>= .65，经 occluderHard）、检测睫毛
%       lashCore、唇核 lipCore。它们已全部位于 hardProtectionMask，
%       T20 不新增任何 hard 像素（hard 原样拷贝，严格二值不变）。
%     soft detail band —— 紧贴 identity core 的检测细节带：
%       eyeDetailBand  = smoothStep(periocular, .50, .78)
%       lipDetailBand  = smoothStep(lip, .55, .85)
%       依据：periocular 的几何环峰值为 .76（featherSoftMask 峰值），
%       检测睫毛/双眼皮褶皱核心为 .99/.92，故 .78 上支撑点≈"检测细节
%       核心 + 环带内缘"，.50 下支撑点≈环带内 1/3（d ≈ .34·R）；
%       lip 环峰值为 .90（lipRadius 羽化），.85/.55 对应环带内缘与
%       内 39%（d ≈ .39·r）。两带的上下支撑点均为各自峰值的固定比例
%       （≈1.03 峰值与 ≈0.66/0.61 峰值），随脸尺度自适应。
%     skin transition band —— 环带外半程的皮肤过渡带：
%       eyeTransition = smoothStep(periocular, .08, .40)
%       lipTransition = smoothStep(lip, .12, .50)
%       依据：上支撑点≈各峰值的 53%/56%（环带中点，d ≈ .47·R），
%       下支撑点≈峰值的 11%/13%（羽化尾部消失处，d ≈ .9·R）。
%       detail 与 transition 用 (1 - detailBand) 互斥，避免双重计入。
%
%     七个 stage 字段的差异化分配（全部以 max/min 作用于 T07 legacy
%     折叠式， Bands 全零时与 legacy 逐位相等）：
%       texture 通道替换 —— 环带内把 texture 中 eye/lip 的贡献替换为
%         policy 值（texture 是合并 max，无法逐分量剥离，只能在
%         evidence 圈定的带内整体替换；structure 门保持乘子原位，
%         结构保护不受 cap 影响）：
%         policyTexture = max(texture, .95·detailBand)
%         policyTexture = min(policyTexture, 1 - .55·transitionBand)
%         .95 取检测细节保护区间 .92（fold）--.99（lash）的中点，细节
%         带内 Fine 门只剩 <=5%；cap 在满权重处保留 >=55% 的 Fine 处
%         理量——legacy 环带 plateau 为 .76--.90（唇环甚至低于 .80 可
%         处理线，形成未处理环带），.55 是普通皮肤（100%）与细节带
%         （5%）的中点。作用于 smoothingFine/repairFine/baseLuminance。
%       Mid 家族（smoothingMid/repairMid）补保护：legacy 折叠不含
%         texture，睫毛/双眼皮褶皱/唇缘的中频细节此前被全强度磨除。
%         smoothingMid 等字段取 max(legacy, .90·detailBand,
%         .30·transitionBand)：.90 与检测细节区间对齐；.30 过渡带轻
%         保护维持眼窝/唇周中频明暗连续，同时保留 >=70% 中频处理量。
%       tone：max(legacy, .90·lipDetailBand)——唇色是 identity 色度，
%         只对唇细节带生效；眼周色度无额外 identity 语义，仍由
%         chroma 保护承载。
%       whitening：max(legacy, .85·detailBand)——防止唇缘/眼缘假白
%         光晕；略低于 Fine 侧 .95，避免美白场在带边形成自身台阶。
%         过渡带不设 cap：眼周/唇周皮肤亮度应与全脸连续。
%
%   消费侧现状（诚实边界）：smoothingFine/smoothingMid/hard 被
%   smoothSkinTexture（T12/T13）直接用于输出算术，本 policy 对磨皮立
%   即生效；repairFine/repairMid/baseLuminance/tone/whitening 仍是
%   T14--T18 consumer 的零瑕疵参考快照（算术门控由未折叠字段承载），
%   分级数值先行发布，待对应 consumer 迁移后生效。
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
%   legacy 折叠式（T07 推导，Bands 全零时逐位还原）：
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
%       (1-structure).*(1-chroma)（比本字段更强），单快照无法同时
%       表达两条分支；T17 起消费侧改由生产端拼装的未折叠
%       uniformFeatureGate 字段精确重建该分支，本快照只作主分支参考
%       （toneGateSnapshot）。
%     whitening
%       beauty.applySkinWhitening 的 supportBase 门控（featureSetback =
%       1 - whitening；structureGate = 1 - structure，脸部（faceSkin
%       >= .5）浅退让为 1 - .10*structure；allowed 中的 (1-hard) 单独
%       保留）：whitening = 1 - structureGateWhitening .* (1 - whitening)。
%       supportBase 重算与生产逐像素等价。
%     hard
%       buildTextureProtectionMask 的 hardProtectionMask =
%       double(occluderHard | lipCore | nostrilCore | lashCore)，原样
%       拷贝（bit-exact，二值 identity）。T20 不扩大 hard：eye/lip
%       identity core 已在其中，soft band / transition band 一律不进
%       hard。
%
%   输入参数：
%     beautyMasks — masks.buildBeautyMasks 的第一输出（含
%                   texture/structure/chroma/whitening/hardProtection、
%                   noseMask、faceSkinMask）；v3.1 顶层 Context 不直接
%                   作为输入，保证与生产门控共用同一份 mask 产物。
%     policyEvidence — 可选。masks.buildBeautyPolicyEvidence 的第一
%                   输出；只消费 periocular/lip 两个 eye/lip 语义字段，
%                   其余字段仍与本层解耦。缺省（nargin<2）、空结构或
%                   缺少 periocular/lip 字段（partial V4）时按零带处理，
%                   输出与 T07 legacy 折叠逐位相等；字段存在但尺寸/
%                   取值非法时 fail-fast。

if nargin < 2
    policyEvidence = [];
end

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

% T20：eye/lip 语义证据带。缺省或 partial evidence 时全部为零带，
% 后续所有 max/min 作用退化为恒等，输出与 T07 legacy 逐位相等。
[eyeField, lipField] = readEyeLipEvidence(policyEvidence, size(texture));
eyeDetailBand = smoothStep(eyeField, .50, .78);
eyeTransitionBand = smoothStep(eyeField, .08, .40);
lipDetailBand = smoothStep(lipField, .55, .85);
lipTransitionBand = smoothStep(lipField, .12, .50);
detailBand = max(eyeDetailBand, lipDetailBand);
transitionBand = max(eyeTransitionBand, lipTransitionBand) .* ...
    (1 - detailBand);

% T20 texture 通道替换：细节带内抬升到检测细节保护水平，过渡带内
% 封顶保留处理量；带外逐位还原（max(x,0)=x，min(x,1)=x）。
policyTexture = max(texture, .95 * detailBand);
policyTexture = min(policyTexture, 1 - .55 * transitionBand);

% smoothSkinTexture L98：fineStructureGate = max(0, 1 - 4*structure)。
fineStructureGate = max(0, 1 - 4 * structure);
% Fine：hard 走生产原位的 max 合并，texture×structure 折叠进本字段。
% T20：texture 通道在 eye/lip 带内替换为 policyTexture。
smoothingFine = 1 - (1 - policyTexture) .* fineStructureGate;
% Mid：midStructureGate（=fineStructureGate）与 noseMidGate 的静态满档
% 快照（生产 noseMidGate = 1 - .50*nose.*alphaCurve，alphaCurve 归
% effect-strength 侧）。T20：eye/lip 带内补中频保护。
smoothingMid = max(max(1 - fineStructureGate .* (1 - .50 * nose), ...
    .90 * detailBand), .30 * transitionBand);

% repairSkinBlemishes L48-51：strongStructure 与 structureGate 上限，
% 零瑕疵参考点为 min(1 - structure, 1 - .65*strongStructure)。
strongStructure = smoothStep(structure, .70, .90) .* ...
    double(bwdist(hard >= .999) <= 3);
structureGateRepair = min(1 - structure, 1 - .65 * strongStructure);
% repairSkinBlemishes L97-100：textureGate = 1 - texture 线性作用于
% fineWeight/mediumWeight/chromaWeight。T20：texture 通道同上替换。
repairFine = 1 - structureGateRepair .* (1 - policyTexture);
% repair 侧 noseMidGate = 1 - .50*nose（L78，无 alphaCurve，纯静态）。
% T20：eye/lip 带内补中频保护（与 smoothingMid 同族）。
repairMid = max(max(1 - structureGateRepair .* (1 - .50 * nose) .* ...
    (1 - policyTexture), .90 * detailBand), .30 * transitionBand);

% evenSkinLuminance L42/L88-93：featureProtection = max(texture, chroma)。
% T20：texture 通道同上替换（过渡带 cap 打开亮度均衡的处理量）。
baseLuminance = 1 - (1 - structure) .* (1 - max(policyTexture, chroma));

% normalizeSkinTone L77-78：featureGate = 1 - .78*chroma（主分支）。
% T20：唇细节带内补唇色 identity 保护。
tone = max(1 - (1 - structure) .* (1 - .78 * chroma), ...
    .90 * lipDetailBand);

% applySkinWhitening L53-57/L61：脸部浅退让 1 - .10*structure 与
% featureSetback = 1 - whitening。T20：细节带内补假白光晕退让。
structureGateWhitening = 1 - structure;
faceSkinSupport = faceSkin >= .5;
structureGateWhitening(faceSkinSupport) = ...
    1 - .10 * structure(faceSkinSupport);
whiteningField = max(1 - structureGateWhitening .* (1 - whitening), ...
    .85 * detailBand);

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

function [eyeField, lipField] = readEyeLipEvidence(policyEvidence, imageSize)
%READEYELIPEVIDENCE 从 policy evidence 中读取 eye/lip 语义字段。
%   缺省输入、空结构或缺少 periocular/lip 字段（partial V4）时返回零
%   矩阵（零带 → legacy 逐位还原）；字段存在但类型/尺寸/取值非法时
%   fail-fast，不静默修正。
emptyField = zeros(imageSize);
if isempty(policyEvidence)
    eyeField = emptyField;
    lipField = emptyField;
    return;
end
if ~isstruct(policyEvidence) || ~isscalar(policyEvidence)
    error('masks:InvalidEvidence', ...
        'policyEvidence 必须是标量 evidence 结构或为空。');
end
eyeField = readEvidenceField(policyEvidence, 'periocular', imageSize);
lipField = readEvidenceField(policyEvidence, 'lip', imageSize);
end

function value = readEvidenceField(evidence, name, imageSize)
if ~isfield(evidence, name) || isempty(evidence.(name))
    value = zeros(imageSize);
    return;
end
value = evidence.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || ...
        any(value(:) > 1)
    error('masks:InvalidEvidence', ...
        'evidence 字段 %s 的尺寸或取值无效。', name);
end
value = double(value);
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
