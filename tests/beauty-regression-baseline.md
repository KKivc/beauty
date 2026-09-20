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
  > **T30 更新（2026-09-20）**：该"零瑕疵参考快照"边界已被 T30 激活——分级保护改由纯 policy 带 `regionBand*` 注入各 stage 真实算术门控，美白-only 场景随之变化。见下文「T30 region policy gate activation 重录记录」。

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

### T21 nose region policy 重录记录（2026-09-20）

T21（工单 `21-nose-region-policy`）是第二批**真实 policy 行为变化**：`masks.buildStageProtectionMasks` 新增消费 `evidence.nostril` / `evidence.noseStructure`（经 `readNoseBands`，缺省/partial evidence 时两带恒零 → 逐位还原 T07 legacy 折叠）：

- 鼻孔边缘软带：`nostrilEdge = max(0, 1 - bwdist(nostrilCore)/(r+1))`，`r = min(4, max(2, round(.006*faceScale)))`——与 `buildTextureProtectionMask` 的 `nostrilProtection` 同一 radius 公式与 footprint（2–5px 软带，非大半径膨胀）；`nostrilDetailBand = smoothStep(nostrilEdge, .40, .80)`。
- 鼻结构带：`noseStructureBand = smoothStep(noseStructure, .15, .50)`（鼻语义支持 × 低频梯度 × 方向一致性）。
- stage 分配：`smoothingFine`（经 `policyTexture`）`+ .95·nostrilDetailBand`；`smoothingMid`/`repairMid` `+ max(.90·nostrilDetailBand, .85·noseStructureBand)`；`baseLuminance` `+ .80·noseStructureBand`；`whitening` `+ .85·nostrilDetailBand`；`tone` **不追加**鼻部项（鼻部无 identity 色度语义，肤色与脸颊保持连续）。
- 消费侧边界与 T20 相同：只有 `smoothingFine`/`smoothingMid` 直接进入输出算术；`repairFine`/`repairMid`/`baseLuminance`/`tone`/`whitening` 仍是 T14–T18 consumer 的零瑕疵参考快照。

**合成 oracle digest 新旧对照**（fixture 与参数组合不变；仅 digest 重录）：

| fixture | smoothing | whitening | T20 旧值 | T21 新值 | 变化 |
| --- | ---: | ---: | --- | --- | --- |
| rich | 100 | 0 | `fffa926c215f1ad2ca4ec2adb027c5f0d56eb1a0ff014145092151190b61bf61` | `330ddc30c63bf9a9d896d1a65e6ef62421a3006230ed2fc8026e65e50ee04204` | 是（鼻孔软带抬升 Fine 侧保护） |
| rich | 0 | 100 | `58ab2f354176fb258dcef67e01ff65d5c4c2b98f0085902cfe16c604281bfe80` | `58ab2f354176fb258dcef67e01ff65d5c4c2b98f0085902cfe16c604281bfe80` | 否（s=0 不触发 smoothing） |
| rich | 100 | 15 | `e981883d03041d1835ce4993ee4b8741feadbe8fdf32e41449cd8dbc214d32a1` | `64f0a75e37bbcc8d893376dc702e83b180823fc717051a9d3098539ba5be9782` | 是（3px，带内） |
| rich | 50 | 25 | `b4cfffbf09872912e27fdc8d1c3f202b1a22d5bf80bef80da8963aa414e00cd7` | `b4cfffbf09872912e27fdc8d1c3f202b1a22d5bf80bef80da8963aa414e00cd7` | 否（T21 增量未越过 uint8 量化） |
| compact | 100 | 15 | `35279975228d5c25334e8b3a3a8fb243a532e9fb85a94a11acbff8c407a21b75` | `35279975228d5c25334e8b3a3a8fb243a532e9fb85a94a11acbff8c407a21b75` | 否（T21 增量只落在非消费参考快照） |
| 预览路径（0.5 缩放，rich） | 100 | 15 | `32ecb919c09c7899e83aa9c48bfe3bd1c212ff3c15f8cf7448fd7652f008485b` | `32ecb919c09c7899e83aa9c48bfe3bd1c212ff3c15f8cf7448fd7652f008485b` | 否 |
| 原尺寸路径（preview→resize 重建，rich） | 100 | 15 | `fe627460bb82d7b4bfd2e07d270c442398d22d80008a131afb681a5020115ea5` | `6b8e96a5088f422c7ff20a9499377cce521d0bb68729ebcbf266aea1a3054176` | 是（resize 在目标分辨率重建 evidence，鼻结构带生效） |

