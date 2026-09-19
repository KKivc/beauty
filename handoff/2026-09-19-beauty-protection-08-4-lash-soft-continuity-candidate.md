# Issue 08.4：睫毛 Soft Protection 局部连续性候选验证

## 1. 结论

本票已按固定 `77.png`、固定 `77-manual-lash-v1`、固定 `faceBox / browEye / lashRoi` 和当前工作区生产链完成唯一候选验证。

结论为：

> **通过候选（固定 77 样本）。**
>
> 在不修改 Repair、Smoothing、模型、hard protection、GUI、公共 Context 或版本字段的前提下，仅对现有 `lashProtection` 做一次基于当前 `faceScale` 的局部 soft closing，并限制在当前已有 `texture.eyeNeighborhood` 内，Candidate 同时降低了人工真实睫毛上的 Repair Fine / Mid 作用量，并使最终结果在 RGB 与亮度上更接近原图；hard protection 保持不变。新增保护只形成睫毛附近的窄带，未出现向大面积普通眼周皮肤扩张的现象。

该结论只适用于固定 77 样本，不外推为所有图像的唯一根因，也不授权新增 hard lash core 或全局提高 texture protection。

## 2. 固定基线

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 图像尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- 人工真值：`tests/eyelashManualLashMask77.m`
- 标注 ID：`77-manual-lash-v1`
- 人工真值像素：`576`
- 磨皮：`100`
- 美白：`15`
- 固定基线 Context：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
- 运行前剥离旧 `runtimeCache` 和派生 Context 字段；`runtimeCacheReused = false`
- 基线和候选均使用同一输入分解、同一 `blemishMap`、同一 Base/tone/whitening 结果；候选只重算受 `textureProtectionMask` 影响的 Smoothing / Repair / compose 后续链路。

## 3. 候选定义与注入范围

候选诊断入口：

- `tests/diagnoseLashSoftContinuityCandidate.m`
- `tests/testLashSoftContinuityCandidate.m`

实际候选为：

```text
existingLashScale = min(5, max(2, round(.008 * faceScale)))
softClosedLashProtection = imclose(lashProtection, strel('disk', existingLashScale, 0))
candidateLashProtection = max(
    lashProtection,
    softClosedLashProtection .* texture.eyeNeighborhood)
```

固定 77 的 `faceScale = 286`，因此本次复用的现有尺度为 `existingLashScale = 2`。

注入只发生在诊断路径：

```text
lashProtection
→ candidateLashProtection
→ eyeDetailProtection
→ textureProtectionMask
→ 当前 Smoothing / Repair / compose
```

未改变：

- `hardProtectionMask`
- `lashCore`
- brow / lip / nose / nostril / ear protection
- `structureProtectionMask`
- `chromaProtectionMask`
- `whiteningProtectionMask`
- `strengthMap`
- Repair Fine/Mid 公式、target/reference、structureGate
- 模型、GUI、公共 Context、schema / algorithm / artifact version

## 4. 数值结果

| 指标 | Baseline | Candidate | 变化 |
|---|---:|---:|---:|
| 人工真实睫毛新增 soft protection 总量 | - | `13.7211418002844` | - |
| 人工真实睫毛新增 soft protection 均值 | - | `0.0238214267366048` | - |
| 人工真值内新增 soft protection 像素 | - | `46 / 576` | - |
| browEye 中、manualLashMask 外新增 soft protection 总量 | - | `43.1365025565028` | - |
| browEye 中、manualLashMask 外新增 soft protection 均值 | - | `0.00294668369127009` | - |
| browEye 中、manualLashMask 外新增像素 | - | `174 / 15000` | - |
| Repair Fine 绝对作用量总量 | `8.20346480648792` | `7.57702712443360` | `-0.626437682054327` |
| Repair Mid 绝对作用量总量 | `18.5054764545722` | `15.6180965211660` | `-2.88737993340621` |
| 真实睫毛最终亮度相对 Baseline 绝对差总量 | - | `2.43302961459238` | - |
| 真实睫毛最终 RGB 相对 Baseline 绝对差总量 | - | `733` | - |
| 真实睫毛最终 RGB 到原图距离均值 | `11.4565972222222` | `10.2309027777778` | `-1.22569444444444` |
| 真实睫毛最终亮度到原图距离均值 | `0.0380998909513494` | `0.0339947650903178` | `-0.00410512413965168` |
| browEye 中、manualLashMask 外最终 RGB 相对 Baseline 总差 | - | `2197` | - |
| browEye 中、manualLashMask 外最终 RGB 相对 Baseline 均值 | - | `0.150078557278503` | - |
| `hardProtectionMask` changed pixels | - | `0` | 不变 |
| hard-protected pixels 最终 RGB changed count | `0` | `0` | 不变 |
| `lashCore` changed pixels | - | `0` | 不变 |

