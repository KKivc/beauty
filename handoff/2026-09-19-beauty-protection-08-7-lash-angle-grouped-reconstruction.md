# Issue 08.7：睫毛多角度响应的 Angle-Grouped Reconstruction 候选验证

## 1. 最终结论

已按固定 `77.png`、固定 `77-manual-lash-v1`、固定 `faceBox / browEye / lashRoi`、磨皮 `100`、美白 `15` 和当前生产链完成 Baseline / 08.4 / 08.6 / 08.7 四组验证。

最终分流为：

> **Case B：按 angle 分组确实削弱了跨方向重构造成的 FP 连续带，但真实睫毛 Recall 明显下降，且最终视觉相对 08.6 退化；候选不通过，不进入生产实现。**

08.7 的结果同时说明：

- 08.6 的 FP 连续带扩大，确实部分来自多角度 response 在 reconstruction 前提前 OR 后的跨方向搭桥；
- 但仅保留已有 morphology angle identity、按 angle 独立做 reconstruction，不能保持 08.6 对真实睫毛的覆盖；
- 因此当前离散 angle-group information 有几何分离作用，但不是足够的真实睫毛判别信息；
- 不能据此宣称已有连续 orientation field，也不能扩大为“模型一定不足”“必须新增模型”或“Repair 公式错误”。

本票未修改生产 `src/`、GUI、模型、Repair / Smoothing 公式、公共 Context、版本字段或其它五官保护逻辑。

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
- `runtimeCacheReused = false`
- 磨皮：`100`
- 美白：`15`
- 固定 angle 集合：`0:15:165`，共 `12` 个 angle

`manualLashMask` 仅用于 Recall / Precision、FP / FN 统计和最终视觉核对，没有参与 Candidate support 生成。

## 3. 08.7 候选实现

新增离线入口：

- `tests/diagnoseLashAngleGroupedReconstruction.m`
- `tests/testLashAngleGroupedReconstruction.m`
- 本 handoff 记录

候选只复用当前 detector 已有的：

- `darkCandidate`
- `edgeCandidate`
- 当前多角度 morphology line response
- `eyeNeighborhood`
- 当前 detector candidate seed
- 当前 near-eye 约束
- 当前 `faceScale` 派生尺度
- 当前 `featherSoftMask(..., .99)` soft weighting 语义

候选顺序为：

```text
每个 angle response_k
    -> allowedEvidence_k
    -> seed_k
    -> 独立 8-connected reconstruction_k
全部 reconstruction_k
    -> 最后 union
    -> 当前 featherSoftMask
```

08.6 对照仍按：

```text
各 angle response
    -> 先 OR 为 lineSupport
    -> 统一 8-connected reconstruction
```

未新增：

- orientation field、`atan2`、structure tensor、Hessian、tangent / normal；
- 新模型、特征、阈值、angle tolerance 或参数搜索；
- hard lash core；
- `manualLashMask` 生成路径；
- Repair / Smoothing / Base / tone / whitening 变化。

诊断核对：逐 angle response 的 union 与当前生产 `lineSupport` 最大误差为 `0`；Candidate 重新构建的现有 `lashProtection` 最大误差为 `0`；Baseline / 08.4 冻结 compose 最大 RGB 差异为 `0`。

## 4. 几何指标

| 指标 | Baseline | 08.4 | 08.6 | 08.7 Angle-Grouped |
|---|---:|---:|---:|---:|
| support 像素 | `849` | `912` | `962` | `833` |
| TP 像素 | `211` | `216` | `242` | `211` |
| FP 像素 | `638` | `696` | `720` | `622` |
| FN 像素 | `365` | `360` | `334` | `365` |
| Recall | `0.366319` | `0.375000` | `0.420139` | `0.366319` |
| Precision | `0.248528` | `0.236842` | `0.251559` | `0.253301` |
| 最大 FP 连通分量 | `577` | `685` | `708` | `561` |
| FP 连通分量数量 | `5` | `4` | `4` | `5` |

相对 08.6：

- FP 减少 `98` 个像素；
- 最大 FP 连通分量减少 `147` 个像素；
- Precision 提高 `0.001742`；
- 但 Recall 从 `0.420139` 降至 `0.366319`，下降 `0.053819`；
- TP 从 `242` 降至 `211`，减少 `31`；
- FN 从 `334` 增至 `365`，增加 `31`。

数值几何分诊为：

```text
numericGeometryDoesNotSupportCandidate
```

原因不是 FP 没有下降，而是 Recall 明显退化，未满足 08.7 的同时验收条件。

## 5. Angle 分组证据

共保存 `12` 个 angle 的原始 response 和独立 reconstruction：

- `line_response_angle_000.png` 至 `line_response_angle_165.png`
- `reconstruction_angle_000.png` 至 `reconstruction_angle_165.png`
- `angle_response_overview.png`
- `angle_reconstruction_overview.png`

统计结果：

| 统计项 | 数值 |
|---|---:|
| angle response 像素总和 | `8464` |
| angle seed 像素总和 | `1359` |
| angle reconstructed 像素总和 | `1359` |
| angle reconstruction pairwise overlap | `6012` |
| 最终不同 angle overlap 像素 | `154` |
| 最终 union 像素 | `159` |

这些数组证明 08.7 实际保留并消费了 angle 分组身份，而不是重新退化为 `response -> OR -> reconstruction`。其中大量 pairwise overlap 表明固定 morphology response 之间本身存在较大重叠；独立 reconstruction 虽能切断一部分跨方向桥接，但也会丢失 08.6 中由统一 evidence 连通性补回的真实睫毛区域。

