# 02：脸缘覆盖缺口诊断记录

记录日期：2026-09-17。

## 范围判定

用户请求是实现 `.scratch/beauty-protection-convergence/issues/02-diagnose-face-boundary-coverage.md`。该任务票中的“只诊断、不修改生产算法”、固定单图与选区、单因素消融、临时产物和交接要求属于本次实现约束；其中关于未来如何扩张皮肤、放松结构或调整阈值的内容不是本票的预设实现方案。

本票只新增可复现诊断入口和中文记录，没有修改 `src/` 生产算法、公共 Context、验收阈值或缓存契约。

## 输入对应关系

- Web 对话附件 `f2dbb140-5af9-4400-b9a3-8ecbace21c89.jpg` 与仓库 `人脸\人脸\80r.jpg` 文件哈希一致。
- Web 对话附件 `db0a1815-0c6d-42eb-b7e1-1192d85530d0.png` 与仓库 `人脸\人脸\80.jpg` 为同一张雀斑人像的裁剪/重采样版本；尺寸不同，因此不宣称字节一致。
- Web 对话黄色背景截图的原图内容可与仓库 `人脸\人脸\77.png` 对应。初次探针中的框落在眼鼻邻域，未将该探针结果作为脸缘结论。
- Web 对话另外两张近景附件没有在仓库中找到可核对的原图、输出配对和参数；本记录不宣称已定位它们的根因。

主诊断采用 `80.jpg`，因为它同时具备可核对的仓库原图、Web 参考图和 `01` 已验证的 v3.2 基线。

## 固定复现条件

- 输入：`人脸\人脸\80.jpg`，原尺寸 `565×850×3`，输入与输出均为 `uint8 RGB`。
- 基线：`schemaVersion=3.1`、`algorithmVersion=v3.2`、`artifactVersion=v3.1`。
- 参数：磨皮 `100`，美白 `15`。
- 人脸框：原尺寸 `[23 1 543 636]`。
- 预览：缩放因子 `0.7529411765`，尺寸 `426×640×3`，预览人脸框由同一检测流程得到。
- 原尺寸脸缘观察框：`[125 300 55 110]`；该框依据原图可见外侧脸颊人工确定，不由任何待验证 Mask 生成。
- 原尺寸内侧对照框：`[180 300 55 110]`。预览对应观察框为 `[94 226 41 83]`，对照框为 `[136 226 41 83]`。

## 基线区域证据

以下作用量在 `faceSkinMask >= 0.35` 的区域像素上统计；`skinSupportFraction` 与 `faceSkinFraction` 仍以完整人工框为分母，因此能够看出框内有多少像素没有进入候选，而不是只报告 Mask 自身覆盖的像素。

| 尺寸/区域 | skinSupportFraction | faceSkinFraction | strength 均值 | structureProtection 均值 | Fine 结构门控均值 | Fine 门控为零比例 | smoothing Alpha 均值 | smoothing Fine 作用量 | 最终 RGB 变化均值 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 预览/脸缘 | 0.9536 | 0.9427 | 0.9716 | 0.1857 | 0.6415 | 0.2893 | 0.6201 | 0.002222 | 5.9521 |
| 预览/内侧对照 | 1.0000 | 1.0000 | 0.9967 | 0.0007 | 0.9973 | 0 | 0.9940 | 0.003607 | 3.5475 |
| 原尺寸/脸缘 | 0.9593 | 0.9484 | 0.9722 | 0.1644 | 0.6633 | 0.2569 | 0.6419 | 0.003279 | 6.2147 |
| 原尺寸/内侧对照 | 1.0000 | 1.0000 | 0.9967 | 0.0008 | 0.9966 | 0 | 0.9933 | 0.005581 | 4.2183 |

脸缘框内约 `94.8%` 的原尺寸像素通过脸部皮肤支持，强度均值约 `0.972`，不是整块没有处理资格。与此同时，脸缘的结构保护均值约为内侧对照的两百倍，Fine 结构门控约四分之一像素直接为零，剩余大部分处于 `0` 和 `1` 之间；这与脸缘比内侧对照的平滑作用量明显偏低相符。

