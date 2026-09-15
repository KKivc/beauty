"""Pure-PyTorch replacements needed to export the 2019 SCHP source."""

from __future__ import annotations

import sys
import types
from collections.abc import Sequence

import torch
import torch.nn as nn
import torch.nn.functional as functional


class ExportInPlaceABN(nn.BatchNorm2d):
    """Inference-equivalent BatchNorm plus activation without the old extension."""

    def __init__(
        self,
        num_features: int,
        eps: float = 1e-5,
        momentum: float = 0.1,
        affine: bool = True,
        activation: str = "leaky_relu",
        slope: float = 0.01,
        **_kwargs: object,
    ) -> None:
        super().__init__(num_features, eps, momentum, affine)
        self.activation = activation
        self.slope = slope

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        value = super().forward(value)
        if self.activation == "relu":
            return functional.relu(value)
        if self.activation == "leaky_relu":
            return functional.leaky_relu(value, negative_slope=self.slope)
        if self.activation == "elu":
            return functional.elu(value)
        return value


_ORIGINAL_INTERPOLATE = functional.interpolate


def static_align_corners(
    value: torch.Tensor, size: Sequence[int]
) -> torch.Tensor:
    """Express fixed align-corners bilinear resize without ONNX Resize nodes."""
    output_height, output_width = int(size[0]), int(size[1])
    input_height, input_width = value.shape[-2:]
    if input_height != output_height:
        y = torch.linspace(
            0, input_height - 1, output_height, device=value.device, dtype=value.dtype
        )
        y0 = torch.floor(y).to(torch.long)
        y1 = torch.clamp(y0 + 1, max=input_height - 1)
        weight = (y - y0.to(value.dtype)).reshape(1, 1, output_height, 1)
        value = (
            value.index_select(2, y0) * (1 - weight)
            + value.index_select(2, y1) * weight
        )
    if input_width != output_width:
        x = torch.linspace(
            0, input_width - 1, output_width, device=value.device, dtype=value.dtype
        )
        x0 = torch.floor(x).to(torch.long)
        x1 = torch.clamp(x0 + 1, max=input_width - 1)
        weight = (x - x0.to(value.dtype)).reshape(1, 1, 1, output_width)
        value = (
            value.index_select(3, x0) * (1 - weight)
            + value.index_select(3, x1) * weight
        )
    return value


def export_interpolate(
    input: torch.Tensor,
    size: Sequence[int] | None = None,
    scale_factor: float | Sequence[float] | None = None,
    mode: str = "nearest",
    align_corners: bool | None = None,
    recompute_scale_factor: bool | None = None,
    antialias: bool = False,
) -> torch.Tensor:
    if size is not None and mode == "bilinear" and align_corners is True:
        return static_align_corners(input, size)
    return _ORIGINAL_INTERPOLATE(
        input,
        size=size,
        scale_factor=scale_factor,
        mode=mode,
        align_corners=align_corners,
        recompute_scale_factor=recompute_scale_factor,
        antialias=antialias,
    )


def install_export_runtime() -> None:
    """Install the two narrow compatibility patches before importing SCHP."""
    module = types.ModuleType("modules")
    module.InPlaceABNSync = ExportInPlaceABN
    module.InPlaceABN = ExportInPlaceABN
    module.ABN = ExportInPlaceABN
    sys.modules["modules"] = module
    functional.interpolate = export_interpolate
