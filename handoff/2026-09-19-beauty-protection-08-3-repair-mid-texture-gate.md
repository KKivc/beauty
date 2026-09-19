# Issue 08.3：Repair Mid 对连续纹理保护的实际消费验证

## 1. 结论

本票已按固定 `77.png`、固定人工真值 `77-manual-lash-v1` 和当前工作区生产链完成 Repair Mid 的连续 `textureGate` 单因素验证，结果归入：

> **Case A：当前 Repair Mid 确实消费现有连续 `textureProtectionMask` / `textureGate`；取消该 gate 后，固定真实睫毛位置出现明确的 Mid 局部变化，最终局部重建差异沿人工真值可见。当前残留更偏向 Protection 较弱位置。**

因此可以确认：

> **当前 Repair Mid 不是“未接入”或“完全失效”；若继续收敛，应优先针对已验证真实睫毛位置的现有 soft protection 局部覆盖/强度不足做独立候选验证。**

本票不是生产修复票；没有修改生产算法、Mask Builder、公共 Context、模型、GUI 或版本字段。

## 2. 固定基线

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 图像尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `lashRoi = [102 248 177 48]`
- `manualLashMask`：复用 `tests/eyelashManualLashMask77.m`，ID 为 `77-manual-lash-v1`
- 人工真值像素：`576`
- 磨皮：`100`
- 美白：`15`
- 固定 Context：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- 运行前剥离旧 `runtimeCache` 和派生 Mask；`runtimeCacheReused = false`
- 使用当前工作区生产链；未重新标注真实睫毛、未重新选择 ROI

## 3. 实现文件

新增：

- `tests/diagnoseRepairMidTextureGateConsumption.m`
- `tests/testRepairMidTextureGateConsumption.m`
- 本 handoff 文件

诊断入口严格完成以下步骤：

1. 先加载固定且独立于诊断结果的 `manualLashMask`；
2. 运行一次当前生产链，取得同一次运行的 frequency、Protection Mask、Smoothing、Repair；
3. 在诊断代码内严格复写当前 `repairSkinBlemishes.m` 的 Mid gate 前公式；
4. 核对 `textureGate = 1 - textureProtectionMask`，以及
   `mediumWeightAfterTextureGate = mediumWeightBeforeTextureGate .* textureGate`；
5. 仅令 Mid 的 `textureGate = 1` 构造 NoTextureGate 反事实，冻结 Base、Fine、target、reference、structureGate、置信度、allowed、Blob、noseMidGate、Smoothing 和 Base/tone/whitening；
6. 只在固定 `manualLashMask` 内统计连续值，并输出局部叠加图、CSV 和 MAT。

## 4. 数值验收结果

| 项目 | 实际结果 |
|---|---:|
| `mediumWeightAfterTextureGate` 公式最大误差 | `0` |
| Baseline Mid delta 公式复算最大误差 | `2.4719809532669501e-17` |
| 真值内 `textureProtectionMask` 均值 | `0.414148092425118` |
| 真值内 `textureGate` 均值 | `0.585851907574882` |
| 真值内 Mid gate 前权重均值 | `0.4696915705994` |
| 真值内 Mid gate 后权重均值 | `0.283085154823303` |
| 真值内权重衰减总量 | `107.485295487032` |
| Baseline Repair Mid 绝对作用量总量 | `18.5054764545722` |
| NoTextureGate Repair Mid 绝对作用量总量 | `39.1945058095728` |
| 取消 gate 带来的 Mid 局部绝对差总量 | `20.6890293550006` |
| 取消 gate 带来的最终亮度绝对差总量 | `20.6890293550006` |
| 最终 RGB 发生变化的人工真值像素 | `191` |
| Baseline Mid 作用量按 Protection 加权均值 | `0.286944115307624` |

Baseline Mid 作用量按 Protection 加权均值低于人工真值整体 Protection 均值，说明当前 Mid 作用更偏向真实睫毛中保护较弱的位置。NoTextureGate 局部结果相对 Baseline 的变化集中沿人工睫毛真值出现；对比图中右侧主眼睫毛区域可见明显局部亮度/纹理差异。

## 5. 产物

正式产物写入系统临时目录，不写入项目仓库：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_3_mid_texture_gate_20260919`

主要文件：

- `mid_texture_protection.png`
- `mid_texture_gate.png`
- `mid_weight_before_texture_gate.png`
- `mid_weight_after_texture_gate.png`
- `mid_weight_attenuation_by_texture_gate.png`
- `mid_baseline_delta.png`
- `mid_no_texture_gate_delta.png`
- `mid_baseline_vs_no_texture_gate.png`
- `mid_texture_gate_metrics.csv`
- `mid_texture_gate_diagnostic.mat`

## 6. 测试结果

目标测试：

- `testRepairMidTextureGateConsumption`：**2 Passed, 0 Failed, 0 Incomplete**
- 覆盖固定真值独立性、非固定 fixture 拒绝、公式一致性、单因素冻结、产物完整性和 CSV 可读性。

运行时出现 PNG 元数据警告：`iCCP: cHRM chunk does not match sRGB`；不影响 MATLAB 数组、公式核对或测试结果。

全量 `tests/` 回归：**141 Passed, 0 Failed, 0 Incomplete**，总测试时间 `141.1218` 秒；结果文件：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_3_mid_texture_gate_20260919\full_test_results.mat`。

## 7. 结论边界

本票只支持固定 77 样本上的以下结论：

- Repair Mid 已实际消费现有连续 `textureGate`；
- 取消 gate 会改变固定真实睫毛位置的 Mid 和最终局部重建；
- 当前残留更偏向 Protection 较弱的真实睫毛位置；
- 后续可针对已验证位置设计局部 soft protection 候选。

本票不支持：

- 全局提高 `textureProtection`；
- 新增 hard lash core；
- 关闭 Repair 或 Mid；
- 修改 Mid target/reference、structureGate、BiSeNet、Base/tone/whitening；
- 将 77 的结果外推到所有图像；
- 宣称已找到所有睫毛异常的唯一根因。
