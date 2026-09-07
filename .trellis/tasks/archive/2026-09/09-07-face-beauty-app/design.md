# 技术设计

## 架构边界

- `gui/faceDetectionApp.mlapp`：App Designer 界面、打开和保存回调、UI 状态及两个图像区域。
- `src/detectSingleFace.m`：调用 `vision.CascadeObjectDetector`，并以“恰好一个检测框”为成功条件。
- `src/annotateFaceDetection.m`：在完整输入图像上绘制人脸框，生成右侧显示和保存使用的结果图。
- `tests/`：检测结果、导出尺寸和 GUI 主流程的 MATLAB 测试脚本及其测试图片。

本 MVP 不包含美颜算法、滑块、指标计算或实时预览模块。

## UI 与状态

界面提供“打开图像”和“保存图像”两个操作，以及左右两个 `uiaxes`：左侧显示输入原图，右侧显示带检测框的成功结果。保存按钮在启动、取消打开、格式不支持或检测失败时禁用；只有右侧成功结果存在时启用。

应用状态只保存以下内容：

- `sourceImage`：已成功读取的原始 RGB 图像；
- `detectedImage`：成功检测后带框的完整 RGB 图像；
- `inputFormat`：输入的 JPG 或 PNG 格式，用作保存对话框的默认格式；
- `hasSingleFace`：是否存在可保存的成功检测结果。

不保存美颜参数、预览图、图像元数据或多张人脸选择状态。

## 数据流与行为契约

1. 用户点击“打开图像”，文件选择器仅展示 JPG/JPEG 和 PNG。
2. 用户取消选择时，现有界面和状态保持不变。
3. 读取后验证图像为三通道彩色 RGB；灰度图、带透明通道的 PNG 或其他不在范围内的输入显示提示，并清空右侧成功结果。
4. 将原图显示在左侧后立即调用 `detectSingleFace`，不提供单独的检测按钮。
5. 检测框数量恰为一时，调用 `annotateFaceDetection` 在原尺寸完整图像上绘制边框；将结果显示在右侧，设置 `hasSingleFace`，并启用保存。
6. 检测到零个或多个框时，提示用户重新选择图像，清空右侧结果并禁用保存。
7. 用户点击“保存图像”时，文件选择器提供 JPG/PNG；默认扩展名与输入格式一致。将 `detectedImage` 写出，不修改 `sourceImage`。输出须保持输入的像素宽高和画幅比例。

## 依赖与兼容性

- 运行环境：MATLAB R2024a、App Designer、Image Processing Toolbox、Computer Vision Toolbox。
- 人脸检测：`vision.CascadeObjectDetector`。其对强遮挡、极端姿态或复杂光照可能失败；这属于本 MVP 的预期失败路径。
- 绘制检测框使用 Computer Vision Toolbox 支持的图像标注方式，确保屏幕显示与保存的像素数组一致。
- 仅承诺像素宽高和画幅比例；DPI/PPI、EXIF、色彩配置文件和透明通道不在本 MVP 的保存兼容性范围内。

## 风险与回滚

- 检测器在部分单人脸照片上可能产生零个或多个框。实现必须将这两种情况都视为失败，不能擅自选择最大框。
- 保存的 JPG 可产生有损压缩；验收比较宽高，不比较逐像素相等性。
- 回滚边界为新增的 GUI、检测和标注文件；不修改或替代将来美颜算法模块。
