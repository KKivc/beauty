function [repairedFrequency, diagnostics] = repairSkinBlemishes( ...
        frequency, beautyMasks, blemishMap, smoothingStrength, ...
        repairContract)
%REPAIRSKINBLEMISHES 对瑕疵位置执行受控的 Fine/Mid 局部修复。
%   普通皮肤仍由 smoothSkinTexture 处理；本函数只读取固定的瑕疵图，
%   低置信度只衰减 Fine，中高置信度才少量收敛 Mid。Base 始终不变。
%
%   T14/T15/T31：第 5 参数 repairContract 是 Repair（Fine/Mid）的 stage
%   contract（组装点 +beauty/repairStageContract，生产组装层 beautifyImage
%   传入）。执行层是**纯执行器**：只消费 contract 的规范门与 strength 层，
%   不读取任何 semantic / evidence / general protection mask。
%
%   Blemish ≠ Should Repair（上位契约第 3.2 节，T31 重点）：
%     repairTargetWeight  = blemishEvidence × processability × strength
%                           × (1 - targetProtection)
%     repairSupportWeight = validSkinReference × (1 - supportProtection)
%   瑕疵证据（repairEvidence/highConfidence）只回答"像不像瑕疵"，**不**单独
%   决定修复强度；"该不该修"由 (1 - targetProtection) 独立决定。结构保护
%   **不**反向塞进 blemish 检测（证据链只消费 blemishMap 与全局/局部密度），
%   blemish 证据也**不**绕过 target 门。
%
%   读取集合（上位契约第 1 节）：
%     beautyMasks.skinMask / strengthMap / nonFaceStrengthMap
%       —— processability 与 strength 层（不参与保护判定）；
%     repairContract.hard                —— hard identity，组合 (1-hard) 乘子；
%     repairContract.support.repairMid   —— 结构保护（1 - 该值 = 生产
%       structureGate，含 runtime blemish 放宽与强结构上限；截断在它与
%       纹理/鼻部门之间，故必须独立发布；同一门也用于邻域参考池）；
%     repairContract.target.repairFine   —— 截断后作用的纹理退让保护；
%     repairContract.target.repairMid    —— 截断后作用的 Mid 鼻部退让保护；
%     repairContract.support.repairFine  —— 邻域参考池纹理保护；
%     repairContract.textureBandGate     —— T30 纯 policy 带门，只乘逐像素
%       权重，不进邻域参考统计；
%     blemishMap                        —— 运行期证据；也可传入含
%       blemishMap/denseBlemishField 的诊断结构。denseBlemishField 走独立
%       的高档分频 Repair 分支，不并入 compact blob。
%
%   生产顺序（与 legacy 逐位等价的关键）：结构门在 [0,1] 截断之前作用于
%   权重；纹理门作用于 Fine/Mid/chroma，鼻部门只作用于 Mid，二者均在截断
%   之后、textureBandGate 之前，且鼻部门先于纹理门（legacy 乘法结合序）。
%   V4 policy 额外要求所有 Repair 证据先经过紧凑 Blob 筛选，Fine 为默认
%   通道，Mid 只接受极高置信紧凑目标；75--100 档的额外修复只通过独立
%   highEndRepairGate 进入，不改变 75 档及以下公式。
%
%   生产链在结构门与纹理/鼻部门之间对权重做 [0,1] 截断（
%   min(max(w·structureGate,0),1) 之后才乘纹理/鼻部门），把纹理或鼻部折叠
%   进前置门会在截断饱和区改变结果（T14 实测偏差 ~0.1 量级，T31 真实图
%   实测 fineWeight 7594px、mediumWeight 3429px 偏离）；因此 target 门按生产
%   原位拆成"前置结构 + 截断后纹理/鼻"两段，消费侧按同一顺序重建。
%
%   邻域参考统计（referenceReliability/referenceWeight）只用
%   support.repairFine / support.repairMid 与 blemish 证据，**不**乘 target
%   门与 textureBandGate：把 target 门并进参考池会让带内变化经 imfilter
%   扩散到带外。compat 使用原有 face-scale 半径；V4 policy 按已接受
%   目标面积与 face scale 收缩窗口，并将所有候选从参考池排除。
%
%   兼容入口（未提供第 5 参的旧调用方）：T31 起不再自行解释 general
%   texture/structure/hard/nose masks，而是向 policy 层索取零带
%   stageProtection 后经同一组装点得到 contract。
%
%   缺字段或取值无效一律 fail-fast，不在函数内部重新拼装 protection，也不
%   静默回退。