## 6. Repair 与 Final 验收

固定 `manualLashMask` 内 Repair 绝对作用量：

| 指标 | Baseline | 08.4 | 08.6 | 08.7 |
|---|---:|---:|---:|---:|
| Repair Fine 绝对作用量总量 | `8.20346480648792` | `7.57702712443360` | `6.99271131650099` | `8.19989258267808` |
| Repair Mid 绝对作用量总量 | `18.5054764545722` | `15.6180965211660` | `13.2587563450944` | `18.5034355995521` |

相对 08.6，08.7 的 Fine / Mid 几乎回到 Baseline：

- Fine 增加 `1.20718126670`；
- Mid 增加 `5.24467925446`。

固定 `manualLashMask` 内 Final 到原图距离均值：

| 指标 | 08.4 | 08.6 | 08.7 |
|---|---:|---:|---:|
| RGB 距离均值 | `10.2309028` | `9.1597222` | `11.4548611` |
| luminance 距离均值 | `0.0339948` | `0.0303898` | `0.0380967` |

因此 08.7 相对 08.6 的最终真实睫毛保留效果明显退化，与 Recall 和 Repair 作用量方向一致。

`hardProtectionMask changed pixels = 0`，`lashCore changed pixels = 0`；没有通过新增 hard protection 掩盖候选退化。

## 7. 最终视觉核对

已按同一 `lashRoi`、同一显示尺度检查：

```text
A Original
B Baseline
C 08.4
D 08.6
E 08.7 Angle-Grouped
```

观察结论：

1. D（08.6）相对 B/C 对主要上睫毛细线有一定恢复，和其较低的 Repair Fine / Mid 作用量一致。
2. E（08.7）相对 D 的主要睫毛细线明显变弱，部分细线重新接近 Baseline，不能确认“主要睫毛不能比 08.6 更差”。
3. E 的普通眼周连续 support 带相对 D 有所收窄；`false_positive_08_7.png` 中错误区域总量和最大连通块均低于 08.6。
4. 但几何收窄是以丢失真实睫毛覆盖为代价，最终视觉没有改善，故不能进入 Case A。
5. 未见新增 hard protection 或独立的断裂状保护伪影来源；主要问题是过度分离造成的真实睫毛断裂/变弱。

## 8. 产物位置

正式诊断产物：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_7_lash_angle_grouped_20260919`

包括：

- `original_lash.png`
- `support_08_4.png`
- `support_08_6.png`
- `support_08_7_angle_grouped.png`
- `manual_vs_08_6.png`
- `manual_vs_08_7.png`
- `false_positive_08_6.png`
- `false_positive_08_7.png`
- `false_negative_08_6.png`
- `false_negative_08_7.png`
- `angle_response_overview.png`
- `angle_reconstruction_overview.png`
- `line_response_angle_000.png` 至 `line_response_angle_165.png`
- `reconstruction_angle_000.png` 至 `reconstruction_angle_165.png`
- `repair_fine_08_6.png`
- `repair_fine_08_7.png`
- `repair_mid_08_6.png`
- `repair_mid_08_7.png`
- `final_08_4.png`
- `final_08_6.png`
- `final_08_7.png`
- `support_geometry_comparison.png`
- `final_angle_grouped_comparison.png`
- `lash_angle_grouped_metrics.csv`
- `lash_angle_grouped_per_angle_metrics.csv`
- `lash_angle_grouped_diagnostic.mat`

测试结果：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_7_lash_angle_grouped_20260919_test_results.mat`

## 9. 测试结果

目标测试：

- `testLashAngleGroupedReconstruction`：**2 Passed, 0 Failed, 0 Incomplete**
- 测试时间约 `83.5 s`

最终全量 `tests/` 回归：

- **149 Passed, 0 Failed, 0 Incomplete**
- 单个 MATLAB R2024a 批处理进程完成
- 测试时间约 `390.6 s`
- 结果：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_7_lash_angle_grouped_20260919_full_test_results.mat`

运行中反复出现既有 PNG 元数据警告：

```text
iCCP: cHRM chunk does not match sRGB
```

该警告来自固定 `77.png` 的 PNG 元数据，不影响 MATLAB 图像数组、候选公式、产物或测试结果。

## 10. 修改范围与后续边界

本票新增：

- `tests/diagnoseLashAngleGroupedReconstruction.m`
- `tests/testLashAngleGroupedReconstruction.m`
- 本 handoff 记录

未修改：

- `src/` 生产算法；
- GUI；
- 模型及依赖；
- Repair / Smoothing / compose 公式；
- 版本号；
- brow / nose / ear / lip / structure protection。

本票不授权生产落地。当前结论收敛为：

> **提前 OR angle response 确实是 08.6 FP 连续带扩大的部分原因；但仅按现有 angle 分组独立重构会明显牺牲真实睫毛覆盖和最终视觉，因此“只重排已有 angle response”路线在当前形式下停止。**

下一步若继续，应新增并单独验收能够同时提供：

1. 真实睫毛连续性；
2. 普通眼睑/眼周分离；
3. 不依赖人工真值生成；
4. 不通过全局提高 soft strength 或 hard protection 掩盖误检；

的判别证据。不得把 08.7 结果扩大为必须换模型或 Repair 全局公式错误。
