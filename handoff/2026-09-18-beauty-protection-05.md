# 05：隔离 Repair 的 Fine/Mid 修改与局部失真贡献

交接目标任务：`01a0ae32-d2e7-7a11-9525-026b3caba99b`。

记录日期：2026-09-18。此记录只交接诊断证据，不代表生产算法已经修复。

## 结论

在 77.png、磨皮 100、美白 15、人脸框 `[95 79 286 372]` 和 03 同一人工选区上，四种输出均使用同一次 v3.2 基线的平滑结果、Repair 结果和 Base/肤色/美白处理结果：完整 Repair、仅 Fine、仅 Mid、无 Repair。

三类局部的 Repair 作用均以 Mid 为主，Fine 也有独立贡献；完整输出不是把 Fine 和 Mid 的 RGB 变化简单相加。局部图中，耳廓块状差异、鼻孔/鼻翼填充差异及眼睑/睫毛附近灰块在无 Repair 时明显减轻，Mid-only 保留了大部分与完整 Repair 相同的变化，Fine-only 变化较小但非零。这个结果确认 Repair 的后续消费是现象的因果贡献之一，但不能单独证明保护不足、检测误判或参考采样是唯一根因。

### Repair 分量量化

以下 `outputRgbDifferenceFromNoRepairMean` 是相对无 Repair 输出的 RGB 差异，不是质量分数；`blemishEnergyReductionRatio` 只表示相对平滑后频率瑕疵能量的下降。

| 症状 | 分量 | Fine 保留率 | Mid 保留率 | 瑕疵能量下降 | 相对无 Repair 的 RGB 差异均值 | 低频结构梯度保留率 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| ear | 完整 Repair | 0.823115 | 0.820677 | 0.505990 | 4.8241 | 0.91578 |
| ear | 仅 Fine | 0.823115 | 1.000000 | 0.145999 | 1.5677 | 1.00000 |
| ear | 仅 Mid | 1.000000 | 0.820677 | 0.359991 | 3.3989 | 0.91578 |
| nostril | 完整 Repair | 0.619654 | 0.672875 | 0.513516 | 6.4646 | 0.88417 |
| nostril | 仅 Fine | 0.619654 | 1.000000 | 0.113399 | 1.7606 | 1.00000 |
| nostril | 仅 Mid | 1.000000 | 0.672875 | 0.400118 | 5.4297 | 0.88417 |
| browEye | 完整 Repair | 0.587981 | 0.662804 | 0.668082 | 4.8096 | 0.97523 |
| browEye | 仅 Fine | 0.587981 | 1.000000 | 0.195739 | 1.8587 | 1.00000 |
| browEye | 仅 Mid | 1.000000 | 0.662804 | 0.472342 | 3.8113 | 0.97523 |

组合检查结果：完整 Repair 重建相对保存的 v3.2 基线最大 RGB 差为 0；频率层 Fine/Mid 亮度组合最大残差为 `2.22044604925031e-16`；最终 RGB 的线性叠加残差均值为 `0.0251128`、最大为 `9`。因此报告按分量实测，不把单项结果未经验证地线性相加。

## 现有保护和检测关系

以下语义、保护和检测记录来自 03 final 的同一 77 基线；本票新运行重新用完整 `context` 计算区域表，三张 03 CSV 与新结果完全一致。

| 症状 | 语义证据最大值 | 纹理保护均值 | 结构保护均值 | 硬保护比例 | Repair 纹理门控均值 | Repair 结构门控均值 | 主要结构来源 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ear | 0.8837 | 0.3830 | 0.1238 | 0.2847 | 0.6170 | 0.9415 | faceStructure |
| nostril | 0.9509 | 0.0597 | 0.3302 | 0 | 0.9403 | 0.7690 | faceStructure |
| browEye | 0.7964 | 0.0378 | 0.2114 | 0.0115 | 0.9622 | 0.8880 | noseStructure |

- ear：人工 ROI 内可见耳廓，现有结构来源是通用 `faceStructure/faceBoundary`，不是耳部专用来源；约 28.47% 像素有硬保护，但其余区域仍有 Repair 作用。03 的 `occluderProtectionMean=0.3830`，`repairTextureGateMean=0.6170`。
- nostril：原图 ROI 内可见鼻孔/鼻翼暗结构；`nostrilCore` 和 `nostrilBoundary` 均为空，`chroma.nostrilCandidate` 覆盖比例为 `0.0217143`，检测不一致比例同为 `0.0217143`，`noseSemanticExcluded=true`，硬保护为 0。该候选差异记录为纹理漏检与色度少量候选不一致，未把色度候选直接定性为错误。
- browEye：原图 ROI 内可见眼睑和睫毛；`leftEye/rightEye/leftBrow/rightBrow` 最大语义证据分别为 `0.2954/0.0105/0.7964/0.3680`。`eyeDetailProtection`、`periocularProtection`、`doubleEyelidProtection` 和 `lashProtection` 均为空，硬保护仅为 `0.0115333`；Repair 仍明显消费该区域。

关键诊断字段现在显式检查；缺少语义结构、保护数组、鼻孔候选或 Repair 权重会以 `diagnoseResidualFeatureArtifacts:MissingDiagnosticField` 失败，不再把缺失字段当作全零检测证据。

## 五项验收

