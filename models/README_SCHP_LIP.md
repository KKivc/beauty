# SCHP LIP-20 固定模型

本地运行文件 `schp_lip_resnet101.onnx` 固定为 473x473 BGR 输入和
119x119x20 `fusion_logits` 输出。它不随仓库提交，由调用方放入 `models/`。

- 官方源码：[PeikeLi/Self-Correction-Human-Parsing](https://github.com/PeikeLi/Self-Correction-Human-Parsing)，固定提交 `eb84c432cc697f494d99662a05f2335eb2f26095`。
- 官方 checkpoint：[exp-schp-201908261155-lip.pth](https://drive.google.com/file/d/1k4dllHpu0bdx38J7H28rVVLpU-kOHmnH/view?usp=sharing)，SHA-256 `24FA3254CEEB74C8435458994A64B522FB439A3635B7B86FF470457E0413DA00`。
- 本项目 ONNX SHA-256：`92E0A10000073B6B6AF4FDE567944ED0F91B52F7D4D79715425B0A13B82AFF54`，大小 266734414 bytes。

## 固定导出环境与命令

使用 Python 3.11.15，并安装 `tools/schp_export/requirements.txt` 中锁定的
torch 2.5.1、numpy 1.26.4、onnx 1.17.0、onnxruntime 1.20.1。完整命令：

```powershell
py -3.11 -m venv .schp-export-venv
.\.schp-export-venv\Scripts\python.exe -m pip install -r tools\schp_export\requirements.txt
.\.schp-export-venv\Scripts\python.exe tools\export_schp_lip.py --source-root C:\path\to\Self-Correction-Human-Parsing --checkpoint C:\path\to\exp-schp-201908261155-lip.pth --output models\schp_lip_resnet101.onnx
```

脚本以纯 PyTorch 替换旧版 `InPlaceABNSync` 推理路径，并把
`align_corners=True` 的固定尺寸插值展开为静态算子。只接受输入
`[1,3,473,473]`、输出 `[1,20,119,119]` 且不含 ONNX `Resize` 节点的版本；
原始含动态或 placeholder `Resize` 的导出文件不可使用。

三段对齐验证的 max abs / argmax agreement 分别为
`4.0531e-06 / 100%`、`3.8624e-05 / 100%`、`8.1062e-06 / 100%`。
