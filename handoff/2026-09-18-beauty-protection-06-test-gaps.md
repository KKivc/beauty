# 06 验收缺口交接：独立 Repair 结构门控

记录日期：2026-09-18。
来源：beauty-protection-convergence 会话（Codex 线程 `01a0ae32-d2e7-7a11-9525-026b3caba99b`）；06 执行工作树 `E:\home\jjiio\.codex\worktrees\156b\image_beauty`；票面 `.scratch/beauty-protection-convergence/issues/06-validate-independent-repair-structure-gate.md`。

本记录只回答一个问题：**06 票哪些验收没有测好**，并给出手上已有的证据和最小补测口径。它不代表 06 已通过，也不代表 Repair 已修复。

## 一、当前状态

- 票面唯一候选：`structureGate = 1 - structureProtection`（保留既有 strongStructure 硬边缘下限、鼻部系数、纹理门控与限幅顺序）。
- 生产源码未保留候选：`src/+beauty/repairSkinBlemishes.m:47,51` 仍是 v3.2 公式 `1 - structureProtection .* (1 - .90 * blemishMap)` 加 `strongStructure` 下限；契约 `schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 随 06 同步进项目的入口：
  - `tests/offlineStructureGateCandidate.m`：已被主会话修正为按票的纯门控探针——冻结磨皮结果与 Fine/Mid 参考目标、旧基线重建必须为 0、只替换结构门控；输出目录 `%TEMP%\image_beauty_issue06_offline_frozen`。
  - `tests/runStructureGateProductionValidation.m`：固定 77 Context 上调用真实 `beautifyImage`，记录门控/权重/修复能量/低频梯度/缓存一致性；候选撤回后仅作诊断入口。
  - `tests/testResidualFeatureDiagnostics.m`：06 目标测试，4 Passed。
- `handoff/2026-09-18-beauty-protection-06.md` 与其工作树副本逐字节一致，但其中的离线数字来自被主会话判定不合规的旧探针，尚未更新（见缺口 1）。
- 关键固定证据：
  - 77 完整基线 MAT：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`
  - 05 分量证据：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue05_77_fine_mid`
  - 旧探针产物：`...\image_beauty_issue06_offline`（10:19）
  - 修正探针产物：`...\image_beauty_issue06_offline_frozen`（10:51）
  - 候选生产运行产物：`...\image_beauty_issue06_production`（10:37，含 `productionStructureGateMetrics.csv`、`productionValidation.mat`）

已经测好的部分（避免接手重复）：固定 77 的旧基线完整重建差为 0；门控与权重的 ROI 统计（修正前后版本数值一致）；候选临时落地期间在固定 77 上跑过真实生产链与缓存一致性；撤回候选后目标测试与全量测试通过。下面只列没有测好的部分。

## 二、06 没有测好的具体位置

### 1. 交接记录里的离线数字来自不合规探针，修正后的结果没有回写

- 证据：旧探针使用分解前的 `frequency.fine/mid`，并重算 `newReferenceReliability / newFineReference / newMidReference / newFineTarget / newMidTarget`，把门控变化和参考采样变化混在一起；主会话已在 10:51 将其改为冻结参考目标后重跑。`handoff/2026-09-18-beauty-protection-06.md` 于 10:47 写成，其离线数字（均值差 `0.810781`、无 Repair 对照 `3.9675/5.4284/3.4673`、瑕疵能量下降 `0.319855/0.383340/0.241926`、低频梯度 `1.006427/0.922411/1.141752`）只能来自 10:19 前的旧探针。
- 修正探针最近一次运行（10:51，控制台输出）为：候选 vs 基线最大 RGB 差 `117.000000`、均值差 `0.298954`；`fineWeight`/`mediumWeight` 最大差均为 `1.000000`；旧基线重建差 `0`。这些都没有写进任何记录，也没有人给出判读。
- 另外，「无 Repair 对照 RGB 差」「瑕疵能量下降」「低频结构梯度保留率」这三项在修正后的入口里**没有任何计算代码，也没有 CSV**，无法由项目内入口复现——它们现在是无出处的数字。
- 影响：`06 交接` 的离线部分整体不可作为证据链引用；「离线候选是否有效」目前没有按票记录过的结论。
- 补测判据：用修正后入口重跑一次，产出 CSV/MAT 并写回记录，至少包含：旧基线重建差（自证）、门控统计、ROI 门控/权重表、候选 vs 基线 RGB 差、无 Repair 对照、修复能量、低频梯度；或明确删除交接中无法复现的数字并注明作废。

### 2. `80.jpg` 的目标回归从未在候选下执行

- 证据：06 交接写明「80 只复用了既有完整证据，未重跑完整图集」；05 交接同样写「80 未重跑」；06 票验收条件第 4 条要求生产候选验证 80 的正常皮肤、真实雀斑仍可修复、鼻梁鼻翼结构不退化、固定头发/背景选区无新增污染。
- 影响：候选引入的两项失败都是合成图（`syntheticPortrait`）上的断言，其中雀斑断言恰好是「修复不足」方向；真实雀斑人像在候选下的表现完全没有观测。
- 补测判据：候选重新落地（或离线合成）后，在 80 的对齐基线上输出正常皮肤、真实雀斑、鼻梁/鼻翼、固定头发与背景选区的对照与量化，记录是否仍保留非零修复、是否出现新的结构或污染问题。

### 3. 参考采样变化没有单独核对

- 证据：验收条件第 3 条要求「权重和参考采样均遵从独立结构门控，并核对参考采样变化后的实际效果」。`productionStructureGateMetrics.csv` 只有门控/权重/能量/梯度/输出差，没有旧/新 `referenceReliability`、`fineReference`、`midReference`、`fineTarget`、`midTarget` 的对照；修正后的离线探针又按第 1 条要求把参考目标冻结了，因此参考采样收紧这一半变化目前是零测量。
- 补测判据：在生产候选下同时输出旧/新参考可靠度与参考值的区域统计及（如可行）只改参考采样不改权重的分解对照；至少要在记录中区分「权重变化」与「参考采样变化」各自的贡献。

### 4. 算法版本与缓存失效路径没有验证

- 证据：验收条件第 4 条要求「行为改变时更新算法版本……接受既有缓存整体失效并验证新缓存与直接计算一致；不重标旧缓存」。主会话在 10:12 已指出候选落地期间「算法版本也没有更新到新行为」；现有缓存证据只是固定 MAT Context 上「复用 runtimeCache 与 rmfield 后直接计算同版本一致（差 0）」。
- 补测判据：候选落地时更新 `algorithmVersion`，验证旧缓存被拒绝并按新行为重算、新缓存与直接计算一致、旧缓存标签未被改写。

### 5. 全量回归口径前后矛盾，失败根因未分离

- 证据：第一版交接称全量 `117/122` 通过、5 个失败为「已知副作用」，被主会话判定为不成立；最终版交接改为 2 项失败并给出数值：`testBeautyProtectsHairHighlightsAndChroma` 实际 `255` 未小于 `255`，`testFrecklesAttenuateProgressivelyWithTextureRetained` 实际 `0.075949805209440` 大于允许上限 `0.042398499629737`。中间失败集合的变化过程没有留下记录。
- 影响：无法判断最终失败集合是否稳定，也无法说明失败来自门控收紧还是参考采样变化；而这两项都指向「正常皮肤修复能力」这一票内明确要求保留的行为。
- 补测判据：候选补丁固定后跑一次受控全量回归，记录完整失败集合；对两项失败分别定位到具体变化来源（门控或参考采样），并说明是候选的可接受副作用还是不可接受退化。

### 6. 只看指标，没有逐症状的视觉判决

- 证据：验收条件第 2 条要求「原图、旧输出与候选输出同尺度并排展示，分别判断耳廓块状变化、鼻孔暗结构及眉眼灰块/涂抹」，并「记录未改善症状及副作用」。现交接只有量化表与「低频梯度区域不一致」的判断；修正后生成的 `offlineStructureGateComparison.png`（`_offline_frozen`）没有任何复核记录。
- 补测判据：按 ear/nostril/browEye 逐项写出「改善 / 未改善 / 变差」的视觉结论与副作用，注明所看的图与选区；低频指标与完整输出检查分开记录。

### 7. 生产候选数字不可复现，补丁也没有留存

- 证据：候选生产数字（最大 RGB 差 `117`、均值差 `0.305408`、能量与梯度）来自 10:37 的运行；候选补丁已撤回，工作树与项目源码都回到 v3.2。现在直接运行 `tests/runStructureGateProductionValidation.m` 只会在 v3.2 源码上做基线自比，无法复现 117 等候选数字。
- 另注意：工作树里的 `tests/runProductionValidation.m` 是被 `runStructureGateProductionValidation.m` 取代的旧入口（主会话认定它「读取旧 Repair 结果直接合成」），项目内没有同步它，不要拿它当生产验证入口。
- 补测判据：补丁以最小 diff 形式记录在交接里（门控一行 + 如有版本行），并注明「重跑前需先落地该补丁」；或在离线 MAT 上重现同一数字。

### 8. 端到端与 GUI 路径仍被阻塞，未被 06 覆盖

- 证据：模型缓存 `Shape_To_ResizeLayer` 实例化失败仍未解决；06 的生产候选验证复用 02 保存的 MAT Context，不是当前模型推理路径，也没有走 GUI 打开/保存链路。
- 影响：06 的所有结论只覆盖「已保存 Context + 生产算法」，不能宣称端到端、GUI 或当前模型推理通过；票内已声明这一点，接手不要把它当成已验收项。

## 三、建议的最小补测顺序（每步一个目标，不顺带加范围）

1. 用修正后的 `offlineStructureGateCandidate.m` 重跑固定 77，落盘 CSV 并更新 06 记录（含旧基线重建自证与修正后的实际数字）；同时处理无法复现的旧数字。
2. 在独立工作树重新落地候选最小补丁并更新算法版本，先跑受影响目标测试，再在 80 上执行第 4 条要求的目标回归（正常皮肤、真实雀斑、鼻梁鼻翼、头发/背景），并验证缓存失效与新缓存一致性。
3. 按第 2 条口径逐症状写出视觉结论与副作用（可用修正探针已生成的对比图）。
4. 结案二选一：候选落地并附全部证据；或明确「候选不落地，仅保留诊断」，并把所有记录中的数字、目录和入口对齐到同一版本。

纪律沿用 06 票：只改 Repair 内部门控、必要的算法版本和最小验证入口；不新增依赖、公共字段或新阈值；补充测量在单个 MATLAB 批处理进程汇总，先读已有输出再决定补测；临时图/CSV/MAT 放临时目录，项目内只留可复现入口和中文记录；不提交、不推送、不删除文件。

## 四、供核对的既有数字

固定 77（磨皮 100、美白 15、人脸框 `[95 79 286 372]`）：

| ROI | 旧门控均值 | 候选门控均值 | 旧 Fine 权重 | 候选 Fine 权重 |
| --- | ---: | ---: | ---: | ---: |
| ear | 0.9415 | 0.8762 | 0.235768 | 0.191672 |
| nostril | 0.7690 | 0.6698 | 0.274552 | 0.223640 |
| browEye | 0.8880 | 0.7886 | 0.202936 | 0.121172 |
| noseBridge | 0.9063 | 0.8962 | 0.087551 | 0.084441 |
| noseWing | 0.8459 | 0.7900 | 0.181871 | 0.154064 |
| hair / background | 1.0000 | 1.0000 | 0 | 0 |

- 全图门控均值 `0.974798 -> 0.959632`；均值绝对差 `0.015166`；最大差 `0.899502`。两张离线探针版本的该组数值一致。
- 生产候选（10:37）：Repair 能量 ear `0.029266 -> 0.017791`、nostril `0.042625 -> 0.024272`、browEye `0.025173 -> 0.017880`；低频梯度保留率 ear `0.954711`、nostril `0.920762`、browEye `1.071336`；候选相对旧基线最大 RGB 差 ear `62`、nostril `40`、browEye `117`；hair/background 输出差 `0`。
- 修正探针最近一次运行（10:51）：旧基线重建差 `0`；候选 vs 基线最大 `117.000000`、均值 `0.298954`；权重最大差 `1.000000`。
- 候选下全量回归记录：`testPortraitBeautyHelpers/testBeautyProtectsHairHighlightsAndChroma` 实际 `255` 未小于 `255`；`testPortraitBeautyHelpers/testFrecklesAttenuateProgressivelyWithTextureRetained` 实际 `0.075949805209440` 大于上限 `0.042398499629737`。候选撤回后的记录为全量通过（06 交接记 `122 Passed`，同批同步记录记 `124 Passed`，两者测试集合不同，需在补测时统一口径）。
