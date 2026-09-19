# 06：验证并按证据落实独立的 Repair 结构门控

记录日期：2026-09-18。任务在独立工作树完成；原项目 `E:\image_beauty` 只作为只读来源，未写回、未提交、未推送、未删除文件。

## 结论

本票唯一候选 `structureGate = 1 - structureProtection` 已完成固定 77 离线验证，但未满足“离线有效且生产无退化”的落地条件，因此**未保留生产候选补丁**。本票最终只交接候选诊断证据、验证入口和当前工作树中的既有 v3.2 基线复制内容，不宣称 Repair 已修复。

候选确实收紧了结构约束并降低了耳部、鼻孔和眉眼的 Repair 权重，但固定 77 的候选生产输出相对旧基线仍有最大 RGB 差 117，且离线候选的结构相关指标出现不一致：耳部和眉眼低频结构梯度分别约为旧基线的 1.0064 和 1.1418，鼻孔为 0.9224；这不能仅凭 RGB 差或修复量下降称为质量改善。候选进入生产后，全量回归出现 2 项既有行为失败，故按票内授权撤回本票候选生产修改。

## 基线来源与范围

- 当前任务工作树：`E:\home\jjiio\.codex\worktrees\156b\image_beauty`
- 原项目只读来源：`E:\image_beauty`
- 工作树默认旧提交：`c784cd4`
- 复制并核对的当前 v3.2 Repair：`E:\home\jjiio\.codex\worktrees\156b\image_beauty\src\+beauty\repairSkinBlemishes.m`
- 复制并核对的当前契约：`E:\home\jjiio\.codex\worktrees\156b\image_beauty\src\beautyPipelineContract.m`
- 固定完整 77 基线：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- 05 已有固定 77 分量证据：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid`
- 03 既有 77 记录：`E:\image_beauty\handoff\2026-09-18-beauty-protection-03.md`
- 05 依赖记录复制到任务工作树：`E:\home\jjiio\.codex\worktrees\156b\image_beauty\handoff\2026-09-18-beauty-protection-05.md`
- 其他旧 probe 未使用。80 只复用了既有完整证据，未重跑完整图集；既有批处理汇总：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_batch_summary.mat`，其中 80 明细：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_80_final\residualFeatureDiagnosticData.mat`。

契约仍为：`schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。本票没有新增公共字段、schema 或 artifact 版本；既有 v3.2 复制内容与本票候选保持分开。

## 离线候选验证

候选入口：

`E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\offlineStructureGateCandidate.m`

运行命令：

```matlab
addpath('E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests', '-begin');
offlineStructureGateCandidate
```

候选严格从固定 77 MAT 读取原 `frequency`、Beauty Masks、blemishMap、Fine/Mid 参考输入和既有结果，只重新计算结构门控、权重、参考可靠度、Reference、Target 与 Fine/Mid 合成；没有缩放已 clip 权重，没有清零 Repair，没有改变检测、参考目标来源、鼻部规则或纹理门控顺序。

离线产物：

- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline\offlineStructureGateCandidate.mat`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline\offlineStructureGateComparison.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline\offlineStructureGateMaps.png`

关键结果：

| ROI | 旧结构门控均值 | 候选结构门控均值 | 旧 Fine 权重均值 | 候选 Fine 权重均值 |
| --- | ---: | ---: | ---: | ---: |
| ear | 0.9415 | 0.8762 | 0.235768 | 0.191672 |
| nostril | 0.7690 | 0.6698 | 0.274552 | 0.223640 |
| browEye | 0.8880 | 0.7886 | 0.202936 | 0.121172 |
| noseBridge | 0.9063 | 0.8962 | 0.087551 | 0.084441 |
| noseWing | 0.8459 | 0.7900 | 0.181871 | 0.154064 |
| hair | 1.0000 | 1.0000 | 0 | 0 |
| background | 1.0000 | 1.0000 | 0 | 0 |

- 全图结构门控均值：`0.974798 -> 0.959632`；均值绝对差 `0.015166`，最大差 `0.899502`。
- 候选输出相对旧基线：最大 RGB 差 `117`，均值差 `0.810781`。
- 既有 v3.2 完整 Repair 重建与保存输出的逐像素 RGB 最大差为 `0`，旧基线核对通过。
- 离线候选相对无 Repair 的 RGB 差均值仍非零：ear `3.9675`、nostril `5.4284`、browEye `3.4673`；因此不是通过全局关闭 Repair。
- 离线候选相对平滑后瑕疵能量下降：ear `0.319855`、nostril `0.383340`、browEye `0.241926`，均保留非零修复。
- 离线低频结构梯度保留率（相对平滑前 `base+mid`）：ear `1.006427`、nostril `0.922411`、browEye `1.141752`。该结果存在区域间不一致，不能作为全面结构改善结论。
- 固定头发和背景 ROI 的候选权重保持为 0；相关安全选区无新增污染证据。