上表"T21 新值"即 `tests/testMaskSystemV4CompatibilityBaseline.m` 当前生效的 `recordedRgbBaseline` / `recordedOriginalSizeDigest`（预览路径保持 T20 值）。

**归因证据（逐 Ticket 字段置零探针，`.scratch/tmp/T21T22-digest-remeasure.log`）**：把某 Ticket 消费的 evidence 字段置零后重算最终 RGB，判定该 Ticket 是否真的改变了该 case 的输出——

| case | T20（periocular+lip） | T21（nostril+noseStructure） | T22（earStructure） |
| --- | ---: | ---: | ---: |
| rich 100/0 | 87px | 9px | 0px |
| rich 0/100 | 0px | 0px | 0px |
| rich 100/15 | 177px | 3px | 0px |
| rich 50/25 | 9px | 0px | 0px |
| compact 100/15 | 158px | 0px | 0px |
| 预览路径 | 变化 | 0px | 0px |
| 原尺寸路径 | 变化 | 变化 | 0px |

带 footprint（合成 fixture）：rich `nostril nnz>0=37`、`noseStructure nnz>0=1353 (max=0.279)`、`earStructure nnz>0=0`；compact `nostril=55`、`noseStructure=572 (max=1.000)`、`earStructure=0`。

**structural 不变量复核**（T21 重录批内实测）：

- 零强度（0/0）输出 = 源图：逐位相等（rich/compact）。
- hard identity 区域 RGB = 源图：逐位相等；hard nnz rich 220、compact 269，与 T20 记录一致（零膨胀）。
- cached/uncached 输出：逐位相等（rich、预览/原尺寸路径）。
- compat / legacy 路径（剥离 evidence 层）：7 项 digest **全部**等于 e889f31 原值（rich 100/0 `8ef2bf0e…`、rich 100/15 `6716ed9e…`、rich 50/25 `b18986f6…`、compact 100/15 `012175a4…`、预览 `dc653930…`、原尺寸 `31e9168c…`；rich 0/100 因不触发 smoothing 本就相同）；真实图 77 链路 compat digest == 冻结 oracle `ce17e323dc4208d973ccae4b4a2cc122b2fed75fe7500088197c5278806bdc4c`（逐位相等）。
- 结构性断言（`testFrozenPipelineContract`、零强度=源图、hard 区域=源图、cached/uncached 一致、预览/原尺寸等价）全部保持 bit-exact，未加任何容差。

### T22 ear region policy：对本合成 oracle 零影响（2026-09-20）

T22（工单 `22-ear-region-policy`）新增 `evidence.earStructure`（第 8 个字段）与耳结构带（`smoothingFine` 经 `policyTexture` `+ .95·band`、`smoothingMid`/`repairMid` `+ .90·band`、`baseLuminance` `+ .80·band`；`tone`/`whitening` 不追加）。**但本文件的合成 oracle 无需再次重录**：

- 两个 fixture 均无 ear 语义，实测 `semantic.ear nnz>0 = 0` → `earStructure nnz>0 = 0` → `earStructureBand` 恒零，`max(x, 0·c) = x` 逐位还原。
- 逐 Ticket 字段置零探针：T22 在全部 7 个 case 的贡献均为 **0px**。
- A/B 对照（`.scratch/tmp/T22-baseline-digests-{no,with}T22.txt`）逐行相同；本批实测 7 项 digest 与 T21 探针 `.scratch/tmp/t21_probe2.log` 逐位一致。
- compat / legacy 路径与 `ce17e3…bdc4c` 的关系不变。

