function [evidence, metadata] = buildBeautyPolicyEvidence( ...
        inputImage, beautyContext, faceBox, maskDiagnostics)
%BUILDBEAUTYPOLICYEVIDENCE 构建 policy-time 证据层（V4 evidence 层，T06）。
%   只依赖输入图像、semantic 语义和 masks.buildBeautyMasks 的静态诊断，
%   发布当前可稳定取得的连续强度证据，供后续 Region Policy 消费：
%     periocular        — 眼周细节（眼周软带 + 睫毛/眼线 + 双眼皮褶皱）；
%     nostril           — 鼻孔暗谷核心（0/1）；
%     noseStructure     — 鼻部结构（鼻语义支持 × 低频梯度×方向一致性）；
%     lip               — 唇部强度（唇体 + 唇周过渡带）；
%     edgeDetail        — 边缘/线性细节（低频梯度 × 方向一致性）；
%     structureGradient — 结构梯度（皮肤域 P55/P95 分位归一的低频梯度）；
%     darkDetail        — 暗部细节（灰度低通与原图的暗残差 smoothstep）；
%     earStructure      — 耳部结构（T22，耳语义支持域 × 局部结构证据）。
%
%   T22（ear region policy 证据）：earStructure 由耳语义支持域门约束，
%   不使用任何纯几何扩张（工单第 4 条：耳外背景不得被误纳入）：
%     earSupport   = smoothStep(semantic.ear, .20, .45)
%       下/上支撑点沿用 v3.1 probabilityMask 的概率域闭合阈值
%       （.20/.45，见 buildBeautyContextFromParsing），即"耳语义概率
%       进入皮肤域的同一门槛"；因此 earSupport 在 ear semantic < .20
%       处严格为零（真实图 77 实测：耳外非零像素数 0）。
%     structureEvidence = max(edgeDetail, darkDetail)
%       稳定边缘（耳轮/对耳轮脊线，edgeDetail）与暗部沟槽（耳甲腔、
%       耳屏间切迹，darkDetail）取并集：耳轮是亮脊、耳甲腔是暗谷，
%       两者都是"结构"但落在不同的亮度极性上，max 同时覆盖。
%     earStructure = clamp01(earSupport .* structureEvidence)
%       两个因子都是 [0,1]，乘积天然 ∈[0,1]；耳语义支持域之外的像素
%       被 earSupport 精确置零，不产生几何外溢。
%
%   边界纪律：
%     * evidence 是只读旁路产物，不得回写或修改任何生产 protection
%       字段；buildTextureProtectionMask/buildStructureProtectionMask
%       不读取本层，保护计算保持与 evidence 解耦。
%     * 显式不包含 blemish map 与 frequency decomposition 结果：本函数
%       不调用 beauty.buildBlemishMap/beauty.decomposeSkinFrequency，
%       因此构建 evidence 不要求先运行任何运行期阶段，无依赖环。
%     * T09 resize 契约：本层全部字段都依赖输入图像内容（texture/
%       structure 静态诊断与暗部残差均由 inputImage 推导），因此带目
%       标原图的 resize 路径必须经 rebuildBeautyDerivedMasks 在目标分
%       辨率重算本层；没有目标原图的轻量路径不得发布本层，也不得用
%       imresize 缩放预览 evidence 充当目标分辨率证据。
%     * 所有字段都是 HxW double、实数、有限、取值 [0,1]；mask 语义的
%       来源/版本元数据不能混入 evidence 层（normalizeBeautyContextV4
%       把 evidence 的每个字段都按 mask 校验），由第二输出返回并由
%       rebuildBeautyDerivedMasks 挂到 context.diagnostics.policyEvidence。
%
%   输入参数：
%     inputImage      — uint8 三通道 RGB 原图；
%     beautyContext   — 标量 Context（至少含 skinMask/faceBox 基础字段）；
%     faceBox         — [x y width height] 人脸框；
%     maskDiagnostics — masks.buildBeautyMasks 的第二输出，且 texture/
%                       structure 诊断必须完整（桥接在派生字段清空后
%                       以双输出调用即可保证）。

if nargin < 2 || ~isstruct(beautyContext) || ~isscalar(beautyContext)
    error('masks:InvalidContext', '必须提供标量 Beauty Context。');