## 生产候选验证与撤回

生产验证入口：

`E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\runStructureGateProductionValidation.m`

该入口曾在候选临时落地期间执行，之后候选源码已恢复为当前 v3.2 基线。最终生产候选产物保留在：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_production`

生产候选执行核对：

- 保存的 v3.2 基线完整 Repair 重建最大 RGB 差：`0`。
- 生产候选相对旧基线最大 RGB 差：`117`；全图均值差：`0.305408`。
- 缓存复用标志：`1`；缓存复用与移除 runtimeCache 的直接计算最大 RGB 差：`0`。
- 生产候选 ROI 的 Repair 能量从旧生产基线到候选：ear `0.029266 -> 0.017791`，nostril `0.042625 -> 0.024272`，browEye `0.025173 -> 0.017880`；均仍有非零修复。
- 生产候选低频结构梯度保留率：ear `0.954711`、nostril `0.920762`、browEye `1.071336`。
- 头发和背景 ROI 生产候选权重为 0，输出相对旧基线最大差为 0。

生产候选全量回归发现：

1. `testPortraitBeautyHelpers/testBeautyProtectsHairHighlightsAndChroma` 失败：实际值 `255` 未小于 `255`。
2. `testPortraitBeautyHelpers/testFrecklesAttenuateProgressivelyWithTextureRetained` 失败：实际值 `0.075949805209440` 大于允许上限 `0.042398499629737`。

因此候选**没有落地保留**。上述失败不是通过放宽阈值、修改无关算法或删除既有改动处理；候选生产补丁已撤回。撤回后 Nose 目标回归恢复，最终全量测试通过。

## 测试结果

- `checkcode`：`repairSkinBlemishes.m`、`beautyPipelineContract.m`、`testNoseSmoothing.m`、`runStructureGateProductionValidation.m` 均无代码诊断。
- 06 目标测试：`testResidualFeatureDiagnostics.m`，`4 Passed, 0 Failed, 0 Incomplete`。
- 受影响鼻部回归（撤回候选后）：`6 Passed, 0 Failed, 0 Incomplete`。
- 候选临时落地期间的受影响目标测试：`Residual=4`、`Nose=7` 通过，但不抵消全量回归失败。
- 候选撤回后的最终全量测试：`122 Passed, 0 Failed, 0 Incomplete`。
- 模型缓存 `Shape_To_ResizeLayer` 实例化失败仍是已知限制；本票未修模型、未下载资源，固定 MAT 只支持已保存 Context/算法验证，不称当前模型推理、GUI 打开或全流程端到端通过。

## 实际工作树差异

工作树状态中，以下是复制来的既有 v3.2 基线或05成果，不是本票新生产补丁：

- `src/+beauty/repairSkinBlemishes.m`：相对旧提交包含既有 v3.2 的纹理门控/参考采样改动；其当前内容与原项目对应文件 SHA-256 一致：`e7ab8020a7e8a4b25c55f0712819529886fbe4709bf3a40fdb6b4b30698fc87f`。
- `src/beautyPipelineContract.m`：既有算法版本 `v3.2`，schema/artifact 未变；与原项目 SHA-256 一致：`b51b9bd871a6bca1e07f3deb28e236bf87ac0d38cc2907a0d9701c3cfaf0c28e`。
- `tests/testBeautyContextV3.m`：既有版本断言 `v3.2`。
- `tests/testNoseSmoothing.m`：既有 fixture 补充 `textureProtectionMask`，没有保留本票候选测试。
- `tests/diagnoseResidualFeatureArtifacts.m`、`tests/testResidualFeatureDiagnostics.m`、`handoff/2026-09-18-beauty-protection-05.md`、`tests/offlineStructureGateCandidate.m`、`tests/runProductionValidation.m`：05 诊断和交接成果复制/保留。

本票新增的最小验证入口是：

- `tests/runStructureGateProductionValidation.m`：固定 77 生产链候选验证、参考采样变化、缓存复用一致性和局部量化记录；候选失败后仅作为诊断入口，不代表生产候选保留。
- `handoff/2026-09-18-beauty-protection-06.md`：本中文交接记录。

当前任务工作树未保留 `structureGate = 1 - structureProtection` 的生产源码修改；原项目 `E:\image_beauty` 未被写回。
