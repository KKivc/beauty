# Codebase Findings

## Scope

人像美颜功能规划前的本地代码勘察记录。

## Existing MATLAB Files

- `gui/faceDetectionApp.m`
  - 手写 App Designer 风格 GUI，继承 `matlab.apps.AppBase`。
  - 当前提供打开图像、保存图像、左右并排显示原图和检测结果、底部状态提示。
  - 打开图像后调用 `detectSingleFace`，要求恰好一张人脸。
  - 结果图当前是带绿色矩形框的检测图。
  - 保存后会重新读取输出文件，并校验输出宽高与输入一致。
- `src/detectSingleFace.m`
  - 校验三通道 RGB 输入。
  - 使用 `vision.CascadeObjectDetector` 检测人脸。
  - 只接受恰好一张人脸，返回 `[x y width height]`。
- `src/annotateFaceDetection.m`
  - 校验 RGB 图和单个人脸框。
  - 使用 `insertShape` 绘制 Rectangle。
- `tests/testFaceDetectionHelpers.m`
  - 覆盖检测标注保持尺寸。
  - 覆盖非 RGB 输入报错。

## Implementation Implications

- GUI 可在现有 `faceDetectionApp.m` 上改造，复用打开、单人脸检测、并排显示和保存校验。
- 美颜算法应放在 `src/` 新函数中，避免把算法塞进 GUI callback。
- 指标计算应放在 `src/` 新函数中，便于测试。
- 需要新增测试，至少覆盖算法输出尺寸、参数边界、指标字段和 RGB 输入校验。
- CodeGraph 当前未同步，`codegraph status` 显示 Files/Nodes/Edges 均为 0；规划阶段使用文件读取和搜索作为依据。
