# 人像美颜功能设计

## 运行环境与范围

- MATLAB R2024a 或更高版本。
- 必需工具箱：Computer Vision Toolbox、Image Processing Toolbox。
- MVP 输入仅支持 `uint8` 三通道 RGB JPG/PNG；不支持 `uint16` PNG 或其他数值类型。
- 保存只保证像素宽高（像素分辨率）、三通道和画幅比例；不承诺 DPI/像素密度、ICC、EXIF 等文件元数据。

## Boundaries

- GUI 层：改造 `gui/faceDetectionApp.m`，负责控件、用户交互、状态、图像显示、指标展示和保存。
- 算法层：`src/beautifyImage.m` 负责参数校验、主脸区域 mask、磨皮、美白和尺寸保持；`src/recommendBeautyParams.m` 负责根据当前图像推荐一组自适应参数。
- 指标层：`src/evaluateImage.m` 负责指标计算和耗时字段校验。
- 检测层：复用 `src/detectSingleFace.m`，通过多角度正面/侧面模型选择最大且相对居中的前景人脸；无可识别人脸时返回失败。
- `annotateFaceDetection.m` 保留并继续使用既有测试，但不参与美颜主流程。

## Function Contracts

### `beautifyImage(inputImage, params, faceBox)`

- `inputImage`：必须为 `uint8`、三维、第三维为 3 的 RGB 图像。
- `params.smoothingStrength`、`params.whiteningStrength`：必须是有限数值标量，范围 `0–100`；缺失、非数值、非标量、`NaN`、`Inf` 或越界时直接报错，不自动 clamp。
- `faceBox`：必须是单个有限数值 `[x y width height]`，宽高为正且矩形位于图像范围内。
- 输出 `beautifiedImage`：`uint8`、三通道，尺寸逐维等于输入。
- 两个强度均为 `0` 时直接返回输入图像，要求逐元素完全相等。
- 建议稳定错误标识：`beautifyImage:InvalidImage`、`beautifyImage:InvalidParams`、`beautifyImage:InvalidFaceBox`。

### `recommendBeautyParams(inputImage, faceBox)`

- 输入遵循 `beautifyImage` 的 `uint8` RGB 和主脸框契约。
- 输出结构体包含 `smoothingStrength` 和 `whiteningStrength`，均为有限标量，范围完整覆盖 `0–100`。
- 使用人脸肤色区域的稳健亮度统计决定美白推荐值，使用局部高频纹理/瑕疵统计决定磨皮推荐值；不同图像允许得到不同结果，也允许推荐值高于 `55`。
- 推荐公式使用连续软饱和映射，而不是固定 `45/30` 或人为 `55` 上限。
- 推荐函数只决定参数，不直接改变图像；实际输出仍由 `beautifyImage` 的 mask、亮度裁剪和边缘保护控制。
- 建议稳定错误标识：`recommendBeautyParams:InvalidImage`、`recommendBeautyParams:InvalidFaceBox`。

### `evaluateImage(originalImage, outputImage, elapsedSeconds)`

- 原图和输出图必须为三通道 RGB，且像素宽高一致；当前 GUI 传入 `uint8` 图像。
- `elapsedSeconds` 必须是有限的非负数标量。
- 输出结构体字段固定为：`entropy`、`standardDeviation`、`averageGradient`、`elapsedSeconds`。
- 指标基于 `outputImage` 的 `rgb2gray` 灰度图：
  - 信息熵：256 级灰度直方图概率 `p`，计算 `-sum(p .* log2(p))`，忽略零概率。
  - 标准差：灰度像素总体标准差，分母为像素总数 `N`。
  - 平均梯度：对灰度矩阵调用 `gradient`，计算 `mean(hypot(gx, gy), 'all')`；边界使用 MATLAB 默认单边差分。
- 建议稳定错误标识：`evaluateImage:InvalidImage`、`evaluateImage:SizeMismatch`、`evaluateImage:InvalidElapsed`。

## 美颜算法管线

