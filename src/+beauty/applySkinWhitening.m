function [whiteningResult, diagnostics] = applySkinWhitening( ...
        inputImage, frequency, beautyMasks, whiteningStrength, ...
        whiteningContract)
%APPLYSKINWHITENING 生成受保护的低频亮度提亮结果。
%   美白只产生亮度增量，不读取或修改 Fine/Mid。强度曲线连续单调，
%   增量由保护门控、硬保护和当前低频高光余量共同限制，最终由
%   composeBeautyResult 一次合成。
%
%   T33（执行契约）：可选第 5 参数 whiteningContract 是 Whitening 的 stage
%   contract，由唯一组装点 +beauty/whiteningStageContract 从 V4 stage
%   protection 的规范门组装（生产组装层 beautifyImage 与兼容入口共用同一份
%   实现）。执行层是**纯执行器**：只消费 contract 与 strength/processability
%   层，不读取任何 semantic / evidence / legacy general protection mask
%   （structure/whitening/hard）或 noseMask。肤色亮度变换与 strength 公式
%   不变。
%   读取集合（上位契约第 1 节）：
%     frequency.sourceLuminance / base —— 输入图像的亮度与低频分解结果；
%     beautyMasks.skinMask / strengthMap / faceSkinMask / faceBox ——
%       processability 与 strength 层（非保护判定；faceSkinMask 只用于
%       脸部 allowed 下限）；
%     whiteningContract.hard —— 独立 hard identity（生产原位 (1-hard) 乘子）；
%     whiteningContract.structureGate / featureGate —— 逐像素修改门因子
%       （policy 层按生产原式一次算好并发布，featureGate 已含 T30
%       regionBandWhitening 的高风险区退让）；
%     whiteningContract.featureZeroGate —— 亮度参考统计选点门
%       （= 1 - support.whitening）；
%     whiteningContract.amplitudeCeiling —— 鼻部退让幅度上限（policy 层判定）。
%   统一权重函数（上位契约第 2 节）：
%     targetWeight  = strength × processabilitySkin × (1 - targetProtection)
%                     → supportBase = allowed .* highlightProtection
%                       .* structureGate .* featureSetback
%     supportWeight = validSkinReference × (1 - supportProtection)
%                     → featureZeroGate（亮度统计选点门）
%   其中 allowed = min(skinMask, strengthMap) .* (1 - hard)，脸部 allowed 下限
%   属 strength 侧区域 policy（保持既有数值）。target.whitening/
%   support.whitening 是 policy 层发布的规范双门控（1 - 该值 即逐像素门控积
%   与统计选点门；因 T07 折叠含 1-x 补码往返舍入，执行层消费 policy 发布的
%   未折叠因子以保证与 legacy 逐位等价）。
%   高风险区退让（上位契约 3.5）：原 applySkinWhitening 读 beautyMasks.noseMask
%   做"存在鼻部结构时幅度封顶"的特殊分支已移除，等价语义由 policy 层发布在
%   whiteningAmplitudeCeiling（幅度上限）与 whiteningGates.featureGate
%   （T30 regionBandWhitening 的 eye/lip/nostril 逐像素退让）上；鼻翼/唇周/
%   眼周退让因此全部经 target.whitening 家族表达，执行层不再读 legacy mask。
%   兼容入口（未提供第 5 参的旧调用方）：不再自行解释 legacy general masks，
%   而是向 policy 层索取零带 stageProtection 并经同一组装点得到零带 contract。
%   缺字段 fail-fast，不在函数内部重新拼装。

if nargin < 4
    error('beauty:InvalidWhiteningInput', ...
        '美白需要输入图像、频率结构、Beauty Masks 和美白强度。');
end
validateImage(inputImage);
imageSize = size(inputImage, 1:2);
validateFrequency(frequency, imageSize);
validateMasks(beautyMasks, imageSize);
if ~isValidStrength(whiteningStrength)
    error('beauty:InvalidStrength', '美白强度必须是 0 到 100 的数值标量。');
end

sourceLuminance = double(frequency.sourceLuminance);
base = double(frequency.base);
skinMask = readMask(beautyMasks, 'skinMask', imageSize);
strengthMap = readMask(beautyMasks, 'strengthMap', imageSize);
faceSkinMask = readOptionalMask(beautyMasks, 'faceSkinMask', imageSize);
% T33：保护门控只来自 contract。兼容入口（未提供第 5 参的旧调用方）不再
% 自行解释 general structure/whitening/hard masks，而是向 policy 层索取零带
% stageProtection（masks.buildStageProtectionMasks(beautyMasks)），经唯一
% 组装点 +beauty/whiteningStageContract 得到零带 contract，与生产路径共用
% 同一份 Single Protection Authority。执行层只消费 target.whitening/
% support.whitening 与 policy 发布的未折叠门控，缺字段 fail-fast，不在函数
% 内部重新拼装。
if nargin < 5 || isempty(whiteningContract)
    stageProtection = masks.buildStageProtectionMasks(beautyMasks);
    whiteningContract = beauty.whiteningStageContract(stageProtection);
