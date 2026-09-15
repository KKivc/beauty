# Face parsing model

将获得许可的模型放置为 `face_parsing_bisenet_resnet18.onnx`。运行时只从
这个本地路径读取，不会自动联网下载。使用 `loadFaceParsingModel` 时传入
已核实的 SHA-256 `0D9BD318E46987C3BDBFACAE9E2C0F461CAE1C6AC6EA6D43BBE541A91727E33F`；未提供权重时应显示 `loadFaceParsingModel:MissingModel`。

当前仓库不包含未经确认可再分发的模型权重或哈希值。

MATLAB R2024a 还需要安装 **Deep Learning Toolbox Converter for ONNX Model
Format**，否则加载器会返回 `loadFaceParsingModel:MissingOnnxConverter`。