Repair 侧的原尺寸证据为：脸缘 `allowed=0.9722`、Repair 结构门控均值 `0.8599`、Repair 纹理门控均值 `1`；内侧对照分别为 `0.9967`、`0.9992`、`1`。脸缘 Repair Fine/Mid 作用量为 `0.001913/0.000166`，内侧对照为 `0.001973/0.000004`。因此 Repair 没有被零门控关闭，且本例的 `textureProtectionMask` 在观察框中没有产生额外抑制。

## 单因素消融

消融固定原图、人脸框、强度、瑕疵图和其他处理结果，只在诊断入口复制 Mask 或 Mid 结果，不接入生产算法。

| 原尺寸脸缘消融 | 相对基线最终 RGB 均值 | Fine 阶段差异 | Mid 阶段差异 | Repair Fine 差异 | Repair Mid 差异 | 头发最大变化 | 眼睛最大变化 | 鼻部最大变化 | 背景最大变化 | 硬保护最大变化 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 移除平滑结构门控 | 1.5352 | 0.001107 | 0.004785 | 0.000882 | 0.004695 | 1 | 2 | 26 | 0 | 0 |
| 移除 Repair 结构门控 | 0.1087 | 0 | 0 | 0.000166 | 0.000046 | 1 | 1 | 4 | 0 | 0 |
| 移除 Repair 纹理门控 | 0 | 0 | 0 | 0 | 0 | 1 | 3 | 22 | 0 | 0 |
| 移除 Mid 第二次门控 | 0.2095 | 0 | 0.000711 | 0 | 0.000537 | 1 | 1 | 6 | 0 | 0 |

内侧对照的对应最终 RGB 差异分别为 `0.0321`、`0.0013`、`0` 和 `0.0124`。移除平滑结构门控只在脸缘观察框产生明显变化，但同时使鼻部最大 RGB 变化达到 `26`；因此不能把全局删除结构门控当作修复方案。移除 Repair 结构门控影响小得多，移除 Repair 纹理门控在目标框内没有变化，排除了 `01` 纹理软保护为本例主要根因。

脸缘的 Mid 结构门控均值为 `0.6633`，其中 `0.7431` 的分析像素处于非零且小于 `1` 的范围；移除 Mid 第二次门控的 Mid 阶段差异为 `0.000711`，明显高于对照的 `0.000015`。这证明重复门控在本例脸缘确实有作用，但该消融仍使鼻部最大 RGB 变化达到 `6`，所以只能作为后续独立验证候选，不能在本票直接取消。

## 结论

### 已确认事实

1. `80.jpg` 在 v3.2、预览和原尺寸两种路径下都能复现脸缘观察框的相对低作用量；不是缓存路径或尺寸恢复差异。
2. 观察框大部分像素已有脸部皮肤支持和较高强度，当前证据不支持“整个缺口都由皮肤召回为零造成”。框内仍有约 `5%` 像素未通过脸部皮肤支持，是否属于真实脸部而非边界外背景，单凭现有语义 Mask 不能继续判定。
3. 已支持区域的主要抑制来自 `buildStructureProtectionMask` 产生的结构保护，以及 `smoothSkinTexture` 中 `fineStructureGate = max(0, 1 - 4 * structureProtection)`；零门控和非零连续门控两种情况均存在。
4. Mid 第二次结构门控在脸缘不是数学上的无效操作：门控有大量 `0 < gate < 1` 像素，且定向消融会改变 Mid 结果。但它不是当前唯一或最大作用来源。
5. `repairSkinBlemishes` 的 `allowed`、Repair 结构门控和纹理门控均非零；本观察框内移除 Repair 纹理门控没有变化。因此 `01` 修复的纹理软保护绕过不是这例脸缘漏磨的根因。
6. 后续亮度和色度处理仍贡献最终图像变化。原尺寸脸缘的平滑亮度作用量、Base 亮度作用量、美白亮度作用量和色度作用量均有记录，不能只用最终 RGB 变化反推某一个阶段。

### 尚未定位项

