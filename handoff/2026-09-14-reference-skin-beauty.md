# 参考级皮肤美颜修复交接

## 当前结论

本轮围绕 `80.jpg → 80r.jpg` 的皮肤效果重构了磨皮、五官保护、身体皮肤 mask 和一键推荐。目标只对齐参考图的皮肤均匀度，不复制参考图中的眼部增强、唇色或全图调色。

**当前工作区不能声明最终通过。** 用户要求结束前，最后一次调整已写入 `src/beautifyImage.m`，但尚未运行任何测试或真实图验证。后续接手者必须先验证该调整，不要直接继续加功能。

## 已完成实现

1. 磨皮核心
   - 脸部与脸外皮肤的效果 alpha 各组合一次，取消重复相乘造成的窄边界。
   - 保留低频结构，分别处理高频纹理、中频肤色和色度异常。
   - 普通皮肤曲线在 75 档封顶，75–100 只继续处理高置信瑕疵。
   - 使用非瑕疵邻域生成局部稳健肤色参考，并用连续结构 mask 防止跨越鼻梁、脸缘和手指边缘。

2. 五官和睫毛保护
   - 鼻子的语义外轮廓不再进入硬保护，鼻孔和鼻部真实低频结构继续保护。
   - 眼睛、眉毛、嘴唇、鼻孔等核心区域逐像素复用原图。
   - 新增眼睑邻域的睫毛、眼线和双眼皮保护；睫毛使用高置信硬保护，双眼皮使用较宽的软保护。
   - 真实 `80.jpg` 局部检查中，睫毛、眼线和双眼皮已明显优于原实现。

3. 身体皮肤 mask
   - 使用 SCHP 软概率、主人物连通性和脸/颈肤色参考生成 mask。
   - 补全雀斑或阴影造成的小封闭孔洞，但保留开放的指缝。
   - 使用原图引导羽化，避免无条件 Gaussian 扩散。
   - 修复“孔洞虽被补回、最终 alpha 又因原始低概率变黑”的问题。

4. 一键推荐
   - 推荐依据改为排除五官后的局部亮度、色度异常面积和强度。
   - 推荐磨皮范围为 45–75，美白范围为 5–25。
   - `80.jpg` 实测推荐值为磨皮 `75`、美白约 `6.399`。

## 最后一次未验证调整

`src/beautifyImage.m` 当前暗斑层包含以下最新变化：

- `toneRegionMask` 从仅脸部扩展为脸部加较弱的脸外皮肤。
- 未命中异常的最低权重从较低值提高到 `0.40`。
- 正向暗斑修复混合系数提高到 `0.85`。
- 修复仍只允许把低于局部中值的暗像素向上抬升，不允许压低亮部。
- 鼻区继续使用 `noseToneWeight` 抑制该层，避免破坏鼻部结构和强度单调性。

这次调整的目的，是进一步清除脸颊、额头和肩部残留雀斑，使一键结果更接近 `80r.jpg`。它可能造成的风险包括：普通纹理保留不足、75–100 档纹理继续下降、身体皮肤偏亮或鼻部单调性回归。

## 调整前已通过的验证

以下结果均发生在“最后一次未验证调整”之前，不能直接代表当前磁盘状态：

- 相关 MATLAB 单元测试：`63 Passed, 0 Failed, 0 Incomplete`。
- `smokePhase3Enhancements` 真实图测试通过，覆盖 9 个 `*r` 配对图以及 `17.jpg`、`80.jpg`。
- `17.jpg`：鼻部低频结构保持率 `0.9612`，鼻内硬保护占比 `0`。
- `80.jpg`：右臂召回率 `0.9970`，身体/脸部变化比 `0.8917`。
- 背景最大变化 `0`，硬保护区域最大变化 `0`。
- 一键推荐调整前的对比图位于：
  - `%TEMP%\image_beauty_oneclick_final_20260914\80_oneclick_compare_v3.png`
- 真实 smoke 输出位于：
  - `%TEMP%\image_beauty_smoke_final_20260914\`

## 接手后的第一步

先运行当前磁盘状态的相关单元测试：

```powershell
& 'D:\Matlab_R2024a\bin\matlab.exe' -batch "cd('E:\image_beauty'); addpath('src'); a=runtests('tests/testPortraitBeautyHelpers.m'); b=runtests('tests/testSkinRegionWeighting.m'); c=runtests('tests/testNoseSmoothing.m'); d=runtests('tests/testPhase3Enhancements.m'); e=runtests('tests/testSchpLipHelpers.m'); f=runtests('tests/testPhase2BeautyEffects.m'); results=[a(:);b(:);c(:);d(:);e(:);f(:)]; fprintf('Passed=%d Failed=%d Incomplete=%d\n',nnz([results.Passed]),nnz([results.Failed]),nnz([results.Incomplete])); failed=results([results.Failed]); if ~isempty(failed),disp(table(failed));end; assert(all([results.Passed]));"
```

如果通过，再运行真实图 smoke：

```powershell
& 'D:\Matlab_R2024a\bin\matlab.exe' -batch "cd('E:\image_beauty'); addpath('src'); addpath('tests'); outDir=fullfile(tempdir,'image_beauty_smoke_handoff'); [summary,diagnostics]=smokePhase3Enhancements('D:\桌面\人脸\人脸',outDir); disp(summary); disp(diagnostics.image17); disp(diagnostics.image80);"
```

随后重新生成 `80.jpg` 的一键结果，与 `80r.jpg` 并排检查：

- 额头和脸颊雀斑是否进一步淡化。
- 睫毛、眼线和双眼皮是否完整保留。
- 鼻梁、鼻翼和眼窝是否没有描边、凹陷或凸起。
- 手指、指甲、关节、下巴与手部交界是否清晰。
- 手臂和肩部是否均匀，但没有乳化模糊或 mask 黑孔。

如果最后一次调整导致测试或视觉回归，优先回调暗斑层的 `0.40` 最低权重和 `0.85` 混合系数，不要先修改已经通过真实图检查的五官保护逻辑。

## 主要涉及文件

- `src/beautifyImage.m`
- `src/beautySmoothingProfile.m`
- `src/buildFeatureProtectionMasks.m`
- `src/buildBodySkinMaskFromSchp.m`
- `src/recommendBeautyParams.m`
- `tests/testPortraitBeautyHelpers.m`
- `tests/testSkinRegionWeighting.m`
- `tests/testNoseSmoothing.m`
- `tests/testPhase2BeautyEffects.m`
- `tests/testPhase3Enhancements.m`
- `tests/testSchpLipHelpers.m`
- `tests/smokePhase3Enhancements.m`

## 工作区注意事项

- 工作区原本就包含大量未提交修改、未跟踪文件以及 `.agents/`、`.claude/`、`.trellis/` 等目录删除；不要回滚或清理这些与本任务无关的用户改动。
- 本轮没有执行 Git 提交或推送。
- `tests/smokePhase2RealImages.m` 依赖本机缺失的 `14.jpg`、`15.jpg`、`人脸2/205.jpg`、`人脸2/206.jpg`，本轮未将其作为最终验收入口。
- 子代理均已完成或中断，没有需要继续等待的运行中子任务。

