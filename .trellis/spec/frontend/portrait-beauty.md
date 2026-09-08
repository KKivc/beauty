# Portrait Beauty GUI Contracts

## 1. Scope / Trigger

This spec records the GUI state and callback rules for `gui/faceDetectionApp.m`.

## 2. Signatures

The AppBase class exposes controls for opening/saving, two strength sliders, one-click beauty, reset, two image axes, and four metric labels.

## 3. Contracts

- The constructor resolves the sibling `src/` directory from `faceDetectionApp.m` using an absolute path and adds it to the MATLAB path; startup must not depend on the current working directory.
- Before a valid single-face `uint8` RGB image is loaded, beauty controls and save are disabled.
- A valid image caches `sourceImage` and `faceBox`; the left axis shows the source and the right axis shows the current preview.
- Slider drag uses `ValueChangingFcn` with approximately 200 ms throttling; `ValueChangedFcn` always performs the final refresh.
- One-click beauty calls `recommendBeautyParams`, writes both slider values, and uses the same preview path as manual adjustment.
- Reset sets both strengths to zero, displays the source image, displays source metrics, and reports `0 ms` processing time.
- The metric area always represents the current right-side result: entropy, standard deviation, average gradient, and one-image processing time.
- Save reads the written JPG/PNG back and verifies pixel dimensions, three channels, and aspect ratio. DPI, ICC, and EXIF are not promised by MVP.

## 4. Validation & Error Matrix

| Condition | GUI behavior |
| --- | --- |
| Cancel open/save dialog | Preserve the current valid state |
| Non-`uint8` or non-RGB input | Clear old state and show an unsupported-image alert |
| No recognizable foreground face | Clear result and show a face-detection alert |
| Processing/recommendation failure | Clear stale result and show an error alert |
| Unsupported output extension | Reject save before writing |

## 5. Good / Base / Bad Cases

- Good: controls become enabled after a recognizable foreground face is selected, including when smaller background faces are present, and every preview updates both image and metrics.
- Base: reset preserves the loaded source and face detection while clearing beauty strengths.
- Bad: leaving old output or metrics visible after a failed reload or processing error.

## 6. Tests Required

- MATLAB smoke test must verify construction, initial disabled state, slider limits, and cleanup.
- Manual GUI regression must cover open, unsupported input, no/multiple face, slider drag, one-click recommendation, reset, metrics, and save read-back.

## 7. Wrong vs Correct

### Wrong

```matlab
slider.ValueChangedFcn = @updatePreview;
```

when continuous drag feedback is required.

### Correct

```matlab
slider.ValueChangingFcn = @updatePreviewDuringDrag;
slider.ValueChangedFcn = @updatePreviewFinally;
```
