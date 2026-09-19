# Issue 08.8：连续方向一致性（Structure Tensor）判别证据验证记录

## 1. 最终结论

固定 `77.png`、固定 `77-manual-lash-v1` 和既有 08.7 false-positive 区域上，已完成 Structure Tensor orientation / coherence 的离线可分性诊断。

最终分流：

> **Case C：连续 coherence / orientation continuity 没有把真实睫毛与 08.6 / 08.7 FP 分开；在目标 FP 集合上反而表现为反向排序。该证据不能进入 production support，也不应继续在当前局部梯度/线结构 evidence 上叠加规则。**

这里的 Case C 是针对本票固定的真实睫毛与 08.6 / 08.7 FP 集合，不表示所有图片或所有眼周像素均有相同结论。广义 `browEye & ~manualLashMask` 对照的 AUC 接近随机，进一步说明不能据此形成通用生产判据。

本票未修改生产 `src/`、GUI、模型、Repair / Smoothing 公式、公共 Context schema 或生产 `lashProtection`。

## 2. 固定输入与证据边界

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- 人工真值：`tests/eyelashManualLashMask77.m`
- 人工真值 ID：`77-manual-lash-v1`
- 人工真值像素：`576`
- 上游 08.7 诊断：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_7_lash_angle_grouped_20260919\lash_angle_grouped_diagnostic.mat`
- 08.6 FP：`candidate086Support & ~manualLashMask`
- 08.7 FP：`candidate087Support & ~manualLashMask`
- `manualLashMask` 仅用于离线分组和统计，没有参与特征计算、候选生成或阈值选择。

## 3. Structure Tensor 构造

严格复用当前 `detectLashLines` 的 `lineImage` 尺度语义：

```matlab
lineSigma = min(1.35, max(.45, .002 * faceScale));
tensorSigma = lineSigma;
```

固定 77 的 `faceScale = 286`，因此：

```text
lineSigma = tensorSigma = 0.572
```

从当前生产 detector 同语义的 `lineImage` 开始计算：

```matlab
[gradientX, gradientY] = gradient(lineImage);
Jxx = imgaussfilt(gradientX .^ 2, tensorSigma, 'Padding', 'replicate');
Jyy = imgaussfilt(gradientY .^ 2, tensorSigma, 'Padding', 'replicate');
Jxy = imgaussfilt(gradientX .* gradientY, tensorSigma, 'Padding', 'replicate');
orientation = 0.5 .* atan2(2 .* Jxy, Jxx - Jyy);
coherence = sqrt((Jxx - Jyy).^2 + 4 .* Jxy.^2) ./ ...
    (Jxx + Jyy + eps);
