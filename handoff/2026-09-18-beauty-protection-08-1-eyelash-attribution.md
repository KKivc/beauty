# Issue 08.1：剩余睫毛细线损失归因交接

## 1. 结论

本票已完成固定 77 样本的离线阶段归因与保护覆盖核对，当前数值分诊归入：

> **Case B：Repair 是剩余睫毛损失的主要新增贡献阶段。**

依据不是最终 RGB 差值，而是同一次生产运行中固定 `lashRoi` 的 Fine/Mid 阶段作用量和同尺度局部探针：

- `Smoothing-only` 相对原图的局部视觉主体基本保留；
- `Smoothing + Repair` 相对 `Smoothing-only` 出现明显额外的局部纹理/亮度改变；
- `lashRoi` 的 Repair 总平均绝对作用量为 `0.0224402751913719`，Smoothing 为 `0.0058941612411691`，Repair/Smoothing = `3.80720415903`；
- 同一 `lashRoi` 中，Repair Fine/Mid 的非零比例分别为 `0.766125235404896`、`0.259063088512241`，Smoothing Fine/Mid 的非零比例均为 `0.429496233521657`。

该结论只定位新增贡献阶段，不等价于“睫毛已经修好”，也不授权直接修改 Repair 公式或新增 hard lash core。

## 2. 固定输入与人工 ROI

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- `lashRoi` 覆盖范围：`x=102..278，y=248..295`
- `lashRoi` 是根据 77 原图可见上睫毛细线人工一次性固定的矩形，不由 detector、语义 Mask 或待验证保护结果反推；后续候选必须复用该坐标。

当前入口支持多个固定子 ROI，但本次使用一个矩形，不动态调整。

## 3. 实现文件

新增：

- `tests/diagnoseResidualEyelashLoss.m`
- `tests/testResidualEyelashLossDiagnostics.m`
- `handoff/2026-09-18-beauty-protection-08-1-eyelash-attribution.md`

本票没有修改生产算法源码，以下文件保持本票前的工作区状态：

- `src/+masks/buildTextureProtectionMask.m`
- `src/+beauty/smoothSkinTexture.m`
- `src/+beauty/repairSkinBlemishes.m`
- `src/+beauty/buildBlemishMap.m`
- `src/beautyPipelineContract.m`
- 其他 Base、tone、whitening、strengthMap、GUI 和模型文件

注意：工作区在本票开始前已经存在 Issue 08 相关的未提交生产改动；本票只新增诊断与测试文件，没有覆盖这些改动。

## 4. 诊断口径

`diagnoseResidualEyelashLoss` 的一次运行流程：

1. 从固定 77 Context 基线读取语义与基础字段；
2. 明确剥离 `runtimeCache`、`textureProtectionMask`、`structureProtectionMask`、`strengthMap` 等全部派生字段；
3. 调用当前工作区生产入口，重新生成 Issue 08 的 Beauty Masks、frequency、Smoothing 和 Repair；
4. 校验 `reusedRuntimeCache=false`，并校验各阶段的 `fineBefore/fineAfter/midBefore/midAfter` 是同一条连续链；
5. 同一次运行保存：
   - 原始 `frequency`；
   - Smoothing 输出 frequency；
   - Repair 输出 frequency；
   - `textureProtectionMask`；
   - `eyeDetailProtection`；
   - `lashProtection`；
   - `doubleEyelidProtection`；
   - `hardProtectionMask`；
6. 生成三组纯 Fine/Mid 探针：
   - A：原图；
   - B：`Base(original) + Mid(smoothed) + Fine(smoothed)`；
   - C：`Base(original) + Mid(repaired) + Fine(repaired)`。

B/C 探针均保留输入图原始 Cb/Cr，并且没有应用 `evenSkinLuminance`、tone、whitening 或最终生产合成。这里的 `Base(original)` 仅是频率重建所需的原始 Base 频带；**没有应用 Base 处理阶段**。

## 5. 频率阶段指标

以下数值来自 `eyelash_stage_metrics.csv`，作用量定义为绝对阶段差分的统计，不直接定义视觉损伤分数。

### 5.1 固定 `lashRoi`

| 指标 | Smoothing Fine | Smoothing Mid | Repair Fine | Repair Mid |
|---|---:|---:|---:|---:|
| 平均绝对作用量 | 0.000764709208140243 | 0.00512945203302886 | 0.00689985342824417 | 0.0155404217631277 |
| 最大绝对作用量 | 0.0375442197157533 | 0.0906710613158928 | 0.277667941870627 | 0.255702904753966 |
| 非零比例 | 0.429496233521657 | 0.429496233521657 | 0.766125235404896 | 0.259063088512241 |

聚合分诊：

- Smoothing：平均绝对作用量 `0.0058941612411691`；最大 `0.0906710613158928`；任一 Fine/Mid 非零比例 `0.429496233521657`。
- Repair：平均绝对作用量 `0.0224402751913719`；最大 `0.277667941870627`；任一 Fine/Mid 非零比例 `0.770951035781544`。
- Repair/Smoothing 平均作用量比：`3.80720415903`。

### 5.2 固定 `browEye`

