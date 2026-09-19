# 04：脸缘结构保护来源归因记录

记录日期：2026-09-17。

## 范围判定

本次用户请求是实现 `.scratch/beauty-protection-convergence/issues/04-attribute-face-boundary-structure-protection.md`。该文档中的固定样本、选区、版本、诊断口径和“不修改生产算法”属于本票实施约束；其中未来局部修复的方向不作为本票预设方案。

本票只扩展既有诊断入口 `tests/diagnoseFaceBoundaryCoverage.m` 和 02 中文交接记录，没有修改 `src/` 生产算法、公共 Context、缓存契约、皮肤支持、强度曲线、Base、肤色或美白，也没有读取、修改或并入 03 会话的实现与产物。

## 固定输入

- 输入：`E:\image_beauty\人脸\人脸\80.jpg`；原尺寸 `850×565×3`，输入为 `uint8 RGB`。
- 基线：`schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 参数：磨皮 `100`，美白 `15`。
- 原尺寸人脸框：`[23 1 543 636]`。
- 原尺寸脸缘框：`[125 300 55 110]`；内侧对照框：`[180 300 55 110]`。
- 预览沿用既有路径，缩放因子约 `0.7529411765`，预览尺寸 `426×640×3`，选区随同一缩放规则转换。

两个选区均由原图可见位置固定给出，不由待验证的皮肤或结构 Mask 生成。原尺寸脸缘框共 `6050` 个像素，其中 `5804` 个通过 `skinMask >= 0.05`，`5738` 个通过 `faceSkinMask >= 0.35`；内侧对照框 `6050` 个像素全部通过两项支持。

## 实现内容

入口现在同时完成以下诊断：

1. 复用生产结构诊断中的 `noseStructure`、`outsideStructure`、`faceBoundary`，在诊断入口按生产公式补算缺失的 `faceStructure`，并按 `max` 后乘皮肤支持重建最终结构保护图。
2. 在脸缘框和内侧框的 `all`、`fineZero`、`finePartial`、`midZero`、`midPartial` 子集中记录来源强度、有效像素、最大项主导比例、并列项和原图/低频梯度证据。
3. 对每个来源执行单项消融：只把该来源置零，冻结基线自适应统计、Fine/Mid 保留率、瑕疵图和 Base/肤色/美白结果；Repair 使用消融后的结构 Mask 重新计算，表中明确标记为下游传播后果。
4. 对鼻梁近似区、鼻翼近似区、眼眉口部语义区、头发语义区和背景语义区记录低频梯度及相对输入的变化。背景和头发检查分别使用语义证据，不由待验证的 `skinMask` 单独定义。
5. 02 的旧整体消融仍可通过 `includeLegacyAblations=true` 显式复现；04 默认不重跑它。02 记录已补充旧实验的真实含义和口径修正。

## 来源重建与主导比例

生产顺序在本入口复现为：

```text
faceStructure = min(faceSkinMask, skinMask) .* continuousEvidence
maxSource = max(noseStructure, outsideStructure, faceStructure, faceBoundary)
finalProtection = maxSource .* min(max(skinMask, 0), 1)
```

预览和原尺寸的 `reconstructionMaxAbsError`、`reconstructionMeanAbsError` 以及冻结基线重建误差均为 `0`；因此后续归因使用的是与基线一致的来源图，而不是近似重建图。

主导比例的分母是“选区分析像素中最终结构保护值大于 `1e-12` 的像素数”。并列最大值按并列项数等分主导权，唯一最大项单独计数；本固定样本各列 `tiePixels=0`，没有因并列而分摊的像素。来源强度同时报告乘皮肤支持前后的值；主导梯度只在该来源唯一最大项像素上计算。空子集的均值、比例和能量比保留 `NaN`，不伪造有效数值。

原尺寸脸缘框的主导比例如下：

| 子集 | 分析像素 | `noseStructure` | `outsideStructure` | `faceStructure` | `faceBoundary` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `all` | 5738 | 53.03% | 0% | 40.69% | 6.27% |
| `fineZero` | 1474 | 0% | 0% | 76.39% | 23.61% |
| `finePartial` | 4264 | 71.36% | 0% | 28.35% | 0.28% |
| `midZero` | 1474 | 0% | 0% | 76.39% | 23.61% |
| `midPartial` | 4264 | 71.36% | 0% | 28.35% | 0.28% |

预览脸缘框得到相同的相对结构：`all` 为 `50.81% / 0% / 41.74% / 7.45%`，`fineZero` 为 `0% / 0% / 74.78% / 25.22%`，`finePartial` 为 `71.49% / 0% / 28.29% / 0.22%`。因此该样本的零门控主要由 `faceStructure` 和少量 `faceBoundary` 主导；非零部分门控主要由 `noseStructure` 主导。`outsideStructure` 在固定脸缘与内侧选区都没有主导像素，不能据此宣称它在全图没有影响。

## 门控、能量和轮廓证据

原尺寸脸缘框基线的 `Fine/Mid` 结构门控相同，均值 `0.663282`，零门控比例 `25.69%`，部分门控比例 `74.31%`。内侧对照均值 `0.996633`，零门控比例为 `0`。对应的输入/输出频率能量比为：

| 区域 | Fine 输入能量 | Fine 磨皮后能量 | Fine 保留率 | Mid 输入能量 | Mid 磨皮后能量 | Mid 保留率 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 脸缘 | 0.0140996 | 0.0108205 | 0.767433 | 0.0334362 | 0.0236571 | 0.707528 |
| 内侧 | 0.0175594 | 0.0119784 | 0.682162 | 0.0123393 | 0.00684269 | 0.554546 |

以上能量输入均大于零，比例可用。入口对其他图或空子集采用同一规则：输入能量为零或选区为空时状态写为不可用并保留 `NaN`，不增加分母常数。

`faceBoundary` 唯一主导像素的原尺寸证据为：低频梯度均值 `0.0089646`，方向连续性均值 `0.999650`，连续结构证据均值 `0.613016`，原图亮度梯度均值 `0.0146487`，低频局部对比均值 `0.00747574`。在 `fineZero` 子集对应值为 `0.00900870`、`0.999646`、`0.619042`、`0.0144956` 和 `0.00733916`。这些像素确有较强的连续方向和原图梯度证据，不能仅因为来源名为 `faceBoundary` 就判定为错误保护。

## 冻结基线的单项来源消融

原尺寸脸缘框的单项消融结果如下。最终 RGB 差异只表示输出副作用，不是结构质量通过条件；`noseMaxChange`、`eyeMaxChange`、`hairMaxChange` 和 `backgroundMaxChange` 使用固定语义安全区，`hardProtectionMaxChange` 要求输入 RGB 严格一致。

| 消融来源 | 结构保护均值下降 | Fine 保留率（基线→消融） | Mid 保留率（基线→消融） | 脸缘最终 RGB 差异均值 | 鼻/眼/发/背景最大变化 | 硬保护最大变化 |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| `noseStructure` | 0.0001035 | 0.767433→0.767282 | 0.707528→0.707263 | 0.00802 | 19 / 0 / 0 / 1 | 0 |
| `outsideStructure` | 0 | 0.767433→0.767433 | 0.707528→0.707528 | 0 | 0 / 0 / 0 / 15 | 0 |
| `faceStructure` | 0.123801 | 0.767433→0.697303 | 0.707528→0.591318 | 1.28791（P90=4） | 11 / 1 / 1 / 1 | 0 |
| `faceBoundary` | 0.007255 | 0.767433→0.766971 | 0.707528→0.706683 | 0.01969 | 0 / 2 / 1 / 6 | 0 |

`faceStructure` 是该固定脸缘框中最有影响的来源；移除它会明显增加局部处理量，但同时在固定鼻梁/鼻翼近似区和五官区产生更大的低频梯度偏离，不能把输出变化包装为改善。`faceBoundary` 只占少数唯一主导像素，且这些像素有较强方向连续和原图轮廓证据；移除它的脸缘差异很小，但仍有背景安全区变化。`outsideStructure` 在该框没有局部作用，单项消融的全图背景最大变化为 `15`，说明不能只看目标框内差异。

固定 `faceStructure` 消融的低频梯度对照为：

| 测量区 | 原图梯度均值 | 基线梯度均值 | `faceStructure` 消融梯度均值 | 基线相对原图梯度差 | 消融相对原图梯度差 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 鼻梁近似区 | 0.0049450 | 0.0045379 | 0.0045213 | 0.0004086 | 0.0004251 |
| 鼻翼近似区 | 0.0033296 | 0.0029393 | 0.0028589 | 0.0004225 | 0.0005113 |
| 五官语义区 | 0.0084727 | 0.0084021 | 0.0082077 | 0.0001677 | 0.0003338 |

鼻梁近似区取鼻语义横向范围中间 50%，鼻翼近似区取外侧区域；这是诊断测量划分，不是生产规则。头发和背景语义区也已写入特征表，未发现硬保护变化。

## 结论与边界

### 已证实

1. `80.jpg` 的预览和原尺寸都复现了脸缘相对内侧的低处理量；脸缘不是单纯皮肤召回为空。
2. 固定脸缘框的零门控主要由 `faceStructure`、其次 `faceBoundary` 主导；部分门控主要由 `noseStructure` 主导；`outsideStructure` 在本框不主导。
3. 四来源重建与基线一致，冻结基线消融没有重新改变自适应统计和保留率；Repair 重算已作为传播后果单独记录。
4. `faceBoundary` 主导像素具有可见的原图梯度和很高方向连续性；来源主导事实不等于错误保护事实。

### 尚未证实

- 尚不能证明 `faceStructure` 或 `faceBoundary` 在本样本中属于不必要保护。`faceStructure` 消融虽然带来最大局部变化，但鼻梁、鼻翼和五官低频梯度偏离扩大；`faceBoundary` 消融又存在背景副作用。现有证据不足以满足“连续性改善且真实轮廓未退化”的修复条件。
- 尚不能把 `80.jpg` 的结论外推到其他姿态、肤色、近景截图或 03 会话症状。
- 旧 02 的整体结构消融和重复 Mid 门控消融保留其真实输出变化含义，但不再作为纯门控因果证据。

本票停在诊断结论，不取消 Mid 第二次门控、不放松全局门控、不新增阈值或修复公式，也不拆生产实现票。

## 可复现入口与产物

入口：`E:\image_beauty\tests\diagnoseFaceBoundaryCoverage.m`

```matlab
addpath('E:\image_beauty\src');
addpath('E:\image_beauty\tests');
options = struct('faceBoundaryRoi', [125 300 55 110], ...
    'controlRoi', [180 300 55 110], ...
    'smoothingStrength', 100, 'whiteningStrength', 15);
