"""SOLEM HAL — Hardware Abstraction Layer per AI inference.

Allineamento Prompt Master v4.0 sez. 4.2 + ADR-007.

GAVIO/agents dichiarano capability (es. "tensor cores con X TFLOPS").
HAL trova combinazione hardware-backend disponibile e seleziona il best.

Step 0 (oggi): solo CPUBackend via Ollama esistente.
Step 3+ (Jetson): CUDABackend driver concreto.
Step 5+: ROCmBackend, VulkanBackend, NPUBackend.
"""

from .base import AccelBackend, BackendCapabilities, ModelHandle  # noqa: F401
from .cpu import CPUBackend  # noqa: F401
from .registry import detect_best_backend, list_available_backends  # noqa: F401

__all__ = [
    "AccelBackend",
    "BackendCapabilities",
    "ModelHandle",
    "CPUBackend",
    "detect_best_backend",
    "list_available_backends",
]