end
if nargin < 3 || isempty(faceBox)
    if isfield(beautyContext, 'faceBox')
        faceBox = beautyContext.faceBox;
    else
        error('masks:InvalidFaceBox', '必须提供人脸框。');
    end
end
if nargin < 4 || ~isstruct(maskDiagnostics) || ~isscalar(maskDiagnostics)
    error('masks:InvalidDiagnostics', ...
        '必须提供 masks.buildBeautyMasks 的 maskDiagnostics。');
end
validateImageAndFace(inputImage, faceBox);
imageSize = size(inputImage, 1:2);
faceScale = min(double(faceBox(3:4)));

textureDiagnostics = requiredStruct(maskDiagnostics, 'texture');
structureDiagnostics = requiredStruct(maskDiagnostics, 'structure');

% 眼周、鼻孔、唇部：来自 texture protection 的静态诊断。
periocular = clamp01(readDiagnosticsMap(textureDiagnostics, ...
    'eyeDetailProtection', imageSize));
nostril = clamp01(readDiagnosticsMap(textureDiagnostics, ...
    'nostrilCore', imageSize));
lip = clamp01(readDiagnosticsMap(textureDiagnostics, ...
    'lipProtection', imageSize));

% 边缘/线性细节与鼻部结构：来自 structure protection 的静态诊断。
edgeDetail = clamp01(readDiagnosticsMap(structureDiagnostics, ...
    'continuousEvidence', imageSize));
noseSupport = readDiagnosticsMap(structureDiagnostics, ...
    'noseSupport', imageSize);
noseStructure = clamp01(noseSupport .* edgeDetail);

% 结构梯度：与 structure protection 的 gradientEvidence 同配方
% （皮肤支持域 P55/P95 分位 + smoothstep），基于已导出的低频梯度幅值。
skin = readContextMask(beautyContext, 'skinMask', imageSize);
structureGradient = structureGradientEvidence( ...
    readDiagnosticsMap(structureDiagnostics, 'gradientMagnitude', ...
    imageSize), skin, imageSize);

% 暗部细节：独立于 protection 的静态亮度证据，只用输入图像与脸尺度。
grayImage = im2double(rgb2gray(inputImage));
darkSigma = min(2.4, max(.7, .004 * double(faceScale)));
smoothedGray = imgaussfilt(grayImage, darkSigma, 'Padding', 'replicate');
darkResidual = max(smoothedGray - grayImage, 0);
darkDetail = smoothStep(darkResidual, .015, .12);

% 耳部结构（T22）：耳语义支持域门 × 局部结构证据（稳定边缘 + 暗部沟槽）。
% 支持域门复用 v3.1 probabilityMask 的 .20/.45 概率阈值，耳语义概率低于
% .20 的像素（含全部耳外背景）严格置零，不做任何纯几何扩张。
earSupport = smoothStep(readSemanticMask(beautyContext, 'ear', imageSize), ...
    .20, .45);
earStructure = clamp01(earSupport .* max(edgeDetail, darkDetail));

% 颜色敏感皮肤（v3.3）：只在可处理面部皮肤内非零。从原图 YCbCr 的 Cb/Cr 相对
% 普通皮肤稳健中位数的偏差构建连续证据，使用当前图皮肤分位归一而非固定肤色阈值，
% 并与已有 periocular/lip/nostril/noseStructure/earStructure 取 max。
% 普通皮肤参考区排除 hard 与已有高风险证据；参考不足必须显式诊断，不得静默伪造成功。
[colorSensitiveSkin, colorSensitiveDiagnostics] = ...
    buildColorSensitiveSkinEvidence(inputImage, beautyContext, ...
    textureDiagnostics, periocular, lip, nostril, noseStructure, ...
    earStructure, imageSize);

evidence = struct( ...
    'periocular', periocular, ...
    'nostril', nostril, ...
    'noseStructure', noseStructure, ...
    'lip', lip, ...
    'edgeDetail', edgeDetail, ...
    'structureGradient', structureGradient, ...
    'darkDetail', darkDetail, ...
    'earStructure', earStructure, ...
    'colorSensitiveSkin', colorSensitiveSkin);
validateEvidence(evidence, imageSize, beautyContext);