end
whiteningContract = validateWhiteningContract(whiteningContract, imageSize);
hardProtection = whiteningContract.hard;
structureGate = whiteningContract.structureGate;
featureSetback = min(max(whiteningContract.featureGate, 0), 1);
featureZeroGate = whiteningContract.featureZeroGate;
amplitudeCeiling = whiteningContract.amplitudeCeiling;

skinPixels = skinMask >= .50 & strengthMap > .05 & ...
    hardProtection < .999 & featureZeroGate & ...
    base < .90;
if any(skinPixels(:))
    luminanceValues = sourceLuminance(skinPixels);
    medianLuminance = median(luminanceValues);
    upperLuminance = percentileValue(luminanceValues, .85);
else
    medianLuminance = .78;
    upperLuminance = .78;
end
brightnessNeed = min(max((.78 - medianLuminance) / .35, .18), 1);
globalHeadroom = min(max((.98 - upperLuminance) / .20, .15), 1);

ratio = double(whiteningStrength) / 100;
whiteningCurve = ratio ^ .85;
highlightProtection = min(max((.985 - base) / .18, 0), 1);
% 高光保护采用低频亮度判断，避免被 Fine/Mid 的细节误导。
highlightProtection = highlightProtection .^ .80;
allowed = min(skinMask, strengthMap) .* (1 - hardProtection);

% 五官过渡由特征身份和人脸尺度单独生成，不能再用色度保护代替；
% T18 起五官退让门与结构门一样由保护来源二选一承载（stage 路径取
% contract，legacy 路径取 general masks），见上方分支。
faceScale = readFaceScale(frequency, beautyMasks, imageSize);
chromaGate = ones(imageSize);

% 合格脸部皮肤在五官近区仍可能因语义边界羽化而只有 0.5--0.7
% 的 strengthMap；直接相乘会制造近区/远区亮度断层。脸部使用
% 连续的最小作用权重，脸外仍保留原有弱化 strengthMap。
faceStrength = faceSkinMask >= .5;
allowed(faceStrength) = max(allowed(faceStrength), .85);

supportBase = allowed .* highlightProtection .* structureGate .* ...
    featureSetback;
whiteningSupport = whiteningCurve .* supportBase;
whiteningSupport = min(max(whiteningSupport, 0), 1);
% supportBase 不含强度曲线，避免把 whiteningCurve 重复相乘。
% T33 高风险区退让（上位契约 3.5）：原实现读 beautyMasks.noseMask 判定
% "存在鼻部结构时仅在幅度上封顶"，属执行层特殊分支；现由 policy 层一次
% 判定并发布幅度上限（whiteningAmplitudeCeiling），执行层只按上限截断。
% 无鼻部结构时上限为 Inf，min(x, Inf) = x 逐位还原生产原式；有鼻部结构
% 时为 .07，与旧分支字面量一致，逐位等价。鼻翼/唇周/眼周的逐像素退让
% 由 policy 发布在 whiteningGates.featureGate（regionBandWhitening）上，
% 与 target.whitening 同源。
whiteningAmplitude = .20 * whiteningCurve;
whiteningAmplitude = min(whiteningAmplitude, amplitudeCeiling);
whiteningDelta = whiteningAmplitude * brightnessNeed * globalHeadroom .* ...
    supportBase;
whiteningDelta = min(max(whiteningDelta, 0), ...
    max(.001, whiteningAmplitude * brightnessNeed));
outputLuminance = min(max(sourceLuminance + whiteningDelta, 0), 1);

whiteningResult = struct( ...
    'whiteningCurve', whiteningCurve, ...
    'brightnessNeed', brightnessNeed, ...
    'globalHeadroom', globalHeadroom, ...
    'highlightProtection', highlightProtection, ...
    'structureGate', structureGate, ...
    'faceSkinMask', faceSkinMask, ...
    'chromaGate', chromaGate, ...
    'whiteningGate', featureSetback, ...
    'faceScale', faceScale, ...
    'toneGate', chromaGate, ...
    'featureSetback', featureSetback, ...
    'supportMap', whiteningSupport, ...
    'alphaMap', whiteningSupport, ...
    'whiteningSupport', whiteningSupport, ...
    'delta', whiteningDelta, ...
    'luminanceDelta', whiteningDelta, ...
    'whiteningDelta', whiteningDelta, ...
    'baseBefore', base, ...
    'baseAfter', base + whiteningDelta, ...
    'fineBefore', double(frequency.fine), ...
    'fineAfter', double(frequency.fine), ...
    'midBefore', double(frequency.mid), ...
    'midAfter', double(frequency.mid), ...
    'fineRetention', 1, ...
    'mediumRetention', 1, ...
    'outputLuminance', outputLuminance, ...
    'imageSize', [imageSize, 3], ...
    'whiteningStrength', double(whiteningStrength));
whiteningResult.outputImage = renderWhiteningImage(inputImage, ...
    outputLuminance);