if nargin < 4
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要频率、Beauty Masks、瑕疵图和磨皮强度。');
end
validateFrequency(frequency);
imageSize = frequency.imageSize(1:2);
validateMasks(beautyMasks, imageSize);
[blemishMap, denseBlemishField] = readBlemishInput( ...
    blemishMap, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

base = double(frequency.base);
mid = double(frequency.mid);
fine = double(frequency.fine);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
if nargin < 5 || isempty(repairContract)
    % T31 兼容入口：向 policy 层索取零带 stageProtection 后经同一组装点
    % 得到 contract（不再读取 general masks）。
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
    repairContract = beauty.repairStageContract(stageProtection, blemishMap);
else
    repairContract = validateRepairContract(repairContract, imageSize);
end

profile = beautySmoothingProfile(smoothingStrength);
hardGate = repairContract.hard;
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
highEndRepairGate = profile.highEndRepairGate;
repairFineGain = 1 + .90 * highEndRepairGate;
repairMidGain = 1 + .65 * highEndRepairGate;
% 前置结构门（含 runtime blemish 放宽与强结构固定下限）由 contract 按生产
% 原式重建并发布为 support.repairMid 的补码；执行层只做补码还原，不再自行
% 组合 general masks。该门同时用于邻域参考池（见下）。
structureGate = 1 - repairContract.support.repairMid;

% policyRepairEnabled 由唯一组装点按 V4 region evidence 发布。旧的
% compat/partial contract 没有该字段时保留旧路径；生产 V4 路径则对
% 全部 Repair 证据启用紧凑局部约束。
policyRepairEnabled = repairContract.policyRepairEnabled;

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
% 证据链只消费 blemish 图与全局/局部密度：结构保护不得反向塞进
% blemish 检测，blemish 证据也不得绕过 target 门（见下方权重）。
repairEvidence = min(max(blemishMap .* sparseGate .* globalGate, 0), 1);
mediumConfidence = smoothStep(repairEvidence, .60, .90);
highConfidence = smoothStep(repairEvidence, .62, .90);
if policyRepairEnabled
    % 普通 Repair 也必须通过紧凑 Blob 筛选；大面积缓变、长线和沟槽
    % 保持可见为拒绝修复，而不是拆分成多个伪小斑点。
    compactCandidate = blemishMap > .60;
    blobMask = smallBlemishBlobs(compactCandidate, faceScale);
    repairEvidence = repairEvidence .* double(blobMask);
    mediumConfidence = smoothStep(repairEvidence, .60, .90);
    highConfidence = smoothStep(repairEvidence, .62, .90);
elseif highEndRepairCurve > 0
    compactCandidate = blemishMap > .65;
    blobMask = smallBlemishBlobs(compactCandidate, faceScale);
else
    compactCandidate = false(imageSize);
    blobMask = false(imageSize);
end
% 高档额外修复必须同时满足高置信局部异常、紧凑 Blob 和全局证据；
% 证据链不消费任何区域语义，鼻部同样只能靠 blemish 证据进入。
highEndConfidence = highConfidence .* double(blobMask) .* globalGate;
repairCurveMap = normalRepairCurve * ones(imageSize);
repairCurveMap = min(max(repairCurveMap, 0), 1);

% 逐像素修复强度 = blemish 证据 × processability/strength（allowed）
% × (1 - 前置结构保护)，截断后再按生产顺序乘后置门：
%   fineWeight   : × (1 - target.repairFine)          （纹理退让）
%   mediumWeight : × noseMidGate × (1 - target.repairFine)
%                  noseMidGate = (1 - target.repairMid) × midBandGate
%                                （鼻部退让 × Mid 专属 policy 带，合成后
%                                 先于纹理门相乘，与 legacy 结合序一致）
%   chromaWeight : × (1 - target.repairFine)
% blemish 证据与 target 门相互独立：改动 target 门只改变"该不该修"，不改变
% blemish 证据；鼻部门先于纹理门相乘，与 legacy 乘法结合序一致（bit-exact）。
if policyRepairEnabled
    % V4 Repair 以 Fine 为唯一默认修复通道；Mid 只接受极高置信、
    % 紧凑且已通过同一结构门的目标，避免用中频把自然曲面拉平。
    fineWeight = repairCurveMap .* repairEvidence .* allowed .* ...
        structureGate .* repairFineGain;
    midConfidence = smoothStep(repairEvidence, .82, .95);
    mediumWeight = highEndRepairCurve .* midConfidence .* ...
        double(blobMask) .* globalGate .* allowed .* structureGate .* ...
        repairMidGain;
else
    fineWeight = repairCurveMap .* (repairEvidence + .25 * highConfidence) .* ...
        allowed .* structureGate .* repairFineGain + ...
        (highEndRepairCurve .* highEndConfidence) .* allowed .* ...
        structureGate .* repairFineGain;
    mediumWeight = repairCurveMap .* (.95 * mediumConfidence + ...
        .40 * highConfidence) .* allowed .* structureGate + ...
        (highEndRepairCurve .* ...
        highEndConfidence) .* allowed .* structureGate;
    mediumWeight = mediumWeight .* repairMidGain;
    midConfidence = highConfidence;
end
mediumWeight = min(max(mediumWeight, 0), 1);
chromaWeight = .16 * repairCurveMap .* highConfidence .* allowed .* ...
    structureGate;
fineWeight = min(max(fineWeight, 0), 1);
chromaWeight = min(max(chromaWeight, 0), 1);

% 脸部和脸外的允许权重完成后统一应用线性纹理软保护；同一门控也
% 从邻域参考采样中排除受保护纹理，避免保护区域反向影响附近修复。
% T30/T31：纯 policy 带 textureBandGate / midBandGate 只乘逐像素权重；
% referenceReliability（下方 imfilter 邻域参考）仍用未带 support 门，
% 避免带内变化经卷积扩散到带外。零带时 textureBandGate == midBandGate == 1。
textureBandGate = repairContract.textureBandGate;
midBandGate = repairContract.midBandGate;
targetFineGate = 1 - repairContract.target.repairFine;
targetMidGate = 1 - repairContract.target.repairMid;
% Mid 逐像素门的合成顺序与 legacy 生产原式一致：
% midPixelGate = (1 - .50·nose) .* (1 - regionBandMid)，随后先于纹理门
% 乘到 mediumWeight，保证 mediumWeight 与生产路径逐位相等。
midPixelGate = targetMidGate .* midBandGate;
fineWeight = fineWeight .* targetFineGate .* textureBandGate;
mediumWeight = mediumWeight .* midPixelGate .* targetFineGate .* ...
    textureBandGate;
chromaWeight = chromaWeight .* targetFineGate .* textureBandGate;

radius = referenceRadius(faceScale, blobMask, policyRepairEnabled);
kernelSize = 2 * radius + 1;
kernel = ones(kernelSize, kernelSize);

% 参考只使用非瑕疵皮肤，并降低跨越结构边缘的贡献；这样鼻梁和
% 手指的低频坡面不会被邻域平均抹平。参考池门来自 support.*（与 target
% 门解耦），blemish 证据按运行期独立乘入；乘法顺序与 legacy 一致
% （textureGate → blemish → structureGate），保证参考统计逐位不变。
supportTextureGate = 1 - repairContract.support.repairFine;
supportStructureGate = 1 - repairContract.support.repairMid;
if policyRepairEnabled
    % 通过紧凑性筛选的候选及被拒绝的大块候选均不进入参考池；否则
    % 参考均值会把结构纹理跨边界传播到真正的修复点。
    referenceBlemishGate = (1 - .86 * blemishMap) .* ...
        double(~compactCandidate);
else
    referenceBlemishGate = 1 - .86 * blemishMap;
end
% dense field 是独立的连续包络：高档路径不让其污染参考池。把排除门
% 乘 highEndRepairGate，保证 0--75 档的 compact Repair 参考统计逐位不变。
denseReferenceGate = 1 - highEndRepairGate .* denseBlemishField;
referenceBlemishGate = referenceBlemishGate .* denseReferenceGate;
referenceReliability = allowed .* supportTextureGate .* ...
    referenceBlemishGate .* supportStructureGate;
referenceWeight = imfilter(referenceReliability, kernel, 'replicate');
referenceCoverage = min(max(referenceWeight ./ max(sum(kernel(:)), 1), ...
    0), 1);
fineReference = imfilter(fine .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
midReference = imfilter(mid .* referenceReliability, kernel, ...
    'replicate') ./ max(referenceWeight, eps);
minimumReferenceCoverage = .05;
referenceAvailable = referenceWeight > eps & ...
    referenceCoverage >= minimumReferenceCoverage;
fineReference(~referenceAvailable) = 0;
midReference(~referenceAvailable) = 0;

% dense Repair 使用排除高置信瑕疵后的同皮肤多尺度参考。小窗口优先
% 保留局部曲面，较大窗口只在 dense 区域缺少近邻参考时补足覆盖；窗口
% 有限且只用于构造参考，不把结果作为全局模糊直接写回图像。
denseFineReference = zeros(imageSize);
denseMidReference = zeros(imageSize);
denseBaseReference = zeros(imageSize);
denseReferenceCoverage = zeros(imageSize);
denseBaseReferenceCoverage = zeros(imageSize);
denseSurfaceReferenceReliability = zeros(imageSize);
hasFaceSurfacePrior = isfield(beautyMasks, 'faceSkinMask') && ...
    any(double(beautyMasks.faceSkinMask(:)) > .05);
if highEndRepairGate > eps && any(denseBlemishField(:) > eps)
    if hasFaceSurfacePrior
        % 真实解析提供 faceSkinMask 时，密集雀斑区本身也是曲面先验
        % 的有效样本。这里不再把 dense/high-confidence 像素排除，
        % 只保留 face-skin、hard、纹理和结构安全域；曲面函数负责
        % 用偏亮分位拒绝暗离群点。
        faceSkin = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);
        denseSurfaceReferenceReliability = allowed .* ...
            double(faceSkin > .05) .* supportTextureGate .* ...
            supportStructureGate;
        [denseFineReference, denseReferenceCoverage] = ...
            beauty.buildRobustSurfaceReference(fine, ...
            denseSurfaceReferenceReliability, faceScale, 'median');
        [denseMidReference, denseMidCoverage] = ...
            beauty.buildRobustSurfaceReference(mid, ...
            denseSurfaceReferenceReliability, faceScale, 'mid');
        denseReferenceCoverage = min(denseReferenceCoverage, ...
            denseMidCoverage);
    else
        % 缺少真实语义 faceSkinMask 的兼容/单元入口仍要求干净近邻，
        % 用于显式验证“完全没有有效皮肤参考时必须归零”。
        denseReferenceGate = double(denseBlemishField <= eps) .* ...
            double(blemishMap <= .60);
        denseReferenceReliability = allowed .* supportTextureGate .* ...
            denseReferenceGate .* supportStructureGate;
        [denseFineReference, denseMidReference, denseReferenceCoverage] = ...
            multiScaleReference(fine, mid, denseReferenceReliability, ...
            faceScale, radius);
        denseSurfaceReferenceReliability = denseReferenceReliability;
    end
    % Base 需要单独的鲁棒曲面：亮度参考允许拒绝安全池中的暗离群点，
    % 同时通过多尺度覆盖保留面部慢变曲面。使用 source luminance
    % 建立先验而不是把 compact Repair 的频带均值直接当作大面积
    % Base 目标；鲁棒曲面本身会抑制 Fine 离群点，最终 Base 仍受
    % 调用方的有限幅度门约束。
    denseSurfaceLuminance = frequency.sourceLuminance;
    [denseBaseReference, denseBaseReferenceCoverage] = ...
        beauty.buildRobustSurfaceReference(denseSurfaceLuminance, ...
        denseSurfaceReferenceReliability, faceScale, 'luminance');
    denseReferenceCoverage = max(denseReferenceCoverage, ...
        denseBaseReferenceCoverage);
end

% 没有任何可信参考时，修复权重必须归零。参考值置零只是为了保持
% 诊断数组有限，不能被解释成“把目标频带修到零”；否则会在紧凑候选
% 或保护带交叠处制造灰块/平坦块。
fineWeight(~referenceAvailable) = 0;
mediumWeight(~referenceAvailable) = 0;
chromaWeight(~referenceAvailable) = 0;

denseReferenceCoverageForTarget = max(referenceCoverage, ...
    denseReferenceCoverage);
denseReferenceAvailable = denseReferenceCoverageForTarget >= ...
    minimumReferenceCoverage;

% 这里的置信度只描述语义安全域中的有效样本覆盖，不再代表“附近
% 是否有完全无斑像素”。高档密集场可以使用自身统计，只在 face-skin
% 不足或结构域没有有效样本时退让。
denseSurfaceConfidence = smoothStep(denseReferenceCoverageForTarget, ...
    .12, .45);
faceSkinGate = ones(imageSize);
if isfield(beautyMasks, 'faceSkinMask')
    faceSkinMask = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);
    if any(faceSkinMask(:) > .05)
        faceSkinGate = double(faceSkinMask > .05);
    end
