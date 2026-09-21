function [toneResult, diagnostics] = normalizeSkinTone( ...
        inputImage, frequency, beautyMasks, blemishMap, smoothingStrength, ...
        toneContract)
%NORMALIZESKINTONE 用一套全皮肤候选结果修正低频色度异常。
%   频率结构只用于校验尺寸；脸部和脸外始终共享同一个候选色度，
%   区域差异仅来自 masks.buildBeautyStrengthMap 的连续强度图。
%
%   T33（执行契约）：可选第 6 参数 toneContract 是 Tone 的 stage contract，
%   由唯一组装点 +beauty/toneStageContract 从 V4 stage protection 的规范门
%   组装（生产组装层 beautifyImage 与兼容入口共用同一份实现）。执行层是
%   **纯执行器**：只消费 contract 与 strength/processability 层，不读取任何
%   semantic / evidence / legacy general protection mask（structure/chroma/
%   hard/tone）。肤色目标估计（候选色度中值）与色彩空间公式不变。
%   读取集合（上位契约第 1 节）：
%     beautyMasks.skinMask / strengthMap —— processability 与 strength 层
%       （非保护判定，显式控制效果幅度，strength 与 protection 不合并）；
%     beautyMasks.faceSkinMask / nonFaceSkinMask / faceBox —— 非保护类
%       processability 与几何字段（诊断分域与参考尺度）；
%     toneContract.hard —— 独立 hard identity（生产原位 (1-hard) 乘子）；
%     toneContract.structureGate / featureGate —— 主分支逐像素门控因子
%       （policy 层按生产原式一次算好并发布）；
%     toneContract.uniformFeatureGate —— uniform 分支逐像素门控因子；
%     toneContract.candidateChromaGate —— 参考样本门（= 1 - support.tone）。
%   统一权重函数（上位契约第 2 节）：
%     targetWeight  = strength × processabilitySkin × (1 - targetProtection)
%                     → weightMap 的 structureGate·featureGate 与
%                       uniformToneSupport 的 structureGate·uniformFeatureGate
%     supportWeight = validSkinReference × (1 - supportProtection)
%                     → candidateChromaGate（肤色目标估计的样本门）
%   其中 skinMask/strengthMap 是 processability×strength 的既有逐像素形式，
%   target.tone/support.tone 是 policy 层发布的规范双门控（1 - 该值 即上述
%   门控积与样本门；因 T07 折叠含 1-x 补码往返舍入，执行层消费 policy 发布
%   的未折叠因子以保证与 legacy 逐位等价）。
%   兼容入口（未提供第 6 参的旧调用方）：不再自行解释 legacy general masks，
%   而是向 policy 层索取零带 stageProtection 并经同一组装点得到零带
%   contract。缺字段 fail-fast，不在函数内部重新拼装。

if nargin < 5
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一需要输入图像、频率、Beauty Masks、瑕疵图和磨皮强度。');
end
validateImage(inputImage);
imageSize = size(inputImage, 1:2);
if ~isempty(frequency)
    validateFrequency(frequency, imageSize);
end
validateMasks(beautyMasks, imageSize);
runtimeBlemish = blemishMap;
blemishMap = readBlemishMap(blemishMap, imageSize);
[denseBlemishField, denseAllowedWeight, denseSurfaceReferenceReliability] = ...
    readDenseRuntimeBlemish( ...
    runtimeBlemish, imageSize);
if ~isValidStrength(smoothingStrength)
    error('beauty:InvalidStrength', '磨皮强度必须是 0 到 100 的数值标量。');
end

ycbcr = rgb2ycbcr(im2double(inputImage));
luminance = ycbcr(:, :, 1);
cb = ycbcr(:, :, 2);
cr = ycbcr(:, :, 3);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
% T33：保护门控只来自 contract。兼容入口（未提供第 6 参的旧调用方）不再
% 自行解释 general structure/chroma/hard masks，而是向 policy 层索取零带
% stageProtection（masks.buildStageProtectionMasks(beautyMasks)），经唯一
% 组装点 +beauty/toneStageContract 得到零带 contract，与生产路径共用同一份
% Single Protection Authority。执行层只消费 target.tone/support.tone 与
% policy 发布的未折叠门控，缺字段 fail-fast，不在函数内部重新拼装。
if nargin < 6 || isempty(toneContract)
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
    toneContract = beauty.toneStageContract(stageProtection);
