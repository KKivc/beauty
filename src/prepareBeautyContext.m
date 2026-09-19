function beautyContext = prepareBeautyContext(inputImage, faceBox, ...
        injectedParsing, bodyParsingParams)
%PREPAREBEAUTYCONTEXT 构建包含脸外皮肤的最终 v3.1 Context。

validateImage(inputImage);
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
if nargin >= 3 && ~isempty(injectedParsing)
    parsing = parseFaceRegions(inputImage, faceBox, injectedParsing);
else
    parsing = parseFaceRegions(inputImage, faceBox);
end

if nargin < 4 || isempty(bodyParsingParams)
    bodyParsingParams = struct();
elseif ~isstruct(bodyParsingParams) || ~isscalar(bodyParsingParams)
    error('prepareBeautyContext:InvalidBodyParsingParams', ...
        '第四个参数必须是标量 SCHP 选项结构体。');
end

beautyContext = buildBeautyContextFromParsing(inputImage, faceBox, parsing);
faceAndNeckMask = beautyContext.skinMask;
probabilities = inferSchpLipProbabilities(inputImage, bodyParsingParams);
bodyMask = buildBodySkinMaskFromSchp(probabilities, ...
    faceAndNeckMask, inputImage);

% SCHP 只补充主人物的脸外皮肤；脸部语义仍以 Face Parsing 为准。
beautyContext.bodySkinMask = bodyMask;
beautyContext.skinMask = max(faceAndNeckMask, bodyMask);
beautyContext.nonFaceSkinMask = max(beautyContext.skinMask - ...
    min(beautyContext.skinMask, beautyContext.faceSkinMask), 0);
% 权威桥接先清掉合并身体皮肤前的旧派生字段，再按最终皮肤字段重建，
% 避免 runtime cache 携带与最终 skinMask 不一致的结构和强度图。
beautyContext = rebuildBeautyDerivedMasks(inputImage, beautyContext, faceBox);
beautyContext = normalizeBeautyContext(inputImage, faceBox, beautyContext);
[runtimeMasks, maskDiagnostics] = masks.buildBeautyMasks( ...
    inputImage, beautyContext, faceBox);
beautyContext.runtimeCache = buildBeautyRuntimeCache( ...
    inputImage, faceBox, runtimeMasks, maskDiagnostics, struct( ...
    'status', 'generated', ...
    'sourceSchemaVersion', '3.1', ...
    'message', '打开图像时已生成 v3.1 运行时产物。'));
end

function validateImage(inputImage)
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ...
        ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('prepareBeautyContext:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end

function validateFaceBox(faceBox, imageWidth, imageHeight)
if ~isnumeric(faceBox) || ~isreal(faceBox) || ...
        ~isequal(size(faceBox), [1, 4]) || any(~isfinite(faceBox)) || ...
        faceBox(1) < 1 || faceBox(2) < 1 || any(faceBox(3:4) <= 0) || ...
        faceBox(1) + faceBox(3) - 1 > imageWidth || ...
        faceBox(2) + faceBox(4) - 1 > imageHeight
    error('prepareBeautyContext:InvalidFaceBox', ...
        'faceBox 必须是位于图像范围内的 [x y width height] 矩形。');
end
end
