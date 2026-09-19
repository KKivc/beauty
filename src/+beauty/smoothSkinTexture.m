function [smoothedFrequency, diagnostics] = smoothSkinTexture( ...
        frequency, beautyMasks, smoothingStrength, blemishMap, stageProtection)
%SMOOTHSKINTEXTURE 以独立保留率图连续衰减 Fine 和 Mid 纹理。
%   Base 始终不变；Fine 和 Mid 使用同一输入分解的不同保留率。
%
%   T12/T13：可选第 5 参数 stageProtection 是 V4 stage contract 的
%   protection 分层（masks.buildStageProtectionMasks 输出）。提供时
%   Fine 与 Mid 门控只从 stage contract 读取，不再自行解释 general
%   texture/structure masks 与 nose 区域特判：
%     Fine：fineProtection = max(smoothingFine, hard)（T07 折叠推导，
%           smoothingFine = 1 - (1-texture)·max(0,1-4·structure)，hard
%           保持生产原位的 max 合并），alphaMap = effectStrength .*
%           (1 - fineProtection)。
%     Mid：快照 smoothingMid 取 alphaCurve=1 满档（T07：
%           smoothingMid = 1 - fineStructureGate·(1 - .50·nose)），
%           生产 noseMidGate = 1 - .50·nose·alphaCurve 的强度插值归属
%           effect-strength 侧，由消费侧按凸组合还原：
%           midGate = alphaCurve·(1 - smoothingMid)
%                   + (1 - alphaCurve)·fineStructureGate。
%           该凸组合代数上恒等于生产门控 fineStructureGate·(1 -
%           .50·nose·alphaCurve)：快照为最强保护端点，1 为零保护
%           端点，强度无关的结构锚点 fineStructureGate 保持生产原值。
%           与生产仅差乘法结合顺序与 1-x 补码往返的浮点噪声（≤1e-15，
%           T07 推导基线 1.11e-16 同量级）；alphaCurve=1 时恰为 T07
%           已验证的快照重算 midAlphaMap = alphaMap·(1 - smoothingMid)。
%           nose 区域身份与 .50 系数只存在于 producer，算法侧 Mid 不
%           再读取 noseMask；结构锚点与 buildStageProtectionMasks 的
%           fineStructureGate 同式（max(0,1-4·structure)），是 Mid 撤
%           销快照强度折叠所需的唯一残余 general mask 读取。诊断随之
%           收口：stage 路径报告单一 midGate 快照，不再报告
%           noseMask/noseMidGate；legacy 路径诊断不变。
%   可处理皮肤统计（processableSkin → fineEnergy/blemishMean）改读
%   生产端合并 protectionMask 产物，与 max(texture,structure,hard)
%   bit-exact 同值（T12）。strength、频段分解、合成公式与 hard
%   identity 不变。
%   未提供 stageProtection 的旧调用方走 legacy 兼容路径，行为不变：
%   Fine 直接解释 general texture/structure masks，Mid 保留局部
%   midStructureGate 与 noseMidGate 特判。

if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'base', 'mid', 'fine', ...
        'sourceLuminance', 'imageSize', 'faceBox'}))
    error('beauty:InvalidFrequency', ...
        '必须提供完整的 Base/Mid/Fine 频率结构。');
end
if nargin < 2 || ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidMasks', '必须提供 v3 Beauty Masks。');
end
if nargin < 3 || ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

imageSize = frequency.imageSize(1:2);
validateBand(frequency.base, imageSize, 'base');
validateBand(frequency.mid, imageSize, 'mid');
validateBand(frequency.fine, imageSize, 'fine');
useStageContract = nargin >= 5 && ~isempty(stageProtection);
if useStageContract
    % T12/T13 stage 路径：必需字段收敛为 strengthMap、structure（Mid
    % α 插值的强度无关锚点，与 buildStageProtectionMasks 的
    % fineStructureGate 同式，见函数头注）与生产端合并 protectionMask
    % （统计路径数据源）。
    requiredMaskFields = {'strengthMap', 'structureProtectionMask', ...
        'protectionMask'};
else
    requiredMaskFields = {'strengthMap', 'textureProtectionMask', ...
        'structureProtectionMask'};
end
if ~all(isfield(beautyMasks, requiredMaskFields))
    error('beauty:InvalidMasks', 'v3 Beauty Masks 缺少必需字段。');
end
% 色度保护只由独立色度模块消费；此处通过规范字段解析兼容 alias，
% 防止错误的 Context 在进入管线后才以难定位的方式失败。
[~, hasChromaProtection] = resolveChromaProtectionMask( ...
    beautyMasks, imageSize, 'beauty:InvalidMasks', ...
    'beauty:ChromaProtectionConflict');
