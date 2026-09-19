# 06 重测记录：独立 Repair 结构门控

记录日期：2026-09-18。

本次重测依据：

- `handoff/2026-09-18-beauty-protection-06-test-gaps.md`
- `.scratch/beauty-protection-convergence/issues/06-validate-independent-repair-structure-gate.md`

## 一、结论

06 的缺口已按要求重新测量，候选仍然**不保留为生产实现**。原因有两类，且分别成立：

1. 候选生产回归仍有 2 项正常行为失败：
   - `testPortraitBeautyHelpers/testBeautyProtectsHairHighlightsAndChroma`：实际最大高光值 `255`，未满足 `<255`。
   - `testPortraitBeautyHelpers/testFrecklesAttenuateProgressivelyWithTextureRetained`：实际 `0.075949805209440`，高于上限 `0.042398499629737`。
2. 80 的真实图目标回归中，固定背景选区仍出现候选相对旧基线的差异：均值 `0.034`、最大 `11`；因此不能宣称“头发和背景选区无新增污染”严格通过。

当前项目生产源码仍为既有 v3.2：

- `src/+beauty/repairSkinBlemishes.m` 保留原公式：
  `structureGate = 1 - structureProtection .* (1 - .90 * blemishMap);`
- `src/beautyPipelineContract.m` 保持 `schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 本次没有把 `structureGate = 1 - structureProtection` 写回生产源码，也没有修改阈值、检测器、Mask、GUI 或模型。

当前项目最终全量回归：`124 Passed, 0 Failed, 0 Incomplete`。

## 二、重测环境与候选补丁

固定基线：

- 77：`77.png`，450×512×3，人脸框 `[95 79 286 372]`，磨皮 100，美白 15。
- 80：`80.jpg`，850×565×3；复用已保存的 02 Context 与 v3.2 输出作为对齐基线。

候选只在临时副本中落地，最小差异为：

```matlab
% src/+beauty/repairSkinBlemishes.m
structureGate = 1 - structureProtection;

% src/beautyPipelineContract.m
algorithmVersion = 'v3.3';
```

临时候选副本：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_candidate_workspace`

临时重测批处理：

`C:\Users\JJiio\AppData\Local\Temp\runIssue06RetestCandidate.m`

上述 v3.3 只用于验证缓存失效和行为变化，未写回项目源码。

## 三、77 冻结参考目标离线重测

入口：

`E:\image_beauty\tests\offlineStructureGateCandidate.m`

该入口冻结保存基线的 Fine/Mid 参考目标、磨皮结果、瑕疵证据、Base、肤色和美白结果，仅重新计算结构门控候选权重并合成对照。新增的可复核 CSV 为：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline_frozen\offlineStructureGateMetrics.csv`

关键结果：

| ROI | 旧 Gate | 候选 Gate | 旧 Fine | 候选 Fine | 瑕疵能量下降 | 低频梯度保留 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ear | 0.941452 | 0.876237 | 0.235768 | 0.191672 | 0.380636 | 0.952647 |
| nostril | 0.768960 | 0.669838 | 0.274552 | 0.223640 | 0.434134 | 0.924152 |
| browEye | 0.887956 | 0.788606 | 0.202936 | 0.121172 | 0.283975 | 1.069432 |
| noseBridge | 0.906282 | 0.896220 | 0.087551 | 0.084441 | 0.376637 | 1.029393 |
| noseWing | 0.845889 | 0.789968 | 0.181871 | 0.154064 | 0.400061 | 0.956152 |
| hair | 1.000000 | 1.000000 | 0 | 0 | 0 | 1.000000 |
| background | 1.000000 | 1.000000 | 0 | 0 | 0 | 1.000000 |

全图和自证结果：

- 冻结旧基线重建最大 RGB 差：`0`。
- 候选相对旧基线最大 RGB 差：`117`；均值差：`0.298954`。
- 候选相对无 Repair 的 RGB 差仍为非零，ear/nostril/browEye 的均值分别为 `3.668111`、`5.506286`、`2.208600`，因此不是通过全局关闭 Repair。
- 离线参考目标冻结标记：`referenceSamplingFrozen=1`。
- 候选没有增大旧 Fine/Mid 权重；最大差记录在 MAT 中。

离线图像产物：

- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline_frozen\offlineStructureGateComparison.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline_frozen\offlineStructureGateMaps.png`
- `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_offline_frozen\offlineStructureGateCandidate.mat`

## 四、77/80 生产候选重测

本次使用临时 v3.3 候选调用真实 `beautifyImage`，没有使用“已限幅旧权重乘比例”的离线伪造结果。

输入与旧基线核对：

- 77、80 文件输入与保存 MAT 中的输入最大 RGB 差均为 `0`。
- 77、80 保存 v3.2 完整输出重建最大 RGB 差均为 `0`。

### 4.1 参考采样变化

候选的 `referenceReliability`、Fine/Mid Reference 和 Target 已单独记录于：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_retest_20260918\issue06CandidateReferenceSamplingMetrics.csv`

代表性区域的 `referenceReliability` 均值变化：

| 样本/ROI | 旧值 | 候选值 | 变化比例（区域内） |
| --- | ---: | ---: | ---: |
| 77 ear | 0.189869 | 0.171603 | 55.6% |
| 77 nostril | 0.350411 | 0.314532 | 99.8% |
| 77 browEye | 0.605023 | 0.570470 | 92.6% |
| 80 normalSkin | 0.796708 | 0.785457 | 99.9% |
| 80 freckle | 0.246339 | 0.222466 | 70.0% |
| 80 noseBridge | 0.627875 | 0.612439 | 100.0% |
| 80 noseWing | 0.699301 | 0.683114 | 100.0% |

参考采样只改动的分解输出也非零：77 的 ear/nostril/browEye 相对旧基线均值差为 `0.2178/0.1623/0.3180`；80 的 freckle/noseBridge/noseWing 均值差为 `0.0585/0.0081/0.0130`。因此候选输出变化不能只归因于权重收紧，参考采样变化已被实际测量。

### 4.2 缓存版本与失效路径

缓存结果文件：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_retest_20260918\issue06CandidateCacheMetrics.csv`

