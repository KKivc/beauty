function contract = repairStageContract(stageProtection, blemishMap)
%REPAIRSTAGECONTRACT 组装 Repair（Fine/Mid）的 stage contract（T14/T15/T30/T31）。
%   本函数是 repair stage contract 的唯一组装点，由生产组装层
%   （beautifyImage）与 repairSkinBlemishes 的兼容入口共用，保证两条入口
%   得到同一份 contract。组装**只**消费 V4 stage protection 的规范门
%   （masks.buildStageProtectionMasks 输出）与本次调用的运行期 blemish
%   证据，不读取任何 legacy general mask（texture/structure/hard/nose
%   保护图）。
%
%   T31 输入门（全部来自 stageProtection，见上位契约第 2 节）：
%     hard                     — 严格二值身份保护（独立字段）；
%     support.repairFine       — repair 参考池纹理保护源（policy 发布 = texture）；
%     support.repairMid        — repair 参考池结构保护源（policy 发布 = structure）；
%     target.repairFine        — T07 零瑕疵折叠快照（仅诊断参考，见下）；
%     target.repairMid         — T07 零瑕疵折叠快照（仅诊断参考，见下）；
%     noseMidProtection        — Mid 鼻部退让保护（policy 发布 = .50·nose）；
%     regionBandFine           — T30 纯 policy 带（T20/T21/T22 追加保护）；
%     regionBandMid            — T30 Mid 专属纯 policy 带（仅 mediumWeight）。
%
%   输出 contract 字段（全部为"保护量"，0 = 无保护，1 = 完全保护）：
%     hard                 — hard identity；
%     support.repairMid    — 结构保护：该像素对 repair 的结构保护量，
%                            **同时**作用于逐像素前置截断与邻域参考池
%                            （legacy 两条路径共用同一 structureGate，
%                            见下"结构门共享"）。1 - support.repairMid 即
%                            生产 structureGate；
%     support.repairFine   — 参考池纹理保护：1 - support.repairFine 即
%                            生产 textureGate；
%     target.repairFine    — 截断后作用的纹理退让保护（Fine/Mid/chroma 逐像素门）；
%     target.repairMid     — 截断后作用的 Mid 鼻部退让保护（仅 mediumWeight）；
%     textureBandGate      — T30 纯 policy 带门 1 - regionBandFine，只乘逐像素
%                            权重，不进邻域参考统计；
%     midBandGate          — T30 Mid 专属纯 policy 带门 1 - regionBandMid，
%                            只乘 mediumWeight，不进邻域参考统计；
%     snapshot.repairFine / .repairMid — T07 零瑕疵折叠快照，仅供诊断与测试
%                            消费（1 - snapshot 即零瑕疵参考门）。
%
%   Mid 逐像素门 = (1 - target.repairMid) .* midBandGate（= legacy
%   noseMidGate = (1-.50·nose)·(1-regionBandMid)），消费侧按生产原式的
%   乘积与顺序重建：两条带门与鼻部退让门都在 [0,1] 截断之后作用于
%   mediumWeight，且都不进参考池（与 textureBandGate 同款）。
%
%   结构门共享（为什么只有一个结构保护字段）：生产链里同一个
%   structureGate = min(1 - structure·(1-.90·blemish), 1 - .65·strongStructure)
%   既乘逐像素权重（截断之前），又乘邻域参考池门。它依赖运行期 blemish
%   证据与 hard 特征带，无法在 policy 层一次算好，因此由本组装层重建。
%   按契约"同一语义只留一个规范字段"，它在 support.repairMid 发布一次，
%   消费侧两处都用 1 - support.repairMid 还原。
%
%   为什么 support.repairMid 取 max(a, b) 而不是 1 - structureGate：
%   `1 - x` 的补码往返（1 - (1 - gate)）在 IEEE double 下不保证逐位还原，
%   而结构保护必须保证消费侧 1 - support.repairMid 与生产 structureGate
%   逐位相等。令 a = structure·(1-.90·blemish)、b = .65·strongStructure，
%   生产 structureGate = min(1 - a, 1 - b)。由于舍入单调，min(1-a, 1-b)
%   恒等于 1 - max(a, b)，故发布 protection = max(a, b) 时
%   1 - protection 逐位还原生产 structureGate。support.repairFine 与
%   target.repair* 的补码同理：它们直接发布生产门的补码源
%   （texture / .50·nose），1 - 该值逐位还原生产门。
%
%   为什么 target 保护分成"前置结构 + 截断后纹理/鼻"两段：生产链在结构门
%   与纹理/鼻部门之间对权重做 [0,1] 截断（min(max(w·structureGate,0),1)
%   之后才乘 textureGate/noseMidGate）。把 texture/nose 折进前置门会在
%   截断饱和区改变结果（真实图 77 实测：fineWeight 7594px、mediumWeight
%   3429px 偏离，最大 1.33）；因此结构分量与纹理/鼻分量必须分别按生产
%   原位发布，消费侧按同一顺序重建。
%
%   target/support 的分离（上位契约第 4 节"全局参考解耦"）：进入邻域参考
%   统计的门（support.*）与逐像素修改门（target.*）解耦，使
%   referenceWeight/referenceReliability 不被 target 门扰动——把 target 门
%   并进参考池会让带内变化经 imfilter（radius = min(20,max(3,round(.070·
%   faceScale)))）扩散到带外，产生 >1 灰度级泄漏。
%
%   Blemish ≠ Should Repair（上位契约第 3.2 节）：blemish 证据只回答"像不像
%   瑕疵"，"该不该修"由 (1 - targetProtection) 单独决定；本层不把结构保护
%   反向塞进 blemish 检测，也不让 blemish 证据单独决定修复强度。结构门里的
%   (1 - .90·blemish) 是 legacy 既有的"高置信瑕疵可适度放宽一般结构门控"，
%   属结构门对瑕疵证据的既有耦合，不改变"证据不单独决定强度"的约束。
%
%   缺字段或取值无效一律 fail-fast，不在本函数内部重新拼装 protection，也不
%   静默回退到 legacy masks 解释。