end
toneContract = validateToneContract(toneContract, imageSize);
hardProtection = toneContract.hard;
structureGate = toneContract.structureGate;
featureGate = toneContract.featureGate;
uniformFeatureGate = toneContract.uniformFeatureGate;
candidateChromaGate = toneContract.candidateChromaGate;

baseCandidate = skinMask > .05 & strengthMap > .01 & ...
    hardProtection < .999 & candidateChromaGate;
candidate = selectToneCandidate(luminance, baseCandidate);
if ~any(candidate(:))
    candidate = skinMask > .05 & strengthMap > .01 & ...
        hardProtection < .999;
end
faceScale = readFaceScale(beautyMasks, frequency, imageSize);
chromaSigma = min(12, max(2.5, .025 * faceScale));
localCb = imgaussfilt(cb, chromaSigma, 'Padding', 'replicate');
localCr = imgaussfilt(cr, chromaSigma, 'Padding', 'replicate');
if any(candidate(:))
    candidateCb = median(localCb(candidate));
    candidateCr = median(localCr(candidate));
    hasCandidate = true;
else
    candidateCb = .5;
    candidateCr = .5;
    hasCandidate = false;
end

chromaResidual = max(abs(localCb - candidateCb), ...
    abs(localCr - candidateCr));
chromaEvidence = smoothStep(chromaResidual, .018, .060);
localChromaResidual = max(abs(cb - localCb), abs(cr - localCr));
localChromaEvidence = smoothStep(localChromaResidual, .010, .045);
blemishEvidence = smoothStep(blemishMap, .32, .72);

% 统一候选只做小幅连续校正。局部色度异常优先向邻域色度收敛，
% 正常皮肤的基础权重很低；不对亮度通道做任何补偿。75--100 档的
% v3.6 Tone 收尾只处理残余色度证据，并通过独立的限幅和暗结构/边缘
% 门保护鼻孔、眼眶、耳部暗结构；75 档及以下继续走原有路径。
profile = beautySmoothingProfile(smoothingStrength);
ratio = double(smoothingStrength) / 100;
toneCurve = profile.toneStrength;
highEndToneGate = profile.highEndToneGate;
fullToneCurve = ratio ^ .85;
toneCurveMap = toneCurve + (fullToneCurve - toneCurve) .* ...
    smoothStep(chromaEvidence, .25, .65);
toneCurveMap = max(toneCurveMap, ...
    fullToneCurve .* localChromaEvidence);
allowed = min(skinMask, strengthMap) .* (1 - hardProtection);
 denseCbReference = zeros(imageSize);
 denseCrReference = zeros(imageSize);
 denseChromaCoverage = zeros(imageSize);
 denseChromaDeltaCb = zeros(imageSize);
 denseChromaDeltaCr = zeros(imageSize);
if highEndToneGate > eps && any(denseBlemishField(:) > eps)
    % 真实解析路径发布的 denseSurfaceReferenceReliability 已经是全脸
    % safe face-skin 先验，允许密集雀斑自身参与鲁棒统计；兼容入口仍
    % 使用旧的干净参考排除门。Cb/Cr 始终分通道估计，禁止 RGB 平均。
    if any(denseSurfaceReferenceReliability(:) > eps)
        denseChromaReliability = denseSurfaceReferenceReliability .* ...
            candidateChromaGate .* structureGate .* featureGate;
    else
        denseChromaReliability = allowed .* candidateChromaGate .* ...
            structureGate .* featureGate .* ...
            double(denseBlemishField <= eps) .* double(blemishMap <= .60);
    end
    [denseCbReference, denseCbCoverage] = ...
        beauty.buildRobustSurfaceReference(cb, denseChromaReliability, ...
        faceScale, 'median');
    [denseCrReference, denseCrCoverage] = ...
        beauty.buildRobustSurfaceReference(cr, denseChromaReliability, ...
        faceScale, 'median');
    denseChromaCoverage = min(denseCbCoverage, denseCrCoverage);
end
if ratio > .50
    uniformToneCurve = .36 * fullToneCurve .* ...
        smoothStep(ratio, .50, .75);
    uniformToneSupport = allowed .* structureGate .* ...
        uniformFeatureGate;
else
    uniformToneCurve = 0;
    uniformToneSupport = zeros(imageSize);
end
weightMap = toneCurveMap .* allowed .* structureGate .* featureGate .* ...
    (.08 + .35 * chromaEvidence + .35 * localChromaEvidence + ...
    .20 * blemishEvidence);
