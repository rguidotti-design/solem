"""HAL API — endpoint per ispezione hardware AI disponibile.

Wrapper sopra `solem_api.hal.*` per esporlo via SOLEM API REST.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..hal import detect_best_backend, list_available_backends
from ..hal.registry import detect_summary

router = APIRouter(prefix="/hal", tags=["hal"])


class CapsResponse(BaseModel):
    name: str
    kind: str
    available: bool
    vram_mb: int = 0
    ram_mb: int = 0
    cores: int = 1
    tflops_fp16: float = 0.0
    supports_streaming: bool = False
    notes: str = ""


class HALInfo(BaseModel):
    available_count: int
    best: CapsResponse
    backends: list[CapsResponse]
    reason: str = Field(..., description="Spiegazione testuale della scelta")


@router.get("/info", response_model=HALInfo)
async def hal_info() -> HALInfo:
    """Hardware AI disponibile + backend scelto come default.

    Step 0: solo CPUBackend (Ollama).
    Step 3+: aggiunge CUDABackend/ROCmBackend/VulkanBackend in base a hardware.
    """
    summary = detect_summary()
    return HALInfo(
        available_count=len(summary["available"]),
        best=CapsResponse(**summary["best"]),
        backends=[CapsResponse(**b) for b in summary["available"]],
        reason=summary["reason"],
    )


@router.get("/backends", response_model=list[CapsResponse])
async def list_backends() -> list[CapsResponse]:
    """Lista tutti i backend (anche non disponibili)."""
    return [CapsResponse(**b.capabilities().__dict__) for b in list_available_backends()]
