# Issue 08.5：睫毛 Soft Protection 修复充分性上界验证

## 1. 结论

本票已按固定 `77.png`、固定 `77-manual-lash-v1`、Issue 08.4 的固定坐标和当前工作区生产链完成 Baseline / 08.4 Candidate / Candidate Upper Bound 三组验证。

最终分流为：

> **Case C：Upper Bound 能明显保留主要睫毛，但在完全相同的 Candidate support 内把保护强度提升到 1 后，普通眼周出现不可接受的冻结/光环副作用；当前 support 几何包含过多普通皮肤，不能通过单纯提高 protection 强度解决。**

数值上，Upper Bound 确实把主要睫毛进一步拉回原图；视觉上，右侧主眼睫毛主体和左下方截断睫毛细线均明显比 Baseline / Candidate 更清楚，主要细线可以连续辨认，未见主体被整段磨掉。但 Upper Bound 同时对 Candidate support 内的大量非人工睫毛像素施加满强度保护，`browEye & ~manualLashMask` 内出现明显连续带状变化和冻结/光环。故不能进入 Case A，也不能把 Upper Bound 直接作为生产强度。

本票未修改任何 `src/` 生产源码、GUI、模型、Repair / Smoothing 公式、公共 Context 或版本字段。

## 2. 固定基线

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 图像尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- 人工真值：`tests/eyelashManualLashMask77.m`
- 人工真值 ID：`77-manual-lash-v1`
- 人工真值像素：`576`
- 磨皮：`100`
- 美白：`15`
- 固定基线 Context：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- `runtimeCacheReused = false`
- Baseline / Candidate / Upper Bound 复用同一输入、frequency、blemishMap、Base、tone、whitening；Upper Bound 只改变同一 Candidate lash support 内的 protection 强度。
- `manualLashMask` 只用于统计和人工验收，没有参与 Candidate 或 Upper Bound 的保护生成。

运行时出现既有 PNG 元数据警告：

```text
iCCP: cHRM chunk does not match sRGB
```

该警告来自 `77.png` 的 PNG 元数据，不影响图像数组、公式核对、产物或测试结果。

## 3. Upper Bound 严格构造核对

Candidate 复用 Issue 08.4 的局部 soft closing 结果。Upper Bound 使用：

```matlab
candidateSupport = candidateLashProtection > 0;
upperBoundLashProtection = candidateLashProtection;
upperBoundLashProtection(candidateSupport) = 1;
```

随后继续执行当前既有的：

```text
upperBound eyeDetailProtection
→ upperBound textureProtectionMask
→ 当前 Smoothing
→ 当前 Repair
→ 当前 Base/tone/whitening
→ 当前 compose
```

核对结果：

- Candidate support 像素：`912`
- Upper Bound support 像素：`912`
- Candidate → Upper Bound support changed pixels：`0`
- Candidate support 外的 Upper Bound texture 增加像素：`0`
- Candidate support 内被提升到上界的像素：`912`
- `manualLashMask` 内 Candidate `lashProtection` 均值：`0.229155737350488`
- `manualLashMask` 内 Upper Bound `lashProtection` 均值：`0.375`
- Upper Bound `lashProtection` 在同一 support 内最大值：`1`
- Baseline → Candidate → Upper Bound 的 hardProtectionMask changed pixels：`0 / 0 / 0`
- Baseline → Candidate → Upper Bound 的 lashCore changed pixels：`0 / 0 / 0`
- Baseline / Candidate / Upper Bound hard-protected final RGB changed count：`0 / 0 / 0`

因此 B → C 的唯一变量满足票据要求：同一 Candidate lash soft support 内的 protection 强度。

## 4. Repair 统计（固定 manualLashMask 内）

| 指标 | Baseline | 08.4 Candidate | Candidate Upper Bound |
|---|---:|---:|---:|
| Repair Fine 绝对作用量总量 | `8.20346480648792` | `7.57702712443360` | `4.83838686601722` |
| Repair Mid 绝对作用量总量 | `18.5054764545722` | `15.6180965211660` | `5.45319092676261` |

Upper Bound 相对 Candidate 的进一步下降：

- Fine：`2.73864025841638`
- Mid：`10.1649055944034`

这确认同一 support 内提高 protection 强度确实进一步抑制了当前 Repair Fine / Mid 对人工真实睫毛的作用。

## 5. Final 到原图距离（固定 manualLashMask 内）

| 指标 | Baseline | 08.4 Candidate | Candidate Upper Bound |
|---|---:|---:|---:|
| 最终 RGB 到原图距离均值 | `11.4565972222222` | `10.2309027777778` | `4.76736111111111` |
| 最终 luminance 到原图距离均值 | `0.0380998909513494` | `0.0339947650903178` | `0.0158082794832408` |

Upper Bound 相对 Candidate 的进一步改善：

- RGB 距离均值下降：`5.46354166666667`
- luminance 距离均值下降：`0.0181864864680769`

数值上，Upper Bound 明显优于 Candidate；但该数值改善不能单独作为通过条件，因为普通眼周副作用不满足绝对视觉要求。

## 6. 普通眼周副作用