weightMap = weightMap + uniformToneCurve .* uniformToneSupport;
denseToneEvidence = smoothStep(denseBlemishField, .05, .55);
denseToneWeight = .70 .* highEndToneGate .* denseAllowedWeight .* ...
    denseToneEvidence .* allowed .* structureGate .* featureGate;
denseToneWeight = min(max(denseToneWeight, 0), .30);
weightMap = weightMap + denseToneWeight;
weightMap = min(max(weightMap, 0), .55);
highEndToneBoost = .22 * highEndToneGate .* ...
    smoothStep(max(max(chromaEvidence, localChromaEvidence), ...
    blemishEvidence), .08, .65) .* allowed .* ...
    structureGate .* featureGate;
weightMap = weightMap + highEndToneBoost;
weightMap = min(max(weightMap, 0), .75);
if ~hasCandidate
    weightMap = zeros(imageSize);
end

% v3.6：dense 重建之后只做轻量 Tone 收尾。高档路径不再把 uniform
% 支撑域当作调色目标，而是要求存在红斑、褐斑或局部色度起伏证据；
% 亮度暗谷与锐边共同形成通用暗结构/光圈保护，不依赖语义字段或
% legacy protection mask。75 档及以下保留上方 v3.5 算术，确保逐位一致。
redResidualEvidence = zeros(imageSize);
brownResidualEvidence = zeros(imageSize);
toneResidualEvidence = zeros(imageSize);
toneResidualGate = zeros(imageSize);
darkStructureEvidence = zeros(imageSize);
darkStructureGate = ones(imageSize);
edgeHaloGate = ones(imageSize);
toneChromaDeltaLimit = Inf;
if highEndToneGate > eps && hasCandidate
    [redResidualEvidence, brownResidualEvidence, darkStructureEvidence, ...
        darkStructureGate, edgeHaloGate] = buildHighEndToneGates( ...
        luminance, cb, cr, candidateCb, candidateCr, faceScale);
    toneResidualEvidence = max(chromaEvidence, localChromaEvidence);
    toneResidualEvidence = max(toneResidualEvidence, ...
        max(redResidualEvidence, brownResidualEvidence));
    toneResidualEvidence = max(toneResidualEvidence, .35 .* ...
        denseToneEvidence);
    toneResidualGate = min(max(toneResidualEvidence, 0), 1) .* ...
        darkStructureGate .* edgeHaloGate;
    denseResidualGate = max(toneResidualGate, .35 .* denseToneEvidence .* ...
        darkStructureGate .* edgeHaloGate);

    % 主分支保留原有候选/色度证据关系，uniform 分支在高档仅作为
    % 诊断参考，不直接制造大面积肤色漂移。dense 分支只增加很小的
    % 局部支持，并再次乘残余证据与保护门。
    weightMap = toneCurveMap .* allowed .* structureGate .* featureGate .* ...
        (.08 + .35 * chromaEvidence + .35 * localChromaEvidence + ...
        .20 * blemishEvidence) .* toneResidualGate;
    densePermission = denseAllowedWeight ./ max(denseChromaCoverage, .05);
    densePermission(denseAllowedWeight <= eps) = 0;
    densePermission = min(max(densePermission, 0), 1);
    denseToneWeight = .62 .* highEndToneGate .* densePermission .* ...
        denseChromaCoverage .* denseToneEvidence .* allowed .* ...
        structureGate .* featureGate .* denseResidualGate;
    denseToneWeight = min(max(denseToneWeight, 0), .42);
    denseChromaDeltaCb = denseToneWeight .* ...
        (denseCbReference - cb);
    denseChromaDeltaCr = denseToneWeight .* ...
        (denseCrReference - cr);
    weightMap = min(max(weightMap + denseToneWeight, 0), .32);
    toneChromaDeltaLimit = .010 + .004 * highEndToneGate;
end

candidateDeltaCb = candidateCb - localCb;
candidateDeltaCr = candidateCr - localCr;
localDeltaCb = localCb - cb;
localDeltaCr = localCr - cr;
if highEndToneGate > eps
    denseToneBlendMap = denseToneEvidence .* double(denseToneWeight > eps);
    localBlend = max(localChromaEvidence, denseToneBlendMap);
    localBlend = max(localBlend, .50 * brownResidualEvidence);
elseif uniformToneCurve > eps
    localBlend = max(localChromaEvidence, double( ...
        uniformToneSupport > eps));
else
    localBlend = localChromaEvidence;
end
if highEndToneGate <= eps
    denseToneBlendMap = denseToneEvidence .* double(denseToneWeight > eps);
    localBlend = max(localBlend, denseToneBlendMap);
