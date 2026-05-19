"""HAL Registry — auto-detection + selezione best backend.

Step 0: solo CPUBackend disponibile.
Step 3+: detect CUDA/ROCm via `nvidia-smi`/`rocm-smi` e attiva backend dedicato.
"""
from __future__ import annotations

import shutil
import subprocess
from typing import Any

from .base import AccelBackend, BackendCapabilities
from .cpu import CPUBackend

# Step 3+ aggiungerà: from .cuda import CUDABackend, ecc.


def list_available_backends() -> list[AccelBackend]:
    """Lista backend istanziati. Filtraggio per .is_available() avviene downstream."""
    backends: list[AccelBackend] = [CPUBackend()]

    if _has_cuda():
        # Step 3+: backends.append(CUDABackend())
        pass

    if _has_rocm():
        # Step 5+: backends.append(ROCmBackend())
        pass

    if _has_vulkan():
        # Step 5+: backends.append(VulkanBackend())
        pass

    return backends


def detect_best_backend(prefer_vram: bool = False) -> AccelBackend:
    """Sceglie il backend migliore disponibile.

    Strategia: priorità a GPU (vram > ram > cpu-only) se prefer_vram, altrimenti
    primo disponibile.
    """
    backends = [b for b in list_available_backends() if b.is_available()]
    if not backends:
        # Fallback inevitabile a CPUBackend stub (potrebbe non funzionare se Ollama down)
        return CPUBackend()

    if prefer_vram:
        backends.sort(key=lambda b: b.capabilities().vram_mb, reverse=True)
    return backends[0]


# ─── Hardware probes (Step 0 stub) ────────────────────────────────────


def _has_cuda() -> bool:
    """True se driver CUDA presenti + GPU NVIDIA visibile."""
    nvidia_smi = shutil.which("nvidia-smi")
    if not nvidia_smi:
        return False
    try:
        r = subprocess.run([nvidia_smi, "-L"], capture_output=True, timeout=2, check=False)
        return r.returncode == 0 and b"GPU" in r.stdout
    except subprocess.SubprocessError:
        return False


def _has_rocm() -> bool:
    """True se driver ROCm presenti + GPU AMD visibile."""
    rocm_smi = shutil.which("rocm-smi")
    if not rocm_smi:
        return False
    try:
        r = subprocess.run([rocm_smi, "--showid"], capture_output=True, timeout=2, check=False)
        return r.returncode == 0
    except subprocess.SubprocessError:
        return False


def _has_vulkan() -> bool:
    """True se Vulkan ICD configurati."""
    vulkaninfo = shutil.which("vulkaninfo")
    if not vulkaninfo:
        return False
    try:
        r = subprocess.run([vulkaninfo, "--summary"], capture_output=True, timeout=2, check=False)
        return r.returncode == 0
    except subprocess.SubprocessError:
        return False


def detect_summary() -> dict[str, Any]:
    """Riassunto detection per API endpoint /solem/hal/info."""
    backends = list_available_backends()
    available = [b for b in backends if b.is_available()]
    best = detect_best_backend()
    return {
        "available": [b.capabilities().__dict__ for b in available],
        "all_kinds": [b.capabilities().kind for b in backends],
        "best": best.capabilities().__dict__,
        "reason": (
            "CUDA detected" if _has_cuda()
            else "ROCm detected" if _has_rocm()
            else "Vulkan detected" if _has_vulkan()
            else "CPU only (no GPU detected)"
        ),
    }
