# Portrait Beauty Backend Contracts

## 1. Scope / Trigger

This spec records the reusable contracts introduced by the portrait beauty helpers in `src/`.

## 2. Signatures

```matlab
outputImage = beautifyImage(inputImage, params, faceBox)
params = recommendBeautyParams(inputImage, faceBox)
metrics = evaluateImage(originalImage, outputImage, elapsedSeconds)
```

## 3. Contracts

- Beauty input is `uint8`, real, three-dimensional RGB data.
- `params.smoothingStrength` and `params.whiteningStrength` are finite numeric scalars in `0..100`.
- `faceBox` is one finite `[x y width height]` rectangle inside the image.
- `beautifyImage` returns `uint8` RGB data with exactly the input dimensions.
- Zero strengths return the input image element-for-element.
- `recommendBeautyParams` returns finite strength fields in `0..100`; values are image-dependent and are not fixed presets.
- Low-reliability skin-mask fallback must retain relative-luminance shadow protection and a stronger peripheral taper; it must not apply a uniform ellipse weight that visibly whitens hair or background near the face-box boundary.
- `evaluateImage` returns `entropy`, `standardDeviation`, `averageGradient`, and `elapsedSeconds`.
- Quality metrics use the output `rgb2gray` image. Entropy uses 256 levels and base 2; standard deviation is population standard deviation; average gradient is the mean `gradient` magnitude.

## 4. Validation & Error Matrix

| Condition | Error identifier |
| --- | --- |
| Non-`uint8` or non-RGB beauty input | `beautifyImage:InvalidImage` |
| Missing, non-scalar, non-finite, or out-of-range strengths | `beautifyImage:InvalidParams` |
| Missing or invalid face rectangle | `beautifyImage:InvalidFaceBox` |
| Missing or invalid recommendation image/face rectangle | `recommendBeautyParams:InvalidImage` / `recommendBeautyParams:InvalidFaceBox` |
| Mismatched metric dimensions | `evaluateImage:SizeMismatch` |
| Invalid elapsed time | `evaluateImage:InvalidElapsed` |

## 5. Good / Base / Bad Cases

- Good: `uint8` RGB image, one valid face rectangle, strengths within `0..100`.
- Base: both strengths are zero; return the original array without conversion.
- Bad: silently converting `uint16` or clamping invalid direct-call parameters.

## 6. Tests Required

- Assert invalid image, parameter, face rectangle, and elapsed-time identifiers.
- Assert zero-strength exact equality, output class/channel/dimensions, adaptive recommendation bounds, and fixed-matrix metric values.
- Assert monotonic visible effects across representative face scales plus strong-edge, highlight, chroma, hair, peripheral-background, and low-reliability fallback protection.
- Keep `tests/testFaceDetectionHelpers.m` passing.

## 7. Wrong vs Correct

### Wrong

```matlab
params.smoothingStrength = min(max(userValue, 0), 100);
```

### Correct

```matlab
if ~isfinite(userValue) || userValue < 0 || userValue > 100
    error('beautifyImage:InvalidParams', 'Invalid beauty strength.');
end
```