因此 `recordedRgbBaseline` / `recordedPreviewDigest` / `recordedOriginalSizeDigest` 自 T21 重录后不再变动；T22 仅在真实图 77 链路上有耳区增量（见 `.scratch/tmp/T22-accept.log`）。

### T30 region policy gate activation 重录记录（2026-09-20）

T30（工单 `30-region-policy-gate-activation`）是一次**跨 stage 的 policy 激活**：T20/T21/T22 施加在
`repairFine`/`repairMid`/`baseLuminance`/`tone`/`whitening` 折叠快照上的分级保护此前是**惰性值**
（消费侧只读未折叠门控字段，快照仅作诊断），T30 把分级保护真正注入输出算术。

**注入机制**：`masks.buildStageProtectionMasks` 额外发布五条**纯 policy 带**
`regionBandFine`/`regionBandMid`/`regionBandBase`/`regionBandTone`/`regionBandWhitening`
（与既有折叠式解耦，缺省/零带时逐位还原 legacy），`beautifyImage` 的 `make*StageContract`
按 `gate := gate .* (1 - band)` 注入真实算术门控。

**关键分界（带外零泄漏的前提）**：band **只作用于逐像素 support/权重**，**不进入任何全局参考统计**：

- `evenSkinLuminance`：band 只乘逐像素 `supportMap`（新增 contract 字段 `regionBandGate`）；
  `referenceReliability`/`referenceWeight`/`weightedReference`/`referenceOffset`/
  `referenceCoverage`/`normalizationMask` 仍用未带 `featureGate`。若把 band 并入
  `featureGate`，带内变化会经 `imgaussfilt` 参考卷积扩散到带外（实测带外 2226px/0.94%、
  ≤2 灰度级）。
- `repairSkinBlemishes`：band 只乘逐像素 `fineWeight`/`mediumWeight`/`chromaWeight`
  （新增 contract 字段 `textureBandGate`）；`referenceReliability` → `imfilter`
  （radius = `min(20, max(3, round(.070*faceScale)))`）的邻域参考采样仍用未带
  `textureGate`。若并入会在耳带外产生 1px 的 2 灰度级泄漏。
- `noseMidGate`（只作用于逐像素 `mediumWeight`）与 `tone`/`whitening` 的 `featureGate`
  （本就无全局统计）可直接并入 band。

**合成 oracle digest 新旧对照**（fixture 与参数组合不变；仅 digest 重录）：

| fixture | smoothing | whitening | T21 旧值 | T30 新值 | 变化 |
| --- | ---: | ---: | --- | --- | --- |
| rich | 100 | 0 | `330ddc30c63bf9a9d896d1a65e6ef62421a3006230ed2fc8026e65e50ee04204` | `803ec4cb63aa9dfe630e556e3d0b9932505460f68076b8c4e6e9e3bafc2148b7` | 是 |
| rich | 0 | 100 | `58ab2f354176fb258dcef67e01ff65d5c4c2b98f0085902cfe16c604281bfe80` | `0f318ac434b6fee89b3e5f00d4394977ddf069ef00f34a5e0e7eb9970fa69d17` | 是（`regionBandWhitening` 首次进入美白算术） |
| rich | 100 | 15 | `64f0a75e37bbcc8d893376dc702e83b180823fc717051a9d3098539ba5be9782` | `155c84665ce4e200e3d2df2bdf4b78bb405bcf9ac5362715bf9a59c99e0824ac` | 是 |
| rich | 50 | 25 | `b4cfffbf09872912e27fdc8d1c3f202b1a22d5bf80bef80da8963aa414e00cd7` | `ae034c0b890adfe1c1d713e714fbcfacf8252fbd03f800f1656c09c3302ed103` | 是 |
| compact | 100 | 15 | `35279975228d5c25334e8b3a3a8fb243a532e9fb85a94a11acbff8c407a21b75` | `11f2607b5aa1ef772c244455aaa24d1d3090ed390b6411c81fb877a589f6c669` | 是 |
| 预览路径（0.5 缩放，rich） | 100 | 15 | `32ecb919c09c7899e83aa9c48bfe3bd1c212ff3c15f8cf7448fd7652f008485b` | `314d13636b0b8de926158a4642b4bd640da72accfd589208d0181b6605d3a3cc` | 是 |
| 原尺寸路径（preview→resize 重建，rich） | 100 | 15 | `6b8e96a5088f422c7ff20a9499377cce521d0bb68729ebcbf266aea1a3054176` | `1e0ddb90166b9a34661276dbf64a8dbed70d3e507cfe54bce815117626fe8059` | 是 |