- Smoothing 聚合平均绝对作用量：`0.00758918784490958`。
- Repair 聚合平均绝对作用量：`0.0129489177459781`。
- Smoothing 与 Repair 均有作用，但在更小的 `lashRoi` 内 Repair 的相对新增作用更强，因此最终按 `lashRoi` 归因。

## 6. 保护覆盖核对

`lashRoi` 内统计如下。比例分母是整个固定矩形像素数 `8496`，不是人工标注的睫毛线像素召回率；因此不能单独替代空间视觉核对。

| 保护项 | 平均值 | 最大值 | 非零比例 | 强保护比例（阈值 0.50） |
|---|---:|---:|---:|---:|
| `textureProtectionMask` | 0.187765806783 | 1 | 0.281897363465160 | 0.195268361581921 |
| `eyeDetailProtection` | 0.0620993959994569 | 0.990000009536744 | 0.106638418079096 | 0.0708568738229755 |
| `lashProtection` | 0.0551968984886401 | 0.990000009536744 | 0.0992231638418079 | 0.0642655367231638 |
| `doubleEyelidProtection` | 0.0152553318387596 | 0.920000016689301 | 0.0254237288135593 | 0.0153013182674200 |
| `hardProtectionMask >= 0.999` | — | — | 0.0896892655367232 | — |
| `lashCore` | — | — | 0 | — |

空间核对结论：

1. `eyelash_coverage_comparison.png` 中，`eyeDetailProtection` 与 `lashProtection` 的高值轮廓与原图上睫毛带存在局部重合，说明 Issue 08 的 soft support 已覆盖部分实际睫毛位置；
2. 覆盖不是整段连续线覆盖，仍可见保护空段，不能把保护 Mask 的最大值非零解释为睫毛完整覆盖；
3. `lashCoreFraction = 0`，说明本次固定 `lashRoi` 内没有由当前检测结果产生 hard lash core；
4. `hardProtectionMask` 在矩形内的非零比例为 `0.0896892655367232`，但 hard mask 是多个 hard source 的并集，不能据此认定睫毛获得 hard protection；应以 `lashCore` 和覆盖图中的实际位置为准；
5. 因此当前证据同时支持：**Repair 是主要新增作用阶段；现有 soft protection 对实际睫毛只有局部空间覆盖，仍存在覆盖不足或强度不足的后续修复候选。**

## 7. 原始 frequency 与一致性验收

- 原始 frequency 重建最大误差：`2.7755575615628914e-17`。
- Smoothing-only 与 Smoothing+Repair 使用同一次生产调用取得的 frequency 和 Mask。
- `runtimeCache` 未复用，旧派生 Context 已剥离。
- Base/tone/whitening 处理阶段在两张离线探针中关闭。
- 诊断脚本对 Smoothing 与 Repair 的前后频率字段逐项做一致性校验。

## 8. 产物位置

正式代码与交接：

- `E:\image_beauty\tests\diagnoseResidualEyelashLoss.m`
- `E:\image_beauty\tests\testResidualEyelashLossDiagnostics.m`
- `E:\image_beauty\handoff\2026-09-18-beauty-protection-08-1-eyelash-attribution.md`

本次离线产物未写入项目目录，位于系统临时目录：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_1_eyelash_20260918`

其中包括：

- `eyelash_original.png`
- `eyelash_smoothing_only.png`
- `eyelash_smoothing_plus_repair.png`
- `eyelash_texture_protection.png`
- `eyelash_eye_detail_protection.png`
- `eyelash_lash_protection.png`
- `eyelash_double_eyelid_protection.png`
- `eyelash_hard_protection.png`
- `eyelash_smoothing_fine_delta.png`
- `eyelash_smoothing_mid_delta.png`
- `eyelash_repair_fine_delta.png`
- `eyelash_repair_mid_delta.png`
- `eyelash_stage_metrics.csv`
- `eyelash_stage_comparison.png`
- `eyelash_coverage_comparison.png`
- `eyelash_diagnostic_data.mat`

## 9. 测试结果

目标测试：

- `testResidualEyelashLossDiagnostics`：**5 Passed, 0 Failed, 0 Incomplete**。

Issue 08 固定回归：

- 77 基线重建最大 RGB 差：`0`；两次无缓存候选计算最大 RGB 差：`0`；hard mask changed pixels：`0`；
- 80 固定回归：基线重建最大 RGB 差 `0`；两次无缓存候选计算最大 RGB 差 `0`；鼻孔、鼻梁、鼻翼、普通皮肤、雀斑、头发、背景均完成输出。

全量 `tests/`：

- **135 Passed, 0 Failed, 0 Incomplete**。

PNG 读取过程有 `iCCP: cHRM chunk does not match sRGB` 警告，但不影响测试结果或输出产物。

## 10. 后续边界

本票不修改生产公式，因此下一张票只能围绕以下方向继续：

- Repair 对现有 soft lash protection 的消费；或
- 现有 soft lash protection 在真实睫毛像素上的覆盖/强度不足。

当前不应据此宣称：

- 眼部问题已经全部解决；
- 应新增 hard lash core；
- 应全局提高 `textureProtection`；
- 应关闭 Repair、Mid 或降低全局 smoothing。