end
deltaCb = weightMap .* ((1 - localBlend) .* candidateDeltaCb + ...
    localBlend .* localDeltaCb);
deltaCr = weightMap .* ((1 - localBlend) .* candidateDeltaCr + ...
    localBlend .* localDeltaCr);
deltaCb = deltaCb + denseChromaDeltaCb;
deltaCr = deltaCr + denseChromaDeltaCr;
rawDeltaCb = deltaCb;
rawDeltaCr = deltaCr;
if highEndToneGate > eps
    deltaCb = min(max(deltaCb, -toneChromaDeltaLimit), ...
        toneChromaDeltaLimit);
    deltaCr = min(max(deltaCr, -toneChromaDeltaLimit), ...
        toneChromaDeltaLimit);
end
outputCb = min(max(cb + deltaCb, 0), 1);
outputCr = min(max(cr + deltaCr, 0), 1);

toneResult = struct( ...
    'candidateChroma', struct('cb', candidateCb, 'cr', candidateCr), ...
    'candidateCb', candidateCb, ...
    'candidateCr', candidateCr, ...
    'localCb', localCb, ...
    'localCr', localCr, ...
    'outputCb', outputCb, ...
    'outputCr', outputCr, ...
    'outputLuminance', luminance, ...
    'deltaCb', deltaCb, ...
    'deltaCr', deltaCr, ...
    'weightMap', weightMap, ...
    'alphaMap', weightMap, ...
    'toneSupport', weightMap, ...
    'uniformToneCurve', uniformToneCurve, ...
    'denseBlemishField', denseBlemishField, ...
    'denseAllowedWeight', denseAllowedWeight, ...
    'denseToneEvidence', denseToneEvidence, ...
    'denseToneWeight', denseToneWeight, ...
    'denseCbReference', denseCbReference, ...
    'denseCrReference', denseCrReference, ...
    'denseChromaCoverage', denseChromaCoverage, ...
    'localBlend', localBlend, ...
    'rawDeltaCb', rawDeltaCb, ...
    'rawDeltaCr', rawDeltaCr, ...
    'toneResidualEvidence', toneResidualEvidence, ...
    'toneResidualGate', toneResidualGate, ...
    'redResidualEvidence', redResidualEvidence, ...
    'brownResidualEvidence', brownResidualEvidence, ...
    'darkStructureEvidence', darkStructureEvidence, ...
    'darkStructureGate', darkStructureGate, ...
    'edgeHaloGate', edgeHaloGate, ...
    'toneChromaDeltaLimit', toneChromaDeltaLimit, ...
    'chromaEvidence', chromaEvidence, ...
    'localChromaResidual', localChromaResidual, ...
    'localChromaEvidence', localChromaEvidence, ...
    'blemishEvidence', blemishEvidence, ...
    'candidateMask', double(candidate), ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
toneResult.outputImage = renderToneImage(inputImage, toneResult);

faceMask = min(skinMask, readOptionalMask(beautyMasks, ...
    'faceSkinMask', imageSize));
nonFaceMask = min(skinMask, readOptionalMask(beautyMasks, ...
    'nonFaceSkinMask', imageSize));
diagnostics = struct( ...
    'candidateMask', double(candidate), ...
    'candidateChroma', toneResult.candidateChroma, ...
    'candidateCb', candidateCb, ...
    'candidateCr', candidateCr, ...
    'localCb', localCb, ...
    'localCr', localCr, ...
    'chromaResidual', chromaResidual, ...
    'chromaEvidence', chromaEvidence, ...
    'localChromaResidual', localChromaResidual, ...
    'localChromaEvidence', localChromaEvidence, ...
    'blemishEvidence', blemishEvidence, ...
    'weightMap', weightMap, ...
    'alphaMap', weightMap, ...
    'toneSupport', weightMap, ...
    'uniformToneCurve', uniformToneCurve, ...
    'denseBlemishField', denseBlemishField, ...
    'denseAllowedWeight', denseAllowedWeight, ...
    'denseToneEvidence', denseToneEvidence, ...
    'denseToneWeight', denseToneWeight, ...
    'denseCbReference', denseCbReference, ...
    'denseCrReference', denseCrReference, ...
    'denseChromaCoverage', denseChromaCoverage, ...
    'localBlend', localBlend, ...
    'rawDeltaCb', rawDeltaCb, ...
    'rawDeltaCr', rawDeltaCr, ...
    'toneResidualEvidence', toneResidualEvidence, ...
    'toneResidualGate', toneResidualGate, ...
    'redResidualEvidence', redResidualEvidence, ...
    'brownResidualEvidence', brownResidualEvidence, ...
    'darkStructureEvidence', darkStructureEvidence, ...
    'darkStructureGate', darkStructureGate, ...
    'edgeHaloGate', edgeHaloGate, ...
    'toneChromaDeltaLimit', toneChromaDeltaLimit, ...
    'deltaCb', deltaCb, ...
    'deltaCr', deltaCr, ...
    'faceWeight', weightMap .* double(faceMask > .01), ...
    'nonFaceWeight', weightMap .* double(nonFaceMask > .01), ...
    'hardProtectionMask', hardProtection, ...
    'imageSize', [imageSize, 3], ...
    'smoothingStrength', double(smoothingStrength));
% T33 诊断收口：执行层只消费 stage contract，不再报告 structure/chroma/
% tone 兼容 alias（保护输入由 contract 承载），新增 T07 tone 快照的参考
% 门；hard identity 继续按 T07 约定单独报告。
diagnostics.toneGateSnapshot = 1 - toneContract.tone;
end

function [redEvidence, brownEvidence, darkEvidence, darkGate, haloGate] = ...
        buildHighEndToneGates(luminance, cb, cr, candidateCb, candidateCr, faceScale)
%BUILDHIGHENDTONEGATES 为高档 Tone 提供残余色度与结构保护门。
%   红斑同时具备 Cr 上偏与 Cb 下偏；褐斑在此基础上还需相对邻域
%   偏暗。暗谷与亮度锐边的交集作为通用结构保护，避免调色穿透
%   鼻孔、眼眶、耳甲腔等暗结构，也避免在色斑边界形成光圈。
imageSize = size(luminance);
redCr = smoothStep(max(cr - candidateCr, 0), .006, .035);
redCb = smoothStep(max(candidateCb - cb, 0), .004, .025);
redEvidence = min(redCr, redCb);

luminanceSigma = min(8, max(1.2, .012 * double(faceScale)));
localLuminance = imgaussfilt(luminance, luminanceSigma, ...
    'Padding', 'replicate');
darkResidual = max(localLuminance - luminance, 0);
brownEvidence = min(redCr, smoothStep(darkResidual, .010, .070));

[gradientX, gradientY] = gradient(luminance);
gradientMagnitude = sqrt(gradientX .^ 2 + gradientY .^ 2);
darkEvidence = smoothStep(darkResidual, .018, .100) .* ...
    smoothStep(gradientMagnitude, .012, .080);
darkValueGate = .30 + .70 * smoothStep(luminance, .15, .38);
darkGate = min(max(1 - .90 * darkEvidence, 0), 1) .* darkValueGate;

% 锐边只衰减高档 Tone，不影响亮度、频率或 0--75 档路径；保留
% 至少 25% 的连续通过量，避免保护门本身形成新的硬边。
haloGate = 1 - .75 * smoothStep(gradientMagnitude, .008, .055);
haloGate = min(max(haloGate, .25), 1);

if ~isequal(size(cb), imageSize) || ~isequal(size(cr), imageSize)
    error('beauty:InvalidSkinToneInput', ...
        '高档 Tone 色度门输入尺寸不一致。');
end
end

function candidate = selectToneCandidate(luminance, baseCandidate)
candidate = baseCandidate;
values = luminance(baseCandidate);
if isempty(values)
    return;
end
low = percentileValue(values, .10);
high = percentileValue(values, .90);
candidate = baseCandidate & luminance >= low & luminance <= high;
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFrequency(frequency, imageSize)
for name = {'base', 'mid', 'fine'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
            any(~isfinite(value(:)))
        error('beauty:InvalidSkinToneInput', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
end

function validateMasks(beautyMasks, imageSize)
%VALIDATEMASKS 校验执行层允许读取的 processability/strength 字段。
%   T33 起保护判定全部由 policy 层承担，本层只读 skinMask 与 strengthMap；
%   structure/chroma/hard 等 legacy general mask 不再被读取。
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidSkinToneInput', ...
        '肤色统一需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidSkinToneInput', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    readMask(beautyMasks, required{index}, imageSize);
end
end

function contract = validateToneContract(contract, imageSize)
%VALIDATETONECONTRACT 校验 Tone stage contract（T17）。
%   必需字段：tone（T07 主分支快照）、hard（hard identity）、
%   structureGate/featureGate/uniformFeatureGate（生产端按生产原式计
%   算的未折叠门控字段）与 candidateChromaGate（候选色度保护门限）。
%   缺字段或取值无效一律 fail-fast，不在函数内部重新拼装，也不静默
%   回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'tone', 'hard', 'structureGate', ...
        'featureGate', 'uniformFeatureGate', 'candidateChromaGate'}))
    error('beauty:InvalidSkinToneInput', ...
        'Tone stage contract 必须是包含 tone、hard、structureGate、featureGate、uniformFeatureGate 和 candidateChromaGate 的标量结构。');
