# 技术设计

## 数据流与接口

GUI 在 `detectSingleFace` 成功后调用 `prepareBeautyContext`，缓存 context，再将它传给 `beautifyImage` 与 `recommendBeautyParams`。重置仅清零滑块并保留 context；打开新图、无脸或处理失败时清空 context。

`beautyContext` 是标量 struct：

- `skinMask`：与图像同高宽的 `double` soft mask，范围 `0..1`，覆盖全部裸露皮肤。
- `faceSkinMask`：同尺寸 `double` soft mask，仅保留人脸皮肤。
- `featureProtectionMask`：同尺寸 `double` mask，`1` 表示完整保留原图。
- `imageSize`：输入图像的完整尺寸。
- `faceBox`：生成 context 时的人脸框。

`beautifyImage` 和 `recommendBeautyParams` 的 context 参数可选。提供时统一验证字段、类型、尺寸、范围、有限值及 faceBox 一致性；无 context 时自动构建。两项强度均为零时在构建或验证 context 前直接返回原图。

## 全裸露皮肤分割

1. 复用人脸框内部的可靠额头、双颊和鼻部样本，稳健估计 Cb/Cr 中心和离散度。
2. 生成全图自适应肤色候选，亮度只作阴影/高光保护，不要求身体各处与脸等亮。
3. 构造脸部种子及下颌到颈部的连通支持；保留这些连通域。
4. 对其余候选连通域使用更严格的色度距离、最小面积、形状紧致度和边界颜色一致性筛选，以允许断开的手或手臂但拒绝肤色背景。
5. 形态学修复小色斑孔洞并生成内容驱动 soft mask；固定椭圆只可用于采样安全区，不能进入最终权重。

## 五官保护

- 在旋转人脸 ROI 上运行 EyePair、Nose、Mouth 级联模型，将候选映射回原图。
- 仅接受眼睛在上、鼻部居中且位于眼睛下方、嘴位于鼻下的组合；单项不满足时忽略该项。
- 可靠眼区扩展到眉毛与睫毛并强保护；嘴唇强保护；鼻区仅将原尺度结构梯度转为保护权重。
- 缺失检测使用人脸相对区域内的原尺度梯度、暗色眼眉/鼻孔及唇色色度构造回退 mask。
- 级联模型只在准备 context 时运行一次，滑块预览不重复检测。

## 多尺度磨皮与美白

- 在 YCbCr 中分离低频结构、中尺度斑点与高频纹理；低频基底不被直接替换。
- 根据强度连续衰减中/高频残差，最大档高频保留目标约 20%；`featureProtectionMask` 将受保护区域混回原始 YCbCr。
- 对 Cb/Cr 使用结构引导的局部平滑，优先压低偏离局部肤色的色斑残差，避免橙红雀斑只剩颜色。
- 美白使用皮肤内有界中间调曲线，仅修改 Y；不向统一目标亮度收敛，不改变非皮肤区域。
- 所有结果通过 `skinMask .* (1 - featureProtectionMask)` 混合，最后恢复原始类型、尺寸和通道。

## 失败与兼容

- 级联五官检测无结果时静默使用结构回退；context 构建失败才报告加载错误并清空旧状态。
- 三参数 `beautifyImage` 与两参数 `recommendBeautyParams` 保持可调用。
- 不新增工具箱、模型文件或网络下载。
- 用户参考图只用于本地评价，不成为测试夹具或提交内容。
