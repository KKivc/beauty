# Repository Guidelines

## 项目结构与模块组织

本项目使用 MATLAB 实现人脸图像美颜算法及 GUI。建议按职责组织：`src/` 存放美颜算法与指标计算函数，`gui/` 存放 GUIDE `.fig/.m` 或 App Designer `.mlapp` 文件，`tests/` 存放测试脚本，`assets/` 存放示例输入和展示素材。算法、界面回调和评价指标应尽量分离，便于单独验证。

## 开发与运行

使用简洁的注释，注释用中文，技术名词之类的保留英文

当前仓库尚未提供固定脚本或工程文件。开发时应在 MATLAB 中打开项目并运行 GUI 入口；提交后请补充实际入口名称，例如 `app.mlapp` 或 `main.m`。常用验证方式包括：

- `run('main.m')`：启动 GUI（以实际入口为准）。
- `results = beautifyImage(img, params)`：独立验证算法输出。
- `results = evaluateImage(original, output, elapsed)`：计算信息熵、标准差、平均梯度和处理耗时。

## GUI 功能要求

界面必须同屏并排显示原图和处理结果，并支持打开图像、保存图像、磨皮参数调节、美白参数调节、一键美颜和重置原图。参数变化应触发实时预览；处理耗时应按单幅图像记录并展示客观指标。保存结果时必须保留输入图像的尺寸、分辨率和画幅比例。

## 算法与编码规范

使用 MATLAB 默认四空格缩进，函数和变量采用 `camelCase`，文件名与主函数名保持一致，参数结构使用清晰字段名。磨皮应淡化斑点、细纹并保留五官轮廓和细节；美白应自然均匀，避免偏色、假白、光晕、伪轮廓和边缘失真。不得改变人脸结构、比例或图像内容；临时缩放和多尺度计算结束后必须恢复原始输出尺寸。

## 测试与验证

至少使用不同尺寸、分辨率、肤色和人脸姿态的图像测试。检查原图/结果图尺寸、分辨率、比例一致，确认无裁剪、拉伸、变形；同时检查细节保留、边缘质量、色彩自然度、指标显示和处理耗时。修改后应在 MATLAB 中完成 GUI 手动回归，并运行已有 `tests/` 脚本。

## 提交与合并请求

提交信息使用简短、祈使式描述，例如 `Add real-time whitening preview`。合并请求应说明算法或界面变化、测试图像与结果，附 GUI 截图或前后对比图，并列出信息熵、标准差、平均梯度及耗时变化；避免提交生成的缓存、临时图片或个人 MATLAB 配置文件。
<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