if ~hasChromaProtection
    error('beauty:InvalidMasks', ...
        'v3 Beauty Masks 缺少 chromaProtectionMask。');
end
strengthMap = validateMask(beautyMasks.strengthMap, imageSize, ...
    'strengthMap');
if useStageContract
    stageProtection = validateStageProtection(stageProtection, imageSize);
    protection = validateMask(beautyMasks.protectionMask, imageSize, ...
        'protectionMask');
    structureProtection = validateMask(beautyMasks.structureProtectionMask, ...
        imageSize, 'structureProtectionMask');
else
    textureProtection = validateMask(beautyMasks.textureProtectionMask, ...
        imageSize, 'textureProtectionMask');
    structureProtection = validateMask(beautyMasks.structureProtectionMask, ...
        imageSize, 'structureProtectionMask');
    hardProtection = optionalMask(beautyMasks, ...
        'hardProtectionMask', imageSize);
    protection = max(cat(3, textureProtection, ...
        structureProtection, hardProtection), [], 3);
end
if nargin < 4 || isempty(blemishMap)
    blemishMap = zeros(imageSize);
else
    blemishMap = validateMask(blemishMap, imageSize, 'blemishMap');
end

profile = beautySmoothingProfile(smoothingStrength);
ratio = double(smoothingStrength) / 100;
processableSkin = strengthMap > .05 & protection < .80;
ordinarySkin = processableSkin & blemishMap < .60;
if any(processableSkin(:))
    blemishMean = mean(blemishMap(processableSkin));
    if any(ordinarySkin(:))
        fineEnergy = mean(abs(frequency.fine(ordinarySkin)));
    else
        fineEnergy = mean(abs(frequency.fine(processableSkin)));
    end
else
    blemishMean = 0;
    fineEnergy = 0;
end
faceScale = readFaceScale(frequency);
highStrengthWeight = profile.highStrengthCurve;
smallResolutionWeight = 1 - smoothStep(faceScale, 140, 180);
textureRetentionFloor = .60 + .12 * smoothStep(fineEnergy, .004, .010) ...
    - .08 * smallResolutionWeight - .08 * ...
    smoothStep(blemishMean, .08, .14);

% 适应性保留率只设置单调下降曲线的下限。用 max 而不是在高档
% 向上插值，保证固定输入下实际 Fine 保留率不会因高档自适应反弹。
fineRetention = max(profile.fineRetention, textureRetentionFloor);
smallFaceWeight = (1 - smoothStep(faceScale, 72, 96)) .* ...
    smoothStep(ratio, .05, .20);
smallFaceFloor = .66 - .06 * smallResolutionWeight;
% 小人脸只把保留率平滑地向 .60 附近收敛，且不允许低于该自然
% 质感下限；目标为常数时，随着强度增加不会出现保留率反弹。
fineRetention = fineRetention - smallFaceWeight .* ...
    max(fineRetention - smallFaceFloor, 0);
if all(isfield(beautyMasks, {'faceStrengthMap', 'nonFaceStrengthMap'}))
    nonFaceStrength = validateMask(beautyMasks.nonFaceStrengthMap, ...
        imageSize, 'nonFaceStrengthMap');
    effectStrength = profile.alphaCurve .* strengthMap;
    nonFacePixels = nonFaceStrength > .01;
    effectStrength(nonFacePixels) = profile.outsideFaceStrength .* ...
        nonFaceStrength(nonFacePixels);
else
    effectStrength = profile.alphaCurve .* strengthMap;
end
% 结构保护同时约束 Fine 与 Mid；直接使用原始保护值会让中等置信的
% 连续结构仍有过大的残差衰减，因此采用连续退让。T12 后该退让图在
% Fine 侧已折叠进 stage contract 的 smoothingFine 字段；T13 起 stage
% 路径将其作为 Mid α 插值的强度无关锚点，legacy 路径仍直接参与
% Fine/Mid 门控。
fineStructureGate = max(0, 1 - 4 * structureProtection);
if useStageContract
    % T12：Fine 门控只读 stage contract。hard 保持生产原位的 max 合并，
    % gate = 1 - max(smoothingFine, hard)；与旧路径
    % (1 - max(texture, hard)) .* fineStructureGate 仅差 1-x 补码与乘法
    % 结合顺序的浮点噪声（≤1e-15，T07 推导基线 1.11e-16 同量级）。
    fineProtection = max(stageProtection.smoothingFine, ...
        stageProtection.hard);
    alphaMap = effectStrength .* (1 - fineProtection);
