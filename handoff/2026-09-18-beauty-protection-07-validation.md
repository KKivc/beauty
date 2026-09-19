# 07：低/中语义置信眉眼细节软保护验证记录

记录日期：2026-09-18。

## 一、结论

本次按 issue 07 的固定基线执行了当前生产实现验证，结论为：**issue 07 当前未通过，生产候选未实现、未落地**。

根因证据明确：`src/+masks/buildTextureProtectionMask.m` 的 `detectEyeDetailProtection` 仍以每眼 `eyeEvidence >= .45` 构造核心，并在全图不存在 `.45` 眼部证据时直接 `return`。因此，低/中眼部语义证据没有产生受限的 soft support；真实 77 基线和独立合成探针均复现该行为。

本次只执行验证和生成中文交接记录，没有修改 `src/`、现有测试、Face Parsing、模型、Repair 主公式、缓存契约或算法版本。工作树中其他会话已有未提交改动保持原样，未清理、未回退、未提交或推送。

## 二、固定基线

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 尺寸：450×512×3
- 人脸框：`[95 79 286 372]`
- 磨皮：100；美白：15
- 眉眼人工选区：`browEye [165 205 150 100]`，矩形均为 `[x y width height]`
- 完整保存基线：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- 验证脚本：`C:\Users\JJiio\AppData\Local\Temp\runIssue07Validation.m`
- 验证产物：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_validation_20260918`

保存基线由当前生产链逐像素重建，最大 RGB 差为 `0`。

## 三、77 眉眼证据

在固定 `browEye` 选区中，实际语义证据最大值为：

| 类别 | ROI 最大证据 |
| --- | ---: |
| leftEye | 0.295373260975 |
| rightEye | 0.0104634976014 |
| leftBrow | 0.796359956264 |
| rightBrow | 0.367980450392 |

当前生产实现的眼部细节检测结果：

| 诊断字段 | 结果 |
| --- | ---: |
| `eyeDetailProtection` 最大值 | 0 |
| `periocularProtection` 最大值 | 0 |
| `doubleEyelidProtection` 最大值 | 0 |
| `lashProtection` 最大值 | 0 |
| `lashCore` 像素数 | 0 |
| browEye 硬保护比例 | 0.0115333333333 |
| browEye 内 eye-detail soft 非零比例 | 0 |

该硬保护比例来自现有其他保护来源，不代表低/中眼部 soft support 已启动。

## 四、Repair 消费证据

使用同一 `smoothingResult`、同一 Base/肤色/美白处理，仅以无 Repair 组合结果与当前 v3.2 输出比较；RGB 差异按每像素最大通道差统计：

- browEye Repair 相对无 Repair 的 RGB 差异均值：`4.8096`
- browEye Repair 相对无 Repair 的 RGB 差异最大值：`121`
- Repair Fine 修正均值：`0.00591166527835`
- Repair Mid 修正均值：`0.0127115654913`
- Fine 非零比例：`0.888066666667`
- Mid 非零比例：`0.158666666667`
- 已有硬保护像素最终相对输入最大 RGB 变化：`0`

因此，低置信眼部保护链失活时，Repair 仍会消费该区域的频率结构；这与 issue 05 的因果诊断一致，但本记录不把 RGB 下降单独称为视觉修复。

## 五、目标级合成探针

使用同一张 96×128 合成眼部结构，只改变左眼语义置信度，并保留远处孤立暗点负对照：

| 情形 | 眼证据 | `eyeDetailProtection` 最大值 | `periocularProtection` 最大值 | `doubleEyelidProtection` 最大值 | `lashCore` 像素数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 单眼低置信 | 0.30 | 0 | 0 | 0 | 0 |
| 单眼高置信对照 | 1.00 | 0.990000009537 | 0.945999979973 | 0.92 | 8 |
| 无眼证据 | 0 | 0 | 0 | 0 | 0 |
| 高置信 + 远处孤立暗点 | 1.00 | 0.990000009537 | 0.945999979973 | 0.92 | 8 |

远处孤立暗点在 `lashCore` 中的命中值为 `0`。高置信路径、无眼安全空结果和负对照均保持现有行为；但是低置信路径仍整体返回零，未满足 issue 07 的核心验收条件。

## 六、验收矩阵

| 验收项 | 结果 | 说明 |
| --- | --- | --- |
| 0.2--0.4 单眼 soft evidence 启动细节链 | **失败** | 0.30 探针的四类眼部保护均为 0，`lashCore=0` |
| 高置信 eye core / hard 契约保持 | 通过现有回归 | 合成高置信探针仍有原有细节保护；全量测试通过 |
| 极低/无眼证据安全为空 | 通过 | 无眼探针四类保护均为 0 |
| 左右眼不串联 | 未形成 issue 07 新增证据 | 当前低置信路径在启动前整体返回，不能替代目标级独立支持验证 |
| 中概率眉毛保持 soft、非 hard | 通过现有回归 | `testBeautyArtifactRegressions/testMidProbabilityBrowReceivesSoftProtection` 通过 |
| 远处孤立暗点负对照 | 通过 | `lashCoreAtPoint=0` |
| 77 眼睑/睫毛 Repair 消费下降 | 当前未修复 | 当前输出相对无 Repair 仍有均值 4.8096、最大 121 的差异 |
| 80 正常皮肤/雀斑/鼻部回归 | 未作为 issue 07 候选重跑 | 本次没有候选实现，因此不把既有 v3.2 结果冒充候选验证 |
| 缓存/算法版本变更 | 不适用 | 没有行为候选写回，未改版本和缓存契约 |

## 七、测试结果

目标测试按眼部细节、Repair 消费、Context/缓存和既有保护回归合并执行：

```matlab
restoredefaultpath;
addpath('E:\image_beauty\src');
addpath('E:\image_beauty\tests');
results = runtests({ ...
    'E:\image_beauty\tests\testPhase3Enhancements.m', ...
    'E:\image_beauty\tests\testBeautyContextV3.m', ...
    'E:\image_beauty\tests\testNoseSmoothing.m', ...
    'E:\image_beauty\tests\testResidualFeatureDiagnostics.m', ...
    'E:\image_beauty\tests\testBeautyArtifactRegressions.m'});
