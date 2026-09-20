function [smoothedFrequency, diagnostics] = smoothSkinTexture( ...
        frequency, beautyMasks, smoothingStrength, blemishMap, stageProtection)
%SMOOTHSKINTEXTURE 以独立保留率图连续衰减 Fine 和 Mid 纹理。
%   Base 始终不变；Fine 和 Mid 使用同一输入分解的不同保留率。
%
%   T12/T13/T31：第 5 参数 stageProtection 是 V4 stage contract 的
%   protection 分层（masks.buildStageProtectionMasks 输出）。执行层是
%   **纯执行器**：只消费 stageProtection 的规范门与 strength 层，
%   不读取任何 semantic / evidence / general protection mask。
%
%   读取集合（上位契约第 1 节）：
%     beautyMasks.strengthMap / nonFaceStrengthMap / faceStrengthMap
%       —— strength 层（强度侧），不参与保护判定；
%     stageProtection.target.smoothingFine / .smoothingMid
%       —— 逐像素修改门（目标保护，T31 规范名）；
%     stageProtection.support.smoothingFine
%       —— 高频参考样本池门（= legacy 合并 protectionMask
%          max(texture,structure,hard) 的等价门，零带逐位同值）；
%     stageProtection.support.smoothingMid
%       —— 中频结构参考门（= 1 - fineStructureGate，零带逐位还原）；
%     stageProtection.hard —— hard identity（生产原位 max 合并）。
%
%   Fine：fineProtection = max(target.smoothingFine, hard)，
%         alphaMap = effectStrength .* (1 - fineProtection)。
%   Mid：target.smoothingMid 是 alphaCurve=1 满档快照（T07：
%         target.smoothingMid = 1 - fineStructureGate·(1 - .50·nose)），
%         生产 noseMidGate = 1 - .50·nose·alphaCurve 的强度插值归属
%         effect-strength 侧，由消费侧按凸组合还原：
%           midGate = alphaCurve·(1 - target.smoothingMid)
%                   + (1 - alphaCurve)·midStructureGate
%         midStructureGate = 1 - support.smoothingMid（强度无关结构锚点，
%         零带时逐位等于 legacy max(0,1-4·structure)）。该凸组合代数上
%         恒等于生产门控 fineStructureGate·(1 - .50·nose·alphaCurve)：
%         快照为最强保护端点，1 为零保护端点。nose 区域身份与 .50 系数
%         只存在于 producer，算法侧 Mid 不再读取 nose 语义。
%   可处理皮肤统计（processableSkin → fineEnergy/blemishMean）改读
%   support.smoothingFine（= 生产端合并 protectionMask 的等价门，与
%   max(texture,structure,hard) bit-exact 同值，T12/T31）。
%   strength、频段分解、合成公式与 hard identity 不变。
%
%   兼容入口（未提供第 5 参的旧调用方）：T31 起不再自行解释 general
%   texture/structure/nose masks，而是向 policy 层索取零带 stageProtection
%   （masks.buildStageProtectionMasks(beautyMasks)），与生产路径共用同一
%   份 Single Protection Authority。

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
if nargin < 5 || isempty(stageProtection)
    % T31 兼容入口：向 policy 层索取零带 stageProtection。
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
end
if ~all(isfield(beautyMasks, {'strengthMap'}))
    error('beauty:InvalidMasks', 'v3 Beauty Masks 缺少必需字段。');
end
strengthMap = validateMask(beautyMasks.strengthMap, imageSize, ...
    'strengthMap');
