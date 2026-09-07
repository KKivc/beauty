# 实施计划

## 实施步骤

1. 建立 `gui/`、`src/`、`tests/` 的最小目录结构，并创建 R2024a 可打开的 App Designer 入口。
2. 实现 `detectSingleFace.m`：接收 RGB 图像，运行 `vision.CascadeObjectDetector`，返回检测框及“恰好一个框”的成功状态。
3. 实现 `annotateFaceDetection.m`：仅在成功状态下，将检测框绘制到完整输入图像副本；验证输出数组的像素宽高与输入一致。
4. 构建 App Designer 界面：左、右两个图像区域；“打开图像”和“保存图像”按钮；保存按钮初始禁用。
5. 实现打开回调：筛选 JPG/JPEG/PNG，验证 RGB 输入，在左侧显示原图后自动检测；根据成功或失败路径更新右侧、提示和保存按钮状态。
6. 实现保存回调：仅保存 `detectedImage`，提供 JPG/PNG 保存筛选，默认使用输入格式与基础文件名；写出后核对输出数组的像素宽高。
7. 添加 MATLAB 测试脚本和手动 GUI 回归步骤，覆盖单脸成功、零脸、多脸、取消选择、不支持图像以及 JPG/PNG 保存。

## 验证命令与检查

- 在 MATLAB R2024a 中打开 `gui/faceDetectionApp.mlapp` 并运行应用。
- 以一张可稳定检测到的人脸 JPG/PNG 验证：左侧原图、右侧完整带框图、保存按钮启用。
- 以零脸和多脸样本验证：出现提示、右侧无成功结果、保存按钮禁用。
- 分别导出 JPG 和 PNG，用 `imread` 读取并比较 `size(output, 1:2)` 与输入的像素宽高。
- 验证用户取消打开或保存对话框后不会报错，也不会错误启用保存按钮。

## 实施边界与回滚点

- 不创建磨皮、美白、参数控件、指标或预览性能相关代码。
- 不为灰度、透明 PNG、BMP、TIF 或元数据保留添加兼容分支。
- 高风险点是 App 回调中的成功结果状态；每完成一个失败路径后先确认 `detectedImage` 已清空且保存禁用。
- 若 GUI 集成出现问题，保留 `detectSingleFace.m` 和 `annotateFaceDetection.m` 的独立测试，再单独修复回调层。
