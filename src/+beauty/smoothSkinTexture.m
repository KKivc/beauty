function [smoothedFrequency, diagnostics] = smoothSkinTexture( ...
        frequency, beautyMasks, smoothingStrength, blemishMap, stageProtection)
%SMOOTHSKINTEXTURE 以独立保留率图连续衰减 Fine 和 Mid 纹理。
%   Base 始终不变；Fine 和 Mid 使用同一输入分解的不同保留率，
%   结构、纹理和硬保护限制作用范围，鼻部 Mid 额外使用保守门控。
%
%   T12：可选第 5 参数 stageProtection 是 V4 stage contract 的
%   protection 分层（masks.buildStageProtectionMasks 输出，至少含
%   smoothingFine 与 hard）。提供时 Fine 门控只从 stage contract 读取：
%   fineProtection = max(smoothingFine, hard)（T07 折叠推导，
%   smoothingFine = 1 - (1-texture)·max(0,1-4·structure)，hard 保持生产
%   原位的 max 合并），Fine 路径不再自行解释 general texture/structure
%   masks；可处理皮肤统计（processableSkin → fineEnergy/blemishMean）
%   改读生产端合并 protectionMask 产物，与 max(texture,structure,hard)
%   bit-exact 同值。strength、频段分解、合成公式与 hard identity 不变。
%   未提供 stageProtection 的旧调用方走 legacy 兼容路径，行为不变；
%   Mid 分支尚未迁移，仍按原兼容逻辑消费 structure/nose 门控。

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
    % T12 stage 路径：Fine 不再读取 texture/structure 的自行解释结果，
    % 必需字段收敛为 strengthMap、structure（Mid 兼容门控仍需）与生产
    % 端合并 protectionMask（统计路径数据源）。
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
% Fine 侧已折叠进 stage contract 的 smoothingFine 字段，这里保留给
% 尚未迁移的 Mid 兼容门控与诊断快照。
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
noseMask = optionalMask(beautyMasks, 'noseMask', imageSize);
% 鼻部门控随当前 Alpha 连续增加，且与既有结构保护相乘；它不能绕过
% nose 的结构保护，只能进一步降低普通 Mid 的处理量。
noseMidGate = 1 - .50 * noseMask .* profile.alphaCurve;
% Mid 承载较大尺度的明暗起伏，比 Fine 更容易误伤鼻梁、脸缘和
% 眼窝等结构，因此对已有结构保护再做一次连续退让；普通平坦皮肤
% 的 structureProtection 为 0 时不受额外影响。
midStructureGate = fineStructureGate;
midAlphaMap = alphaMap .* midStructureGate .* noseMidGate;
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
% hard)；legacy 路径保持原 max(texture, hard) 快照。
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
    'noseMask', noseMask, ...
    'noseMidGate', noseMidGate, ...
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
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function protection = validateStageProtection(protection, imageSize)
%VALIDATESTAGEPROTECTION 校验 V4 stage contract 的 protection 分层输入。
%   Fine consumer 只消费 smoothingFine 与 hard 两个字段（T12 目标读取
%   集合：processability.skin（经 strengthMap）+ protection.smoothingFine
%   + protection.hard + strengthMap）。缺字段或取值无效一律 fail-fast，
%   不在函数内部重新拼装 protection，也不静默回退。
if ~isstruct(protection) || ~isscalar(protection) || ...
        ~all(isfield(protection, {'smoothingFine', 'hard'}))
    error('beauty:InvalidMasks', ...
        'stage protection 必须是包含 smoothingFine 和 hard 的标量结构。');
end
protection.smoothingFine = validateMask(protection.smoothingFine, ...
    imageSize, 'smoothingFine');
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