end

% dense field 独立使用高档门；不得把大片连续证据伪装成 compact blob。
% denseReferenceCoverageForTarget 允许大面积目标使用多尺度同皮肤参考，
% 同时保留 referenceCoverage 作为已有 compact 参考的必要条件。
denseAllowedWeight = denseBlemishField .* allowed .* structureGate .* ...
    targetFineGate .* textureBandGate .* ...
    highEndRepairGate .* double(~blobMask) .* ...
    denseSurfaceConfidence .* faceSkinGate;
denseAllowedWeight(~denseReferenceAvailable) = 0;
denseAllowedWeight = min(max(denseAllowedWeight, 0), 1);

% 参考只允许把同号残差向零收敛，避免局部邻域的反向纹理在
% 强度升高时被重新放大，从而保证 Fine 和瑕疵能量单调下降。
fineTarget = sign(fine) .* min(abs(fine), abs(fineReference));
midTarget = sign(mid) .* min(abs(mid), abs(midReference));
fineCorrection = fineWeight .* (fineTarget - fine);
mediumCorrection = mediumWeight .* (midTarget - mid);

% dense 分支只在 highEndRepairGate 打开后进入。Mid 承担缓慢斑驳的
% 主要收敛，Fine 仅轻量衰减以保留微纹理；所有权重仍受 target/band
% 与同皮肤参考覆盖约束。Mid 增量再做有限幅度裁剪，避免鼻梁、脸颊
% 曲面因参考尺度变化被拉平。
denseFineWeight = .38 .* highEndRepairGate .* denseAllowedWeight .* ...
    targetFineGate .* textureBandGate;
