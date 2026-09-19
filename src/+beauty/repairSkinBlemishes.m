function [repairedFrequency, diagnostics] = repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, smoothingStrength, ...
        repairContract)
%REPAIRSKINBLEMISHES 对瑕疵位置执行受控的 Fine/Mid 局部修复。
%   普通皮肤仍由 smoothSkinTexture 处理；本函数只读取固定的瑕疵图，
%   低置信度只衰减 Fine，中高置信度才少量收敛 Mid。Base 始终不变，
%   且所有修复权重都由结构门和纹理门连续限制。
%
%   T14/T15：可选第 5 参数 repairContract 是 Repair（Fine/Mid）的
%   stage contract，由 beautifyImage 生产端从与生产门控共用的同一份
%   beautyMasks 产物和本次调用的 runtime blemish evidence 拼装传入
%   （T12/T13 范式）。提供时 Fine/Mid 的门控不再自行组合 general
%   texture/structure/hard/nose masks，而是从 contract 按生产原式、
%   原顺序重建：
%     structureGate = min(blemishRelaxedGate, strongStructureCap)
%     fineWeight    = clamp(Wf .* structureGate, 0, 1) .* textureGate
%     mediumWeight  = clamp(Wm .* structureGate, 0, 1) .* noseMidGate
%                     .* textureGate
%   字段语义：
%     repairFine / repairMid — T07 发布的零瑕疵参考快照
%                          repairFine = 1 - structureGate0·(1 - texture)、
%                          repairMid = 1 - structureGate0·(1 - .50·nose)
%                          ·(1 - texture)；消费侧读取为零瑕疵参考门
%                          （诊断 fineGateZeroBlemish/
%                          mediumGateZeroBlemish 与测试断言消费）；
%     hard               — hard identity（T07 单独发布），按生产原位
%                          组合进 allowed 的 (1-hard) 乘子；
%     blemishRelaxedGate — 零瑕疵参考门 + runtime blemish 放宽量：
%                          structureGate0 + .90·structure·blemish
%                          （= 1 - structure·(1 - .90·blemish)，其中
%                          structureGate0 = 1 - structure 恒成立）；
%     strongStructureCap — 强结构固定下限 1 - .65·strongStructure；
%     textureGate        — v3.2 线性纹理门 1 - texture，单独发布；
%     noseMidGate        — Mid 鼻部门 1 - .50·nose（repair 侧无
%                          alphaCurve，纯静态），单独发布。
%   textureGate/noseMidGate 必须独立于结构门发布：生产链在结构门与
%   纹理/鼻部门之间对权重做 [0,1] 截断（clamp(W·structureGate) 之后
%   才乘 nose/texture 门），把纹理或 nose 折叠进门控积会在截断饱和区
%   改变结果（T14 实测饱和像素偏差 ~0.1 量级）；且 repairFine/
%   repairMid 的 1-x 补码往返有舍入，无法逐位还原门控积。因此快照的
%   折叠只保留为零瑕疵参考，运行期由生产端按与 repairSkinBlemishes
%   完全相同的表达式、同一份 mask/blemish 产物计算未折叠字段，消费侧
%   重建与 legacy 路径逐位等价（bit-exact）。repairFine/repairMid 的
%   语义（零瑕疵参考 + runtime 放宽单调松弛）由测试断言：blemish = 0
%   时结构门与纹理/nose 门的门控积与 1 - 快照一致（≤1e-15），blemish
%   > 0 时相对快照只增不减。缺字段 fail-fast，不在函数内部重新拼装，
%   也不静默回退；未提供第 5 参的旧调用方走 legacy 兼容路径，行为
%   不变。
%   T15 收口后，general textureProtection/structureProtection/
%   hardProtection 与 noseMask 的读取只服务 legacy 兼容路径（4 参调
%   用方）与输入校验；stage 路径的 fineWeight/mediumWeight/
%   chromaWeight 与共享 referenceReliability 的门控来源全部来自
%   stage contract（bit-exact 同值），Fine/Mid 都只消费 stage-
%   specific protection。

