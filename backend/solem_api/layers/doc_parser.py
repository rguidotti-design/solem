"""DOC PARSER — estrazione testo da PDF/DOCX/ODT/HTML/EPUB.

Single responsibility: SOLO file → testo puro. Niente analisi semantica
(delega a /summarize o /rag).

Backend: subprocess pdftotext (poppler), pandoc per docx/odt/epub.
Tutto FOSS, costo 0 €.

Endpoint:
  POST /docparse/extract  — upload file, ritorna testo + metadata
  GET  /docparse/formats  — formati supportati
"""
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel

router = APIRouter(prefix="/docparse", tags=["doc-parser"])

SUPPORTED_FORMATS = {
    ".pdf":  "pdftotext",
    ".docx": "pandoc",
    ".doc":  "pandoc",
    ".odt":  "pandoc",
    ".rtf":  "pandoc",
    ".epub": "pandoc",
    ".html": "pandoc",
    ".md":   "cat",
    ".txt":  "cat",
}

MAX_BYTES = 50 * 1024 * 1024  # 50 MB


class ExtractResponse(BaseModel):
    text: str
    chars: int
    backend: str
    suffix: str


def _run(cmd: list[str], timeout: int = 60) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)
    if r.returncode != 0:
        raise HTTPException(500, {"code": "extract_failed", "stderr": r.stderr[:500]})
    return r.stdout


@router.get("/health", response_model=dict)
async def parse_health() -> dict:
    return {
        "pdftotext_available": shutil.which("pdftotext") is not None,
        "pandoc_available": shutil.which("pandoc") is not None,
        "supported_formats": list(SUPPORTED_FORMATS.keys()),
        "max_bytes": MAX_BYTES,
    }


@router.get("/formats", response_model=list[str])
async def list_formats() -> list[str]:
    return list(SUPPORTED_FORMATS.keys())


@router.post("/extract", response_model=ExtractResponse)
async def extract(file: UploadFile = File(...)) -> ExtractResponse:
    if file.filename is None:
        raise HTTPException(400, {"code": "no_filename"})
    suffix = Path(file.filename).suffix.lower()
    if suffix not in SUPPORTED_FORMATS:
        raise HTTPException(400, {
            "code": "format_not_supported",
            "suffix": suffix,
            "supported": list(SUPPORTED_FORMATS.keys()),
        })

    content = await file.read()
    if len(content) > MAX_BYTES:
        raise HTTPException(413, {"code": "too_large", "max_bytes": MAX_BYTES})

    backend = SUPPORTED_FORMATS[suffix]

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)

    try:
        if backend == "pdftotext":
            if not shutil.which("pdftotext"):
                raise HTTPException(503, {"code": "pdftotext_missing", "hint": "installa poppler_utils"})
            text = _run(["pdftotext", "-layout", str(tmp_path), "-"])
        elif backend == "pandoc":
            if not shutil.which("pandoc"):
                raise HTTPException(503, {"code": "pandoc_missing"})
            text = _run(["pandoc", "-f", suffix.lstrip("."), "-t", "plain", str(tmp_path)])
        elif backend == "cat":
            text = tmp_path.read_text(encoding="utf-8", errors="replace")
        else:
            raise HTTPException(500, {"code": "unknown_backend"})
    finally:
        tmp_path.unlink(missing_ok=True)

    return ExtractResponse(text=text, chars=len(text), backend=backend, suffix=suffix)