1. 强度和输入校验；两个强度均为 `0` 时立即返回，避免无效类型转换。
2. 根据 `faceBox` 生成位于人脸框内的椭圆软 mask，并使用 smoothstep 边界羽化降低脸框边缘的突变。
3. 在人脸椭圆内使用 YCbCr 肤色条件生成肤色 mask；覆盖不足或分布不可靠时混合带外围衰减的椭圆先验，并使用相对人脸核心亮度保护深色头发、阴影和背景。
4. 磨皮只处理亮度通道。基础层尺度随 `faceBox` 尺寸调整，通过衰减小纹理细节层实现可见且单调的磨皮效果；强细节和梯度边缘使用独立保护权重保留，不做任何几何变换。
5. 美白只提升亮度通道，使用低档可见、高档软饱和的非线性强度映射；同时按剩余亮度空间、高光保护和边缘保护限制增量，保持色度通道不变，避免偏色、假白和溢出。
6. 转回 RGB，裁剪到 `[0, 255]` 并转换为 `uint8`；不得调用会改变输出宽高的 resize 或 crop。

上述管线中的 mask 组合、强度映射和边缘羽化必须保持单一实现，不在 GUI 中重复实现。滤波参数可以在固定测试图上做小范围调整，但不能改变输入输出契约。

## GUI 状态与数据流

数据流：

普通预览：`imread` → 类型/RGB 校验 → `detectSingleFace` → 缓存 `sourceImage/faceBox` → `beautifyImage` → `evaluateImage` → 右侧显示、指标显示和保存。

一键美颜：`sourceImage/faceBox` → `recommendBeautyParams` → 写入滑块 → `beautifyImage` → `evaluateImage` → 右侧显示、指标显示和保存。

私有状态：

- `sourceImage`：原图。
- `beautifiedImage`：当前右侧预览和保存结果。
- `faceBox`：单个人脸框。
- `hasSingleFace`：是否允许处理和保存。
- `currentMetrics`：当前结果指标。
- `inputFormat`、`inputBaseName`：保存默认名和格式。

控件：

- 原图和美颜结果两个并排 `UIAxes`。
- 磨皮 `0–100` 滑块，默认 `35`；美白 `0–100` 滑块，默认 `25`。
- 一键美颜按钮调用 `recommendBeautyParams`，将当前图像的推荐值写入两个滑块后复用普通预览；重置按钮将参数设为 `0/0`。
- 独立指标区域显示“信息熵”“标准差”“平均梯度”“单幅图像处理耗时”。
- 未加载有效图像前，滑块、处理按钮和保存按钮禁用；检测失败或处理失败时清空结果、指标、faceBox 和旧状态。

回调：

- 滑块使用 `ValueChangingFcn` 读取拖动中的 `event.Value`，允许约 `200 ms` 节流；使用 `ValueChangedFcn` 读取最终 `Value` 并强制完成最终刷新。不要在 `ValueChangingFcn` 中回写滑块自身的 `Value`。
- 每次美颜预览调用 `tic/toc` 包围一次完整 `beautifyImage`，随后调用 `evaluateImage` 并更新图像和四项指标。
- 重置后直接使用原图作为右侧结果，前三项指标计算原图，`elapsedSeconds` 为 `0`，不伪造美颜耗时。
- 保存时写入当前 `beautifiedImage`，读回并检查像素宽高（像素分辨率）和通道数；不检查或承诺元数据。

## 验收与验证边界

- 自动测试验证输入类型、参数和 faceBox 错误、零强度逐元素相等、输出尺寸/通道、推荐值范围/自适应变化、指标字段和固定矩阵数值。
- 使用固定 4 张测试图人工检查不同尺寸、肤色、姿态和光照；检查瑕疵淡化、五官细节、背景保护、色彩自然、无光晕/伪轮廓和结构比例不变。
- GUI 手动回归需覆盖打开、主脸检测（含背景人物和倾斜人脸）、检测失败、滑块拖动、一键美颜、重置、指标更新和保存读回。
- 从仓库根目录启动 GUI 时显式执行 `addpath('gui', 'src'); app = faceDetectionApp;`。

## Rollback Shape

- 算法效果异常时回退 `beautifyImage.m` 的处理管线，不改变 GUI 和指标契约。
- GUI 布局或回调异常时回退 `faceDetectionApp.m`，保留独立算法、指标函数和测试。