上表"T30 新值"即 `tests/testMaskSystemV4CompatibilityBaseline.m` 当前生效的
`recordedRgbBaseline` / `recordedPreviewDigest` / `recordedOriginalSizeDigest`。
T30 与 T20/T21/T22 不同：两个 fixture 的 eye/lip/nostril/noseStructure 证据非零，
五条带全部非零，**全部 7 项**都进入消费侧算术，因此全部重录（含此前因未触发消费而保持原值的
rich 0/100、rich 50/25、compact 100/15 与预览路径）。

**structural 不变量复核**（T30 重录批内实测）：

- 零强度（0/0）输出 = 源图：逐位相等（rich/compact）。
- hard identity 区域 RGB = 源图：逐位相等；hard nnz rich 220、compact 269，与 T20/T21/T22
  记录一致（零膨胀、严格二值、`protection.hard` 逐位不变）。
- cached/uncached 输出：逐位相等（rich、预览/原尺寸路径）。
- 结构性断言（`testFrozenPipelineContract`、零强度=源图、hard 区域=源图、cached/uncached
  一致、预览/原尺寸等价）全部保持 bit-exact，未加任何容差。
- **compat / legacy 路径（剥离 evidence 层）**：真实图 77 链路 compat digest == 冻结 oracle
  `ce17e323dc4208d973ccae4b4a2cc122b2fed75fe7500088197c5278806bdc4c`（逐位相等，实测
  `compat bit-exact = 1`，见 `.scratch/tmp/T30-compat-check.log`）；零带（显式全零 evidence）
  下全部 13 个 protection 字段与最终输出逐位还原 legacy。
- **带外泄漏**：合成 fixture（T20 eye/lip、T21 nose、T22 ear）在五带 union == 0 处输出变化
  **0px（严格逐位，max=0.000）**；真实图 77 链路 policy-vs-legacy 带外（223324px）变化
  196px（0.088%），**max = 1.000 灰度级**（`>1` 计数 0）；逐 consumer 诊断在带外
  **全部逐位相等**（`repair.fineWeight`/`mediumWeight`/`referenceReliability`、
  `base.baseAfter`/`referenceWeight`、`tone.deltaCb`/`deltaCr`、`whitening.delta`、
  `smoothing.alphaMap` 的 outside changed 均为 0）。剩余 196px 来自邻域滤波
  （`imgaussfilt`/`imfilter`/磨皮空域核）的亚量化传播，与 T20/T21/T22 记录的同类泄漏同源。

**真实图局部验收**（私有图 77 链路，smoothing=100/whitening=15；路径与人物信息不入库，
对比图在 `.scratch/tmp/t30_{ear,nose,eyelip}_{source,legacy,policy}.png`）：

