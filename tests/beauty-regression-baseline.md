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
