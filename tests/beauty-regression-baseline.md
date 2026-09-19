# 美颜回归基线

该基线由 `src/runBeautyRegression.m` 在合成图上生成，默认不读取外部图片。默认实现固定为 v3，统一指标使用 YCbCr 亮度通道、按人脸尺度计算的低通尺度、语义 ROI 和 90% 梯度分位数；鼻部和脸外皮肤结构共用同一套配置与统计公式。

## 当前 v3 基线

记录时间：2026-09-16。强度顺序为 `0/25/50/75/100`；磨皮时美白为 0，美白时磨皮为 0。

| 指标 | 0 | 25 | 50 | 75 | 100 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 磨皮纹理能量 | 0.00243466 | 0.00208287 | 0.00180369 | 0.00160131 | 0.00160104 |
| 磨皮瑕疵能量 | 0.00348572 | 0.00288498 | 0.00240470 | 0.00216450 | 0.00216265 |
| 鼻部结构 | 0.00742720 | 0.00728571 | 0.00724176 | 0.00723927 | 0.00723715 |
| 脸外皮肤结构 | 0.00150615 | 0.00161016 | 0.00158428 | 0.00149938 | 0.00149938 |
| 美白平均亮度 | 0.59227780 | 0.61526385 | 0.63516017 | 0.65281702 | 0.67026860 |

基于强度 0 的实测结构基线，当前允许下限为：

- 鼻部结构：`0.00668448`（基线的 90%）。
- 脸外皮肤结构：`0.00135553`（基线的 90%）。
- 纹理能量、瑕疵能量须随磨皮强度不增加；亮度须随美白强度不降低。
- 合成图背景最大变化为 `0`，硬保护最大变化为 `0`。
- 输出保持输入的尺寸、三通道和 `uint8` 类型。

本次 `runBeautyRegression('Assert', true)` 返回 `pipeline: 'v3'`、`violations: {}` 和 `passed: true`。

## 重复运行

```matlab
addpath('src');
report = runBeautyRegression('Assert', true);
```

本地真人图只通过 `runBeautyRegression('PrivateSmoke', entries)` 参数化传入；报告只返回聚合指标和数量，不保存路径、EXIF 或人物信息。2026-09-16 已使用用户提供的 `D:\桌面\人脸\人脸` 完成第二、第三阶段 smoke；本基线不替代 GUI 手动视觉结论。

## V4 架构迁移兼容基线（T01）

V4 迁移期间（只改架构、不改效果）的一切 Ticket 必须对本基线保持 bit-exact 等价。