```

未扫描多个尺度、未新增绝对像素常数、未使用 coherence threshold、未使用 angular threshold、未使用 ROC threshold，也未用人工真值调节特征。

有效 tensor energy 像素数为 `228032`；该有效性只排除非有限或零能量位置，不构造生产 mask。

## 4. Coherence 分布统计

所有组使用同一 `[0, 1]` coherence 坐标范围。

| 集合 | count | mean | median | std | P10 | P25 | P50 | P75 | P90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Manual Lash | 576 | 0.749964 | 0.806314 | 0.205886 | 0.433620 | 0.639050 | 0.806314 | 0.907690 | 0.960970 |
| 08.6 FP | 720 | 0.843928 | 0.932439 | 0.192132 | 0.545520 | 0.776590 | 0.932439 | 0.977920 | 0.989540 |
| 08.7 FP | 622 | 0.835421 | 0.924985 | 0.198913 | 0.538430 | 0.756510 | 0.924985 | 0.976930 | 0.989360 |
| BrowEye non-lash | 14639 | 0.739183 | 0.802563 | 0.217710 | 0.405110 | 0.615650 | 0.802563 | 0.914670 | 0.964470 |
| EyeNeighborhood non-lash | 1502 | 0.830385 | 0.908163 | 0.192219 | 0.542200 | 0.752910 | 0.908163 | 0.971060 | 0.986750 |
| Manual Lash & lineSupport | 342 | 0.766200 | 0.821330 | 0.195890 | 0.476140 | 0.676280 | 0.821330 | 0.912470 | 0.962180 |
| 08.6 FP & lineSupport | 494 | 0.839410 | 0.929120 | 0.196910 | 0.540660 | 0.757920 | 0.929120 | 0.980090 | 0.990880 |
| 08.7 FP & lineSupport | 452 | 0.832200 | 0.917780 | 0.199420 | 0.522160 | 0.747020 | 0.917780 | 0.977910 | 0.990210 |

关键方向不是 Manual Lash 更高，而是 08.6 / 08.7 FP 整体更高。仅凭均值差异不能形成 production 结论，但该差异与后续 rank effect、梯度分箱和 orientation continuity 方向一致。

## 5. 阈值无关排序结果

AUC 以 coherence 越高越倾向 Manual Lash 为正类；rank-biserial 为 `2*AUC-1`。

| 比较 | Positive / Negative count | ROC AUC | rank-biserial |
|---|---:|---:|---:|
| Manual Lash vs 08.6 FP | 576 / 720 | 0.314779 | -0.370443 |
| Manual Lash vs 08.7 FP | 576 / 622 | 0.327997 | -0.344007 |
| Manual Lash vs BrowEye non-lash | 576 / 14639 | 0.506906 | 0.013813 |
| Manual Lash vs EyeNeighborhood non-lash | 576 / 1502 | 0.346530 | -0.306930 |
| Manual Lash & lineSupport vs 08.6 FP & lineSupport | 342 / 494 | 0.336174 | -0.327651 |
| Manual Lash & lineSupport vs 08.7 FP & lineSupport | 342 / 452 | 0.350741 | -0.298517 |

结论：

1. 对 08.6 / 08.7 FP，AUC 明显低于 0.5，coherence 的排序方向与预期相反。
2. 在 `lineSupport == 1` 内方向仍然相反，说明 coherence 没有提供可利用的新增正向判别信息。
3. 对广义 BrowEye non-lash，AUC 为 `0.506906`，接近随机，不能宣称存在普适眼周分离。

## 6. Orientation 连续性

采用轴向角差，正确处理 `θ` 与 `θ + π` 等价；不设 angular threshold。统计的是 mask 内相邻有效像素的水平/垂直邻接 pair。

| 集合 | 有效 pair 数 | mean | median | P75 | P90 |
|---|---:|---:|---:|---:|---:|
| Manual Lash | 983 | 0.343710 rad | 0.231800 | 0.453000 | 0.873060 |
| 08.6 FP | 1286 | 0.208800 rad | 0.104340 | 0.245830 | 0.513350 |
| 08.7 FP | 1088 | 0.220790 rad | 0.109130 | 0.266920 | 0.538140 |

角差越小表示局部方向越稳定；固定真值的平均、P50、P75、P90 均高于两个 FP 集合。因此 orientation continuity 也没有支持“真实睫毛更连续”的假设。

## 7. 与 Gradient Magnitude / lineSupport 去重复

coherence 与 gradientMagnitude 的 Pearson 相关：

| 集合 | correlation |
|---|---:|
| 全部有效 tensor energy | 0.311340 |
| Manual Lash | 0.337210 |
| 08.6 FP | 0.498640 |
| 08.7 FP | 0.516210 |

相关性为中等而非完全同义编码；但在相同 gradientMagnitude 分箱内，Manual Lash 与 FP 仍然保持反向差异：

- Manual - 08.6 FP：6 个共同非空分箱，按共同样本数加权 coherence 差 `-0.060576`，6/6 分箱 Manual 更高的比例为 `0`。
- Manual - 08.7 FP：6 个共同非空分箱，按共同样本数加权 coherence 差 `-0.050856`，6/6 分箱 Manual 更高的比例为 `0`。

因此可以排除“只是完全重复 gradientMagnitude”的简单解释；但去重复后的方向仍然对目标分离无效，甚至偏向保护 FP。

在 `lineSupport == 1` 内，Manual Lash 的 coherence 仍低于两个 FP，AUC 分别为 `0.336174` 和 `0.350741`。该路线不具备进入下一张 support candidate 票的依据。

## 8. 产物与代码

新增离线诊断与目标测试：

- `tests/diagnoseLashOrientationCoherenceEvidence.m`
- `tests/testLashOrientationCoherenceEvidence.m`
- 本 handoff

固定临时产物目录：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_8_lash_orientation_coherence_20260919`

包含：

- `line_image.png`
- `gradient_magnitude.png`
- `tensor_coherence.png`
- `tensor_orientation.png`
- 三组 coherence / orientation overlay
- `coherence_histogram.png`
- `coherence_ecdf.png`
- `coherence_boxplot.png`
- `coherence_gradient_joint.png`
- `coherence_by_gradient_bin.png`
- `orientation_continuity_distribution.png`
- `lash_orientation_coherence_metrics.csv`
- `lash_orientation_coherence_group_stats.csv`
- `lash_orientation_continuity_stats.csv`
- `lash_orientation_coherence_gradient_bins.csv`
- `lash_orientation_coherence_diagnostic.mat`

MAT 至少保存了 `gradientX`、`gradientY`、`gradientMagnitude`、`Jxx`、`Jyy`、`Jxy`、`orientation`、`coherence`、`manualLashMask`、`fp08_6`、`fp08_7`、`eyeNeighborhood` 和 `lineSupport`。

## 9. 测试结果

目标测试：

- `testLashOrientationCoherenceEvidence`：`2 Passed, 0 Failed, 0 Incomplete`
- 测试时间约 `42.7 s`

运行期间出现既有固定 `77.png` PNG 元数据警告：

```text
iCCP: cHRM chunk does not match sRGB
```

该警告来自输入 PNG 元数据，不影响图像数组、张量计算、CSV/MAT 产物或测试结果。

最终全量 `tests/` 回归：

- `151 Passed, 0 Failed, 0 Incomplete`
- 单个 MATLAB 批处理进程完成
- 测试时间约 `415.8 s`
- 结果文件：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_8_lash_orientation_coherence_20260919_full_test_results.mat`

运行期间同样出现固定 `77.png` 的 `iCCP: cHRM chunk does not match sRGB` 元数据警告；未影响测试通过。

## 10. 后续边界

本票结论只授权：

- 停止把 Structure Tensor coherence / orientation continuity 接入当前 lash support；
- 停止在同类局部 gradient / morphology line evidence 上继续堆叠规则；
- 后续若继续，应另票验证更有判别力的局部纹理/脊线特征、专门 eyelash segmentation / parsing 或模型级语义增强。

本票不证明：

- 所有图片与 `77.png` 一致；
- Repair 全局公式错误；
- BiSeNet 必须替换；
- 必须新增 hard eyelash mask。
