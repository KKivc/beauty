# 03：修复后残留耳部、鼻孔及眉眼失真诊断记录

记录日期：2026-09-18。

## 范围判定

本次用户请求是实现 03 诊断票，不是直接修复残留失真。03 票中的“只定位、不修改生产算法”、人工选区、单图消融、临时产物和中文证据记录属于本次实现约束；其中未来可能的耳部规则、鼻孔检测改写、标签契约变化或强度调整不是本票的实现方案。

04 已在另一个会话执行。本次没有读取、修改或纳入 04 的实现结论；当前工作区中由其他会话新增的 handoff/2026-09-17-beauty-protection-04.md 不属于本票。

本票只新增可复现诊断入口、入口参数测试和本记录，没有修改 src/ 生产算法、公共 Context、缓存契约、检测阈值或强度曲线。

## 输入对应关系

- Web 对话《美颜算法修复方案》的 db0a1815-0c6d-42eb-b7e1-1192d85530d0.png 与仓库 人脸\人脸\80.jpg 是同一张雀斑人像的裁剪/重采样版本；f2dbb140-5af9-4400-b9a3-8ecbace21c89.jpg 与 人脸\人脸\80r.jpg 对应。沿用 02 记录的对应关系，不宣称字节一致。
- Web 对话的 9df0aad2-8218-40e8-b31a-396404e422cf.png 是带 GUI 原图/结果面板的黄背景截图。截图原图内容与仓库 人脸\人脸\77.png 对应；这是内容核对，不宣称截图文件与仓库文件字节一致。
- 77 截图上的 GUI 参数明确显示磨皮 100、美白 15，因此 77 用该参数复现。
- Web 对话的 b14067a6-266e-4f4c-81c4-6148565857fe.png 和 559204bb-8f2e-43a3-ac57-4d43fd8aa39a.png 只有近景附件，当前仓库没有可核对的原图、输出配对和参数。本票不把它们标为已复现，也不把替代样本结论外推到这两张近景。

## 固定输入、基线和选区

矩形统一使用 [x y width height]，选区依据原图或截图人工确定，不由待验证的皮肤或保护 Mask 生成。

| 样本 | 尺寸 | 实际人脸框 | 参数 | 运行模式 |
| --- | --- | --- | --- | --- |
| 77.png | 450×512×3 | [95 79 286 372] | smoothing=100，whitening=15 | 原尺寸；previewScale=1，未重复运行相同模式 |
| 80.jpg | 850×565×3 | [39 1 527 638] | smoothing=100，whitening=15 | 预览和原尺寸；previewScale=0.7529411765 |

77 的人工选区：

| 选区 | 矩形 |
| --- | --- |
| ear | [345 110 75 120] |
| nostril | [185 335 50 35] |
| browEye | [165 205 150 100] |
| noseBridge | [160 295 90 50] |
| noseWing | [155 325 80 45] |
| hair | [80 90 90 70] |
| background | [465 20 40 140] |

80 的验证选区：

| 选区 | 矩形 |
| --- | --- |
| nostril | [300 330 125 80] |
| noseBridge | [320 245 80 90] |
| noseWing | [295 320 140 90] |
| normalSkin | [200 330 100 100] |
| freckle | [200 180 100 100] |
| hair | [60 60 40 50] |
| background | [1 100 50 200] |

## 测量口径

- skinSupportFraction 的分母是完整人工 ROI，分子是 skinMask > 0.05；faceSkinFraction 的分子是 faceSkinMask > 0.35。阶段作用量不因皮肤 Mask 为空而偷偷改用另一个选区。
- smoothing Fine/Mid 作用量分别是平滑前后频率分量绝对差；Repair Fine/Mid 作用量分别是 repair 诊断中的 fineCorrection 和 mediumCorrection 绝对值；Base、美白和色度分别取合成阶段的 baseDelta、whiteningDelta 及 Cb/Cr 最大绝对差。
- firstActiveStage 表示该 ROI 内第一个出现大于 1e-6 数值作用量的阶段，只表示先后顺序，不把非零作用量自动称为失真。
- 消融表中的 finalRgbDifference 是消融输出相对 v3.2 基线输出的 RGB 最大通道差，不是质量提升分数。forceTexture 和 forceHard 是诊断入口向固定 ROI 注入保护后的对照；scopeOutputRgbChange 是该对照输出相对输入图像的变化。
- 结构来源在诊断入口按当前生产公式重建为 noseStructure、outsideStructure、faceStructure、faceBoundary，重建图与基线 structureProtectionMask 的最大误差为 0。
- 低频结构梯度使用 base+mid 与 base+Repair 后的 mid 比较，只作证据，不设置新的通过阈值。零能量时保留为 NaN，不用分母常数制造比值。