else
    % legacy 兼容路径（未提供 stageProtection 的调用方）：Fine 仍直接
    % 解释 general texture/structure masks，行为与 v3.2 完全一致。
    fineProtection = max(textureProtection, hardProtection);
    alphaMap = effectStrength .* (1 - fineProtection) .* fineStructureGate;
end
alphaMap = min(max(double(alphaMap), 0), 1);
% Mid 承载较大尺度的明暗起伏，比 Fine 更容易误伤鼻梁、脸缘和
% 眼窝等结构，因此对已有结构保护再做一次连续退让；普通平坦皮肤
% 的 structureProtection 为 0 时不受额外影响。该锚点在两条路径下
% 同值（与 fineStructureGate 相同），诊断快照保持一致。
midStructureGate = fineStructureGate;
if useStageContract
    % T13 stage 路径：Mid 门控只从 stage contract 派生（凸组合推导见
    % 函数头注）。快照 smoothingMid（alphaCurve=1 满档）为最强保护
    % 端点，强度无关锚点 midStructureGate 为零 nose 保护端点，α 插值
    % 归属 effect-strength 侧；代数上恒等于生产门控
    % midStructureGate .* (1 - .50*nose.*alphaCurve)。算法侧 Mid 不再
    % 读取 noseMask，nose 区域身份与 .50 系数只存在于 producer。
    midGate = profile.alphaCurve .* ...
        (1 - stageProtection.smoothingMid) + ...
        (1 - profile.alphaCurve) .* midStructureGate;
    midAlphaMap = alphaMap .* midGate;
else
    % legacy 兼容路径（未提供 stageProtection 的调用方）：Mid 保留
    % v3.2 的局部结构退让与 nose 特判，行为不变。
    noseMask = optionalMask(beautyMasks, 'noseMask', imageSize);
    % 鼻部门控随当前 Alpha 连续增加，且与既有结构保护相乘；它不能绕过
    % nose 的结构保护，只能进一步降低普通 Mid 的处理量。
    noseMidGate = 1 - .50 * noseMask .* profile.alphaCurve;
    midAlphaMap = alphaMap .* midStructureGate .* noseMidGate;
end
fineRetentionMap = 1 - alphaMap .* (1 - fineRetention);
midRetention = profile.mediumRetention;
midRetentionMap = 1 - midAlphaMap .* (1 - midRetention);
smoothedFine = frequency.fine .* fineRetentionMap;
smoothedMid = frequency.mid .* midRetentionMap;
outputLuminance = frequency.base + smoothedMid + smoothedFine;