77、80 结果一致：

- 旧缓存标签：`v3.2`。
- 旧缓存传入 v3.3 候选后：`regenerated`，来源标签仍为 `v3.2`。
- 新缓存版本：`v3.3`，旧缓存标签未被改写。
- 旧缓存失效后的重算与无缓存直接计算最大 RGB 差：`0`。
- 新缓存复用标志：`true`。
- 新缓存复用与直接计算最大 RGB 差：`0`。

这部分满足“旧缓存整体失效、新缓存与直接计算一致、不重标旧缓存”的验证要求，但只对临时 v3.3 候选成立。

### 4.3 80 真实图目标回归

结果文件：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue06_retest_20260918\issue06CandidateRoiMetrics.csv`

| ROI | 候选 Fine/Mid 作用非零比例 | 瑕疵能量下降 | 低频梯度保留 | 候选-旧基线均值/最大 RGB 差 |
| --- | ---: | ---: | ---: | ---: |
| normalSkin | 0.9701 | 0.101649 | 1.016577 | 0.0857 / 9 |
| freckle | 0.5656 | 0.023194 | 0.998371 | 0.3792 / 18 |
| noseBridge | 0.9706 | 0.092081 | 0.997458 | 0.1669 / 2 |
| noseWing | 0.9619 | 0.097564 | 0.993437 | 0.2534 / 16 |
| hair | 0 | 0 | 1.000000 | 0 / 0 |
| background | 0.0358 | 0.039302 | 1.003447 | 0.0340 / 11 |

结论：

- 正常皮肤、真实雀斑、鼻梁和鼻翼仍有非零 Repair，未被候选全局禁用。
- 鼻梁/鼻翼的本次低频梯度测量没有显示明显结构塌陷，但这只是样本观测，不是新增阈值。
- 头发固定选区保持无变化；背景固定选区仍有候选相对旧基线的最大差 `11`，严格“无新增污染”不通过。
- 80 全图候选相对旧基线最大 RGB 差 `49`，均值差 `0.174592`。

### 4.4 77 逐症状视觉判决

依据并排图 `issue06Candidate_77_roiComparison.png` 和 `issue06Candidate_77_fullComparison.png`，将视觉判断与低频指标分开记录：

- ear：**部分改善，未完全消除**。候选较 v3.2 减少局部块状 Repair 痕迹，耳廓主体轮廓仍可见；仍有残留，不能据此宣称问题根因已修复。
- nostril：**部分改善，未完全消除**。候选相对旧基线减少部分暗部收敛，鼻孔暗结构保留更明显；低频梯度保留约 `0.9242`，仍需谨慎，未宣称无损。
- browEye：**局部痕迹减轻，但安全性不足**。候选减少部分眉眼灰块/涂抹感，但候选相对基线最大 RGB 差达 `117`，低频梯度保留约 `1.0694`，表现为局部对比变化而非单向质量改善。
- hair/background：77 固定选区无新增差异；该结论只覆盖明确选区，不外推整图。

## 五、测试结果

### 临时 v3.3 候选

- 受影响目标：`testNoseSmoothing` 8 项、`testBeautyContextV3` 11 项、`testResidualFeatureDiagnostics` 4 项，共 `23 Passed`。
- 候选完整测试集：`122 Passed, 2 Failed, 0 Incomplete`，失败即本记录第一节列出的两项 `testPortraitBeautyHelpers` 回归。
- 候选失败后未放宽阈值、未删除测试、未修改无关算法。

### 当前项目 v3.2

最终全量测试入口：

```matlab
addpath('E:\image_beauty\src', '-begin');
addpath('E:\image_beauty\tests', '-begin');
results = runtests('E:\image_beauty\tests');
```

结果：`124 Passed, 0 Failed, 0 Incomplete`。

## 六、项目文件变更与限制

本次为补齐离线缺口，修改了已有验证入口：

- `tests/offlineStructureGateCandidate.m`：新增 `offlineStructureGateMetrics.csv`，补齐无 Repair 对照、瑕疵能量、低频梯度、候选-无 Repair 差异，并明确冻结参考目标。

本次没有修改生产 `src/`。项目工作树中的其他既有未提交改动不属于本次候选重测，未做清理、回退或删除。

模型缓存 `Shape_To_ResizeLayer` 实例化失败仍未解决；本次结论覆盖已保存 Context、生产算法和固定真实图重测，不覆盖当前模型推理、GUI 打开/保存或端到端链路。

## 七、最终判定

**06：候选验证证据补齐；生产候选不通过，不保留。**

保留内容：

- 现有 v3.2 生产实现。
- 离线候选诊断入口及 CSV/MAT/PNG 证据。
- 参考采样分解、80 目标回归和缓存失效测试结果。
- 本重测记录中的最小候选补丁和失败原因。

不保留内容：

- `structureGate = 1 - structureProtection` 的生产源码修改。
- v3.3 算法契约写回项目。 