## 77.png 残留症状证据

### 耳部

当前 v3.2 基线在 ear ROI 中仍可看到截图相同的耳廓块状失真，原图/基线/局部图位于 original-residualFeatureCompare.png 和 original-residualFeatureAblation.png。

耳部 ROI 的主要量化结果：

- skinSupportFraction=0.5403，faceSkinFraction=0.4854，语义证据最大值=0.8837；
- textureProtectionMean=0.3830，structureProtectionMean=0.1238，hardProtectionFraction=0.2847；
- 结构来源主导比例为 faceStructure=0.5580、faceBoundary=0.2393、noseStructure=0.1995、outsideStructure=0.0033。现有结构诊断没有独立 earStructure 来源；
- smoothing Fine/Mid 作用量为 0.001131/0.005607，Repair Fine/Mid 作用量为 0.004920/0.011278；Base、美白和色度作用量分别为 0.000465、0.002379 和 0.003349；
- 首个数值作用阶段为 smoothing；低频结构梯度保留比为 0.8824；
- final RGB 变化均值/最大值为 7.656/92。

单因素对照中，禁用 Repair 后相对基线的 ROI RGB 差为 4.824、最大 83；同时禁用 smoothing 和 Repair 为 6.692、最大 86；禁用 skinTone 为 1.550、最大 16；禁用 whitening 为 0.893、最大 2。向 ear ROI 注入 texture protection 后，注入区域相对输入仍有 1.764 的均值和 14 的最大变化；注入 hard protection 后注入区域相对输入为 0/0。

结论：已确认耳部 ROI 首先经过 smoothing，Repair 也产生较大的后续作用，whitening 不是主要来源；现有证据还不足以把问题唯一归类为“通用结构保护不足”或“Repair 越界”。结构来源是通用 faceStructure/faceBoundary，而不是耳部专用来源，但这只能说明当前链路如何作用，不能单凭来源名称证明保护错误。forceHard 的 0/0 只证明下游硬保护消费有效，不证明视觉质量已经改善。

### 鼻孔

77 的 nostril ROI 中，texture.nostrilCore 和 texture.nostrilBoundary 均为空，chroma.nostrilCandidate 覆盖比例为 0.0217，whitening.nostrilCore 为空，hardProtectionFraction=0；nostril detector disagreement=0.0217，noseSemanticExcluded=true。

同一 ROI 的 smoothing Fine/Mid 作用量为 0.000865/0.004799，Repair Fine/Mid 为 0.005387/0.018065，Repair 纹理门控均值为 0.9403，Repair 结构门控均值为 0.7690，最终 RGB 变化均值/最大值为 10.013/93。禁用 Repair 的相对基线差为 6.465、最大 79；同时禁用 smoothing 和 Repair 为 8.013、最大 85；禁用 skinTone 为 1.965、最大 10；禁用 whitening 为 1.593、最大 2。forceTexture 的注入区域相对输入为 2.722/11，forceHard 为 0/0。

结论：77 已确认两个现有鼻孔检测输出不一致：色度模块找到少量候选，但纹理模块没有生成 nostrilCore，因此没有形成鼻孔硬保护；这比“只看到有两个检测函数”更直接地证明了当前样本的检测链路差异。首个数值作用阶段仍是 smoothing，Repair 尤其是 Mid 也继续作用。forceHard 后 ROI 严格不变，说明硬保护消费链路可工作；不能据此把色度候选本身称为错误，也不能在本票合并检测器。

80 的鼻部验证进一步显示：nostril、noseBridge、noseWing 三个固定 ROI 的 hardProtectionFraction 均为 0，nostril 的 texture.nostrilCore、texture.nostrilBoundary、chroma.nostrilCandidate 和 whitening.nostrilCore 均为空。80 不是 77 截图的原图，只作为另一张真实鼻部的链路验证。

### 眉眼

