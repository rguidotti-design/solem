"""CPUBackend — implementazione HAL via Ollama locale.

Ollama gira come servizio systemd (vedi gavio.nix `services.ollama`).
Espone API HTTP su :11434. Questo backend è SEMPRE disponibile su SOLEM.
"""
from __future__ import annotations

import os
import shutil
from typing import Any, AsyncIterator

import httpx

from .base import AccelBackend, BackendCapabilities, ModelHandle

OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")


class CPUBackend(AccelBackend):
    """Backend CPU via Ollama API."""

    def __init__(self) -> None:
        self._loaded: dict[str, ModelHandle] = {}

    def capabilities(self) -> BackendCapabilities:
        ram_mb = _read_ram_mb()
        cores = _read_cpu_cores()
        return BackendCapabilities(
            name="ollama-cpu",
            kind="cpu",
            available=self.is_available(),
            vram_mb=0,
            ram_mb=ram_mb,
            cores=cores,
            tflops_fp16=0.0,
            supports_streaming=True,
            notes="Ollama locale via API HTTP :11434. Default backend SOLEM.",
        )

    def is_available(self) -> bool:
        try:
            r = httpx.get(f"{OLLAMA_URL}/api/version", timeout=2.0)
            return r.status_code == 200
        except (httpx.HTTPError, OSError):
            return False

    async def load_model(self, model_id: str, **opts: Any) -> ModelHandle:
        async with httpx.AsyncClient(timeout=60.0) as c:
            r = await c.post(f"{OLLAMA_URL}/api/pull", json={"name": model_id, "stream": False})
            r.raise_for_status()
        handle = ModelHandle(model_id=model_id, backend="cpu", loaded=True, metadata=opts)
        self._loaded[model_id] = handle
        return handle

    async def unload_model(self, handle: ModelHandle) -> None:
        # Ollama scarica automaticamente dopo idle; qui solo segnaliamo intent
        self._loaded.pop(handle.model_id, None)
        handle.loaded = False

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
        payload = {
            "model": handle.model_id,
            "prompt": prompt,
            "stream": stream,
            "options": {"num_predict": max_tokens, "temperature": temperature},
        }
        if system:
            payload["system"] = system

        if not stream:
            async with httpx.AsyncClient(timeout=120.0) as c:
                r = await c.post(f"{OLLAMA_URL}/api/generate", json=payload)
                r.raise_for_status()
                return r.json().get("response", "")

        # Streaming: ritorna AsyncIterator
        return _stream_ollama(payload)

    async def list_loaded(self) -> list[ModelHandle]:
        try:
            async with httpx.AsyncClient(timeout=3.0) as c:
                r = await c.get(f"{OLLAMA_URL}/api/ps")
                if r.status_code == 200:
                    return [
                        ModelHandle(model_id=m["name"], backend="cpu", loaded=True, metadata=m)
                        for m in r.json().get("models", [])
                    ]
        except httpx.HTTPError:
            pass
        return list(self._loaded.values())


async def _stream_ollama(payload: dict) -> AsyncIterator[str]:
    """Generator async che yield token from Ollama streaming."""
    import json as _json
    async with httpx.AsyncClient(timeout=300.0) as c:
        async with c.stream("POST", f"{OLLAMA_URL}/api/generate", json=payload) as r:
            async for line in r.aiter_lines():
                if not line:
                    continue
                try:
                    chunk = _json.loads(line)
                    if "response" in chunk:
                        yield chunk["response"]
                    if chunk.get("done"):
                        break
                except _json.JSONDecodeError:
                    continue


# ─── Hardware introspection ───────────────────────────────────────────


def _read_ram_mb() -> int:
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return 0


def _read_cpu_cores() -> int:
    return os.cpu_count() or 1