1. **四种同基线输出：通过。** 入口只替换同一 `smoothingResult` 上的 Fine 或 Mid 频率，其他处理结果固定；完整 Repair 重建最大差为 0。无 Repair 的区域消融指标与 03 final 的 `residualFeatureAblationMetrics.csv` 完全一致。
2. **局部对照和分量量化：通过。** 已生成耳部、鼻孔、眉眼的原图/基线/完整 Repair/仅 Fine/仅 Mid/无 Repair 六列局部图，并记录保留率、作用量、瑕疵能量、相对无 Repair 差异和低频结构测量；RGB 差异未被当作质量改善。
3. **真实特征和现有证据：通过。** 77 的固定人工 ROI 保留耳廓、鼻孔、眼睑/睫毛位置；语义、保护、检测候选和 Repair 权重均来自实际字段，鼻孔候选差异单独记录，未改阈值或检测器。
4. **结构与安全：通过。** 四种分量输出在所有记录 ROI 的 `hardProtectionMaxRgbChange`、固定头发 ROI 和背景 ROI 最大 RGB 变化均为 0；低频结构梯度仅作证据。没有用整矩形恢复原图来宣称修复成功。
5. **可复现交接和验证：通过。** 入口、目标测试、量化 CSV、MAT 和局部 PNG 均已交付；80 只复用 03 既有证据，没有重跑完整两图批次。

## 基线来源和资源处理

- 原项目只读基线：`E:\image_beauty` 当前未提交的 v3.2 `src/+beauty/repairSkinBlemishes.m` 与 `src/beautyPipelineContract.m`；契约为 `schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 独立工作树的旧提交为 `c784cd4`；诊断运行通过 `productionRoot='E:\image_beauty'` 明确优先使用原项目当前生产源，未使用工作树旧 `src/`。
- 采用的完整 77 基线：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`，含完整 `context`、`diagnostics` 和 `output`。其中 `output` 与 03 final MAT 的原尺寸 77 输出逐像素一致，最大/均值差均为 0。
- 未采用的 `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_probe\77_probe.mat` 与 03 final 输出和作用量不一致，已排除，避免混拼不同基线。
- 新 MATLAB 批处理曾验证直接模型推理路径，但本机缓存模型在当前运行时无法实例化 `Shape_To_ResizeLayer...` 并回退导入失败；未下载模型、未改生产代码解决资源路径问题，改为复用上述已验证完整 MAT。该过程没有静默替换为其他模型或旧算法。

## 可复现入口

从任意位置启动 MATLAB 后，将诊断测试目录置于路径首位，并显式传入原项目生产根目录和既有完整基线：

    addpath('E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests', '-begin');
    options = struct('productionRoot', 'E:\image_beauty', ...
        'faceBox', [95 79 286 372], ...
        'earRoi', [345 110 75 120], ...
        'nostrilRoi', [185 335 50 35], ...
        'browEyeRoi', [165 205 150 100], ...
        'noseBridgeRoi', [160 295 90 50], ...
        'noseWingRoi', [155 325 80 45], ...
        'hairRoi', [80 90 90 70], ...
        'backgroundRoi', [465 20 40 140], ...
        'smoothingStrength', 100, 'whiteningStrength', 15, ...
        'precomputedDiagnosticsPath', ...
        'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat', ...
        'existingRegionMetricsPath', ...
        'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_77_final\residualFeatureRegionMetrics.csv', ...
        'existingImageMetricsPath', ...
        'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_77_final\residualFeatureImageMetrics.csv');
    [summary, diagnostics] = diagnoseResidualFeatureArtifacts( ...
        'E:\image_beauty\人脸\人脸\77.png', ...
        'C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid', ...
        options);

## 文件差异

只在本票独立工作树新增/修改以下文件：

- `E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\diagnoseResidualFeatureArtifacts.m`：从 03 入口局部扩展，增加 v3.2 基线定位、严格字段检查、四分量隔离、组合残差、CSV 和局部图。
- `E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\testResidualFeatureDiagnostics.m`：目标边界测试，含旧生产基线拒绝检查。
- `E:\home\jjiio\.codex\worktrees\156b\image_beauty\handoff\2026-09-18-beauty-protection-05.md`：本中文交接记录。

未修改 `src/`、GUI、04 入口、公共 Context、缓存版本、检测器、保护阈值或强度曲线；未提交、未推送、未删除文件。

## 验证结果

- `checkcode('E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\diagnoseResidualFeatureArtifacts.m','-id')`：0 条。
- `runtests('E:\home\jjiio\.codex\worktrees\156b\image_beauty\tests\testResidualFeatureDiagnostics.m')`：4 Passed，0 Failed，0 Incomplete。
- 最终全量测试：原项目当前 `src/` + 原项目测试文件 + 本票目标测试，`124 Passed`、`0 Failed`、`0 Incomplete`。
- 77 诊断在一个 MATLAB 批处理进程完成；没有运行 80 或 03 的完整两图批次。
- 03 final 三张既有 CSV 与本票输出的对应 CSV 完全一致：`residualFeatureRegionMetrics.csv`、`residualFeatureAblationMetrics.csv`、`residualFeatureImageMetrics.csv`。

## 临时产物

本票新产物目录：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid`

- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid\original-residualFeatureRepairComponents.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid\residualFeatureRepairComponentMetrics.csv`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid\residualFeatureRepairCombinationMetrics.csv`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid\residualFeatureDiagnosticData.mat`
- 同目录内的 `original-residualFeatureCompare.png`、`original-residualFeatureMaps.png`、`original-residualFeatureAblation.png`、`residualFeatureRegionMetrics.csv`、`residualFeatureAblationMetrics.csv` 和 `residualFeatureImageMetrics.csv` 为本票批处理同步生成的 77 对照产物。

以上临时产物均未写入原项目工作区。
