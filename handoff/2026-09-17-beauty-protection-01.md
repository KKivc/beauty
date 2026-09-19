# 01：瑕疵修复纹理软保护验收记录

记录日期：2026-09-17。

## 需求与范围

用户请求是实现 `.scratch/beauty-protection-convergence/issues/01-fix-repair-texture-protection.md`。该文档作为本票的实现约束：只修改瑕疵修复阶段、算法行为版本和必要测试，不改瑕疵检测、Mask 生成、公共 Context 字段、缩放链路、Base、肤色、美白或磨皮强度曲线。

## 代码变化

- `beauty.repairSkinBlemishes` 现在必须接收有效的 `textureProtectionMask`；缺失、尺寸不匹配、非有限值或超出 `[0, 1]` 时明确报错。
- 脸部和脸外的瑕疵修复权重完成计算后，统一乘以线性 `1 - textureProtectionMask`；Fine、Mid 和诊断用色度权重均受同一门控。
- 邻域参考采样同时使用该有效权重，受保护纹理不会作为修复参考贡献给邻域。
- `algorithmVersion` 从 `v3.1` 更新为 `v3.2`；`schemaVersion` 保持 `3.1`，`artifactVersion` 保持 `v3.1`。旧算法缓存按现有校验规则重新生成。

## 验证结果

### MATLAB 目标测试

`testNoseSmoothing`、`testBeautyMigration`、`testBeautyContextV3` 和 `testBeautyArtifactRegressions`：`29 Passed, 0 Failed, 0 Incomplete`。

新增断言覆盖：

- 纹理保护字段缺失和无效值明确失败；
- 脸内、脸外非零瑕疵的 Fine/Mid 权重按线性保护门控下降；
- 参考采样可靠度同步受保护门控限制；
- 旧 `v3.1` 算法缓存不复用，新 `v3.2` 缓存可复用。

### MATLAB 全量测试

运行 `runtests('tests')`：`120 Passed, 0 Failed, 0 Incomplete`。

### 代表性真实图

输入：`人脸/人脸/80.jpg`，源尺寸 `850×565`，输入与输出分辨率均为 `72×72 DPI`。使用 `tests/smokeIntegratedBeautyPipeline.m` 对预览和原尺寸各执行 `5×5` 强度组合、缓存复用、历史缓存重建和零强度原图检查，结果为 `passed=1`，共 `50` 个组合格；所有组合的缓存/直接计算结果一致，零强度逐像素返回原图，硬保护区域最大 RGB 变化为 `0`。

01 专项诊断固定磨皮 `100`、美白 `0`，将实际纹理保护与瑕疵证据重叠区域和清零保护对照：

| 尺寸 | 软保护像素 | 重叠像素 | 有保护/无保护修复权重 | 有保护校正能量 | 无保护校正能量 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 预览 `426×640` | 13,805 | 4,884 | 0.422613 | 0.00650977 | 0.0167039 |
| 原尺寸 `565×850` | 20,787 | 7,302 | 0.417033 | 0.0121583 | 0.0312076 |

最终图像指标由同一 smoke 进程记录如下：

| 尺寸 | 案例 | 信息熵 | 标准差 | 平均梯度 | 耗时（秒） |
| --- | --- | ---: | ---: | ---: | ---: |
| 预览 | `default_25_15` | 7.3697 | 0.19975 | 0.016369 | 0.70575 |
| 预览 | `combined_50_50` | 7.3563 | 0.19926 | 0.015612 | 0.64383 |
| 预览 | `maximum_100_100` | 7.3459 | 0.19815 | 0.014861 | 0.68546 |
| 原尺寸 | `default_25_15` | 7.3766 | 0.20032 | 0.017329 | 2.0604 |
| 原尺寸 | `combined_50_50` | 7.3619 | 0.19962 | 0.016252 | 2.0497 |
| 原尺寸 | `maximum_100_100` | 7.3509 | 0.19828 | 0.015233 | 2.0676 |

可查看产物：

- 对比图：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue01_v32\80_preview_compare.png`
- 量化表目录：`C:\Users\JJiio\AppData\Local\Temp\image_beauty_issue01_v32\`

可复现入口：

```powershell
& 'D:\Matlab_R2024a\bin\matlab.exe' -batch "cd('E:\image_beauty'); addpath('src'); addpath('tests'); outDir=fullfile(tempdir,'image_beauty_issue01_v32'); if ~isfolder(outDir), mkdir(outDir); end; [summary,diagnostics]=smokeIntegratedBeautyPipeline('E:\image_beauty\人脸\人脸',outDir,{'80.jpg'}); assert(summary.passed);"
```

本次真实图只证明 `80.jpg` 的预览和原尺寸结果；未据此承诺其他图像的所有残留症状均已消失。未执行 Git 提交或推送。本轮没有出现阻塞问题，不需要交接到 `beauty-protection-convergence` 对话。
