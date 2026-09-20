function contract = toneStageContract(stageProtection)
%TONESTAGECONTRACT 组装 Tone 的 stage contract（T17/T30/T33）。
%   本函数是 Tone stage contract 的唯一组装点，由生产组装层
%   （beautifyImage）与 normalizeSkinTone 的兼容入口共用，保证两条入口
%   得到同一份 contract。组装**只**消费 V4 stage protection 的规范门
%   （masks.buildStageProtectionMasks 输出），不读取任何 legacy general
%   mask（texture/structure/chroma/hard/nose 保护图），也不再从
%   beautyMasks 反解未折叠门控——组合逻辑已上移到 policy 层。
%
%   T33 输入门（全部来自 stageProtection，见上位契约第 2、3.4 节）：
%     hard                      — 严格二值身份保护（独立字段）；
%     target.tone               — 逐像素修改保护（1 - 该值 = 主分支门控积
%                                 structureGate·featureGate）；
%     support.tone              — 参考样本保护（1 - 该值 = tone 候选选点
%                                 门限 candidateChromaGate）；
%     toneGates.structureGate   — 主/uniform 分支共用的未折叠结构门；
%     toneGates.featureGate     — 主分支未折叠 feature 门（含 regionBandTone）；
%     toneGates.uniformFeatureGate — uniform 分支未折叠 feature 门。
%
%   输出 contract 字段（与 T17 迁移期同名，语义不变）：
%     tone                — T07 折叠快照（诊断参考，不参与输出算术）；
%     hard                — hard identity；
%     structureGate       — 主/uniform 共用结构门；
%     featureGate         — 主分支 feature 门；
%     uniformFeatureGate  — uniform 分支 feature 门（ratio>.50 时生效）；
%     candidateChromaGate — 候选色度保护门限 = 1 - support.tone。
%
%   为什么 target.tone 不直接参与门控积：T07 折叠快照含 1-x 补码往返
%   舍入（1-(1-x) 在 IEEE double 下不保证逐位还原），而门控必须与 legacy
%   路径逐位等价。policy 层因此把未折叠门控因子原样发布在 toneGates，
%   消费侧按生产原位相乘；target.tone 作为规范"逐像素保护"字段发布并供
%   诊断（toneGateSnapshot = target.tone）与测试消费。
%
%   双门控独立（上位契约第 5 节第 6 条）：target.tone 只影响逐像素修改，
%   support.tone 只影响候选参考统计（candidateChromaGate），两者互不污染。
%
%   缺字段或取值无效一律 fail-fast，不在本函数内部重新拼装 protection，
%   也不静默回退到 legacy masks 解释。

if ~isstruct(stageProtection) || ~isscalar(stageProtection)
    error('beauty:InvalidSkinToneInput', ...
        'Tone stage contract 需要标量 stage protection。');
end
if ~all(isfield(stageProtection, {'hard', 'target', 'support', 'toneGates'}))
    error('beauty:InvalidSkinToneInput', ...
        'stage protection 缺少 tone 组装所需的 hard/target/support/toneGates。');
end
if ~isstruct(stageProtection.target) || ~isscalar(stageProtection.target) || ...
        ~isfield(stageProtection.target, 'tone')
    error('beauty:InvalidSkinToneInput', ...
        'stage protection.target 缺少 tone。');
end
if ~isstruct(stageProtection.support) || ~isscalar(stageProtection.support) || ...
        ~isfield(stageProtection.support, 'tone')
    error('beauty:InvalidSkinToneInput', ...
        'stage protection.support 缺少 tone。');
end
if ~isstruct(stageProtection.toneGates) || ~isscalar(stageProtection.toneGates) || ...
        ~all(isfield(stageProtection.toneGates, ...
        {'structureGate', 'featureGate', 'uniformFeatureGate'}))
    error('beauty:InvalidSkinToneInput', ...
        'stage protection.toneGates 缺少 structureGate/featureGate/uniformFeatureGate。');
end
hard = readMask(stageProtection.hard, 'hard');
snapshot = readMask(stageProtection.target.tone, 'target.tone');
supportProtection = readMask(stageProtection.support.tone, 'support.tone');
structureGate = readMask(stageProtection.toneGates.structureGate, ...
    'toneGates.structureGate');
featureGate = readMask(stageProtection.toneGates.featureGate, ...
    'toneGates.featureGate');
uniformFeatureGate = readMask(stageProtection.toneGates.uniformFeatureGate, ...
    'toneGates.uniformFeatureGate');

contract = struct( ...
    'tone', snapshot, ...
    'hard', hard, ...
    'structureGate', structureGate, ...
    'featureGate', featureGate, ...
    'uniformFeatureGate', uniformFeatureGate, ...
    'candidateChromaGate', 1 - supportProtection);
end

function value = readMask(value, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidSkinToneInput', 'Mask %s 无效。', name);
end
value = double(value);
end