if ~isstruct(stageProtection) || ~isscalar(stageProtection)
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 需要标量 stage protection。');
end
if ~all(isfield(stageProtection, {'hard', 'target', 'support', ...
        'noseMidProtection', 'regionBandFine', 'regionBandMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'stage protection 缺少 repair 组装所需的 hard/target/support/noseMidProtection/regionBandFine/regionBandMid。');
end
if ~isstruct(stageProtection.target) || ~isscalar(stageProtection.target) || ...
        ~all(isfield(stageProtection.target, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'stage protection.target 缺少 repairFine/repairMid。');
end
if ~isstruct(stageProtection.support) || ~isscalar(stageProtection.support) || ...
        ~all(isfield(stageProtection.support, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'stage protection.support 缺少 repairFine/repairMid。');
end
hard = readMask(stageProtection.hard, 'hard');
textureProtection = readMask(stageProtection.support.repairFine, ...
    'support.repairFine');
structureProtection = readMask(stageProtection.support.repairMid, ...
    'support.repairMid');
noseProtection = readMask(stageProtection.noseMidProtection, ...
    'noseMidProtection');
regionBandFine = readMask(stageProtection.regionBandFine, 'regionBandFine');
regionBandMid = readMask(stageProtection.regionBandMid, 'regionBandMid');
snapshotFine = readMask(stageProtection.target.repairFine, 'target.repairFine');
snapshotMid = readMask(stageProtection.target.repairMid, 'target.repairMid');
blemishMap = readMask(blemishMap, 'blemishMap');

% 生产 structureGate = min(1 - structure·(1-.90·blemish), 1 - .65·strongStructure)。
% 按上面的单调性推导，发布 max(a, b) 使消费侧 1 - support.repairMid 逐位还原。
strongStructure = smoothStep(structureProtection, .70, .90) .* ...
    double(bwdist(hard >= .999) <= 3);
blemishRelaxedProtection = structureProtection .* (1 - .90 * blemishMap);
structureSupportProtection = max(blemishRelaxedProtection, ...
    .65 * strongStructure);

contract = struct( ...
    'hard', hard, ...
    'support', struct( ...
    'repairFine', textureProtection, ...
    'repairMid', structureSupportProtection), ...
    'target', struct( ...
    'repairFine', textureProtection, ...
    'repairMid', noseProtection), ...
    'textureBandGate', 1 - regionBandFine, ...
    'midBandGate', 1 - regionBandMid, ...
    'snapshot', struct( ...
    'repairFine', snapshotFine, ...
    'repairMid', snapshotMid));
end

function value = readMask(value, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidBlemishRepair', 'Mask %s 无效。', name);
end
value = double(value);
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end