contract = beautyPipelineContract();
metadata = struct( ...
    'builder', 'masks.buildBeautyPolicyEvidence', ...
    'evidenceVersion', 'v3', ...
    'algorithmVersion', contract.algorithmVersion, ...
    'sources', struct( ...
    'periocular', 'maskDiagnostics.texture.eyeDetailProtection', ...
    'nostril', 'maskDiagnostics.texture.nostrilCore', ...
    'noseStructure', 'maskDiagnostics.structure.noseSupport .* continuousEvidence', ...
    'lip', 'maskDiagnostics.texture.lipProtection', ...
    'edgeDetail', 'maskDiagnostics.structure.continuousEvidence', ...
    'structureGradient', 'maskDiagnostics.structure.gradientMagnitude P55/P95', ...
    'darkDetail', 'inputImage dark residual', ...
    'earStructure', 'smoothStep(beautyContext.semantic.ear, .20, .45) .* max(continuousEvidence, darkDetail)', ...
    'colorSensitiveSkin', 'YCbCr Cb/Cr delta from robust normal skin median normalized by skin quantiles max with structure evidence'), ...
    'colorSensitiveSkinDiagnostics', colorSensitiveDiagnostics);
end

function [colorSensitiveSkin, diagnostics] = buildColorSensitiveSkinEvidence( ...
        inputImage, beautyContext, textureDiagnostics, periocular, ...
        lip, nostril, noseStructure, earStructure, imageSize)
faceSkin = readContextMask(beautyContext, 'faceSkinMask', imageSize);
skin = readContextMask(beautyContext, 'skinMask', imageSize);
processableFaceSkin = min(faceSkin, skin) > .05;
if ~any(processableFaceSkin(:))
    colorSensitiveSkin = zeros(imageSize);
    diagnostics = struct('valid', false, 'referenceCount', 0, ...
        'minRequired', 0, 'reason', '可处理面部皮肤为空。');
    return;
end

hardMask = readDiagnosticsMap(textureDiagnostics, 'hardProtectionMask', imageSize) >= .50;
highRisk = periocular > .20 | lip > .20 | nostril > .20 | ...
    noseStructure > .20 | earStructure > .20 | hardMask;
normalSkinReference = processableFaceSkin & ~highRisk & (skin >= .35);
referenceCount = nnz(normalSkinReference);
minRequired = max(30, round(.001 * numel(skin)));

if referenceCount < minRequired
    diagnostics = struct('valid', false, 'referenceCount', referenceCount, ...
        'minRequired', minRequired, 'reason', '普通皮肤参考样本不足。');
    chromaDeviation = zeros(imageSize);
else
    ycbcr = rgb2ycbcr(im2double(inputImage));
    cb = ycbcr(:, :, 2);
    cr = ycbcr(:, :, 3);
    medianCb = median(cb(normalSkinReference));
    medianCr = median(cr(normalSkinReference));
    chromaDelta = hypot(cb - medianCb, cr - medianCr);

    faceDeltas = sort(chromaDelta(processableFaceSkin));
    pLow = percentileValue(faceDeltas, .85);
    pHighRaw = percentileValue(faceDeltas, .98);
    if pHighRaw <= pLow + 1e-4
        chromaDeviation = zeros(imageSize);
        diagnostics = struct('valid', false, 'referenceCount', referenceCount, ...
            'minRequired', minRequired, 'medianCb', medianCb, ...
            'medianCr', medianCr, 'pLow', pLow, 'pHigh', pHighRaw, ...
            'reason', '分位区间退化：低高支撑点过于接近，面部色差无显著变化。');
    else
        pHigh = max(pHighRaw, pLow + 0.005);
        chromaDeviation = smoothStep(chromaDelta, pLow, pHigh) .* ...
            double(processableFaceSkin);
        diagnostics = struct('valid', true, 'referenceCount', referenceCount, ...
            'minRequired', minRequired, 'medianCb', medianCb, ...
            'medianCr', medianCr, 'pLow', pLow, 'pHigh', pHigh, ...
            'reason', '自适应皮肤分位数构建连续色度敏感证据。');
    end
end