diagnostics = struct( ...
    'whiteningCurve', whiteningCurve, ...
    'brightnessNeed', brightnessNeed, ...
    'globalHeadroom', globalHeadroom, ...
    'highlightProtection', highlightProtection, ...
    'structureGate', structureGate, ...
    'faceSkinMask', faceSkinMask, ...
    'chromaGate', chromaGate, ...
    'whiteningGate', featureSetback, ...
    'faceScale', faceScale, ...
    'toneGate', chromaGate, ...
    'featureSetback', featureSetback, ...
    'supportMap', whiteningSupport, ...
    'alphaMap', whiteningSupport, ...
    'whiteningSupport', whiteningSupport, ...
    'delta', whiteningDelta, ...
    'luminanceDelta', whiteningDelta, ...
    'whiteningDelta', whiteningDelta, ...
    'outputLuminance', outputLuminance, ...
    'fineRetention', 1, ...
    'mediumRetention', 1, ...
    'skinPixels', skinPixels, ...
    'hardProtectionMask', hardProtection, ...
    'imageSize', [imageSize, 3], ...
    'whiteningStrength', double(whiteningStrength));
% T33 诊断收口：执行层只消费 stage contract，不再报告 structure/whitening
% 兼容 alias（保护输入由 contract 承载），新增 T07 whitening 快照的参考门
% 与鼻部幅度上限；hard identity 继续按 T07 约定单独报告。
diagnostics.whiteningGateSnapshot = 1 - whiteningContract.whitening;
diagnostics.amplitudeCeiling = amplitudeCeiling;
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('beauty:InvalidWhiteningInput', ...
        '美白输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFrequency(frequency, imageSize)
if ~isstruct(frequency) || ~isscalar(frequency) || ...
        ~all(isfield(frequency, {'sourceLuminance', 'base', 'mid', 'fine'}))
    error('beauty:InvalidWhiteningInput', ...
        '美白需要完整的亮度和 Base/Mid/Fine 频率结构。');
end
for name = {'sourceLuminance', 'base', 'mid', 'fine'}
    value = frequency.(name{1});
    if ~isnumeric(value) || ~isreal(value) || ...
            ~isequal(size(value), imageSize) || any(~isfinite(value(:)))
        error('beauty:InvalidWhiteningInput', ...
            '频率字段 %s 的尺寸或取值无效。', name{1});
    end
end
end

function validateMasks(beautyMasks, imageSize)
%VALIDATEMASKS 校验执行层允许读取的 processability/strength 字段。
%   T33 起保护判定全部由 policy 层承担，本层只读 skinMask 与 strengthMap；
%   structure/whitening/hard/nose 等 legacy general mask 不再被读取。
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidWhiteningInput', ...
        '美白需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidWhiteningInput', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    readMask(beautyMasks, required{index}, imageSize);
end
end

function contract = validateWhiteningContract(contract, imageSize)
%VALIDATEWHITENINGCONTRACT 校验 Whitening stage contract（T18/T33）。
%   必需字段：whitening（T07 快照）、hard（hard identity）、
%   structureGate（含脸部/脸外差异分支的未折叠结构门）、featureGate
%   （未折叠五官退让门）、featureZeroGate（统计选点的五官零保护门限）
%   与 amplitudeCeiling（鼻部退让幅度上限）。缺字段或取值无效一律
%   fail-fast，不在函数内部重新拼装，也不静默回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'whitening', 'hard', 'structureGate', ...
        'featureGate', 'featureZeroGate', 'amplitudeCeiling'}))
    error('beauty:InvalidWhiteningInput', ...
        'Whitening stage contract 必须是包含 whitening、hard、structureGate、featureGate、featureZeroGate 和 amplitudeCeiling 的标量结构。');
end
contract.whitening = readMask(contract, 'whitening', imageSize);
contract.hard = readMask(contract, 'hard', imageSize);
contract.structureGate = readMask(contract, 'structureGate', imageSize);
contract.featureGate = readMask(contract, 'featureGate', imageSize);
contract.featureZeroGate = readMask(contract, 'featureZeroGate', ...
    imageSize);
ceiling = contract.amplitudeCeiling;
if ~isnumeric(ceiling) || ~isreal(ceiling) || ~isscalar(ceiling) || ...
        isnan(ceiling) || ceiling <= 0
    error('beauty:InvalidWhiteningInput', ...
        'Whitening stage contract 的 amplitudeCeiling 无效。');
end
contract.amplitudeCeiling = double(ceiling);
end

function value = readMask(context, name, imageSize)
if ~isfield(context, name)
    error('beauty:InvalidWhiteningInput', ...
        'Beauty Masks 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidWhiteningInput', ...
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

function faceScale = readFaceScale(frequency, beautyMasks, imageSize)
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

function outputImage = renderWhiteningImage(inputImage, outputLuminance)
ycbcr = rgb2ycbcr(double(inputImage) / 255);
sourceLuminance = ycbcr(:, :, 1);
ycbcr(:, :, 1) = outputLuminance;
outputImage = uint8(round(min(max(ycbcr2rgb(ycbcr), 0), 1) * 255));
inactive = abs(outputLuminance - sourceLuminance) <= eps;
for channel = 1:size(inputImage, 3)
    outputChannel = outputImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(inactive) = sourceChannel(inactive);
    outputImage(:, :, channel) = outputChannel;
end
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end