denseMidWeight = .92 .* highEndRepairGate .* denseAllowedWeight .* ...
    targetMidGate .* midBandGate .* targetFineGate .* textureBandGate;
denseChromaWeight = .58 .* highEndRepairGate .* denseAllowedWeight .* ...
    targetFineGate .* textureBandGate;
denseFineWeight = min(max(denseFineWeight, 0), 1);
denseMidWeight = min(max(denseMidWeight, 0), 1);
denseChromaWeight = min(max(denseChromaWeight, 0), 1);
denseFineTarget = sign(fine) .* min(abs(fine), abs(denseFineReference));
denseMidTarget = min(max(denseMidReference, -.035), .035);
denseMidDifference = denseMidTarget - mid;
denseMidLimit = min(.035, .35 .* abs(mid) + .004);
denseMidDifference = min(max(denseMidDifference, -denseMidLimit), ...
    denseMidLimit);
denseFineCorrection = denseFineWeight .* (denseFineTarget - fine);
denseMediumCorrection = denseMidWeight .* denseMidDifference;
fineCorrection = fineCorrection + denseFineCorrection;
mediumCorrection = mediumCorrection + denseMediumCorrection;
fineWeight = min(max(fineWeight + denseFineWeight, 0), 1);
mediumWeight = min(max(mediumWeight + denseMidWeight, 0), 1);
chromaWeight = min(max(chromaWeight + denseChromaWeight, 0), 1);

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
    'chromaWeight', chromaWeight, ...
    'denseFineCorrection', denseFineCorrection, ...
    'denseMediumCorrection', denseMediumCorrection, ...
    'denseChromaWeight', denseChromaWeight);