end
contract.tone = readMask(contract, 'tone', imageSize);
contract.hard = readMask(contract, 'hard', imageSize);
contract.structureGate = readMask(contract, 'structureGate', imageSize);
contract.featureGate = readMask(contract, 'featureGate', imageSize);
contract.uniformFeatureGate = readMask(contract, ...
    'uniformFeatureGate', imageSize);
contract.candidateChromaGate = readMask(contract, ...
    'candidateChromaGate', imageSize);
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('beauty:InvalidSkinToneInput', ...
        'Beauty Masks 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidSkinToneInput', ...
        'Beauty Masks 字段 %s 无效。', name);
end
value = double(value);
end

function value = readOptionalMask(context, name, imageSize)
if isfield(context, name)
    value = readMask(context, name, imageSize);
else
    value = zeros(imageSize);
end
end

function value = readBlemishMap(value, imageSize)
if isempty(value)
    value = zeros(imageSize);
elseif isstruct(value)
    if isfield(value, 'blemishMap')
        value = value.blemishMap;
    elseif isfield(value, 'confidence')
        value = value.confidence;
    else
        error('beauty:InvalidSkinToneInput', ...
            '瑕疵诊断结构缺少 blemishMap 或 confidence。');
    end
end
value = readStandaloneMask(value, imageSize, 'blemishMap');
end

