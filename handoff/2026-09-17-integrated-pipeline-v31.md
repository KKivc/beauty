# v3.1 组合与真实图集成验收记录

记录日期：2026-09-17。输入来自用户本机 `D:\桌面\人脸\人脸`，未复制到仓库。

## 实现收口

- `resizeBeautyContext` 在原尺寸合并脸外皮肤后清理旧派生字段，再重建结构、强度和保护 Mask，避免 runtime cache 与最终 `skinMask` 不一致。
- 美白保留低档可见起效；存在真实鼻部结构时高档 Y 增量封顶为 `0.07`，并对合格脸部使用连续最小作用权重，降低鼻梁裁切和眉周亮度断层。
- 眉周过渡保持规划半径，调整衰减形状；GUI 增加按路径打开、调参、一键、重置和保存接口供可重复 smoke 调用。带分辨率元数据的 JPG 默认保存为 PNG，保存校验允许编码造成的 1 个分辨率单位量化误差。
- 新增 `tests/smokeIntegratedBeautyPipeline.m` 和 `tests/smokeGuiWorkflow.m`；旧 Phase 3 smoke 改用独立美白增量检查身体弱化，整体色调仅拦截明显偏移。

## 验证结果

- MATLAB 全量测试：`118 Passed, 0 Failed, 0 Incomplete`。
- `smokePhase2RealImages` 使用 `[14.jpg, 15.jpg, 80.jpg]` 通过；`80.jpg` 确认身体皮肤像素 `99590`，背景和硬保护最大变化均为 `0`。
- `smokePhase3Enhancements` 的 9 组 `*r` 参考图、`17.jpg` 旋转图和 `80.jpg` 身体召回通过；`17` 鼻部结构保留 `0.9644`，`80` 右臂召回 `0.9970`，背景/硬保护最大变化均为 `0`。
- 集成入口使用 `10/14/17/70/80/81.jpg`，分别检查预览和原尺寸、`0/25/50/75/100` 的 `5×5` 组合，共 `300` 个组合格、`48` 个指标行、`12` 个连续性行和 `12` 个缓存行全部通过。适用选区最低鼻部提亮比约 `0.980`、眉周提亮比约 `0.802`、独立美白鼻部结构保留约 `0.922`；重分解 Fine/Mid 能量均单调，alias 与迁移结果严格相等。
- GUI `80.jpg` 流程通过：预览 `[640 426 3]`，调参预览发生变化，一键推荐 `75/6.1957`，重置逐像素恢复原图，PNG 保存结果 `[850 565 3]`，画幅比例和分辨率通过。

## 可查看产物

- 集成对比图：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_integrated_final4\80_preview_compare.png`
- 集成量化表：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_integrated_final4\integrated-image-metrics.csv`、`integrated-continuity-metrics.csv`、`integrated-cache-metrics.csv`、`integrated-grid.csv`
- Phase 3 对比图：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_phase3_current\private-008_phase3.jpg`
- GUI 保存结果：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue07_gui_final.png`

## 限制

- `17.jpg` 和 `81.jpg` 在部分预览尺寸没有足够的眉周远区，报告为“不适用”，不计入通过样本；其余适用样本正常核验。
- 历史 Phase 2 入口所需的 `人脸2/205.jpg`、`人脸2/206.jpg` 不在当前目录，因此用现有 `14/15/80` 完成同一入口契约；未把缺失样本伪装成通过。
- 源 PNG 的 `iCCP` 元数据和部分 JPG 的 EXIF 偏移警告来自输入文件。MATLAB JPG 写入器不能携带任意 DPI，GUI 已默认选择可保存分辨率的 PNG；用户显式选择 JPG 时会保留可见的保存校验错误。

本轮未执行 Git 提交或推送。