- 耳结构带（与 T22 accept 完全同 ROI：`smoothStep(earStructure,.05,.30) > .5`，nnz=2697，
  `midSigma=12.87`）Mid 尺度结构高频：source=0.11062、legacy=0.07245、policy=0.10906 →
  **policy/legacy=1.5052**（+50%，T22 记录的 +0.24% 量级已消除）、
  **policy/source=0.9859**（T22 仅 0.6566）；Fine 尺度 policy/legacy=1.5058、
  policy/source=1.1603；legacy/source=0.6550。
- 鼻结构带（`smoothStep(noseStructure,.15,.50) > .5`，nnz=229）Mid 尺度结构高频：
  source=0.04760、legacy=0.03227、policy=0.03649 → policy/legacy=1.1308。
- 眼/唇 detail 带 Mid 尺度结构高频：policy/legacy=1.0046。
- 肤色连续性：耳-颊 tone 保护差 policy=0.0664 / legacy=0.0664（逐位相同）；耳-颊
  whitening 差 0.0230/0.0231；耳-颈 tone 差 0.1458/0.1458、whitening 差 -0.0451/-0.0451
  （耳部不追加 tone/whitening 项，无耳-颊/耳-颈异色块）。
- 带内门控实测变化（真实图）：`textureBandGate` in-band 4907px maxΔ0.95 meanΔ0.404；
  `noseMidGate` 2166px maxΔ0.85 meanΔ0.202；`baseSupportGate` 5253px maxΔ0.95 meanΔ0.387；
  `toneGate` 1522px maxΔ0.697 meanΔ0.215；`whiteningGate` 2192px maxΔ0.85 meanΔ0.671；
  全部 outside nnz=0 / maxΔ=0。
- 带内输出变化：Fine 2979px、Mid 981px、Base 3124px、Tone 153px、Whitening 761px。

**测试同步**（T30 激活后旧期望不再成立，按真实契约改写，未放宽任何容差）：

- 四处「美白-only 输出必须与 legacy 逐位一致」改为「带外（`regionBandWhitening == 0`）逐位
  相等 + 带内可观测变化 + 单字段归因（置零 `regionBandWhitening` 的证据来源后逐位回到
  legacy；置零其他带来源则输出不变、仍不等于 legacy）」：
  `testNoseSmoothing`、`testBeautyArtifactRegressions`（T21/T20 用例）、
  `testPortraitBeautyHelpers`。`testBeautyArtifactRegressions` 的 T22 用例（policy vs 无 T22
  基线）因 `regionBandWhitening` 不含耳部项仍保持 bit-exact。
- `testBeautyArtifactRegressions` 的 T21 鼻孔-鼻内低频对比度按真实符号约定改为**幅值**比较
  （`valleyContrast = mean(谷底) - mean(鼻内)` 为负，"对比度更强"对应"更负/幅值更大"；
  policy=-0.024465 vs legacy=-0.023011，算法未改动）。
- `testBeautyArtifactRegressions` T20 用例的带外定义由 T20 时代的核心 footprint
  （`detailBand > .5 | transitionBand > .5`）改为真实的 band support
  （`detailBand > 0 | transitionBand > 0`），保持**零容差**逐位断言；实测
  `outside bandUnion>0` 变化 0px。
- `stageNames` 精确 `fieldnames` 断言（`testBeautyV3`、`testBeautyContextV3`）同步加入
  五条 `regionBand*` 字段。
- 目标测试合计 118 项全部通过（`testEarProtectionPolicy`、`testNoseSmoothing`、
  `testBeautyArtifactRegressions`、`testPortraitBeautyHelpers`、`testBaseLuminanceEqualization`、
  `testBeautyV3`、`testBeautyContextV3`、`testMaskSystemV4CompatibilityBaseline`；
  见 `.scratch/tmp/T30-target-tests5.log`）。

### T31 Smoothing + Repair 执行契约重录记录（2026-09-20）

T31（工单 `31-a-smoothing-repair-execution-contract`）是**纯架构重构**：把 Smoothing 与
Repair 两个 stage 从"执行层自行读取 legacy general mask"改为"执行层只消费 policy 层发布的
规范双门控"（上位契约第 1 节 Single Protection Authority）。算法数值路径无任何改动。

