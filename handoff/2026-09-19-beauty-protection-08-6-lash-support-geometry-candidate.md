# Issue 08.6：睫毛 Support 几何分离候选验证

## 1. 最终结论

本票已按固定 `77.png`、固定 `77-manual-lash-v1`、固定 `faceBox / browEye / lashRoi`、磨皮 `100`、美白 `15` 和当前生产链完成 Baseline / 08.4 Candidate / 08.6 Geometry Candidate 三组验证。

最终分流为：

> **Case C：Recall 和 Precision 均有小幅改善，但普通眼周 FP 连续带没有减少，反而增加；候选不通过，不进入生产实现。**

该结果说明：

- 现有 dark / edge / line evidence 可以补回一部分人工真值内的真实睫毛细线；
- 但把现有 evidence 做连通重构后，仍会把普通眼睑 / 眼周皮肤作为连续 support 保留下来；
- 本票提出的这一种 Evidence-Constrained Lash Support 几何重组，尚不足以同时完成真实睫毛覆盖和普通眼周分离；
- 不能据此扩大到“模型一定不足”“必须新增模型”或“Repair 公式一定有新根因”。

本票未修改任何生产 `src/`、GUI、模型、Repair / Smoothing 公式、公共 Context、版本字段或其它五官保护逻辑。

## 2. 固定基线

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 图像尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- 人工真值：`tests/eyelashManualLashMask77.m`
- 人工真值 ID：`77-manual-lash-v1`
- 人工真值像素：`576`
- 固定 Context：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- 运行前剥离派生 Context 字段和旧 `runtimeCache`；`runtimeCacheReused = false`
- 磨皮：`100`
- 美白：`15`

`manualLashMask` 仅用于 Recall / Precision、FP / FN 统计和最终视觉核对，没有参与 Candidate support 生成。

## 3. 08.6 候选实现

新增离线入口：

- `tests/diagnoseLashSupportGeometryCandidate.m`
- `tests/testLashSupportGeometryCandidate.m`

候选只复用当前 `src/+masks/buildTextureProtectionMask.m` 已存在的 detector 证据和尺度：

- `darkCandidate`
- `edgeCandidate`
- `lineSupport`
- `eyeNeighborhood`
- 当前 detector candidate seed
- 当前 `faceScale` 派生的 `softRadius`
- 当前 `featherSoftMask(..., .99)` soft weighting 语义

候选几何为：

```text
allowedEvidence = 现有 dark / edge / line evidence
                  ∩ 现有 eyeNeighborhood
                  ∩ 现有 near-eye 约束

candidateGeometrySeed = allowedEvidence 中与当前 detector seed
                        8-connected reconstruction 的区域

candidateLashProtection = 当前 featherSoftMask(candidateGeometrySeed,
                                                softRadius,
                                                .99)
```

候选未新增：

- 模型、图像算子、特征或经验阈值；
- 绝对像素半径；
- hard lash core；
- `manualLashMask` 生成路径；
- 其它 Mask 或全局 texture protection 调整。

内部 evidence 重建与生产基线的 `lashProtection` 最大误差为 `0`；Baseline / 08.4 冻结 compose 重建最大 RGB 差异均为 `0`。

## 4. 几何指标

| 指标 | Baseline | 08.4 Candidate | 08.6 Geometry Candidate |
|---|---:|---:|---:|
| support 像素 | `849` | `912` | `962` |
| TP 像素 | `211` | `216` | `242` |
| FP 像素 | `638` | `696` | `720` |
| FN 像素 | `365` | `360` | `334` |
| Recall | `0.366319` | `0.375000` | `0.420139` |
| Precision | `0.248528` | `0.236842` | `0.251559` |
| 最大 FP 连通分量 | `577` | `685` | `708` |

相对 08.4：

- Recall 增加 `0.045139`；
- Precision 增加 `0.014717`；
- 但 FP 增加 `24` 个像素；
- 最大 FP 连通分量增加 `23` 个像素；
- support 总量增加 `50` 个像素。

因此 08.6 虽然满足“Recall 不下降”和“Precision 提高”，但不满足“普通眼周 FP 连续带明显减少”。数值分诊为：

```text
numericGeometryDoesNotSupportCandidate
```

## 5. Repair 与 Final

固定 `manualLashMask` 内的 Repair 绝对作用量：

