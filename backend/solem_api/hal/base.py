"""HAL — Interface astratta AccelBackend.

Ogni backend (CPU/CUDA/ROCm/Vulkan/NPU) implementa questa interface.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Literal


@dataclass(frozen=True)
class BackendCapabilities:
    """Capability dichiarate da un backend."""
    name: str
    kind: Literal["cpu", "cuda", "rocm", "oneapi", "vulkan", "metal", "npu"]
    available: bool
    vram_mb: int = 0          # 0 = no GPU
    ram_mb: int = 0
    cores: int = 1
    tflops_fp16: float = 0.0  # stimato, 0 se sconosciuto
    supports_streaming: bool = False
    notes: str = ""


@dataclass
class ModelHandle:
    """Handle a un modello caricato in memoria/VRAM."""
    model_id: str            # es. "llama3.2:3b"
    backend: str             # es. "cpu", "cuda"
    loaded: bool = False
    metadata: dict[str, Any] = field(default_factory=dict)


class AccelBackend(ABC):
    """Interface per backend di accelerazione AI.

    Implementazioni concrete:
      - CPUBackend       — Ollama via REST API (Step 0+)
      - CUDABackend      — llama.cpp con LLAMA_CUDA (Step 3+)
      - ROCmBackend      — llama.cpp con LLAMA_HIPBLAS (Step 5+)
      - VulkanBackend    — fallback universale FOSS (Step 5+)
      - NPUBackend       — Hailo/Coral/Rockchip (Step 5+)
    """

    @abstractmethod
    def capabilities(self) -> BackendCapabilities:
        """Dichiara le capability del backend."""
        ...

    @abstractmethod
    def is_available(self) -> bool:
        """True se il backend è funzionante (driver presenti, hardware OK)."""
        ...

    @abstractmethod
    async def load_model(self, model_id: str, **opts: Any) -> ModelHandle:
        """Carica modello in VRAM/RAM. Idempotente."""
        ...

    @abstractmethod
    async def unload_model(self, handle: ModelHandle) -> None:
        """Scarica modello, libera memoria."""
        ...

    @abstractmethod
    async def infer(
        self,
        handle: ModelHandle,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 512,
        temperature: float = 0.7,
        stream: bool = False,
    ) -> str | AsyncIterator[str]:
        """Inference (testo→testo).

        Se stream=True, ritorna AsyncIterator[str] (token streaming).
        Se stream=False, ritorna stringa completa.
        """
        ...

    @abstractmethod
    async def list_loaded(self) -> list[ModelHandle]:
        """Modelli attualmente caricati."""
        ...

    def __repr__(self) -> str:
        caps = self.capabilities()
        return f"<{self.__class__.__name__} kind={caps.kind} available={caps.available}>"
