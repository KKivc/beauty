# Issue 08.2：真实睫毛像素上的 Repair 改动与保护覆盖空间对应验证

## 1. 结论

本票已完成固定 `77.png` 的空间对应验证，结果归入：

> **Case C：Repair Fine 与 Repair Mid 没有同时指向同一类保护空间，当前证据不足以把“现有保护空洞”作为 Repair 异常的统一直接解释。**

这不是生产修复票。本票没有修改 `src/`、Mask Builder、Repair、Smoothing、模型、GUI 或公共 Context 字段。

核心数值来自同一次无缓存 Issue 08.1 生产诊断运行，并在固定人工真值 `manualLashMask` 内统计：

| 范围 | 像素 | soft support 覆盖 | Repair Fine 绝对作用量 | Repair Mid 绝对作用量 | Repair Fine/Mid action 像素 |
|---|---:|---:|---:|---:|---:|
| 全部人工真实睫毛 | 576 | 100% | 8.20346480648792 | 18.5054764545722 | 355 / 284 |
| 已有 soft support 覆盖 | 386 | 67.0139% | 3.40319999387879 | 12.2714465789600 | 206 / 197 |
| soft protection 空洞 | 190 | 32.9861% | 4.80026481260913 | 6.23402987561220 | 149 / 87 |

Repair Fine 的绝对作用量主要落在空洞区域；Repair Mid 的绝对作用量主要落在已有 soft support 区域。两阶段空间方向不一致，因此不能按 Case A 宣称“Fine/Mid 主要发生在保护空洞”，也不能按 Case B 宣称“连续保护仍无法解释全部 Repair”，最终按票据三分流进入 **Case C**。

## 2. 固定基线与人工真值

- 输入：`E:\image_beauty\人脸\人脸\77.png`
- 图像尺寸：`450×512×3`
- `faceBox = [95 79 286 372]`
- `browEye = [165 205 150 100]`
- `lashRoi = [102 248 177 48]`
- 磨皮：`100`
- 美白：`15`（复用 Issue 08.1 当前基线）
- 基线 Context：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_probe\77_v32_probe.mat`

新增固定人工标注入口：

- `tests/eyelashManualLashMask77.m`

标注 ID 为 `77-manual-lash-v1`，共 `576` 个标注像素。标注只根据 `77.png` 原图视觉真值固定建立，包含固定 ROI 内可直接辨认的两段上睫毛细线；不把眼线、双眼皮褶皱、眼球、眉毛、普通皮肤或不确定像素并入。该 helper 不读取 Protection Mask、Repair/Smoothing delta、Detector 或生产诊断结果，并在测试中声明 `diagnosticsIndependent=true`、`fixedAfterAnnotation=true`。

## 3. 实现文件

新增：

- `tests/eyelashManualLashMask77.m`
- `tests/diagnoseResidualEyelashCoverageAttribution.m`
- `tests/testResidualEyelashCoverageAttribution.m`
- `handoff/2026-09-18-beauty-protection-08-2-eyelash-coverage-attribution.md`

诊断入口流程：

1. 固定坐标和 77 图像尺寸校验；
2. 先建立独立且固定的 `manualLashMask`；
3. 调用现有 `diagnoseResidualEyelashLoss`，由当前工作区生产入口重新生成同一次运行的 frequency、`textureProtectionMask`、`eyeDetailProtection`、`lashProtection`、`doubleEyelidProtection`、`hardProtectionMask`、Smoothing delta、Repair Fine/Mid delta；
4. 在同一 `manualLashMask` 内分为 `coveredBySoftSupport` 与 `uncoveredProtectionHole`；soft support 使用现有 `textureProtectionMask` / `eyeDetailProtection` / `lashProtection` 的严格非零并集，不新增经验等级阈值；
5. 分别核对 Repair Fine 与 Repair Mid 的绝对作用量、作用像素、保护边界和局部叠加图；
6. 输出 CSV、MAT 和空间叠加图。

## 4. 产物

正式验证产物写入系统临时目录，不写入项目仓库：

`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_2_eyelash_20260918`

包括：

- `eyelash_manual_lash_mask.png`
- `eyelash_manual_lash_overlay.png`
- `eyelash_manual_vs_texture_protection.png`
- `eyelash_manual_vs_lash_protection.png`
- `eyelash_manual_vs_eye_detail_protection.png`
- `eyelash_manual_vs_repair_fine.png`
- `eyelash_manual_vs_repair_mid.png`
- `eyelash_manual_protection_repair_overlay.png`
- `eyelash_coverage_attribution.csv`
- `eyelash_coverage_attribution.mat`
- `issue08_1_base/`：本票复用的 Issue 08.1 同次基线产物

核心图说明：

- `eyelash_manual_lash_overlay.png`：原图与人工真值边界；
- `eyelash_manual_vs_*`：同一真实睫毛真值与单项 Protection / Repair 连续值空间叠加；
- `eyelash_manual_protection_repair_overlay.png`：红色为真实睫毛/保护空洞边界，绿色为已有 soft support，黄色为 Repair Fine/Mid 非零作用位置，同时显示原图及两阶段作用图。

## 5. 验证结果

目标测试：

- `testResidualEyelashCoverageAttribution`：**4 Passed, 0 Failed, 0 Incomplete**。

覆盖内容：

- 固定人工真值独立性与固定 ID；
- 非固定 ROI / 尺寸拒绝；
- 固定 77 生产基线、同一次 Mask/频率链、无旧 runtimeCache 复用；
- 原始 frequency 重建误差不超过 Issue 08.1 容差；
- 所有建议核心图、CSV、MAT 产物存在；
- CSV 含全部人工真值、已覆盖和空洞三类空间统计。

本次运行日志中的固定基线检查：

- 原始 frequency 重建最大误差：`2.7755575615628914e-17`；
- `runtimeCacheReused = false`；
- Smoothing / Repair 使用同一次生产诊断链；
- Base / tone / whitening 在离线 Fine/Mid 探针中关闭。

PNG 读取出现 `iCCP: cHRM chunk does not match sRGB` 警告；不影响测试通过或诊断数组。

最终全量 `tests/` 回归（同一 MATLAB 批处理进程）：

- **139 Passed, 0 Failed, 0 Incomplete**。
- 其中包含 Issue 08.1 的 `testResidualEyelashLossDiagnostics` 与本票 `testResidualEyelashCoverageAttribution`。
- 全量结果另存于：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue08_2_eyelash_20260918\full_test_results.mat`。

## 6. 后续边界

本票只支持以下结论：

> 在固定 77 样本、固定人工真实睫毛真值上，Repair Fine/Mid 与现有 soft protection 覆盖的空间对应不一致，当前不能把保护空洞作为两个 Repair 阶段共同的直接根因。

本票不支持：

- 修改 Repair 全局公式；
- 新增 hard lash core；
- 全局提高 texture protection；
- 关闭 Repair Fine/Mid；
- 修改 BiSeNet / Face Parsing 阈值；
- 对其他图像外推相同根因。

若要继续，应先针对 Case C 的空间不一致分别核查 Fine 与 Mid 的消费路径及局部视觉效果，仍不得直接把本票结果改写为 Case A 的 soft coverage 修复授权。