77 的 browEye ROI 中，四类语义证据最大值分别为 leftEye=0.2954、rightEye=0.0105、leftBrow=0.7964、rightBrow=0.3680。该 ROI 的 textureProtectionMean=0.0378，browProtectionMean=0.0301，eyeDetailProtectionMean、periocularProtectionMean、doubleEyelidProtectionMean 和 lashProtectionMean 均为 0，hardProtectionFraction=0.0115。

smoothing Fine/Mid 作用量为 0.001729/0.006297，Repair Fine/Mid 为 0.005912/0.012712，Repair 纹理门控均值为 0.9622；Repair 加权瑕疵能量下降比例为 0.6681，低频结构梯度保留比为 0.9465，最终 RGB 变化均值/最大值为 7.766/126。禁用 Repair 的相对基线差为 4.810、最大 121；同时禁用 smoothing 和 Repair 为 6.926、最大 121；禁用 skinTone 为 1.343、最大 13；禁用 whitening 为 1.671、最大 2。forceTexture 的注入区域相对输入为 2.279/12，forceHard 为 0/0。

结论：当前 77 样本确认眼部语义和 eye-detail 检测置信度不足，只有一侧眉部达到较高证据，眼部局部保护没有生成；同时 Repair 仍对该 ROI 产生明显作用。首个数值作用阶段是 smoothing，Repair 是明显后续作用来源。由于没有逐像素目标标注，不能进一步证明是保护不足、Repair 越界还是两者叠加导致截图灰块；下一轮应继续冻结输入和 ROI，分别验证 eye-detail 检测与 Repair 消费链路，不在本票直接加入 hardLabels 或新的阈值。

## 正常皮肤、雀斑和鼻部结构对照

80.jpg 只用于验证现有链路没有被残留症状诊断假设替代，不用于宣称 77 截图已经修复。

- normalSkin ROI 的 skinSupportFraction=0.9989，faceSkinFraction=0.9979，Repair Fine/Mid 作用量为 0.002267/0.000201，Repair 加权瑕疵能量下降比例为 0.1207，fineRepairRetentionRatio=0.8043，midRepairRetentionRatio=0.9921。
- freckle ROI 的 skinSupportFraction=0.7434，faceSkinFraction=0.7167，Repair Fine/Mid 作用量为 0.003016/0.000366，Repair 加权瑕疵能量下降比例为 0.0526，fineRepairRetentionRatio=0.9242，midRepairRetentionRatio=0.9958。该 ROI 仍有实际修复作用，没有因诊断用保护对照而被清零。
- noseBridge ROI 的低频结构梯度保留比为 0.9544，noseWing ROI 为 0.9247；这两个比值仅说明本次样本的前后测量结果，不是新增质量阈值。
- 80 原尺寸 nostril、noseBridge、noseWing 的最终 RGB 变化均值分别为 4.754、4.741、4.733；对应最大值为 50、31、50。RGB 变化不是结构损伤结论。
- 77 和 80 的所有记录 ROI 中，hardProtectionMaxRgbChange 均为 0；手工选定的纯头发 ROI 与背景 ROI 在基线及本次消融表中的最大变化均为 0。该结果只覆盖这些明确选区，不外推整张图所有头发和背景。

## 结论与后续边界

本票已确认：

1. 77.png 在当前 v3.2、磨皮 100、美白 15 下仍复现耳部、鼻孔和眉眼局部残留失真。
2. 三类症状的首个数值作用阶段均为 smoothing，但 Repair 对耳部、鼻孔和眉眼仍有显著后续作用；不能只看最终观感或单个 Mask 名称归因。
3. 77 鼻孔存在实测的纹理检测漏检/两检测输出不一致；强制 hard protection 后 ROI 严格保持输入，说明下游硬保护路径可消费。
4. 77 眉眼存在当前样本的低眼部语义证据和空 eye-detail 保护；Repair 仍有作用，但尚未证明单独由 Repair 越界造成。
5. 80 的正常皮肤和真实雀斑仍可产生非零 Repair 作用；鼻梁/鼻翼低频结构测量已记录，未将 RGB 差包装为质量提升。
6. 结构来源重建误差为 0，硬保护、纯头发和纯背景固定选区未出现 RGB 变化。

本票未确认：