% 与五官及高风险结构证据（眼周、唇部、鼻孔、鼻结构、耳部）取 max，并严格限制在可处理面部皮肤内
combined = max(cat(3, chromaDeviation, periocular, lip, nostril, ...
    noseStructure, earStructure), [], 3);
colorSensitiveSkin = clamp01(combined .* double(processableFaceSkin));
colorSensitiveSkin(~processableFaceSkin) = 0;
end

function evidenceValue = structureGradientEvidence(gradientMagnitude, ...
        skin, imageSize)
%STRUCTUREGRADIENTEVIDENCE 把皮肤域低频梯度分位归一为 [0,1] 结构梯度。
skinSupport = skin > .05;
if ~any(skinSupport(:))
    evidenceValue = zeros(imageSize);
    return;
end
gradientValues = sort(gradientMagnitude(skinSupport));
low = percentileValue(gradientValues, .55);
high = max(percentileValue(gradientValues, .95), low + 1e-6);
evidenceValue = smoothStep(gradientMagnitude, low, high);
end

function value = requiredStruct(value, name)
if ~isstruct(value) || ~isscalar(value) || ~isfield(value, name) || ...
        ~isstruct(value.(name)) || ~isscalar(value.(name))
    error('masks:InvalidDiagnostics', ...
        'maskDiagnostics 缺少完整的 %s 诊断，无法构建 policy evidence。', ...
        name);
end
value = value.(name);
end

function value = readDiagnosticsMap(diagnostics, name, imageSize)
value = diagnostics.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:)))
    error('masks:InvalidDiagnostics', ...
        '诊断字段 %s 的尺寸或取值无效。', name);
end
value = double(value);
end

function value = readContextMask(context, name, imageSize)
if ~isfield(context, name)
    error('masks:InvalidContext', 'Context 缺少字段 %s。', name);
end
value = context.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 %s 无效。', name);
end
value = double(value);
end

function value = readSemanticMask(context, name, imageSize)
%READSEMANTICMASK 读取 beautyContext.semantic 的分组语义字段。
%   语义层缺失（partial V4 / compat 路径）、semantic 非法、或缺少该分组
%   字段时返回零矩阵——对应 evidence 字段为零带，输出与 T07 legacy 折叠
%   逐位相等；字段存在但类型/尺寸/取值非法时 fail-fast，不静默修正。
value = zeros(imageSize);
if ~isfield(context, 'semantic') || isempty(context.semantic)
    return;
end
if ~isstruct(context.semantic) || ~isscalar(context.semantic)
    error('masks:InvalidContext', 'Context 字段 semantic 必须是标量结构体。');
end
if ~isfield(context.semantic, name) || isempty(context.semantic.(name))
    return;
end
value = context.semantic.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidContext', 'Context 字段 semantic.%s 无效。', name);
end
value = double(value);
end

function value = clamp01(value)
value = min(max(double(value), 0), 1);
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function value = percentileValue(sortedValues, fraction)
index = 1 + round(fraction * (numel(sortedValues) - 1));
value = sortedValues(index);
end

function validateEvidence(evidence, imageSize, beautyContext)
fieldNames = fieldnames(evidence);
for index = 1:numel(fieldNames)
    name = fieldNames{index};
    value = evidence.(name);
    if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), ...
            imageSize) || any(~isfinite(value(:))) || ...
            any(value(:) < 0) || any(value(:) > 1)
        error('masks:InvalidEvidence', ...
            'evidence 字段 %s 的尺寸、类型或取值范围无效。', name);
    end
end
if isfield(evidence, 'colorSensitiveSkin') && nargin >= 3 && ~isempty(beautyContext)
    faceSkin = readContextMask(beautyContext, 'faceSkinMask', imageSize);
    skin = readContextMask(beautyContext, 'skinMask', imageSize);
    processableFaceSkin = min(faceSkin, skin) > .05;
    if any(evidence.colorSensitiveSkin(~processableFaceSkin) > 0)
        error('masks:InvalidEvidence', ...
            'colorSensitiveSkin 在可处理面部皮肤外必须严格为零。');
    end
end
end

function validateImageAndFace(inputImage, faceBox)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('masks:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > size(inputImage, 2) || ...
        faceBox(2) + faceBox(4) - 1 > size(inputImage, 1)
    error('masks:InvalidFaceBox', '人脸框超出图像范围。');
end
end
