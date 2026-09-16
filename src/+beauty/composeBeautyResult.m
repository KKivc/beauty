function [beautifiedImage, diagnostics] = composeBeautyResult( ...
        inputImage, frequency, smoothedFrequency, beautyMasks, ...
        whiteningStrength, processing)
%COMPOSEBEAUTYRESULT 使用一个连续 Alpha Map 合成 v3 结果。
%   保护区域不通过脸部/脸外结果拼接，而是在同一张全图 Alpha 上
%   完成一次主合成。可选的 processing 参数承载瑕疵、统一肤色和
%   美白模块的诊断/结果；省略时仍由本函数调用独立美白模块。

if nargin < 4 || ~isValidRgbImage(inputImage) || ...
        ~isstruct(frequency) || ~isstruct(smoothedFrequency) || ...
        ~isstruct(beautyMasks)
    error('beauty:InvalidComposeInput', ...
        '合成需要输入图像、频率结构和 v3 Beauty Masks。');
end
if nargin < 5 || isempty(whiteningStrength)
    whiteningStrength = 0;
end
if ~isValidStrength(whiteningStrength)
    error('beauty:InvalidStrength', '美白强度必须是 0 到 100 的数值标量。');
end
if nargin < 6 || isempty(processing)
    processing = struct();
elseif ~isstruct(processing) || ~isscalar(processing)
    error('beauty:InvalidComposeInput', '处理结果必须是标量结构体。');
end
imageSize = size(inputImage, 1:2);
if ~isfield(frequency, 'sourceLuminance') || ...
        ~isequal(size(frequency.sourceLuminance), imageSize) || ...
        ~isfield(smoothedFrequency, 'outputLuminance') || ...
        ~isequal(size(smoothedFrequency.outputLuminance), imageSize) || ...
        ~isfield(smoothedFrequency, 'alphaMap') || ...
        ~isequal(size(smoothedFrequency.alphaMap), imageSize)
    error('beauty:InvalidComposeInput', '频率结构的尺寸不匹配。');
end
requiredMasks = {'strengthMap', 'hardProtectionMask'};
if ~all(isfield(beautyMasks, requiredMasks))
    error('beauty:InvalidMasks', 'v3 Beauty Masks 缺少合成字段。');
end
readMask(beautyMasks.strengthMap, imageSize, 'strengthMap');
hardProtection = readMask(beautyMasks.hardProtectionMask, ...
    imageSize, 'hardProtectionMask');
smoothingAlpha = readMask(smoothedFrequency.alphaMap, ...
    imageSize, 'alphaMap');
sourceLuminance = double(frequency.sourceLuminance);
smoothingDelta = double(smoothedFrequency.outputLuminance) - ...
    sourceLuminance;

baseSupport = zeros(imageSize);
baseDelta = zeros(imageSize);
if isfield(processing, 'baseLuminance')
    baseResult = processing.baseLuminance;
    validateBaseLuminanceResult(baseResult, imageSize);
    baseSupport = readMask(baseResult.supportMap, imageSize, ...
        'baseSupport');
    baseDelta = readSignedDelta(baseResult.baseDelta, imageSize, ...
        'baseDelta');
elseif isfield(processing, 'evenSkinLuminance')
    baseResult = processing.evenSkinLuminance;
    validateBaseLuminanceResult(baseResult, imageSize);
    baseSupport = readMask(baseResult.supportMap, imageSize, ...
        'baseSupport');
    baseDelta = readSignedDelta(baseResult.baseDelta, imageSize, ...
        'baseDelta');
elseif isfield(processing, 'baseLuminanceResult')
    baseResult = processing.baseLuminanceResult;
    validateBaseLuminanceResult(baseResult, imageSize);
    baseSupport = readMask(baseResult.supportMap, imageSize, ...
        'baseSupport');
    baseDelta = readSignedDelta(baseResult.baseDelta, imageSize, ...
        'baseDelta');
elseif isfield(processing, 'evenSkinLuminanceResult')
    baseResult = processing.evenSkinLuminanceResult;
    validateBaseLuminanceResult(baseResult, imageSize);
    baseSupport = readMask(baseResult.supportMap, imageSize, ...
        'baseSupport');
    baseDelta = readSignedDelta(baseResult.baseDelta, imageSize, ...
        'baseDelta');
end

if isfield(processing, 'whitening')
    whiteningResult = processing.whitening;
    validateWhiteningResult(whiteningResult, imageSize);
else
    [whiteningResult, ~] = beauty.applySkinWhitening(inputImage, ...
        frequency, beautyMasks, whiteningStrength);
end
whiteningSupport = readMask(whiteningResult.supportMap, imageSize, ...
    'whiteningSupport');
whiteningDelta = readMask(whiteningResult.delta, imageSize, ...
    'whiteningDelta');

toneSupport = zeros(imageSize);
toneDeltaCb = zeros(imageSize);
toneDeltaCr = zeros(imageSize);
if isfield(processing, 'skinTone')
    toneResult = processing.skinTone;
    validateToneResult(toneResult, imageSize);
    toneSupport = readMask(toneResult.toneSupport, imageSize, ...
        'toneSupport');
    sourceYcbcr = rgb2ycbcr(im2double(inputImage));
    toneDeltaCb = double(toneResult.outputCb) - sourceYcbcr(:, :, 2);
    toneDeltaCr = double(toneResult.outputCr) - sourceYcbcr(:, :, 3);