**规范门结构发布**（`masks.buildStageProtectionMasks` 输出 `protection`）：

| 字段 | 语义 |
| --- | --- |
| `hard` | 严格二值身份保护；独立字段，**不**参与 target/support 的 max 折叠 |
| `target.smoothingFine` / `.smoothingMid` | 逐像素修改门（该像素能不能被改） |
| `target.repairFine` / `.repairMid` | 同上（Repair stage） |
| `support.smoothingFine` / `.smoothingMid` | 邻域参考样本池门（能不能当参考样本） |
| `support.repairFine` / `.repairMid` | 同上（Repair stage） |
| `noseMidProtection` / `baseLuminance` / `tone` / `whitening` | 过渡扁平字段（T32/T33 前由各 stage contract 组装点消费） |
| `regionBandFine/Mid/Base/Tone/Whitening` | T30 纯 policy 带 |

- **旧扁平折叠名已删除**：`smoothingFine` / `smoothingMid` / `repairFine` / `repairMid`
  不再出现在 `protection` 顶层（同一语义只保留 `target.*` 一个规范字段）；`target`/`support`
  各恰好 4 个字段。`fieldnames(protection)` 精确断言见 `testBeautyV3` / `testBeautyContextV3`。
- `target.*` 零带值与 T07 折叠快照逐位相等；`support.*` 零带值与 **T30 之前 consumer 侧同名
  基准门**逐位相等：`smoothingFine = max(max(texture,structure),hard)`、
  `smoothingMid = min(4·structure,1)`、`repairFine = texture`、`repairMid = structure`。
- 组装层只转发：`beautifyImage` 的 `makeRepairStageContract` 已删除，Repair contract 由唯一
  组装点 `+beauty/repairStageContract.m` 生成（生产组装层与 `repairSkinBlemishes` 兼容入口共用），
  只从 `stageProtection` + runtime `blemishMap` 组装，不再读 legacy mask。
- `repairStageContract` 新增 `midBandGate`（= `1 - regionBandMid`）：Mid 逐像素门按生产原式
  结合序重建为 `(1 - target.repairMid) .* midBandGate`（= legacy `noseMidGate`），
  **逐位**还原 T30 的 `mediumWeight`。`textureBandGate` 语义不变（只乘逐像素权重，不进参考池）。
- **Blemish ≠ Should Repair**（上位契约第 3.2 节）：`repairTargetWeight = blemishEvidence ×
  processability × strength × (1 - target.repairFine/Mid)`；`repairSupportWeight =
  validSkinReference × (1 - support.repairFine/Mid)`。blemish 证据只回答"像不像瑕疵"，
  不单独决定修复强度；结构保护也不反向塞进 blemish 检测。双因子解耦单测
  `testBeautyArtifactRegressions/testRepairTargetGateAndBlemishEvidenceAreIndependentFactors`
  实测：仅扰动 `target.repairFine` → fine/medium 各 ×.60；仅扰动 `target.repairMid` → 只 medium
  ×.60；仅扰动 blemish 证据 → 证据与强度变化而 target 门逐位不变。
- **T30 之前 consumer 侧 `structureGate` 合并**：生产链里同一个
  `structureGate = min(1 - structure·(1-.90·blemish), 1 - .65·strongStructure)` 既乘逐像素权重
  （截断之前）又乘邻域参考池门；它依赖 runtime blemish 与 hard 特征带，无法在 policy 层预算，
  故由组装层重建并按"同一语义一个规范字段"发布为 `support.repairMid`。发布取 `max(a,b)` 而非
  `1 - structureGate`，利用舍入单调性 `min(1-a,1-b) === 1-max(a,b)` 保证消费侧
  `1 - support.repairMid` 逐位还原生产 `structureGate`（`1-(1-x)` 补码往返不保证逐位）。

