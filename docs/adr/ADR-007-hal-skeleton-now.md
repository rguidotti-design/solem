# ADR-007 — HAL AI skeleton ora, driver Step 3 con Jetson

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Prompt v4.0 sez. 4.2 chiede Hardware Abstraction Layer per AI (CUDA/ROCm/oneAPI/Vulkan/Metal/NPU). L'utente sviluppa oggi solo in VM TCG senza GPU. Hardware AI dedicato arriva Step 3+ (Jetson Orin Nano).

## Decisione

### Da subito (Mese 2-3) — HAL skeleton
- Modulo Python `backend/solem_api/hal/` con:
  - Interface astratta `AccelBackend` (load_model, infer, unload, get_capabilities)
  - Implementazione `CPUBackend` via Ollama esistente
  - Stub `CUDABackend`, `ROCmBackend`, `VulkanBackend`, `NPUBackend` con `NotImplementedError` chiaro
  - Auto-detection: legge `/proc/cpuinfo`, `lspci`, `nvidia-smi`, `rocm-smi` → sceglie backend
  - API `/solem/hal/info` ritorna `{available: ["cpu"], best: "cpu", reason: "no GPU detected"}`

### Step 3 (con Jetson) — driver concreti
- Implementazione `CUDABackend` via `llama.cpp` con `LLAMA_CUDA=1`
- Test su Jetson reale
- Auto-quantizzazione modelli in base a VRAM disponibile (Q4_K_M default)

### Step 5+ — backend aggiuntivi
- `ROCmBackend` se Beelink futuro con AMD GPU
- `VulkanBackend` come fallback universale (NixOS supporta `mesa.vulkan`)
- `NPUBackend` per Hailo/Coral/Rockchip se hardware target lo include

## Conseguenze

**Positive**:
- Quando arriva Jetson = solo plug-in driver, zero refactoring client code
- Architettura pronta per backend multipli
- Test su CPU non bloccato in attesa di GPU

**Negative**:
- Codice "skeleton" non testato su hardware reale fino a Step 3
- Possibile over-engineering se Jetson cambia priorità

## Implementazione

M1.2 (Mese 2-3): scrivo `hal/` con interface + CPUBackend funzionante + 3 stub. Test pytest che verifica interface contract.