Fine 绝对作用量下降约 `7.64%`，Mid 绝对作用量下降约 `15.60%`。Candidate 的真实睫毛 RGB / luminance 到原图距离均下降，说明不是仅因输出变化而判定改善。

## 5. 图像观察

已核对以下固定 ROI 产物：

- `baseline_lash_protection.png`
- `candidate_lash_protection.png`
- `added_soft_protection.png`
- `manual_vs_added_soft_protection.png`
- `baseline_repair_fine_delta.png`
- `candidate_repair_fine_delta.png`
- `baseline_repair_mid_delta.png`
- `candidate_repair_mid_delta.png`
- `baseline_final_lash.png`
- `candidate_final_lash.png`
- `original_final_candidate_comparison.png`
- `original_baseline_candidate_lash_zoom.png`

人工观察结论：

1. 新增 support 主要位于已有 lashProtection 的短间断及其当前 eye neighborhood 内，呈睫毛附近窄带，不是全局膨胀。
2. Candidate 的 Fine/Mid 作用热区在人工真值上的强度下降，与数值统计一致。
3. Candidate 最终睫毛线相对 Baseline 更接近原图；原图中的深色细线保留略好，灰块/涂抹感减弱。
4. 未观察到大面积普通眼周皮肤被整体冻结，也未观察到新的明显硬边或保护光环。manualLashMask 外的新增 support 像素数为 `174`，但仅占固定 `browEye` 的约 `1.16%`，新增 soft 均值为 `0.00295`，空间上仍为局部窄带。

## 6. 验证与测试

目标测试：

- `testLashSoftContinuityCandidate`：**2 Passed, 0 Failed, 0 Incomplete**
- 覆盖固定真值独立性、非固定 fixture 拒绝、候选公式、单因素 Mask 隔离、产物完整性、Fine/Mid 作用量、最终接近度及 hard protection 不变性。

全量 `tests/` 回归：

- **143 Passed, 0 Failed, 0 Incomplete**
- 使用单个 MATLAB R2024a 批处理进程完成
- 结果文件：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_4_lash_soft_continuity_20260919_full_test_results.mat`

运行中出现既有输入 PNG 元数据警告：

```text
iCCP: cHRM chunk does not match sRGB
```

该警告来自 `77.png` 的 PNG 元数据，不影响 MATLAB 数组、公式核对、候选产物或测试结果。

## 7. 产物位置

正式诊断产物全部写入系统临时目录，不写入项目仓库：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_4_lash_soft_continuity_20260919`

主要数据文件：

- `lash_soft_continuity_candidate_metrics.csv`
- `lash_soft_continuity_candidate_diagnostic.mat`

## 8. 后续边界

本票通过后，可以进入单独的正式生产落地票：

> 将已验证的局部 lash soft continuity completion 合入 `buildTextureProtectionMask`，并按 Mask Builder 变更处理 algorithm/artifact 版本与派生产物重建。

正式落地前必须复用 Issue 08.1 / 08.2 / 08.3 固定 77 回归、80 正常雀斑修复、80 鼻梁/鼻翼结构保持、鼻孔 hard RGB 严格保持、hard mask changed pixels = 0 以及全量 `tests/`。

本票不支持以下结论：

- 所有图像的睫毛唯一根因已确定；
- 所有睫毛都应 hard protect；
- Repair 全局公式错误；
- BiSeNet / Face Parsing 有问题；
- 可以直接扩大 lashProtection 或关闭 Repair / Mid。