smoothedFrequency = frequency;
smoothedFrequency.fine = smoothedFine;
smoothedFrequency.mid = smoothedMid;
smoothedFrequency.reconstructedLuminance = outputLuminance;
smoothedFrequency.outputLuminance = outputLuminance;
smoothedFrequency.alphaMap = alphaMap;
smoothedFrequency.fineAlphaMap = alphaMap;
smoothedFrequency.fineRetention = fineRetention;
smoothedFrequency.effectiveProfileFineRetention = fineRetention;
smoothedFrequency.profileFineRetention = profile.fineRetention;
smoothedFrequency.profileMediumRetention = profile.mediumRetention;
smoothedFrequency.profile = profile;
smoothedFrequency.fineRetentionMap = fineRetentionMap;
smoothedFrequency.retentionMap = fineRetentionMap;
smoothedFrequency.actualFineRetentionMap = fineRetentionMap;
smoothedFrequency.fineActualRetentionMap = fineRetentionMap;
smoothedFrequency.midAlphaMap = midAlphaMap;
smoothedFrequency.midRetention = midRetention;
smoothedFrequency.mediumRetention = midRetention;
smoothedFrequency.midRetentionMap = midRetentionMap;
smoothedFrequency.mediumRetentionMap = midRetentionMap;
smoothedFrequency.actualMidRetentionMap = midRetentionMap;
smoothedFrequency.midActualRetentionMap = midRetentionMap;
smoothedFrequency.actualMediumRetentionMap = midRetentionMap;
% fineProtectionMask 在 stage 路径下为折叠语义 max(smoothingFine,
% hard)；legacy 路径保持原 max(texture, hard) 快照。T13 收口：stage
% 路径的 Mid 门控收敛为单一 midGate 快照（凸组合，见上），不再报告
% nose 特判字段 noseMask/noseMidGate（nose 语义已上收到 producer 侧
% stage contract）；legacy 路径继续报告两者以维持 v3.2 诊断不变。
% midStructureGate 在两条路径下均为强度无关结构锚点。
diagnostics = struct( ...
    'alphaMap', alphaMap, ...
    'fineAlphaMap', alphaMap, ...
    'midAlphaMap', midAlphaMap, ...
    'profile', profile, ...
    'fineRetention', fineRetention, ...
    'effectiveProfileFineRetention', fineRetention, ...
    'profileFineRetention', profile.fineRetention, ...
    'profileMediumRetention', profile.mediumRetention, ...
    'adaptiveFineRetention', fineRetention, ...
    'highStrengthWeight', highStrengthWeight, ...
    'blemishMean', blemishMean, ...
    'fineEnergy', fineEnergy, ...
    'ordinarySkinMask', ordinarySkin, ...
    'smallResolutionWeight', smallResolutionWeight, ...
    'textureRetentionFloor', textureRetentionFloor, ...
    'smallFaceWeight', smallFaceWeight, ...
    'smallFaceFloor', smallFaceFloor, ...
    'midStructureGate', midStructureGate, ...
    'fineStructureGate', fineStructureGate, ...
    'fineProtectionMask', fineProtection, ...
    'fineRetentionMap', fineRetentionMap, ...
    'retentionMap', fineRetentionMap, ...
    'midRetention', midRetention, ...
    'mediumRetention', midRetention, ...
    'midRetentionMap', midRetentionMap, ...
    'mediumRetentionMap', midRetentionMap, ...
    'fineActualRetentionMap', fineRetentionMap, ...
    'actualFineRetentionMap', fineRetentionMap, ...
    'midActualRetentionMap', midRetentionMap, ...
    'actualMidRetentionMap', midRetentionMap, ...
    'actualMediumRetentionMap', midRetentionMap, ...
    'protectionMask', protection, ...
    'fineBefore', frequency.fine, ...
    'fineAfter', smoothedFine, ...
    'midBefore', frequency.mid, ...
    'midAfter', smoothedMid, ...
    'fineEnergyBefore', mean(abs(frequency.fine(:))), ...
    'fineEnergyAfter', mean(abs(smoothedFine(:))), ...
    'midEnergyBefore', mean(abs(frequency.mid(:))), ...
    'midEnergyAfter', mean(abs(smoothedMid(:))), ...
    'fineActualRetention', mean(fineRetentionMap(processableSkin)), ...
    'midActualRetention', mean(midRetentionMap(processableSkin)), ...
    'baseUnchanged', isequal(smoothedFrequency.base, frequency.base), ...
    'midUnchanged', isequal(smoothedMid, frequency.mid));
if useStageContract
    diagnostics.midGate = midGate;
else
    diagnostics.noseMask = noseMask;
    diagnostics.noseMidGate = noseMidGate;
end
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function protection = validateStageProtection(protection, imageSize)
%VALIDATESTAGEPROTECTION 校验 V4 stage contract 的 protection 分层输入。
%   T12 Fine consumer 目标读取集合：processability.skin（经
%   strengthMap）+ protection.smoothingFine + protection.hard +
%   strengthMap。T13 起 Mid consumer 追加快照字段 smoothingMid（α 插
%   值在消费侧按凸组合完成，见函数头注）。缺字段或取值无效一律
%   fail-fast，不在函数内部重新拼装 protection，也不静默回退。
if ~isstruct(protection) || ~isscalar(protection) || ...
        ~all(isfield(protection, {'smoothingFine', 'smoothingMid', ...
        'hard'}))
    error('beauty:InvalidMasks', ...
        'stage protection 必须是包含 smoothingFine、smoothingMid 和 hard 的标量结构。');
end
protection.smoothingFine = validateMask(protection.smoothingFine, ...
    imageSize, 'smoothingFine');
protection.smoothingMid = validateMask(protection.smoothingMid, ...
    imageSize, 'smoothingMid');
protection.hard = validateMask(protection.hard, imageSize, 'hard');
end

function validateBand(value, imageSize, name)
if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
        any(~isfinite(value(:)))
    error('beauty:InvalidFrequency', '频率分量 %s 无效。', name);
end
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidMasks', 'Mask %s 无效。', name);
end
value = double(value);
end

function value = optionalMask(context, name, imageSize)
if isfield(context, name)
    value = validateMask(context.(name), imageSize, name);
else
    value = zeros(imageSize);
end
end

function faceScale = readFaceScale(frequency)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isreal(frequency.faceScale) && isscalar(frequency.faceScale) && ...
        isfinite(frequency.faceScale) && frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
elseif isfield(frequency, 'faceBox') && isnumeric(frequency.faceBox) && ...
        numel(frequency.faceBox) == 4
    faceScale = min(double(frequency.faceBox(3:4)));
else
    faceScale = min(size(frequency.fine));
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end