function [denseField, denseAllowedWeight, denseSurfaceReferenceReliability] = ...
        readDenseRuntimeBlemish( ...
        value, imageSize)
%READDENSERUNTIMEBLEMISH 读取 Repair 发布的 dense 运行期证据。
denseField = zeros(imageSize);
denseAllowedWeight = zeros(imageSize);
denseSurfaceReferenceReliability = zeros(imageSize);
if isempty(value) || ~isstruct(value)
    return;
end
if isfield(value, 'denseBlemishField')
    denseField = readStandaloneMask(value.denseBlemishField, ...
        imageSize, 'denseBlemishField');
end
if isfield(value, 'denseAllowedWeight')
    denseAllowedWeight = readStandaloneMask(value.denseAllowedWeight, ...
        imageSize, 'denseAllowedWeight');
end
if isfield(value, 'denseSurfaceReferenceReliability')
    denseSurfaceReferenceReliability = readStandaloneMask( ...
        value.denseSurfaceReferenceReliability, imageSize, ...
        'denseSurfaceReferenceReliability');
end
end

function value = readStandaloneMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidSkinToneInput', '字段 %s 无效。', name);
end
value = double(value);
end

function faceScale = readFaceScale(beautyMasks, frequency, imageSize)
if isfield(frequency, 'faceScale') && isnumeric(frequency.faceScale) && ...
        isscalar(frequency.faceScale) && isfinite(frequency.faceScale) && ...
        frequency.faceScale > 0
    faceScale = double(frequency.faceScale);
elseif isfield(beautyMasks, 'faceBox')
    faceScale = min(double(beautyMasks.faceBox(3:4)));
else
    faceScale = min(imageSize);
end
end

function outputImage = renderToneImage(inputImage, toneResult)
ycbcr = rgb2ycbcr(im2double(inputImage));
ycbcr(:, :, 2) = toneResult.outputCb;
ycbcr(:, :, 3) = toneResult.outputCr;
outputImage = uint8(round(min(max(ycbcr2rgb(ycbcr), 0), 1) * 255));
inactive = toneResult.weightMap <= eps;
for channel = 1:size(inputImage, 3)
    outputChannel = outputImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(inactive) = sourceChannel(inactive);
    outputImage(:, :, channel) = outputChannel;
end
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function value = percentileValue(values, fraction)
values = sort(double(values(:)));
if isempty(values)
    value = 0;
    return;
end
position = 1 + (numel(values) - 1) * fraction;
lower = floor(position);
upper = ceil(position);
if lower == upper
    value = values(lower);
else
    weight = position - lower;
    value = (1 - weight) * values(lower) + weight * values(upper);
end
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