stageProtection = validateStageProtection(stageProtection, imageSize);
targetProtection = stageProtection.target;
supportProtection = stageProtection.support;
hardProtection = stageProtection.hard;
% 高频参考样本池门（= legacy 合并 protectionMask 的等价门）。
protection = supportProtection.smoothingFine;
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
% 连续结构仍有过大的残差衰减，因此采用连续退让。T31 起该退让图由
% producer 发布为 support.smoothingMid（= 1 - fineStructureGate），
% 算法侧只做补码还原，不再读取 general structure mask。
fineStructureGate = 1 - supportProtection.smoothingMid;
% T12：Fine 门控只读 stage contract。hard 保持生产原位的 max 合并，
% gate = 1 - max(target.smoothingFine, hard)。
fineProtection = max(targetProtection.smoothingFine, hardProtection);
alphaMap = effectStrength .* (1 - fineProtection);
alphaMap = min(max(double(alphaMap), 0), 1);
% Mid 承载较大尺度的明暗起伏，比 Fine 更容易误伤鼻梁、脸缘和
% 眼窝等结构，因此对已有结构保护再做一次连续退让；普通平坦皮肤
% 的结构保护为 0 时不受额外影响。该锚点与 producer 的
% fineStructureGate 同式同值。
midStructureGate = fineStructureGate;
% T13：Mid 门控只从 stage contract 派生（凸组合推导见函数头注）。
% 快照 target.smoothingMid（alphaCurve=1 满档）为最强保护端点，
% 强度无关锚点 midStructureGate 为零 nose 保护端点，α 插值归属
% effect-strength 侧；代数上恒等于生产门控
% midStructureGate .* (1 - .50*nose.*alphaCurve)。
midGate = profile.alphaCurve .* ...
    (1 - targetProtection.smoothingMid) + ...
    (1 - profile.alphaCurve) .* midStructureGate;
midAlphaMap = alphaMap .* midGate;
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
% T31 诊断收口：算法侧不再持有任何 nose 语义，诊断统一报告
% protection（= support.smoothingFine，高频参考样本池门）、
% fineStructureGate/midStructureGate 与单一 midGate 快照；不再报告
% noseMask/noseMidGate（nose 语义只存在于 producer 侧 stage contract）。
% fineProtectionMask 为折叠语义 max(target.smoothingFine, hard)。
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
    'supportSmoothingFine', supportProtection.smoothingFine, ...
    'supportSmoothingMid', supportProtection.smoothingMid, ...
    'midGate', midGate, ...
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
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function protection = validateStageProtection(protection, imageSize)
%VALIDATESTAGEPROTECTION 校验 V4 stage contract 的 protection 分层输入。
%   T31 目标读取集合：target.smoothingFine / target.smoothingMid /
%   support.smoothingFine / support.smoothingMid / hard。缺字段或取值无效
%   一律 fail-fast，不在函数内部重新拼装 protection，也不静默回退到
%   general masks 解释。
if ~isstruct(protection) || ~isscalar(protection) || ...
        ~all(isfield(protection, {'target', 'support', 'hard'}))
    error('beauty:InvalidMasks', ...
        'stage protection 必须是包含 target/support/hard 的标量结构。');
end
if ~isstruct(protection.target) || ~isscalar(protection.target) || ...
        ~all(isfield(protection.target, {'smoothingFine', 'smoothingMid'}))
    error('beauty:InvalidMasks', ...
        'stage protection.target 缺少 smoothingFine/smoothingMid。');
end
if ~isstruct(protection.support) || ~isscalar(protection.support) || ...
        ~all(isfield(protection.support, {'smoothingFine', 'smoothingMid'}))
    error('beauty:InvalidMasks', ...
        'stage protection.support 缺少 smoothingFine/smoothingMid。');
end
protection.target.smoothingFine = validateMask( ...
    protection.target.smoothingFine, imageSize, 'target.smoothingFine');
protection.target.smoothingMid = validateMask( ...
    protection.target.smoothingMid, imageSize, 'target.smoothingMid');
protection.support.smoothingFine = validateMask( ...
    protection.support.smoothingFine, imageSize, 'support.smoothingFine');
protection.support.smoothingMid = validateMask( ...
    protection.support.smoothingMid, imageSize, 'support.smoothingMid');
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
