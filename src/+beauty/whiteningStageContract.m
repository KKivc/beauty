function contract = whiteningStageContract(stageProtection)
%WHITENINGSTAGECONTRACT 组装 Whitening 的 stage contract（T18/T30/T33）。
%   本函数是 Whitening stage contract 的唯一组装点，由生产组装层
%   （beautifyImage）与 applySkinWhitening 的兼容入口共用，保证两条入口
%   得到同一份 contract。组装**只**消费 V4 stage protection 的规范门
%   （masks.buildStageProtectionMasks 输出），不读取任何 legacy general
%   mask（structure/whitening/faceSkin/nose 保护图），也不再从 beautyMasks
%   反解未折叠门控——组合逻辑已上移到 policy 层。
%
%   T33 输入门（全部来自 stageProtection，见上位契约第 2、3.5 节）：
%     hard                       — 严格二值身份保护（独立字段）；
%     target.whitening           — 逐像素修改保护（1 - 该值 =
%                                  structureGate·featureSetback）；
%     support.whitening          — 参考样本保护（1 - 该值 = 亮度统计选点
%                                  门限 featureZeroGate）；
%     whiteningGates.structureGate — 未折叠结构门（含 faceSkin 浅退让分支）；
%     whiteningGates.featureGate   — 未折叠五官退让门（含 regionBandWhitening）；
%     whiteningAmplitudeCeiling  — 鼻部退让幅度上限（policy 层判定）。
%
%   输出 contract 字段（与 T18 迁移期同名，语义不变）：
%     whitening       — T07 折叠快照（诊断参考，不参与输出算术）；
%     hard            — hard identity；
%     structureGate   — 未折叠结构门；
%     featureGate     — 未折叠五官退让门；
%     featureZeroGate — 五官零保护门限 = 1 - support.whitening；
%     amplitudeCeiling— 鼻部结构存在时的美白幅度上限（.07），否则 Inf。
%
%   高风险区退让（上位契约 3.5）：鼻翼/唇周/眼周退让由 policy 层发布在
%   whiteningGates.featureGate（T30 regionBandWhitening 注入）与
%   whiteningAmplitudeCeiling（鼻部结构幅度上限）上；执行层不再读
%   beautyMasks.noseMask 做特殊分支。ceiling = Inf 时 min(x, Inf) = x 逐位
%   还原生产原式，故零带/无鼻部结构路径与 legacy 逐位等价。
%
%   双门控独立（上位契约第 5 节第 6 条）：target.whitening 只影响逐像素
%   修改，support.whitening 只影响亮度参考统计（featureZeroGate），两者
%   互不污染。
%
%   缺字段或取值无效一律 fail-fast，不在本函数内部重新拼装 protection，
%   也不静默回退到 legacy masks 解释。

if ~isstruct(stageProtection) || ~isscalar(stageProtection)
    error('beauty:InvalidWhiteningInput', ...
        'Whitening stage contract 需要标量 stage protection。');
end
if ~all(isfield(stageProtection, {'hard', 'target', 'support', ...
        'whiteningGates', 'whiteningAmplitudeCeiling'}))
    error('beauty:InvalidWhiteningInput', ...
        'stage protection 缺少 whitening 组装所需的 hard/target/support/whiteningGates/whiteningAmplitudeCeiling。');
end
if ~isstruct(stageProtection.target) || ~isscalar(stageProtection.target) || ...
        ~isfield(stageProtection.target, 'whitening')
    error('beauty:InvalidWhiteningInput', ...
        'stage protection.target 缺少 whitening。');
end
if ~isstruct(stageProtection.support) || ~isscalar(stageProtection.support) || ...
        ~isfield(stageProtection.support, 'whitening')
    error('beauty:InvalidWhiteningInput', ...
        'stage protection.support 缺少 whitening。');
end
if ~isstruct(stageProtection.whiteningGates) || ...
        ~isscalar(stageProtection.whiteningGates) || ...
        ~all(isfield(stageProtection.whiteningGates, ...
        {'structureGate', 'featureGate'}))
    error('beauty:InvalidWhiteningInput', ...
        'stage protection.whiteningGates 缺少 structureGate/featureGate。');
end
hard = readMask(stageProtection.hard, 'hard');
snapshot = readMask(stageProtection.target.whitening, 'target.whitening');
supportProtection = readMask(stageProtection.support.whitening, ...
    'support.whitening');
structureGate = readMask(stageProtection.whiteningGates.structureGate, ...
    'whiteningGates.structureGate');
featureGate = readMask(stageProtection.whiteningGates.featureGate, ...
    'whiteningGates.featureGate');
ceiling = stageProtection.whiteningAmplitudeCeiling;
if ~isnumeric(ceiling) || ~isreal(ceiling) || ~isscalar(ceiling) || ...
        isnan(ceiling) || ceiling <= 0
    error('beauty:InvalidWhiteningInput', ...
        'Mask whiteningAmplitudeCeiling 无效。');
end

contract = struct( ...
    'whitening', snapshot, ...
    'hard', hard, ...
    'structureGate', structureGate, ...
    'featureGate', featureGate, ...
    'featureZeroGate', 1 - supportProtection, ...
    'amplitudeCeiling', double(ceiling));
end

function value = readMask(value, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidWhiteningInput', 'Mask %s 无效。', name);
end
value = double(value);
end