[summary, diagnostics] = diagnoseFaceBoundaryCoverage( ...
    'E:\image_beauty\人脸\人脸\80.jpg', ...
    fullfile(tempdir, 'image_beauty_issue04_v32_80'), options);
disp(summary.sourceMetrics);
disp(summary.sourceAblationMetrics);
disp(summary.featureMetrics);
```

本轮固定单图产物目录：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue04_v32_80`

- `faceBoundaryRegionMetrics.csv`：基线区域支持、门控、能量和阶段作用量；
- `faceBoundarySourceMetrics.csv`：四来源在全部、零门控和部分门控子集的强度与主导比例；
- `faceBoundarySourceAblationMetrics.csv`：冻结基线的来源单项消融、能量比、传播差异和安全区检查；
- `faceBoundaryFeatureMetrics.csv`：鼻梁/鼻翼/五官/头发/背景低频梯度与 RGB 副作用标记；
- `preview-faceBoundarySources.png`、`original-faceBoundarySources.png`：来源图、主导图、低频梯度、方向连续性和原图叠加；
- `preview-faceBoundarySourceAblations.png`、`original-faceBoundarySourceAblations.png`：四项来源单项消融视觉对照；
- `preview-faceBoundaryCompare.png`、`original-faceBoundaryCompare.png`：输入、基线和最终 RGB 变化；
- `faceBoundaryDiagnosticData.mat`：紧凑可复现诊断数据。

## 验证

- `checkcode('tests/diagnoseFaceBoundaryCoverage.m', '-id')`：`CHECKCODE_OK`。
- 固定 `80.jpg` 预览/原尺寸批处理：`ISSUE04_DIAGNOSTIC_OK`；路径、空旧消融、四来源重建、冻结基线误差和硬保护最大变化均已断言。
- 受影响目标测试 `testNoseSmoothing`、`testBeautyContextV3`、`testBeautyArtifactRegressions`：`24 Passed, 0 Failed, 0 Incomplete`。
- 当前 `tests/` 全量测试：`123 Passed, 0 Failed, 0 Incomplete`；其中包含 03 会话已加入的测试，该计数不把 03 代码变化归入 04。
- 04 运行未修改 `src/`；未执行 Git 提交或推送。