```

结果：`37 Passed, 0 Failed, 0 Incomplete`。

最终全量入口：

```matlab
restoredefaultpath;
addpath('E:\image_beauty\src');
addpath('E:\image_beauty\tests');
results = runtests('E:\image_beauty\tests');
```

结果：`124 Passed, 0 Failed, 0 Incomplete`，测试耗时约 `161.3989` 秒。

代码诊断：

```matlab
issues = checkcode('E:\image_beauty\src\+masks\buildTextureProtectionMask.m', '-id');
```

结果：`0` 条。

注意：以上测试全通过只说明现有 v3.2 契约和既有回归未被本次验证破坏；由于没有低置信眼部目标回归和生产候选实现，不能据此宣称 issue 07 通过。

## 八、临时产物

- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_validation_20260918\issue07_current_full_comparison.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_validation_20260918\issue07_current_browEye_comparison.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_validation_20260918\issue07_current_validation.csv`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_validation_20260918\issue07_current_validation.mat`

局部图按“原图 / 当前 v3.2 / 无 Repair / eye evidence / eye-detail protection / periocular protection / double-eyelid protection / hard protection / Repair 作用量”顺序拼接；图像仅作为证据，不把保护图转写为目标标注。

## 九、后续边界

若继续实现 issue 07，应只在 `buildTextureProtectionMask.m` 内增加低/中 eye evidence 的每眼受限邻域启动支持，保留 `.45` 高置信身份核心和硬保护规则；随后新增正式目标回归、左右眼隔离/范围负对照，并在独立工作树中按 77 固定基线重新生成候选输出。不得通过整体降低 `.45`、整框恢复原图、关闭 Repair、提高全局纹理保护或重启 06 结构门控候选来替代修复。