if nargin < 4
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要频率、Beauty Masks、瑕疵图和磨皮强度。');
end
useStageContract = nargin >= 5 && ~isempty(repairContract);
validateFrequency(frequency);
imageSize = frequency.imageSize(1:2);
validateMasks(beautyMasks, imageSize);
blemishMap = readBlemishMap(blemishMap, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

base = double(frequency.base);
mid = double(frequency.mid);
fine = double(frequency.fine);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
structureProtection = readMask(beautyMasks, ...
    'structureProtectionMask', imageSize);
textureProtection = readMask(beautyMasks, ...
    'textureProtectionMask', imageSize);
hardProtection = readOptionalMask(beautyMasks, ...
    'hardProtectionMask', imageSize);
if useStageContract
    % T14/T15：缺字段或取值无效 fail-fast，不静默回退拼装。
    repairContract = validateRepairContract(repairContract, imageSize);
end

profile = beautySmoothingProfile(smoothingStrength);
% T14/T15：stage 路径的 (1-hard) 乘子按 T07 边界约定从 contract.hard
% 组合；legacy 路径保持读取 beautyMasks.hardProtectionMask。生产端两
% 条来源同 artifact bit-exact 同值。
if useStageContract
    hardGate = repairContract.hard;
else
    hardGate = hardProtection;
end
allowed = min(skinMask, strengthMap) .* (1 - hardGate);
nonFaceStrength = readOptionalMask(beautyMasks, ...
    'nonFaceStrengthMap', imageSize);
nonFacePixels = nonFaceStrength > .01;
if any(nonFacePixels(:))
    allowed(nonFacePixels) = profile.outsideFaceStrength .* ...
        min(skinMask(nonFacePixels), nonFaceStrength(nonFacePixels)) .* ...
        (1 - hardGate(nonFacePixels));
end
normalRepairCurve = min(profile.blemishStrength / (.75 ^ .85), 1);
highEndRepairCurve = max(profile.blemishStrength - .75 ^ .85, 0);
% 高置信瑕疵可适度放宽一般结构门控；只有强结构边缘保留固定下限，
% 避免眼唇边界被瑕疵修复覆盖，同时不阻断普通雀斑修复。
% T15：stage 路径的 structureGate（Fine/Mid/chroma/共享参考共用的结
% 构门）按 T14 同式从 contract 未折叠字段重建，与 legacy 组合式
% bit-exact 同值（生产端同一份 mask/blemish 产物、同一表达式）；
% legacy 路径保持直接解释 general texture/structure/hard masks。
if useStageContract
    structureGate = min(repairContract.blemishRelaxedGate, ...
        repairContract.strongStructureCap);
else
    structureGate = 1 - structureProtection .* (1 - .90 * blemishMap);
    hardFeatureBand = bwdist(hardProtection >= .999) <= 3;
    strongStructure = smoothStep(structureProtection, .70, .90) .* ...
        double(hardFeatureBand);
    structureGate = min(structureGate, 1 - .65 * strongStructure);
end

% 低置信度瑕疵保留在 Fine 层；Mid 仅在连续置信度达到中高档后
% 开启，避免普通皮肤被大面积拉向一个颜色。
faceScale = readFaceScale(frequency);
blemishDensity = imgaussfilt(double(blemishMap > .60), ...
    max(3, min(12, .04 * faceScale)), 'Padding', 'replicate');
globalHighDensity = mean(blemishMap(:) > .60);
globalBlemishMean = mean(blemishMap(:));
sparseGate = 1 - smoothStep(globalHighDensity, .05, .15) .* ...
    smoothStep(blemishDensity, .03, .20);
globalGate = smoothStep(globalBlemishMean, .005, .015);
% 鼻部只能使用与普通皮肤相同的全局和局部瑕疵证据，不能因语义位置
% 绕过全局 Gate。鼻部语义只用于 Mid 的连续保守系数，不参与 Fine 证据。
repairEvidence = min(max(blemishMap .* sparseGate .* globalGate, 0), 1);
mediumConfidence = smoothStep(repairEvidence, .60, .90);
highConfidence = smoothStep(repairEvidence, .62, .90);
if highEndRepairCurve > 0
    blobMask = smallBlemishBlobs(blemishMap > .65, faceScale);
else
    blobMask = false(imageSize);
end
% 高档额外修复必须同时满足高置信局部异常、紧凑 Blob 和全局证据；
% nose 不得替代任一 Gate。鼻部 Mid 只保留初始 0.5 系数，并按语义
% 概率连续退让，避免鼻梁和鼻翼的中频明暗结构被整片收敛。
% T15：stage 路径的 noseMidGate 从 contract 读取（生产端 1 - .50·nose，
% repair 侧无 alphaCurve，纯静态；快照无法逐位还原门控积，按 T14 同
% 款以未折叠字段发布）；算法侧 Mid 不再读取 noseMask，nose 区域身份
% 只存在于 producer。legacy 路径保持从 beautyMasks.noseMask 计算，
% 行为不变。
highEndConfidence = highConfidence .* double(blobMask) .* globalGate;
if useStageContract
    noseMidGate = repairContract.noseMidGate;
else
    noseMask = readOptionalMask(beautyMasks, 'noseMask', imageSize);
    noseMidGate = 1 - .50 * noseMask;
end
repairCurveMap = normalRepairCurve * ones(imageSize);
repairCurveMap = min(max(repairCurveMap, 0), 1);
% T14/T15：stage 路径的 Fine 门控只从 stage contract 按生产原式、原
% 顺序重建（字段语义与逐位等价推导见函数头注），Fine/Mid 不再自行
% 组合 general texture/structure/hard/nose masks；runtime blemish 放
% 宽量由生产端在零瑕疵参考门上重建后随 contract 传入（structureGate
% 即 min(blemishRelaxedGate, strongStructureCap) 重建值，两条路径
% bit-exact 同值），Fine 与 Mid 权重共享同一表达式。
fineWeight = repairCurveMap .* (repairEvidence + .25 * highConfidence) .* ...
    allowed .* structureGate + (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = repairCurveMap .* (.95 * mediumConfidence + ...
    .40 * highConfidence) .* allowed .* structureGate + ...
    (highEndRepairCurve .* ...
    highEndConfidence) .* allowed .* structureGate;
mediumWeight = min(max(mediumWeight, 0), 1);
mediumWeight = mediumWeight .* noseMidGate;
chromaWeight = .16 * repairCurveMap .* highConfidence .* allowed .* ...
    structureGate;
fineWeight = min(max(fineWeight, 0), 1);
chromaWeight = min(max(chromaWeight, 0), 1);

% 脸部和脸外的允许权重完成后统一应用线性纹理软保护；同一门控也
% 从邻域参考采样中排除受保护纹理，避免保护区域反向影响附近修复。
% T14/T15：stage 路径的纹理门按生产原位（截断之后）从 contract 读取，
% Fine/Mid/chromaWeight 与共享 referenceReliability 统一应用；legacy
% 路径继续从 general texture mask 计算，行为不变。
if useStageContract
    textureGate = repairContract.textureGate;
else
    textureGate = 1 - textureProtection;
end
fineWeight = fineWeight .* textureGate;
mediumWeight = mediumWeight .* textureGate;
chromaWeight = chromaWeight .* textureGate;

radius = min(20, max(3, round(.070 * faceScale)));
kernelSize = 2 * radius + 1;
kernel = ones(kernelSize, kernelSize);

% 参考只使用非瑕疵皮肤，并降低跨越结构边缘的贡献；这样鼻梁和
% 手指的低频坡面不会被邻域平均抹平。
% T15：共享参考的门控来源收口——stage 路径的 textureGate/
% structureGate 即 contract 重建值（bit-exact 同值），不再从 general
% masks 重新解释；legacy 路径维持原读取。
referenceReliability = allowed .* textureGate .* ...
    (1 - .86 * blemishMap) .* ...
    structureGate;
referenceWeight = imfilter(referenceReliability, kernel, 'replicate');
fineReference = imfilter(fine .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
midReference = imfilter(mid .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
fineReference(referenceWeight <= eps) = 0;
midReference(referenceWeight <= eps) = 0;

% 参考只允许把同号残差向零收敛，避免局部邻域的反向纹理在
% 强度升高时被重新放大，从而保证 Fine 和瑕疵能量单调下降。
fineTarget = sign(fine) .* min(abs(fine), abs(fineReference));
midTarget = sign(mid) .* min(abs(mid), abs(midReference));
fineCorrection = fineWeight .* (fineTarget - fine);
mediumCorrection = mediumWeight .* (midTarget - mid);

repairedFrequency = frequency;
repairedFrequency.fine = fine + fineCorrection;
repairedFrequency.mid = mid + mediumCorrection;
repairedFrequency.reconstructedLuminance = base + ...
    repairedFrequency.mid + repairedFrequency.fine;
repairedFrequency.outputLuminance = repairedFrequency.reconstructedLuminance;
if isfield(frequency, 'alphaMap')
    alphaMap = validateMask(frequency.alphaMap, imageSize, 'alphaMap');
else
    alphaMap = zeros(imageSize);
end
repairedFrequency.alphaMap = min(1, max(alphaMap, ...
    fineWeight + mediumWeight));
repairedFrequency.blemishRepair = struct( ...
    'fineCorrection', fineCorrection, ...
    'mediumCorrection', mediumCorrection, ...
    'chromaWeight', chromaWeight);

beforeEnergy = mean(abs(fine(:)) + abs(mid(:)));
afterEnergy = mean(abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:)));
blemishBefore = mean((abs(fine(:)) + abs(mid(:))) .* blemishMap(:));
blemishAfter = mean((abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:))) .* blemishMap(:));
diagnostics = struct( ...
    'blemishMap', blemishMap, ...
    'sparseGate', sparseGate, ...
    'globalHighDensity', globalHighDensity, ...
    'globalBlemishMean', globalBlemishMean, ...
    'globalGate', globalGate, ...
    'normalRepairCurve', normalRepairCurve, ...
    'highEndRepairCurve', highEndRepairCurve, ...
    'repairEvidence', repairEvidence, ...
    'mediumConfidence', mediumConfidence, ...
    'highConfidence', highConfidence, ...
    'repairCurveMap', repairCurveMap, ...
    'blobMask', blobMask, ...
    'highEndConfidence', highEndConfidence, ...
    'noseMidGate', noseMidGate, ...
    'textureProtectionMask', textureProtection, ...
    'textureGate', textureGate, ...
    'fineWeight', fineWeight, ...
    'mediumWeight', mediumWeight, ...
    'midWeight', mediumWeight, ...
    'chromaWeight', chromaWeight, ...
    'repairWeight', min(1, fineWeight + mediumWeight), ...
    'allowed', allowed, ...
    'structureGate', structureGate, ...
    'referenceReliability', referenceReliability, ...
    'referenceWeight', referenceWeight, ...
    'fineReference', fineReference, ...
    'midReference', midReference, ...
    'fineTarget', fineTarget, ...
    'midTarget', midTarget, ...
    'fineCorrection', fineCorrection, ...
    'mediumCorrection', mediumCorrection, ...
    'fineBefore', fine, ...
    'fineAfter', repairedFrequency.fine, ...
    'midBefore', mid, ...
    'midAfter', repairedFrequency.mid, ...
    'fineEnergyBefore', mean(abs(fine(:))), ...
    'fineEnergyAfter', mean(abs(repairedFrequency.fine(:))), ...
    'frequencyEnergyBefore', beforeEnergy, ...
    'frequencyEnergyAfter', afterEnergy, ...
    'blemishEnergyBefore', blemishBefore, ...
    'blemishEnergyAfter', blemishAfter, ...
    'baseUnchanged', isequal(repairedFrequency.base, frequency.base), ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
if useStageContract
    % T14/T15：stage 路径新增重建门控与零瑕疵参考门快照；Mid 不再读取
    % noseMask，诊断不报告该字段（T13 同款收口）；legacy 路径诊断保持
    % v3.2 不变。fineGateRuntime 与 structureGate 同值（contract 重建
    % 的结构门），保留字段名以延续 T14 消费者；mediumGateZeroBlemish
    % 为 T07 repairMid 快照的零瑕疵参考门。
    diagnostics.fineGateRuntime = structureGate;
    diagnostics.fineGateZeroBlemish = 1 - repairContract.repairFine;
    diagnostics.mediumGateZeroBlemish = 1 - repairContract.repairMid;
else
    diagnostics.noseMask = noseMask;
end
end

function contract = validateRepairContract(contract, imageSize)
%VALIDATEREPAIRCONTRACT 校验 Repair（Fine/Mid）stage contract（T14/T15）。
%   必需字段：repairFine/repairMid（T07 零瑕疵快照）、hard（hard
%   identity）、blemishRelaxedGate/strongStructureCap/textureGate/
%   noseMidGate（生产端按生产原式计算的未折叠门控字段）。缺字段或取
%   值无效一律 fail-fast，不在函数内部重新拼装，也不静默回退到
%   general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'repairFine', 'repairMid', 'hard', ...
        'blemishRelaxedGate', 'strongStructureCap', 'textureGate', ...
        'noseMidGate'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 必须是包含 repairFine、repairMid、hard、blemishRelaxedGate、strongStructureCap、textureGate 和 noseMidGate 的标量结构。');
end
contract.repairFine = validateMask(contract.repairFine, imageSize, ...
    'repairFine');
contract.repairMid = validateMask(contract.repairMid, imageSize, ...
    'repairMid');
contract.hard = validateMask(contract.hard, imageSize, 'hard');
contract.blemishRelaxedGate = validateMask( ...
    contract.blemishRelaxedGate, imageSize, 'blemishRelaxedGate');
contract.strongStructureCap = validateMask( ...
    contract.strongStructureCap, imageSize, 'strongStructureCap');
contract.textureGate = validateMask(contract.textureGate, imageSize, ...
    'textureGate');
contract.noseMidGate = validateMask(contract.noseMidGate, imageSize, ...
    'noseMidGate');
end

function validateFrequency(frequency)
if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'base', 'mid', 'fine', 'imageSize'}))
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要完整的 Base/Mid/Fine 频率结构。');
end
imageSize = frequency.imageSize(1:2);
for name = {'base', 'mid', 'fine'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:)))
        error('beauty:InvalidBlemishRepair', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
end

function validateMasks(beautyMasks, imageSize)
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap', 'structureProtectionMask', ...
    'textureProtectionMask'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidBlemishRepair', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    validateMask(beautyMasks.(required{index}), imageSize, required{index});
end
if isfield(beautyMasks, 'hardProtectionMask')
    validateMask(beautyMasks.hardProtectionMask, imageSize, ...
        'hardProtectionMask');
end
end

function value = readBlemishMap(value, imageSize)
if isstruct(value)
    if isfield(value, 'blemishMap')
        value = value.blemishMap;
    elseif isfield(value, 'confidence')
        value = value.confidence;
    else
        error('beauty:InvalidBlemishRepair', ...
            '瑕疵诊断结构缺少 blemishMap 或 confidence。');
    end
end
value = validateMask(value, imageSize, 'blemishMap');
end

function value = readMask(context, name, imageSize)
value = validateMask(context.(name), imageSize, name);
end

function value = readOptionalMask(context, name, imageSize)
if isfield(context, name)
    value = validateMask(context.(name), imageSize, name);
else
    value = zeros(imageSize);
end
end

function value = validateMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidBlemishRepair', 'Mask %s 无效。', name);
end
value = double(value);
end

function faceScale = readFaceScale(frequency)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
else
    if isfield(frequency, 'faceBox')
        faceScale = min(frequency.faceBox(3:4));
    else
        faceScale = min(size(frequency.base));
    end
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function blobMask = smallBlemishBlobs(candidate, faceScale)
% 只有小而紧凑的连通瑕疵才接受高档额外修复，长条纹理不进入该层。
blobMask = false(size(candidate));
if ~any(candidate(:))
    return;
end
components = bwconncomp(candidate, 8);
areaLimit = max(24, round(.006 * faceScale ^ 2));
spanLimit = max(5, round(.045 * faceScale));
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    [rows, columns] = ind2sub(size(candidate), pixels);
    rowSpan = max(rows) - min(rows) + 1;
    columnSpan = max(columns) - min(columns) + 1;
    fillRatio = numel(pixels) / max(1, rowSpan * columnSpan);
    if numel(pixels) <= areaLimit && max(rowSpan, columnSpan) <= spanLimit && ...
            fillRatio >= .18
        blobMask(pixels) = true;
    end
end
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