beforeEnergy = mean(abs(fine(:)) + abs(mid(:)));
afterEnergy = mean(abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:)));
blemishBefore = mean((abs(fine(:)) + abs(mid(:))) .* blemishMap(:));
blemishAfter = mean((abs(repairedFrequency.fine(:)) + ...
    abs(repairedFrequency.mid(:))) .* blemishMap(:));
% T31 诊断收口：不再报告 noseMask/noseMidGate 与 general texture mask；
% 报告 target 门（逐像素修改保护）与 support 门（参考池保护）两族。
diagnostics = struct( ...
    'blemishMap', blemishMap, ...
    'denseBlemishField', denseBlemishField, ...
    'denseAllowedWeight', denseAllowedWeight, ...
    'sparseGate', sparseGate, ...
    'globalHighDensity', globalHighDensity, ...
    'globalBlemishMean', globalBlemishMean, ...
    'globalGate', globalGate, ...
    'normalRepairCurve', normalRepairCurve, ...
    'highEndRepairCurve', highEndRepairCurve, ...
    'highEndRepairGate', highEndRepairGate, ...
    'repairFineGain', repairFineGain, ...
    'repairMidGain', repairMidGain, ...
    'policyRepairEnabled', policyRepairEnabled, ...
    'compactCandidate', compactCandidate, ...
    'compactBlobAreaLimit', blobAreaLimit(faceScale), ...
    'compactBlobSpanLimit', blobSpanLimit(faceScale), ...
    'compactBlobAcceptedPixels', nnz(blobMask), ...
    'repairEvidence', repairEvidence, ...
    'mediumConfidence', mediumConfidence, ...
    'highConfidence', highConfidence, ...
    'repairCurveMap', repairCurveMap, ...
    'blobMask', blobMask, ...
    'highEndConfidence', highEndConfidence, ...
    'textureGate', targetFineGate, ...
    'targetFineGate', targetFineGate, ...
    'targetMidGate', targetMidGate, ...
    'supportTextureGate', supportTextureGate, ...
    'supportStructureGate', supportStructureGate, ...
    'textureBandGate', textureBandGate, ...
    'midBandGate', midBandGate, ...
    'fineWeight', fineWeight, ...
    'mediumWeight', mediumWeight, ...
    'midWeight', mediumWeight, ...
    'chromaWeight', chromaWeight, ...
    'repairWeight', min(1, fineWeight + mediumWeight), ...
    'allowed', allowed, ...
    'structureGate', structureGate, ...
    'referenceReliability', referenceReliability, ...
    'referenceWeight', referenceWeight, ...
    'referenceCoverage', referenceCoverage, ...
    'denseReferenceCoverage', denseReferenceCoverage, ...
    'denseReferenceCoverageForTarget', denseReferenceCoverageForTarget, ...
    'denseReferenceAvailable', denseReferenceAvailable, ...
    'denseSurfaceReferenceReliability', denseSurfaceReferenceReliability, ...
    'denseSurfaceConfidence', denseSurfaceConfidence, ...
    'faceSkinGate', faceSkinGate, ...
    'hasFaceSurfacePrior', hasFaceSurfacePrior, ...
    'denseBaseReference', denseBaseReference, ...
    'denseBaseReferenceCoverage', denseBaseReferenceCoverage, ...
    'referenceRadius', radius, ...
    'fineReference', fineReference, ...
    'midReference', midReference, ...
    'denseFineReference', denseFineReference, ...
    'denseMidReference', denseMidReference, ...
    'fineTarget', fineTarget, ...
    'midTarget', midTarget, ...
    'denseFineTarget', denseFineTarget, ...
    'denseMidTarget', denseMidTarget, ...
    'fineCorrection', fineCorrection, ...
    'mediumCorrection', mediumCorrection, ...
    'denseFineCorrection', denseFineCorrection, ...
    'denseMediumCorrection', denseMediumCorrection, ...
    'denseFineWeight', denseFineWeight, ...
    'denseMidWeight', denseMidWeight, ...
    'denseChromaWeight', denseChromaWeight, ...
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
% 零瑕疵参考门快照（T07 target 快照的补码）保留，供诊断与测试消费；
% fineGateRuntime 为 contract 重建的前置结构门（= structureGate）。
diagnostics.fineGateRuntime = structureGate;
diagnostics.fineGateZeroBlemish = 1 - repairContract.snapshot.repairFine;
diagnostics.mediumGateZeroBlemish = 1 - repairContract.snapshot.repairMid;
end

function contract = validateRepairContract(contract, imageSize)
%VALIDATEREPAIRCONTRACT 校验 Repair（Fine/Mid）stage contract（T14/T15/T30/T31）。
%   必需字段：hard、support.repairMid（结构保护，1 - 该值 = 生产
%   structureGate，同时作用于逐像素前置截断与邻域参考池）、
%   support.repairFine（参考池纹理保护）、target.repairFine/.repairMid
%   （截断后逐像素退让保护）、textureBandGate/midBandGate（T30 纯 policy
%   带门，分别只乘 texture 通道与 Mid 通道）、snapshot.repairFine/.repairMid
%   （T07 零瑕疵参考快照）。缺字段或取值无效一律 fail-fast，不在函数内部
%   重新拼装，也不静默回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'hard', 'target', 'support', ...
        'textureBandGate', 'midBandGate', 'snapshot'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 必须是包含 hard/target/support/textureBandGate/midBandGate/snapshot 的标量结构。');
end
if ~isfield(contract, 'policyRepairEnabled')
    contract.policyRepairEnabled = false;
elseif ~islogical(contract.policyRepairEnabled) && ...
        ~(isnumeric(contract.policyRepairEnabled) && ...
        isreal(contract.policyRepairEnabled) && isscalar(contract.policyRepairEnabled) && ...
        isfinite(contract.policyRepairEnabled))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 policyRepairEnabled 无效。');
else
    contract.policyRepairEnabled = logical(contract.policyRepairEnabled);
end
if ~isstruct(contract.target) || ~isscalar(contract.target) || ...
        ~all(isfield(contract.target, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 target 缺少 repairFine/repairMid。');
end
if ~isstruct(contract.support) || ~isscalar(contract.support) || ...
        ~all(isfield(contract.support, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 support 缺少 repairFine/repairMid。');
end
if ~isstruct(contract.snapshot) || ~isscalar(contract.snapshot) || ...
        ~all(isfield(contract.snapshot, {'repairFine', 'repairMid'}))
    error('beauty:InvalidBlemishRepair', ...
        'Repair stage contract 的 snapshot 缺少 repairFine/repairMid。');
end
contract.hard = validateMask(contract.hard, imageSize, 'hard');
contract.target.repairFine = validateMask(contract.target.repairFine, ...
    imageSize, 'target.repairFine');
contract.target.repairMid = validateMask(contract.target.repairMid, ...
    imageSize, 'target.repairMid');
contract.support.repairFine = validateMask(contract.support.repairFine, ...
    imageSize, 'support.repairFine');
contract.support.repairMid = validateMask(contract.support.repairMid, ...
    imageSize, 'support.repairMid');
contract.textureBandGate = validateMask(contract.textureBandGate, ...
    imageSize, 'textureBandGate');
contract.midBandGate = validateMask(contract.midBandGate, ...
    imageSize, 'midBandGate');
contract.snapshot.repairFine = validateMask(contract.snapshot.repairFine, ...
    imageSize, 'snapshot.repairFine');
contract.snapshot.repairMid = validateMask(contract.snapshot.repairMid, ...
    imageSize, 'snapshot.repairMid');
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
%VALIDATEMASKS 校验 strength/processability 层输入。
%   T31 起本函数只校验 skinMask 与 strengthMap：repair 执行层不再读取
%   任何 general protection mask（texture/structure/hard/nose），保护门
%   全部来自 stage contract。
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidBlemishRepair', ...
        '瑕疵修复需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidBlemishRepair', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    validateMask(beautyMasks.(required{index}), imageSize, required{index});
end
end

function [blemishMap, denseBlemishField] = readBlemishInput(value, imageSize)
denseBlemishField = zeros(imageSize);
if isstruct(value)
    if isfield(value, 'blemishMap')
        blemishMap = value.blemishMap;
    elseif isfield(value, 'confidence')
        blemishMap = value.confidence;
    else
        error('beauty:InvalidBlemishRepair', ...
            '瑕疵诊断结构缺少 blemishMap 或 confidence。');
    end
    if isfield(value, 'denseBlemishField')
        denseBlemishField = validateMask(value.denseBlemishField, ...
            imageSize, 'denseBlemishField');
    end
else
    blemishMap = value;
end
blemishMap = validateMask(blemishMap, imageSize, 'blemishMap');
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
areaLimit = blobAreaLimit(faceScale);
spanLimit = blobSpanLimit(faceScale);
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

function areaLimit = blobAreaLimit(faceScale)
% 面积上限按人脸尺度归一，避免用单张图的绝对像素阈值。
areaLimit = max(24, round(.006 * double(faceScale) ^ 2));
end

function spanLimit = blobSpanLimit(faceScale)
% 跨度上限排除睫毛、眼线、鼻翼沟和耳轮等长线结构。
spanLimit = max(5, round(.045 * double(faceScale)));
end

function radius = referenceRadius(faceScale, blobMask, policyRepairEnabled)
% 参考窗口随已接受目标面积和人脸尺度变化。小斑点不再使用覆盖
% 整个眼周/鼻部的固定大窗口；compat 路径保留既有尺度公式。
if ~policyRepairEnabled || ~any(blobMask(:))
    radius = min(20, max(3, round(.070 * double(faceScale))));
    return;
end
components = bwconncomp(blobMask, 8);
if components.NumObjects == 0
    radius = 3;
    return;
end
areas = cellfun(@numel, components.PixelIdxList);
largestRadius = 2 * sqrt(max(areas) / pi);
scaleRadius = .040 * double(faceScale);
radius = min(12, max(3, round(min(scaleRadius, largestRadius))));
end

function [fineReference, midReference, coverage] = multiScaleReference( ...
        fine, mid, reliability, faceScale, compactRadius)
%MULTISCALEREFERENCE 用有限尺度的同皮肤样本补足 dense 区域参考。
%   参考只由 reliability 允许的像素贡献；尺度权重偏向近邻，较大窗口
%   只在局部覆盖不足时提供稳定参考，不把卷积结果直接作为输出图像。
imageSize = size(reliability);
fineReference = zeros(imageSize);
midReference = zeros(imageSize);
coverage = zeros(imageSize);

mediumRadius = min(24, max(compactRadius + 2, round(.055 * faceScale)));
broadRadius = min(40, max(mediumRadius + 2, round(.11 * faceScale)));
radii = unique(max(3, round([compactRadius, mediumRadius, broadRadius])));
scaleWeights = 1 ./ sqrt(double(radii));
totalScaleWeight = sum(scaleWeights);
weightedFine = zeros(imageSize);
weightedMid = zeros(imageSize);
weightedCoverage = zeros(imageSize);

for index = 1:numel(radii)
    radius = radii(index);
    kernel = ones(2 * radius + 1, 2 * radius + 1);
    referenceWeight = imfilter(reliability, kernel, 'replicate');
    scaleCoverage = min(max(referenceWeight ./ sum(kernel(:)), 0), 1);
    fineAtScale = imfilter(fine .* reliability, kernel, 'replicate') ./ ...
        max(referenceWeight, eps);
    midAtScale = imfilter(mid .* reliability, kernel, 'replicate') ./ ...
        max(referenceWeight, eps);
    scaleContribution = scaleWeights(index) .* scaleCoverage;
    weightedFine = weightedFine + scaleContribution .* fineAtScale;
    weightedMid = weightedMid + scaleContribution .* midAtScale;
    weightedCoverage = weightedCoverage + scaleContribution;
end

fineReference = weightedFine ./ max(weightedCoverage, eps);
midReference = weightedMid ./ max(weightedCoverage, eps);
coverage = min(max(weightedCoverage ./ max(totalScaleWeight, eps), 0), 1);
fineReference(coverage <= eps) = 0;
midReference(coverage <= eps) = 0;
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