| 指标 | Baseline | 08.4 Candidate | 08.6 Geometry Candidate |
|---|---:|---:|---:|
| Repair Fine 绝对作用量总量 | `8.20346480648792` | `7.57702712443360` | `6.99271131650099` |
| Repair Mid 绝对作用量总量 | `18.5054764545722` | `15.6180965211660` | `13.2587563450944` |

相对 08.4：

- Fine 下降 `0.584315807932610`，约 `7.71%`；
- Mid 下降 `2.35934017607160`，约 `15.11%`。

固定 `manualLashMask` 内 Final 到原图距离：

| 指标 | 08.4 Candidate | 08.6 Geometry Candidate |
|---|---:|---:|
| RGB 距离均值 | `10.2309027777778` | `9.15972222222222` |
| luminance 距离均值 | `0.0339947650903178` | `0.0303897727743080` |

因此，08.6 没有导致真实睫毛上的 Repair 改善方向退化，且数值上进一步接近原图。但这不能抵消几何 FP 连续带未减少这一硬性失败条件。

## 6. 最终视觉验收

已按同一 `lashRoi`、同一显示尺度检查：

```text
A 原图
B Baseline
C 08.4 Candidate
D 08.6 Geometry Candidate
```

观察结论：

1. D 中主要上睫毛细线相对 B / C 有一定恢复，和 Repair Fine / Mid 数值改善方向一致。
2. D 仍保留沿主眼睑和普通眼周皮肤延伸的连续 support 带；`false_positive_08_6.png` 与 `support_geometry_comparison.png` 中未见相对 C 的明显收窄。
3. 08.6 的 FP 连续结构比 08.4 更大，而不是更少；因此不能确认普通眼周冻结 / 光环已减轻。
4. 不能仅凭 Recall、Precision 或真实睫毛 Final 距离下降判定候选通过。
5. `hardProtectionMask` changed pixels 为 `0`，`lashCore` changed pixels 为 `0`；本票没有通过新增 hard protection 掩盖几何问题。

## 7. 产物

正式诊断产物写入系统临时目录：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_6_lash_support_geometry_20260919`

包括：

- `original_lash.png`
- `baseline_support.png`
- `candidate_08_4_support.png`
- `candidate_08_6_support.png`
- `manual_vs_08_4_support.png`
- `manual_vs_08_6_support.png`
- `false_positive_08_4.png`
- `false_positive_08_6.png`
- `false_negative_08_4.png`
- `false_negative_08_6.png`
- `baseline_repair_fine_delta.png`
- `candidate_08_4_repair_fine_delta.png`
- `candidate_08_6_repair_fine_delta.png`
- `baseline_repair_mid_delta.png`
- `candidate_08_4_repair_mid_delta.png`
- `candidate_08_6_repair_mid_delta.png`
- `baseline_final_lash.png`
- `candidate_08_4_final_lash.png`
- `candidate_08_6_final_lash.png`
- `support_geometry_comparison.png`
- `final_geometry_comparison.png`
- `lash_support_geometry_metrics.csv`
- `lash_support_geometry_diagnostic.mat`

## 8. 测试结果

目标测试：

- `testLashSupportGeometryCandidate`：**2 Passed, 0 Failed, 0 Incomplete**
- 结果：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_6_lash_support_geometry_20260919_test_results.mat`

全量 `tests/` 回归：

- **147 Passed, 0 Failed, 0 Incomplete**
- 单个 MATLAB R2024a 批处理进程完成
- 结果：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_6_lash_support_geometry_20260919_full_test_results.mat`

运行中反复出现既有 PNG 元数据警告：

```text
iCCP: cHRM chunk does not match sRGB
```

该警告来自固定 `77.png` 的 PNG 元数据，不影响 MATLAB 图像数组、候选公式、产物或测试结果。

## 9. 修改范围与后续边界

本票新增：

- `tests/diagnoseLashSupportGeometryCandidate.m`
- `tests/testLashSupportGeometryCandidate.m`
- 本 handoff 记录

未修改：

- `src/` 生产算法；
- GUI；
- 模型及依赖；
- Repair / Smoothing / compose 公式；
- 版本号；
- brow / nose / ear / lip / structure protection。

本票不授权生产落地。下一步只能重新设计或验证更强的“真实睫毛细线—普通眼周”分离证据；不得通过调高同一 support 的 soft strength、扩张 hard protection、修改 Repair 全局公式或引入人工真值来掩盖本票 Case C 结果。
