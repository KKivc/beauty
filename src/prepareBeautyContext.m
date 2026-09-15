function beautyContext = prepareBeautyContext(inputImage, faceBox, injectedParsing, bodyParsingParams)
%PREPAREBEAUTYCONTEXT 构建版本化语义美颜 context。
if ~isa(inputImage, 'uint8') || ~isreal(inputImage) || ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
    error('prepareBeautyContext:InvalidImage', 'inputImage must be uint8 RGB.');
end
validateFaceBox(faceBox, size(inputImage, 2), size(inputImage, 1));
if nargin >= 3
    parsing = parseFaceRegions(inputImage, faceBox, injectedParsing);
else
    parsing = parseFaceRegions(inputImage, faceBox);
end
beautyContext = buildBeautyContextFromParsing(inputImage, faceBox, parsing);
if nargin < 4 || isempty(bodyParsingParams)
    bodyParsingParams = struct();
elseif ~isstruct(bodyParsingParams) || ~isscalar(bodyParsingParams)
    error('prepareBeautyContext:InvalidBodyParsingParams', ...
        'The fourth argument must be a scalar SCHP options struct.');
end
baseFaceAndNeckMask = beautyContext.skinMask;
probabilities = inferSchpLipProbabilities(inputImage, bodyParsingParams);
bodyMask = buildBodySkinMaskFromSchp(probabilities, ...
    baseFaceAndNeckMask, inputImage);
beautyContext.bodySkinMask = bodyMask;
beautyContext.skinMask = max(baseFaceAndNeckMask, bodyMask);
end

function validateFaceBox(box, imageWidth, imageHeight)
if ~isnumeric(box) || ~isreal(box) || ~isequal(size(box), [1, 4]) || any(~isfinite(box)) || ...
        box(1) < 1 || box(2) < 1 || any(box(3:4) <= 0) || ...
        box(1) + box(3) - 1 > imageWidth || box(2) + box(4) - 1 > imageHeight
    error('prepareBeautyContext:InvalidFaceBox', 'Invalid face rectangle.');
end
end