- 尚不能证明 `structureProtectionMask` 在所有脸缘都错误；本例只确认它在人工脸缘观察框中造成了可观的处理抑制。
- 尚不能仅凭 `80r.jpg` 参考图把目标观感当作像素级真值；参考图只用于视觉前后对照，不参与 Mask 定义、阈值或通过条件。
- Web 对话附件中的其他近景样本缺少可核对的原图和参数，不能把本例结论外推到它们。

### 04 口径修正

04 在同一输入上补充了四来源分解和冻结基线的单项来源消融，以下修正不删除或改写本节旧实验数据：

- `smoothingWithoutStructure` 和 `smoothingWithoutRepeatedMid` 是整体输入/传播对照。它们重新计算了磨皮阶段，后续 Repair 也随之重新计算，因此最终 RGB 差异不能作为纯门控因果量；旧数值仍保留为“整体消融改变了输出”的事实。
- 跨区域的绝对作用量只能说明输出变化规模，不能直接排序保护强弱。来源主导应使用同一固定选区、同一分析像素分母和四来源最终值的主导比例。
- 鼻部消融的 RGB 差异只标记输出副作用，不等同于结构损伤。结构判断还要结合原图叠加、低频梯度、方向连续性和鼻梁/鼻翼/五官固定测量。

04 的单项来源消融冻结基线自适应统计与 Fine/Mid 保留率，仅替换一个结构来源；Repair 的重新计算单独标记为下游传播后果。后续修复分析应以 04 的 `faceBoundarySourceMetrics.csv`、`faceBoundarySourceAblationMetrics.csv` 和 `faceBoundaryFeatureMetrics.csv` 为准。

### 后续交接建议

如需拆下一张实现票，应只围绕已证实的“脸缘结构保护/重复 Mid 门控抑制”建立独立修复和轮廓安全回归；同时保留鼻部、眼睛、头发、背景和硬保护检查。不要在没有新证据前同时扩张皮肤、删除结构门控和提高磨皮强度，也不在本票预设新的阈值或公式。

本票完成的是诊断和证据交接，不代表生产算法已经修复。

## 可复现入口与产物

入口文件：[diagnoseFaceBoundaryCoverage.m](/E:/image_beauty/tests/diagnoseFaceBoundaryCoverage.m)

```matlab
addpath('E:\image_beauty\src');
addpath('E:\image_beauty\tests');
files = dir('**/80.jpg');
options = struct('faceBoundaryRoi', [125 300 55 110], ...
    'controlRoi', [180 300 55 110], ...
    'smoothingStrength', 100, 'whiteningStrength', 15);
[summary, diagnostics] = diagnoseFaceBoundaryCoverage( ...
    fullfile(files(1).folder, files(1).name), ...
    fullfile(tempdir, 'image_beauty_issue02_v32_80_final'), options);
disp(summary.regionMetrics);
disp(summary.ablationMetrics);
```

本次产物位于临时目录 `C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue02_v32_80_final`：

- 对比图：`original-faceBoundaryCompare.png`；
- 门控与作用量图：`original-faceBoundaryMaps.png`；
- 单因素消融对比：`original-faceBoundaryAblation.png`；
- 区域量化：`faceBoundaryRegionMetrics.csv`；
- 消融量化：`faceBoundaryAblationMetrics.csv`；
- 紧凑诊断数据：`faceBoundaryDiagnosticData.mat`。

未执行 Git 提交或推送。

## 验证

- `checkcode('tests/diagnoseFaceBoundaryCoverage.m', '-id')`：无诊断项。
- 受影响目标测试 `testNoseSmoothing`、`testBeautyContextV3`、`testBeautyArtifactRegressions`：`24 Passed, 0 Failed, 0 Incomplete`。
- `runtests('tests')` 已在单个 MATLAB 批处理进程中执行；10 个测试套件均输出完成，未见失败输出，命令中的失败断言未触发。终端没有回传最后的汇总计数，因此本记录不虚报全量精确数量。
- `diagnoseFaceBoundaryCoverage` 已对固定 `80.jpg` 完成预览/原尺寸、基线和四组单因素消融；CSV、PNG 和紧凑 MAT 产物均已生成。
