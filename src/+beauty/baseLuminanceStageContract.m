function contract = baseLuminanceStageContract(stageProtection)
%BASELUMINANCESTAGECONTRACT 组装 Base Luminance 的 stage contract（T32）。
%   本函数是 Base Luminance stage contract 的唯一组装点，由生产组装层
%   （beautifyImage）与 evenSkinLuminance 的兼容入口共用，保证两条入口
%   得到同一份 contract。组装**只**消费 V4 stage protection 的规范门
%   （masks.buildStageProtectionMasks 输出），不读取任何 legacy general
%   mask（texture/structure/chroma/hard 保护图）。
%
%   T32 输入门（全部来自 stageProtection，见上位契约第 2、3.3 节）：
%     hard                     — 严格二值身份保护（独立字段）；
%     target.baseLuminance     — 逐像素修改保护：该像素允不允许做低频
%                                亮度均衡（1 - 该值 = 生产逐像素均衡门）；
%     support.baseLuminance    — 参考池保护：该像素允不允许进入低频参考
%                                统计（1 - 该值 = T30 之前 referenceReliability
%                                的基准门 structureGate·hardProtectionGate·
%                                featureGate）；
%     regionBandBase           — T30 纯 policy 带（T20/T21/T22 追加保护），
%                                **只**乘逐像素 supportMap，不进参考统计。
%
%   输出 contract 字段（全部为"保护量"，0 = 无保护，1 = 完全保护）：
%     hard                 — hard identity；
%     target.baseLuminance — 逐像素均衡保护（原样透传 policy 门）；
%     support.baseLuminance— 参考池保护（原样透传 policy 门）；
%     regionBandGate       — T30 纯 policy 带门 1 - regionBandBase，只乘
%                            逐像素 supportMap。
%
%   target / support 的分离（上位契约第 3.3 节、第 5 节第 6 条）：进入
%   全局参考统计的门（support.baseLuminance）与逐像素修改门
%   （target.baseLuminance）解耦，使 referenceWeight/referenceReliability/
%   referenceCoverage 不被 target 门扰动——把 target 门并进参考池会让带内
%   变化经 imgaussfilt 参考卷积（referenceSigma）扩散到带外，产生 >1
%   灰度级泄漏（T30 实测带外 2226px/0.94% ≤2 灰度级）。
%
%   hard 不并入 target/support（上位契约第 4 节）：它是最终合成的硬约束，
%   消费侧按生产原位单独组合（referenceReliability 与 supportMap 各乘一次
%   (1 - hard)）。
%
%   为什么 target/support 直接透传 policy 门：policy 层已按生产原式
%   （1 - (1-structure).*(1-max(texture,chroma)) 与
%   1 - (1-structure).*(1-hard).*(1-max(texture,chroma))）算好，
%   组装层不再重新拼装，也不再从 legacy mask 反解。
%
%   缺字段或取值无效一律 fail-fast，不在本函数内部重新拼装 protection，
%   也不静默回退到 legacy masks 解释。

if ~isstruct(stageProtection) || ~isscalar(stageProtection)
    error('beauty:InvalidEvenLuminanceInput', ...
        'Base Luminance stage contract 需要标量 stage protection。');
end
if ~all(isfield(stageProtection, {'hard', 'target', 'support', ...
        'regionBandBase'}))
    error('beauty:InvalidEvenLuminanceInput', ...
        'stage protection 缺少 baseLuminance 组装所需的 hard/target/support/regionBandBase。');
end
if ~isstruct(stageProtection.target) || ~isscalar(stageProtection.target) || ...
        ~isfield(stageProtection.target, 'baseLuminance')
    error('beauty:InvalidEvenLuminanceInput', ...
        'stage protection.target 缺少 baseLuminance。');
end
if ~isstruct(stageProtection.support) || ~isscalar(stageProtection.support) || ...
        ~isfield(stageProtection.support, 'baseLuminance')
    error('beauty:InvalidEvenLuminanceInput', ...
        'stage protection.support 缺少 baseLuminance。');
end
hard = readMask(stageProtection.hard, 'hard');
targetProtection = readMask(stageProtection.target.baseLuminance, ...
    'target.baseLuminance');
supportProtection = readMask(stageProtection.support.baseLuminance, ...
    'support.baseLuminance');
regionBandBase = readMask(stageProtection.regionBandBase, 'regionBandBase');

contract = struct( ...
    'hard', hard, ...
    'target', struct('baseLuminance', targetProtection), ...
    'support', struct('baseLuminance', supportProtection), ...
    'regionBandGate', 1 - regionBandBase);
end

function value = readMask(value, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidEvenLuminanceInput', 'Mask %s 无效。', name);
end
value = double(value);
end
