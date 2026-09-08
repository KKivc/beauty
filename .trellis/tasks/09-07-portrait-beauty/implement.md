# 人像美颜功能实施计划

## Success Criteria

- `gui/faceDetectionApp.m` 提供打开、保存、磨皮滑块、美白滑块、一键美颜、重置、实时预览和指标展示。
- `src/beautifyImage.m` 与 `src/evaluateImage.m` 可独立调用，输入输出契约和错误标识稳定。
- 仅接受 `uint8` 三通道 RGB JPG/PNG；最终输出像素宽高（像素分辨率）、通道数和画幅比例不变，临时缩放不得泄漏到输出。
- 现有检测测试继续通过，并新增算法、指标和参数错误测试。
- 固定 4 张测试图完成不同尺寸、肤色、姿态、光照和背景人物场景的人工验收。
- 保存范围只承诺像素数据，不承诺 DPI、ICC 或 EXIF。

## Ordered Checklist

1. **准备实现上下文**
   - 从仓库根目录确认 MATLAB R2024a 或更高版本。
   - 确认 Computer Vision Toolbox 和 Image Processing Toolbox 可用。
   - 检查现有工作区状态，不覆盖无关改动。
   - 明确运行路径：`addpath('gui', 'src');`；测试脚本自行添加 `src/`。

2. **新增 `src/beautifyImage.m`**
   - 校验 `uint8` 三通道 RGB、`params` 字段和有限标量 `0–100` 参数。
   - 校验单个 faceBox 为有效、位于图像范围内的 `[x y width height]` 矩形。
   - 两强度为 `0` 时逐元素返回原图。
   - 按设计实现椭圆软 mask、YCbCr 肤色 mask、可靠性混合回退以及深色头发和外围背景保护。
   - 使用随 `faceBox` 调整尺度的亮度基础层/细节层分离实现磨皮，并保护强细节和梯度边缘。
   - 使用低档可见、高档软饱和的非线性亮度曲线实现自然美白，保持色度并限制高光增量。
   - 保证输出为 `uint8`、三通道、原始尺寸。

3. **新增 `src/recommendBeautyParams.m`**
   - 复用人脸区域和肤色 mask 逻辑，提取稳健亮度和局部高频纹理特征。
   - 根据亮度差推荐美白强度，根据纹理/瑕疵指数推荐磨皮强度。
   - 使用连续软饱和映射，推荐值允许覆盖完整 `0–100`，不得写死为 `45/30` 或限制在 `55` 以下。
   - 仅返回参数，不直接修改图像；推荐结果交给 `beautifyImage` 处理。

4. **新增 `src/evaluateImage.m`**
   - 校验原图/结果图为 RGB 且像素宽高一致。
   - 校验耗时为有限非负标量。
   - 按 PRD 定义计算 256 级底数 2 信息熵、总体标准差和平均梯度。
   - 返回固定字段：`entropy`、`standardDeviation`、`averageGradient`、`elapsedSeconds`。

5. **改造 `gui/faceDetectionApp.m`**
   - 保留打开、主脸检测、双栏显示和保存尺寸校验的有效路径；主脸检测允许忽略背景人物。
   - 增加磨皮/美白滑块及数值标签；默认值 `35/25`。
   - 增加一键美颜按钮：调用 `recommendBeautyParams`，将当前图像的自适应推荐值写入滑块；重置按钮设置 `0/0`。
   - 增加独立指标区域，显示信息熵、标准差、平均梯度和单幅图像处理耗时。
   - 打开有效图像后调用 `beautifyImage` 并展示默认预览及指标。
   - 使用 `ValueChangingFcn` 在拖动中约 `200 ms` 节流更新，使用 `ValueChangedFcn` 强制最终更新。
   - 每次预览只将 `beautifyImage` 包在 `tic/toc` 中，随后调用 `evaluateImage`。
   - 重置后显示原图指标，耗时为 `0 ms`。
   - 未加载、检测失败、处理失败和重新打开非法图片时清理旧结果、指标、faceBox 和保存状态。
   - 保存后读回并校验像素宽高（像素分辨率）及通道数；不实现元数据保留。

6. **新增 `tests/testPortraitBeautyHelpers.m`**
   - 校验非 `uint8`、非 RGB 输入报错。
   - 校验推荐函数输出始终位于 `0–100`，并在亮度/纹理明显不同的测试输入上产生相应不同的推荐值；不要求每两张真实图片必然不同。
   - 校验缺字段、非数值、非标量、`NaN`、`Inf` 和越界参数报错。
   - 校验非法 faceBox 报错。
   - 校验零强度结果与原图逐元素相等。
   - 校验非零输出为 `uint8`、三通道且尺寸不变。
   - 使用固定小矩阵校验四项指标数值和字段。
   - 校验原图/结果图尺寸不一致及非法耗时报错。

7. **准备并执行人工图像验收**
   - 将 4 张批准的测试图放入 `assets/portrait-beauty/`，记录尺寸、肤色、姿态、光照和背景人物覆盖情况。
   - 从仓库根目录执行：
     ```matlab
     addpath('gui', 'src');
     app = faceDetectionApp;
     ```
   - 逐图检查默认预览、滑块拖动、一键美颜、重置、指标更新和保存读回。
   - 记录瑕疵淡化、五官细节、背景/头发保护、色彩自然、无光晕/伪轮廓和结构比例结果。

8. **执行自动验证与质量检查**
   - 运行：
     ```matlab
     results = runtests('tests');
     assertSuccess(results);
     ```
   - 检查新增函数的路径、错误标识、输出类型和尺寸。
   - 检查 diff，确认只涉及本任务文件，不删除既有检测能力。
   - 若 MATLAB、工具箱或固定测试图不可用，明确记录未验证项，不宣称完成。

## Traceability

- PRD GUI 功能：步骤 4、6。
- PRD 输入/输出和参数契约：步骤 2、5。
- PRD 指标和耗时：步骤 3、4、5。
- PRD 保存尺寸/通道/比例：步骤 4、5、7。
- PRD 主观图像质量：步骤 6。
- PRD 元数据范围：步骤 4、7。

## Review Gates

- 开始 GUI 改造前，先让 `beautifyImage` 和 `evaluateImage` 契约、错误标识及测试通过。
- 修改保存逻辑后，确认读回像素宽高和通道数校验仍存在。
- 完成后执行 `trellis-check` 质量检查，并核对每条 PRD 验收标准有自动或手动证据。

## Rollback Points

- 算法效果异常：回退 `beautifyImage.m` 管线，保留函数契约和测试。
- GUI 布局或回调异常：回退 `faceDetectionApp.m`，保留算法和指标函数。
- 人工图像验收未完成：保留代码但标记验收阻塞，不进入完成状态。
