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
%     darkDetail        — 暗部细节（灰度低通与原图的暗残差 smoothstep）。
%
%   边界纪律：
%     * evidence 是只读旁路产物，不得回写或修改任何生产 protection
%       字段；buildTextureProtectionMask/buildStructureProtectionMask
%       不读取本层，保护计算保持与 evidence 解耦。
%     * 显式不包含 blemish map 与 frequency decomposition 结果：本函数
%       不调用 beauty.buildBlemishMap/beauty.decomposeSkinFrequency，
%       因此构建 evidence 不要求先运行任何运行期阶段，无依赖环。
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

evidence = struct( ...
    'periocular', periocular, ...
    'nostril', nostril, ...
    'noseStructure', noseStructure, ...
    'lip', lip, ...
    'edgeDetail', edgeDetail, ...
    'structureGradient', structureGradient, ...
    'darkDetail', darkDetail);
validateEvidence(evidence, imageSize);

contract = beautyPipelineContract();
metadata = struct( ...
    'builder', 'masks.buildBeautyPolicyEvidence', ...
    'evidenceVersion', 'v1', ...
    'algorithmVersion', contract.algorithmVersion, ...
    'sources', struct( ...
    'periocular', 'maskDiagnostics.texture.eyeDetailProtection', ...
    'nostril', 'maskDiagnostics.texture.nostrilCore', ...
    'noseStructure', 'maskDiagnostics.structure.noseSupport .* continuousEvidence', ...
    'lip', 'maskDiagnostics.texture.lipProtection', ...
    'edgeDetail', 'maskDiagnostics.structure.continuousEvidence', ...
    'structureGradient', 'maskDiagnostics.structure.gradientMagnitude P55/P95', ...
    'darkDetail', 'inputImage dark residual'));
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

function validateEvidence(evidence, imageSize)
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