- Oracle commit：`e889f31ab04de3d10f21be3c3a6f1b09df19dd80`（main）。
- 契约版本：`schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 记录时间：2026-09-19，MATLAB R2024a，Windows。
- 比较口径：架构兼容阶段全部 bit-exact。最终 RGB 以 SHA-256（输出 `uint8` 列优先字节序；R2024a 无原生 `sha256`，经 JVM `MessageDigest` 计算）断言；零强度输出、hard identity 区域、cached/uncached 输出、预览/原尺寸路径要求精确相等。基线 commit 上已实测两次全量重算、缓存复用与重算输出完全一致，因此不设数值容差，禁止视觉阈值。

### T08 schema 切换记录（2026-09-19）

T08 把默认生产 Context 从 `3.1` compat 形态有意切换为 `4.0` canonical 分层形态（架构 schema expand：发布 semantic/processability/evidence/protection/diagnostics 分层，保留 skinMask、textureProtectionMask 等迁移期 compat alias）。变更依据与影响范围：

- 这是纯架构迁移：`algorithmVersion=v3.2`、`artifactVersion=v3.1` 不变，算法数值路径无任何改动；上表全部 RGB digest、零强度、hard identity、cached/uncached、预览/原尺寸 oracle 必须继续 bit-exact 一致（已在本批 MATLAB 进程内用改动前后 SHA-256 探针逐项复核，digest 全部一致）。
- 上方契约版本行保留 e889f31 录制时的 `3.1` 快照；`testFrozenPipelineContract` 自 T08 起断言 `schemaVersion='4.0'`。
- 缓存兼容仍由 `artifactVersion` 把握：`3.1` 戳旧缓存与 `4.0` 戳新缓存都是读者已知的合法形态，与 V4 Context 指纹一致时可安全复用，不一致时安全重建。

### 合成 oracle（`tests/testMaskSystemV4CompatibilityBaseline.m`）

- 样本来源：测试内确定性合成 fixture（解析公式 + 注入语义 + 零 SCHP 概率；不读外部图片、无随机数、无模型推理）：rich 180×260（皮肤/脖颈/鼻侧影/雀斑/硬保护眼部，公式复用 `runBeautyRegression`）；compact 120×160（正弦皮肤纹理 + 眼/唇语义，公式复用 `testBeautyV3`）。
- 固定参数组合与最终 RGB digest：

| fixture | smoothing | whitening | SHA-256 |
| --- | ---: | ---: | --- |
| rich | 100 | 0 | `8ef2bf0ec01c681a2ee1d649220581ff7bf3dbb9cb650b5a37db9cab78682dc6` |
| rich | 0 | 100 | `58ab2f354176fb258dcef67e01ff65d5c4c2b98f0085902cfe16c604281bfe80` |
| rich | 100 | 15 | `6716ed9ef1db1c9a3f91c5c1aa877732a92398e2452abdacd6d3aefc9fac21f9` |
| rich | 50 | 25 | `b18986f62ffa6952b2252160dc79264448d2fac9c16b935cf6b4e966104dc6fe` |
| compact | 100 | 15 | `012175a4b7b63b06bd73dd8a3dd638c811d4fcde24d544047e4b154b6e4b6304` |
| 预览路径（0.5 缩放，rich） | 100 | 15 | `dc6539302f6c001509f0cb69a95ae87691d852e551ba915b83ba98e10e3b89b2` |
| 原尺寸路径（preview→resize 重建，rich） | 100 | 15 | `31e9168c9dc1d74d3a0c40104c64eb40bd1d74ce6e1eb57e4f748db96c7a1ef7` |

- 零强度（0/0）输出必须与源图完全一致；hard identity 区域（`hardProtectionMask >= .999`）RGB 必须与源图完全一致；cached/uncached 输出必须完全一致。

### 真实图 oracle（`tests/runIssue08Validation.m`）

- 固定 77 链路（私有图路径仅存在于该既有入口，产物写入系统临时目录，不在提交中出现）：参数 `smoothingStrength=100, whiteningStrength=15`，faceBox `[95 79 286 372]`，语义取自冻结 context（剥离 runtimeCache 与派生 Mask 后由当前生产链重建）。
- e889f31 输出 digest：`ce17e323dc4208d973ccae4b4a2cc122b2fed75fe7500088197c5278806bdc4c`，当前生产输出必须 bit-exact 一致；hard identity 区域（82266 像素）相对源图变化必须为 0。
- 注意：`%TEMP%\image_beauty_issue02_probe\77_v32_probe.mat` 是 issue08 入口的内部重建夹具，其输出与 e889f31 生产输出不同（实测最大 RGB 差 118），不得当作 T01 oracle。

### T20 eye/lip identity policy 重录记录（2026-09-19）

T20（工单 `20-eye-lip-identity-policy`）是 V4 迁移完成后第一批**真实 policy 行为变化**："bit-exact 纪元"结束。生产链（V4 Context 携带 evidence 层）对眼周/唇周执行三带分级保护（`masks.buildStageProtectionMasks` 第二输入 `policyEvidence`，经 `rebuildBeautyDerivedMasks` 桥接与 `beautifyImage` evidence 转发生效）：

- identity core（眼语义 ≥.65 经 occluderHard、检测睫毛 lashCore、唇核 lipCore）：本就全部位于 `hardProtectionMask`，T20 **不新增任何 hard 像素**（hard 原样拷贝，严格二值）。
- soft detail band（`smoothStep(periocular,.50,.78)` / `smoothStep(lip,.55,.85)`）：抬升 smoothingFine/repairFine/baseLuminance 至 `.95`、smoothingMid/repairMid 至 `.90·band`、whitening 至 `.85·band`、tone 至 `.90·lipBand`；legacy 环带 plateau 仅 .76（眼）/.90（唇）。
- skin transition band（`smoothStep(periocular,.08,.40)` / `smoothStep(lip,.12,.50)`，与 detail band 互斥）：texture 通道封顶 `1-.55·transitionBand`，把 legacy 满保护环带的处理量重新打开（≥55%），保留眼周/唇周皮肤的可处理性。
- 消费侧边界：smoothingFine/smoothingMid/hard 由 smoothSkinTexture（T12/T13）直接用于输出算术，policy 对磨皮立即生效；repairFine/repairMid/baseLuminance/tone/whitening 仍是 T14–T18 consumer 的零瑕疵参考快照（算术门控由未折叠字段承载），分级数值先行发布。因此美白-only 场景输出不变（见下表 0/100 行 digest 保持 e889f31 原值）。

**合成 oracle digest 新旧对照**（fixture 与参数组合不变；仅 digest 重录）：

| fixture | smoothing | whitening | e889f31 旧值 | T20 新值 | 变化 |
| --- | ---: | ---: | --- | --- | --- |
| rich | 100 | 0 | `8ef2bf0e…78682dc6` | `fffa926c…51190b61bf61` | 是（眼周 smoothing） |
| rich | 0 | 100 | `58ab2f35…604281bfe80` | `58ab2f35…604281bfe80` | 否（s=0 不触发 smoothing） |
| rich | 100 | 15 | `6716ed9e…c9fac21f9` | `e981883d…cdbc214d32a1` | 是 |
| rich | 50 | 25 | `b18986f6…966104dc6fe` | `b4cfffbf…a414e00cd7` | 是 |
| compact | 100 | 15 | `012175a4…54b6e4b6304` | `35279975…07a21b75` | 是（眼+唇 smoothing） |
| 预览路径（0.5 缩放，rich） | 100 | 15 | `dc653930…e10e3b89b2` | `32ecb919…2f008485b` | 是 |
| 原尺寸路径（preview→resize，rich） | 100 | 15 | `31e9168c…c7a1ef7` | `fe627460…0115ea5` | 是 |

变化原因：policy 只经 smoothingFine/smoothingMid 影响输出算术，变化集中在眼周/唇周 evidence 带内（合成 rich fixture：detail band 237px、transition band 333px；compact：399px/388px）；带外（背景与普通脸颊）所有 stage 字段与输出逐位不变。

**structural 不变量复核**（T20 重录批内实测）：

- 零强度（0/0）输出 = 源图：逐位相等（rich/compact）。
- hard identity 区域 RGB = 源图：逐位相等；hard nnz 改动前后对照：rich 220→220、compact 269→269、真实图 77 链路 82266→82266（全部逐位相等，零膨胀）。
- cached/uncached 输出：逐位相等（rich、预览/原尺寸路径）。
- 预览/原尺寸路径：各自 digest 重录后测试通过，两路径 cached/uncached 一致性保持。
- 背景与普通脸颊不变性：evidence 全零像素处 8 个 stage 字段与 Fine alphaMap 逐位等于 legacy；合成 fixture 输出差异带外像素为 0；真实图 77 链路带外变化 37/227685（≤0.02%，平滑空间卷积的亚像素泄漏）。
- compat Context（无 evidence 层，v3.1 轻量路径/手工 legacy Context）仍走 T07 legacy 折叠：真实图 77 链路在剥离 evidence 后输出 digest 与 e889f31 oracle `ce17e323…8806bdc4c` 逐位一致。

**真实图局部验收**（私有图 77 链路，smoothing=100/whitening=15；路径与人物信息不入库，对比图在 `.scratch/tmp/real77_roi_*.png`）：

- policy 相对 legacy 的全图变化：135 像素（0.06%），max |dRGB|=4.7，全部集中在眼/唇 evidence 带内（带内 mean|dRGB|=0.05）。
- 眼/唇 detail band 高频细节能量保留：policy=1.045 vs legacy=1.047（以源图为 1）；transition band 输出变化保持连续，无未处理环带回归。
- hard 区域（82266 像素）RGB 与源图逐位相等；视觉上眼周/唇周无新增光晕、无缝合描边，唇缘色彩与眼睑细节保留完整。