**合成 oracle digest：全部 7 项保持 T30 值，无需重录**（`testFinalRgbMatchesRecordedBaselineDigests`
与 `testPreviewAndOriginalSizePathsMatchRecordedBaselineDigests` 均按 T30 重录基线通过）。

**真实图 77 链路验收实测**（`.scratch/tmp/T31-accept.log`，T30 源码同夹具对照
`.scratch/tmp/T31_t30_real.mat`）：

- compat / legacy 路径 digest == 冻结 oracle `ce17e323dc4208d973ccae4b4a2cc122b2fed75fe7500088197c5278806bdc4c`（逐位相等）。
- 零带（显式全零 evidence）下 `protection` 全部字段（含嵌套 `target`/`support`）与最终输出
  逐位还原 legacy；`support.*` 逐位等于上述 pre-T30 基准门；`bridge`（`buildStageProtectionMasks`
  vs `Context.protection`）逐位一致。
- hard identity：nnz policy=82266 legacy=82266（**不增**）、严格二值、hard 区 RGB 逐位回源、
  `protection.hard` 逐位不变。
- 全局参考统计逐位不变：`base.referenceWeight`/`referenceReliability`、
  `repair.referenceReliability`/`referenceWeight`、smoothing `fineEnergy`/`blemishMean`/
  `ordinarySkinMask` 全部相等（`target` 门不扰动参考统计）。
- 带外泄漏：policy-vs-legacy 带外（223324px）变化 196px（0.088%），**max = 1.000 灰度级**
  （`>1` 计数 0）；逐 consumer 诊断（`repair.fineWeight`/`mediumWeight`/`referenceReliability`、
  `base.baseAfter`/`referenceWeight`、`tone.deltaCb`/`deltaCr`、`whitening.delta`、
  `smoothing.alphaMap`）在带外**全部逐位相等**（outside changed = 0）。
- 结构断言：零强度（0/0）= 源图逐位；cached/uncached 逐位；预览路径 / 原尺寸路径输出与 T30
  **逐位相等**（`preview vs T30 bit-exact=1`、`original-size vs T30 bit-exact=1`），未加任何容差。
- ROI 细节保留 vs T30：smoothing ROI（鼻结构带 ∪ 耳结构带，nnz=2719）Mid 尺度 `|hp|`
  T31/T30 = **1.0000**、Fine 尺度 = **1.0000**；repair ROI（`blemishMap > .30`，nnz=19396）
  Mid/Fine 尺度 T31/T30 均 = **1.0000**（输出逐位相等 ⇒ 比值恒为 1）。
  对照 legacy（未带）：smoothing ROI T31/legacy = 1.5059、repair ROI T31/legacy = 1.0795。
  ROI 裁剪图：`.scratch/tmp/t31_{ear,nose,eyelip}_{source,legacy,policy}.png`。

**测试同步**（未放宽任何容差）：目标测试 111 项全部通过
（`testBeautyArtifactRegressions`、`testNoseSmoothing`、`testPortraitBeautyHelpers`、
`testBaseLuminanceEqualization`、`testBeautyV3`、`testBeautyContextV3`；
见 `.scratch/tmp/T31-target-tests.log`）；兼容基线 7 项全部通过
（见 `.scratch/tmp/T31-compat-baseline.log`）。`testEarProtectionPolicy` 的
`flattenProtection` 适配与字段名重命名属同步改动（3 项全部通过）。
执行层净化证据见 `.scratch/tmp/T31-grep-proof.txt`：`smoothSkinTexture.m` /
`repairSkinBlemishes.m` 的**代码行**中 `ProtectionMask`（仅剩
`masks.buildStageProtectionMasks` 兼容入口调用与 `fineProtectionMask` 诊断字段名）、
`noseMask`、`semantic`、`evidence`、`textureProtection`、`structureProtection`、
`chromaProtection`、`whiteningProtection`、`toneProtection`、`nose` **全部无匹配**。
