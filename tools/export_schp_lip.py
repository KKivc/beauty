"""Export the pinned SCHP LIP checkpoint as a static fusion-logits ONNX."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch

from schp_export.runtime import install_export_runtime


SOURCE_COMMIT = "eb84c432cc697f494d99662a05f2335eb2f26095"
CHECKPOINT_SHA256 = "24fa3254ceeb74c8435458994a64b522fb439a3635b7b86ff470457e0413da00"


class FusionOnly(torch.nn.Module):
    """Expose only the final LIP20 fusion branch used by inference."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return self.model(image)[0][-1]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_commit(source_root: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(source_root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.STDOUT,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as exception:
        raise SystemExit(f"Unable to verify SCHP source commit: {exception}") from exception


def load_model(source_root: Path, checkpoint_path: Path) -> FusionOnly:
    if source_commit(source_root) != SOURCE_COMMIT:
        raise SystemExit(f"SCHP source must be pinned to commit {SOURCE_COMMIT}.")
    if sha256_file(checkpoint_path) != CHECKPOINT_SHA256:
        raise SystemExit("Unexpected exp-schp-201908261155-lip.pth SHA-256.")

    install_export_runtime()
    sys.path.insert(0, str(source_root))
    import networks  # type: ignore[import-not-found]  # pylint: disable=import-error

    model = networks.init_model("resnet101", num_classes=20, pretrained=None)
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    state = {
        (name[7:] if name.startswith("module.") else name): value
        for name, value in checkpoint["state_dict"].items()
    }
    model.load_state_dict(state)
    return FusionOnly(model.eval()).eval()


def validate_static_onnx(
    model: FusionOnly, sample: torch.Tensor, output_path: Path
) -> dict[str, object]:
    graph = onnx.load(output_path)
    onnx.checker.check_model(graph)
    operation_types = {node.op_type for node in graph.graph.node}
    if "Resize" in operation_types:
        raise SystemExit("Dynamic/placeholder Resize nodes are forbidden in SCHP ONNX.")

    input_shape = [
        dimension.dim_value
        for dimension in graph.graph.input[0].type.tensor_type.shape.dim
    ]
    output_shape = [
        dimension.dim_value
        for dimension in graph.graph.output[0].type.tensor_type.shape.dim
    ]
    if input_shape != [1, 3, 473, 473] or output_shape != [1, 20, 119, 119]:
        raise SystemExit(
            f"Unexpected static shapes: input={input_shape}, output={output_shape}."
        )

    session = ort.InferenceSession(str(output_path), providers=["CPUExecutionProvider"])
    probes = [
        sample,
        torch.zeros_like(sample),
        torch.linspace(-1, 1, sample.numel(), dtype=sample.dtype).reshape(sample.shape),
    ]
    maximum_errors: list[float] = []
    label_agreements: list[float] = []
    for probe in probes:
        with torch.inference_mode():
            expected = model(probe).cpu().numpy()
        actual = session.run(["fusion_logits"], {"input": probe.numpy()})[0]
        maximum_errors.append(float(np.max(np.abs(expected - actual))))
        label_agreements.append(
            float(np.mean(np.argmax(expected, axis=1) == np.argmax(actual, axis=1)))
        )
    if max(maximum_errors) > 1e-3 or min(label_agreements) < 1.0:
        raise SystemExit("Static ONNX alignment threshold failed.")
    return {
        "input_shape": input_shape,
        "output_shape": output_shape,
        "maximum_errors": maximum_errors,
        "label_agreements": label_agreements,
        "opset": 14,
        "onnx_sha256": sha256_file(output_path),
        "torch": torch.__version__,
        "onnx": onnx.__version__,
        "onnxruntime": ort.__version__,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path)
    arguments = parser.parse_args()

    model = load_model(arguments.source_root.resolve(), arguments.checkpoint.resolve())
    torch.manual_seed(20260910)
    sample = torch.randn(1, 3, 473, 473)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        sample,
        arguments.output,
        input_names=["input"],
        output_names=["fusion_logits"],
        opset_version=14,
        do_constant_folding=True,
        dynamic_axes=None,
    )
    metadata = validate_static_onnx(model, sample, arguments.output)
    metadata_path = arguments.metadata or arguments.output.with_suffix(".export.json")
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