end

ycbcr = rgb2ycbcr(im2double(inputImage));
% 所有亮度 Delta 都已经在各自模块中完成计权；Alpha 只用于统一记录
% 支持范围和保留无作用区域，不再把同一作用权重乘第二次。
alphaMap = min(1, max(cat(3, smoothingAlpha, baseSupport, ...
    whiteningSupport, toneSupport), [], 3));
delta = smoothingDelta + baseDelta + whiteningDelta;
targetLuminance = min(max(sourceLuminance + delta, 0), 1);
outputLuminance = targetLuminance;
inactive = alphaMap <= eps;
outputLuminance(inactive) = sourceLuminance(inactive);

ycbcr(:, :, 1) = outputLuminance;
sourceCb = ycbcr(:, :, 2);
sourceCr = ycbcr(:, :, 3);
toneTargetCb = min(max(sourceCb + toneDeltaCb, 0), 1);
toneTargetCr = min(max(sourceCr + toneDeltaCr, 0), 1);
ycbcr(:, :, 2) = toneTargetCb;
ycbcr(:, :, 3) = toneTargetCr;
outputDouble = min(max(ycbcr2rgb(ycbcr), 0), 1);
beautifiedImage = uint8(round(outputDouble * 255));
inactive = alphaMap <= eps;
for channel = 1:size(inputImage, 3)
    outputChannel = beautifiedImage(:, :, channel);
    sourceChannel = inputImage(:, :, channel);
    outputChannel(inactive) = sourceChannel(inactive);
    outputChannel(hardProtection >= .999) = sourceChannel( ...
        hardProtection >= .999);
    beautifiedImage(:, :, channel) = outputChannel;
end
if ~isequal(size(beautifiedImage), size(inputImage))
    error('beauty:InvalidOutput', 'v3 合成结果没有保持输入图像尺寸。');
end

diagnostics = struct( ...
    'alphaMap', alphaMap, ...
    'smoothingAlpha', smoothingAlpha, ...
    'baseSupport', baseSupport, ...
    'baseDelta', baseDelta, ...
    'whiteningSupport', whiteningSupport, ...
    'toneSupport', toneSupport, ...
    'smoothingDelta', smoothingDelta, ...
    'whiteningDelta', whiteningDelta, ...
    'toneDeltaCb', toneDeltaCb, ...
    'toneDeltaCr', toneDeltaCr, ...
    'toneTargetCb', toneTargetCb, ...
    'toneTargetCr', toneTargetCr, ...
    'targetLuminance', targetLuminance, ...
    'luminanceDelta', delta, ...
    'outputLuminance', outputLuminance, ...
    'hardProtectionMask', hardProtection, ...
    'backgroundUnchanged', maxChange(inputImage, beautifiedImage, ...
    alphaMap <= eps), ...
    'hardProtectionUnchanged', maxChange(inputImage, beautifiedImage, ...
    hardProtection >= .999));
end

function valid = isValidRgbImage(image)
valid = isa(image, 'uint8') && isreal(image) && ndims(image) == 3 && ...
    size(image, 3) == 3;
end

function valid = isValidStrength(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 100;
end

function value = readMask(value, imageSize, name)
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || any(~isfinite(value(:))) || ...
        any(value(:) < 0) || any(value(:) > 1)
    error('beauty:InvalidMasks', 'Mask %s 无效。', name);
end
value = double(value);
end

function validateBaseLuminanceResult(result, imageSize)
if ~isstruct(result) || ~isscalar(result) || ...
        ~all(isfield(result, {'supportMap', 'baseDelta'}))
    error('beauty:InvalidComposeInput', ...
        'Base 亮度均匀化结果缺少 supportMap 或 baseDelta。');
end
readMask(result.supportMap, imageSize, 'baseSupport');
readSignedDelta(result.baseDelta, imageSize, 'baseDelta');
end

function value = readSignedDelta(value, imageSize, name)
if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), imageSize) || ...
        any(~isfinite(value(:))) || any(value(:) < -.03) || ...
        any(value(:) > .03)
    error('beauty:InvalidComposeInput', ...
        '有符号 Base 亮度增量 %s 必须位于 [-0.03, 0.03]。', name);
end
value = double(value);
end

function value = maxChange(inputImage, outputImage, mask)
if ~any(mask(:))
    value = 0;
    return;
end
difference = max(abs(double(outputImage) - double(inputImage)), [], 3);
value = max(difference(mask));
end

function validateWhiteningResult(result, imageSize)
if ~isstruct(result) || ~isscalar(result) || ...
        ~all(isfield(result, {'supportMap', 'delta'}))
    error('beauty:InvalidComposeInput', ...
        '美白结果缺少 supportMap 或 delta。');
end
readMask(result.supportMap, imageSize, 'whiteningSupport');
readMask(result.delta, imageSize, 'whiteningDelta');
end

function validateToneResult(result, imageSize)
if ~isstruct(result) || ~isscalar(result) || ...
        ~all(isfield(result, {'toneSupport', 'outputCb', 'outputCr'}))
    error('beauty:InvalidComposeInput', ...
        '肤色结果缺少 toneSupport 或输出色度。');
end
readMask(result.toneSupport, imageSize, 'toneSupport');
readMask(result.outputCb, imageSize, 'outputCb');
readMask(result.outputCr, imageSize, 'outputCr');
end
