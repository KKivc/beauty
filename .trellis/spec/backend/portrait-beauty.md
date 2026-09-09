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
- The beauty mask must be derived from adaptive YCbCr skin samples and connected image content inside `faceBox`; neither normal processing nor low-reliability fallback may use a fixed ellipse as the final effect shape.
- Small holes caused by freckles or spots must remain inside the connected skin region, while larger eye, mouth, hair, and background regions stay excluded. Feathering proceeds inward from the content-derived boundary to avoid background leakage and visible halos.
- Smoothing strength must progressively attenuate fine texture and medium-scale spots. Structural-edge protection is computed from scale-filtered luminance so isolated freckles are not mistaken for facial structure; medium-scale attenuation is capped so maximum strength retains low-frequency facial shape and non-zero natural texture.
- Whitening changes only the Y channel with a bounded, monotonic midtone curve proportional to `Y * (1 - Y)`. It must preserve luminance ordering, must not push all skin pixels toward one flat target, add a white RGB overlay, or modify Cb/Cr chroma.
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
- Assert that a non-elliptical skin-color interruption changes mask support, mask boundaries do not leak into background, and discrete synthetic freckles lose contrast monotonically while final texture remains non-zero.
- Assert that smoothing `100`, whitening `100`, and their combined maximum preserve the signs and minimum magnitudes of eye-socket/cheek and nose/cheek low-frequency contrasts.
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

### Dynamic mask anti-pattern

Wrong: combine unreliable skin detection with a fixed ellipse fallback. The geometric boundary becomes visible after whitening and can miss the actual forehead, cheeks, or chin.

Correct: relax content-adaptive color thresholds, retain only regions connected to internal face seeds, fill only small spot holes, and feather inward from that dynamic boundary.
