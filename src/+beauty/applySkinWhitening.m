function [whiteningResult, diagnostics] = applySkinWhitening( ...
        inputImage, frequency, beautyMasks, whiteningStrength, ...
        whiteningContract)
%APPLYSKINWHITENING 生成受保护的低频亮度提亮结果。
%   美白只产生亮度增量，不读取或修改 Fine/Mid。强度曲线连续单调，
%   增量由保护门控、硬保护和当前低频高光余量共同限制，最终由
%   composeBeautyResult 一次合成。
%
%   T18：可选第 5 参数 whiteningContract 是 Whitening 的 stage
%   contract，由 beautifyImage 生产端从与生产门控共用的同一份
%   beautyMasks 产物拼装传入（T12--T17 范式）。提供时 supportBase 的
%   保护门控只来自 contract，不再自行解释 general structure/whitening
%   masks；肤色亮度变换与 strength 公式不变。字段语义：
%     whitening       — T07 发布的 stage protection 快照
%                       whitening = 1 - structureGateWhitening .*
%                       (1 - whitening)（脸部浅退让分支已折叠）；该
%                       折叠含 1-x 补码往返舍入，无法逐位还原门控积
%                       structureGate .* featureSetback，因此快照不
%                       参与输出算术，只作为 T07 参考门由诊断
%                       （whiteningGateSnapshot）与测试消费；
%     hard            — hard identity（T07 单独发布），按生产原位
%                       组合进亮度统计选点（hard < .999）与 allowed
%                       的 (1-hard) 乘子；
%     structureGate   — 未折叠结构门，含生产原位的脸部/脸外差异分
%                       支：全场 1 - structure，脸部（faceSkinMask
%                       >= .5）浅退让为 1 - .10*structure（避免整个
%                       鼻部语义阻断美白）；
%     featureGate     — 未折叠五官退让门 1 - whitening（消费侧按生
%                       产原式做 [0,1] 截断）；
%     featureZeroGate — double(whitening <= eps)（亮度统计选点的五
%                       官零保护门限，生产原式原样发布）。
%   运行期由生产端按与 legacy 完全相同的表达式、同一份 mask 产物计
%   算未折叠字段，消费侧按生产原式、原顺序重建门控，与 legacy 路径
%   逐位等价（bit-exact）。缺字段 fail-fast，不在函数内部重新拼装，
%   也不静默回退；未提供第 5 参的旧调用方走 legacy 兼容路径，行为
%   不变。processability（skinMask）与强度（strengthMap）不属于
%   protection，两条路径都继续从 beautyMasks 读取并显式控制效果幅
%   度；脸部 allowed 下限与鼻部幅度封顶属强度侧区域 policy，两条路
%   径共用同一读取，strength 与 protection 不合并。

if nargin < 4
    error('beauty:InvalidWhiteningInput', ...
        '美白需要输入图像、频率结构、Beauty Masks 和美白强度。');
end
useStageContract = nargin >= 5 && ~isempty(whiteningContract);
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
% T18：保护门控来源二选一。stage 路径只消费 contract（快照不参与输
% 出算术，脸部/脸外差异分支由生产端在未折叠 structureGate 上原样保
% 留）；legacy 路径保持对 general structure/whitening/hard masks 的
% 原解释与数值。两条路径的门控字段按同一表达式、同一份 mask 产物取
% 得，数值逐位一致。
if useStageContract
    whiteningContract = validateWhiteningContract( ...
        whiteningContract, imageSize);
    hardProtection = whiteningContract.hard;
    structureGate = whiteningContract.structureGate;
    featureSetback = min(max(whiteningContract.featureGate, 0), 1);
    featureZeroGate = whiteningContract.featureZeroGate;
else
    structureProtection = readMask(beautyMasks, ...
        'structureProtectionMask', imageSize);
    whiteningProtection = readOptionalMask(beautyMasks, ...
        'whiteningProtectionMask', imageSize);
    hardProtection = readOptionalMask(beautyMasks, ...
        'hardProtectionMask', imageSize);
    structureGate = 1 - structureProtection;
    faceSkin = faceSkinMask >= .5;
    % 脸部结构只做浅退让；过强的软门控会让眉周近区比远区
    % 少获得一档美白，形成可量化的亮度断层。
    structureGate(faceSkin) = 1 - .10 * structureProtection(faceSkin);
    featureSetback = 1 - whiteningProtection;
    featureSetback = min(max(featureSetback, 0), 1);
    featureZeroGate = whiteningProtection <= eps;
end

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
% 没有真实鼻部结构的输入保留完整连续曲线；存在鼻部结构时仅在
% 高档封顶，避免高对比侧脸在 RGB 裁切后丢失鼻梁/鼻侧结构。
whiteningAmplitude = .20 * whiteningCurve;
hasNoseStructure = isfield(beautyMasks, 'noseMask') && ...
    any(beautyMasks.noseMask(:) > .5);
if hasNoseStructure
    whiteningAmplitude = min(whiteningAmplitude, .07);
end
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
if ~useStageContract
    % legacy 兼容路径继续报告 whiteningProtectionMask 原图；stage 路
    % 径的保护输入由 contract 承载，不再报告 general alias（T18）。
    whiteningResult.whiteningProtectionMask = whiteningProtection;
end
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
if useStageContract
    % T18 诊断收口：stage 路径不再报告 structure/whitening 兼容
    % alias（保护输入由 contract 承载），新增 T07 whitening 快照的
    % 参考门；hard identity 继续按 T07 约定单独报告。
    diagnostics.whiteningGateSnapshot = 1 - whiteningContract.whitening;
else
    diagnostics.whiteningProtectionMask = whiteningProtection;
    diagnostics.structureProtectionMask = structureProtection;
end
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
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks)
    error('beauty:InvalidWhiteningInput', ...
        '美白需要标量 v3 Beauty Masks。');
end
required = {'skinMask', 'strengthMap', 'structureProtectionMask'};
for index = 1:numel(required)
    if ~isfield(beautyMasks, required{index})
        error('beauty:InvalidWhiteningInput', ...
            'Beauty Masks 缺少字段 %s。', required{index});
    end
    readMask(beautyMasks, required{index}, imageSize);
end
if isfield(beautyMasks, 'whiteningProtectionMask')
    readMask(beautyMasks, 'whiteningProtectionMask', imageSize);
end
end

function contract = validateWhiteningContract(contract, imageSize)
%VALIDATEWHITENINGCONTRACT 校验 Whitening stage contract（T18）。
%   必需字段：whitening（T07 快照）、hard（hard identity）、
%   structureGate（含脸部/脸外差异分支的未折叠结构门）、featureGate
%   （未折叠五官退让门）与 featureZeroGate（统计选点的五官零保护门
%   限）。缺字段或取值无效一律 fail-fast，不在函数内部重新拼装，也
%   不静默回退到 general masks 解释。
if ~isstruct(contract) || ~isscalar(contract) || ...
        ~all(isfield(contract, {'whitening', 'hard', 'structureGate', ...
        'featureGate', 'featureZeroGate'}))
    error('beauty:InvalidWhiteningInput', ...
        'Whitening stage contract 必须是包含 whitening、hard、structureGate、featureGate 和 featureZeroGate 的标量结构。');
end
contract.whitening = readMask(contract, 'whitening', imageSize);
contract.hard = readMask(contract, 'hard', imageSize);
contract.structureGate = readMask(contract, 'structureGate', imageSize);
contract.featureGate = readMask(contract, 'featureGate', imageSize);
contract.featureZeroGate = readMask(contract, 'featureZeroGate', ...
    imageSize);
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