统计范围为 `browEye & ~manualLashMask`，不把人工真值外的区域当作睫毛成功证据。

Candidate → Upper Bound：

- 最终 RGB 变化总量：`13077`
- 最终 RGB 变化均值：`0.893298722590341`
- 发生 RGB 变化的像素：`1414`
- 变化最大值：`118`
- 最终 luminance 变化总量：`42.8091814509001`
- 最终 luminance 变化均值：`0.00292432416496346`
- 发生 luminance 变化的像素：`5542`
- luminance 最大变化：`0.396935829560420`

Candidate support 总计 `912` 像素，而与人工真值的交集只有 `216` 像素；其余 `696` 个 support 像素位于人工真值之外，主要落在普通眼睑/眼周皮肤。把这些像素统一提升到 `1` 后，副作用图中可见沿睫毛形成连续的带状变化，包含明显的冻结/光环区域，而不是只影响真实睫毛细线。

重点图：

- `candidate_upper_bound_side_effect.png`：Candidate / Upper Bound browEye、固定色阶 RGB 差异和 manualLashMask 外的变化像素。
- `candidate_support.png` / `upper_bound_lash_protection.png`：显示 support 几何覆盖了比人工真实睫毛更宽的眼周区域。

## 7. 绝对视觉验收

已按同一 `lashRoi`、同一显示尺度核对主图：

```text
A 原图
B Baseline
C 08.4 Candidate
D Candidate Upper Bound
```

观察结果：

1. D 中右侧主眼的主要上睫毛细线相对 B / C 明显变深，主体可以连续辨认；左下方被 ROI 截断的可见睫毛也有相同方向的改善。
2. D 未改变 hard protection 或 lashCore，未出现因 Upper Bound 新增 hard mask 导致的硬保护变化。
3. D 的改善不是只在数字上成立，RGB / luminance 到原图距离和局部视觉均同步改善。
4. 但 D 在睫毛外侧及下方普通眼睑/皮肤区域形成明显的连续保护带；`candidate_upper_bound_side_effect.png` 中可见较大范围的 RGB 变化和 manualLashMask 外变化像素。
5. 该带状区域属于普通眼周冻结/光环副作用，不满足票据要求的“不能出现明显保护光环、一条完整不磨皮带或新的硬边”。

因此最终不能判定为 Case A。由于主要睫毛能保留、但同一 support 的强度上限会冻结过多普通皮肤，判定为 **Case C**。

## 8. 测试结果

新增文件：

- `tests/diagnoseLashProtectionSufficiencyUpperBound.m`
- `tests/testLashProtectionSufficiencyUpperBound.m`
- 本 handoff 文件

目标测试：

- `testLashProtectionSufficiencyUpperBound`：**2 Passed, 0 Failed, 0 Incomplete**

测试覆盖：

- 固定 fixture 拒绝；
- 固定 `77-manual-lash-v1` 与人工真值独立性；
- 无旧 runtimeCache 复用；
- Candidate / Upper Bound support 完全一致；
- Upper Bound 单因素 mask 隔离；
- Fine / Mid 绝对作用量；
- RGB / luminance 到原图距离；
- hardProtectionMask、lashCore 和 hard-protected final RGB 不变；
- 必需 PNG / CSV / MAT 产物和 CSV 字段完整性。

全量 `tests/` 回归：

- **145 Passed, 0 Failed, 0 Incomplete**
- 结果文件：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_5_lash_protection_sufficiency_upper_bound_20260919_full_test_results.mat`

## 9. 产物位置

正式诊断产物：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_5_lash_protection_sufficiency_upper_bound_20260919`

必须图像已生成：

- `original_lash.png`
- `baseline_final_lash.png`
- `candidate_final_lash.png`
- `upper_bound_final_lash.png`
- `baseline_candidate_upperbound_comparison.png`
- `candidate_lash_protection.png`
- `upper_bound_lash_protection.png`
- `candidate_support.png`
- `baseline_repair_fine_delta.png`
- `candidate_repair_fine_delta.png`
- `upper_bound_repair_fine_delta.png`
- `baseline_repair_mid_delta.png`
- `candidate_repair_mid_delta.png`
- `upper_bound_repair_mid_delta.png`
- `candidate_upper_bound_side_effect.png`

数据产物：

- `lash_protection_sufficiency_upper_bound_metrics.csv`
- `lash_protection_sufficiency_upper_bound_diagnostic.mat`

## 10. 后续边界

本票支持的结论是：

> 在固定 77 样本上，现有 08.4 Candidate support 内提高 protection 强度可以显著降低睫毛上的 Repair Fine / Mid 并恢复主要睫毛，但该 support 同时覆盖过多普通眼周；因此当前问题不能只用同一 support 内的强度调参解决。

下一步应重新检查 lash support 的几何覆盖方式，尤其是如何把真实睫毛细线与普通眼睑/皮肤分开；不应：

- 把 Upper Bound 直接合入生产；
- 把生产 `lashProtection` 全设为 `1`；
- 继续用同一过宽 support 做强度调参；
- 扩大 hard protection 或新增 hard lash core；
- 修改 Repair / Smoothing 全局公式；
- 将固定 77 的 Case C 直接外推到所有图像。