- 耳部通用结构保护是否错误，以及是否需要耳部专用保护；
- 鼻孔检测候选应由哪个模块拥有，或两套检测是否应合并；
- 眉眼残留中检测置信度不足与 Repair 后续作用的独立因果贡献；
- Web 近景 b14067a6-266e-4f4c-81c4-6148565857fe.png、559204bb-8f2e-43a3-ac57-4d43fd8aa39a.png 的原截图根因。

因此本票不提出专用耳部系数、鼻孔新规则、检测器合并、标签契约变化或强度曲线调整。若拆下一票，应继续使用 77 的相同输入、参数和人工 ROI，针对已经确认的检测输出差异与 Repair 作用分别做小范围因果验证；证据不足时停止在诊断，不把 forceHard 的输出变化称为修复成功。

## 可复现入口

入口文件：[diagnoseResidualFeatureArtifacts.m](/E:/image_beauty/tests/diagnoseResidualFeatureArtifacts.m)。

在 MATLAB 中从项目根目录执行以下单批处理调用，可重新生成本记录使用的两组临时产物：

    addpath('E:\image_beauty\src');
    addpath('E:\image_beauty\tests');

    options77 = struct('earRoi', [345 110 75 120], ...
        'nostrilRoi', [185 335 50 35], ...
        'browEyeRoi', [165 205 150 100], ...
        'noseBridgeRoi', [160 295 90 50], ...
        'noseWingRoi', [155 325 80 45], ...
        'hairRoi', [80 90 90 70], ...
        'backgroundRoi', [465 20 40 140], ...
        'smoothingStrength', 100, 'whiteningStrength', 15);
    [summary77, diagnostics77] = diagnoseResidualFeatureArtifacts( ...
        'E:\image_beauty\人脸\人脸\77.png', ...
        fullfile(tempdir, 'image_beauty_issue03_77_final'), options77);

    options80 = struct('nostrilRoi', [300 330 125 80], ...
        'noseBridgeRoi', [320 245 80 90], ...
        'noseWingRoi', [295 320 140 90], ...
        'normalSkinRoi', [200 330 100 100], ...
        'freckleRoi', [200 180 100 100], ...
        'hairRoi', [60 60 40 50], ...
        'backgroundRoi', [1 100 50 200], ...
        'smoothingStrength', 100, 'whiteningStrength', 15);
    [summary80, diagnostics80] = diagnoseResidualFeatureArtifacts( ...
        'E:\image_beauty\人脸\人脸\80.jpg', ...
        fullfile(tempdir, 'image_beauty_issue03_80_final'), options80);

运行入口测试：

    results = runtests('tests/testResidualFeatureDiagnostics.m');

## 临时对比产物

77 产物目录：C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_77_final

- original-residualFeatureCompare.png：输入、v3.2 基线、最终 RGB 变化和耳/鼻孔/眉眼局部对比；
- original-residualFeatureMaps.png：语义、保护、各阶段作用量和最终变化图；
- original-residualFeatureAblation.png：禁用 Repair、纹理保护注入和硬保护注入的局部对比；
- residualFeatureRegionMetrics.csv：区域语义、保护、阶段作用量、保留率和结构来源统计；
- residualFeatureAblationMetrics.csv：单因素消融相对基线的差异和安全选区检查；
- residualFeatureImageMetrics.csv：信息熵、标准差、平均梯度和基线耗时；
- residualFeatureDiagnosticData.mat：紧凑诊断数据。

80 产物目录：C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_80_final，包含 preview 和 original 两套 PNG，以及同名的三张 CSV/MAT 汇总文件。

两张样本本批次汇总：C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue03_batch_summary.mat。

## 验证

- checkcode('tests/diagnoseResidualFeatureArtifacts.m', '-id')：0 条。
- tests/testResidualFeatureDiagnostics.m：3 Passed, 0 Failed, 0 Incomplete。
- 77.png 和 80.jpg 的诊断在同一 MATLAB 批处理进程完成；77 输出指标为熵 7.19399、标准差 0.217182、平均梯度 0.0293901、基线耗时 0.74049 秒；80 预览为熵 7.35078、标准差 0.197816、平均梯度 0.0148316、耗时 0.49845 秒，原尺寸为熵 7.35569、标准差 0.197938、平均梯度 0.0152133、耗时 0.55360 秒。
- 全量 runtests('tests')：123 Passed, 0 Failed, 0 Incomplete。
- 未执行 Git 提交或推送。

