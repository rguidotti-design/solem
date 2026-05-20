"""RAG — capability retrieval-augmented generation, generate delega a GAVIO.

Single responsibility: SOLO orchestrare chunk+embed+search e poi mandare
contesto+domanda a GAVIO. Embedding va tramite vector_store (Ollama
embedding model, deterministico). Generate è SEMPRE GAVIO.

Pipeline:
  1. /rag/ingest  → split documenti in chunk + indicizza in vector_store
  2. /rag/query   → search top-K → costruisce prompt → GAVIO genera
"""
from __future__ import annotations

import os

import httpx
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

router = APIRouter(prefix="/rag", tags=["rag"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")

CHUNK_SIZE = 800
CHUNK_OVERLAP = 100


class IngestRequest(BaseModel):
    collection: str = Field(..., min_length=1)
    document_id: str = Field(..., min_length=1)
    text: str = Field(..., min_length=10)
    metadata: dict = Field(default_factory=dict)


class QueryRequest(BaseModel):
    collection: str
    question: str = Field(..., min_length=3)
    top_k: int = Field(5, ge=1, le=20)


class Source(BaseModel):
    doc_id: str
    chunk_idx: int
    score: float
    snippet: str


class QueryResponse(BaseModel):
    answer: str
    sources: list[Source]
    via: str = "gavio"


def _chunk(text: str) -> list[str]:
    chunks: list[str] = []
    i = 0
    while i < len(text):
        chunks.append(text[i:i + CHUNK_SIZE])
        i += CHUNK_SIZE - CHUNK_OVERLAP
    return chunks


async def _index_chunk(collection: str, chunk_id: str, text: str, metadata: dict) -> None:
    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/vector/index/{collection}",
            json={"id": chunk_id, "text": text, "metadata": metadata},
        )
        if r.status_code >= 400:
            raise HTTPException(r.status_code, r.json())


async def _search(collection: str, query: str, top_k: int) -> list[dict]:
    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/vector/search/{collection}",
            json={"query": query, "top_k": top_k},
        )
        if r.status_code == 404:
            raise HTTPException(404, {"code": "collection_not_found", "collection": collection})
        if r.status_code >= 400:
            raise HTTPException(r.status_code, r.json())
        return r.json()


async def _generate(prompt: str) -> str:
    """Delega a GAVIO via SOLEM proxy. GAVIO sceglie il modello."""
    async with httpx.AsyncClient(timeout=180.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/ai/route",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "hint": "rag",
                "max_tokens": 600,
                "temperature": 0.2,
            },
        )
        if r.status_code != 200:
            raise HTTPException(503, {"code": "gavio_unavailable", "status": r.status_code})
        return r.json().get("content", "").strip()


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def rag_health() -> dict:
    return {
        "ai_backend": "gavio (via /solem/ai/route)",
        "embedding_backend": "vector_store (Ollama embedding model)",
        "chunk_size": CHUNK_SIZE,
        "chunk_overlap": CHUNK_OVERLAP,
    }


@router.post("/ingest", response_model=dict)
async def ingest(req: IngestRequest) -> dict:
    chunks = _chunk(req.text)
    for i, chunk in enumerate(chunks):
        meta = {**req.metadata, "doc_id": req.document_id, "chunk_idx": i}
        await _index_chunk(req.collection, f"{req.document_id}#{i}", chunk, meta)
    return {
        "ingested": True,
        "collection": req.collection,
        "document_id": req.document_id,
        "chunks_indexed": len(chunks),
    }


@router.post("/ingest/file", response_model=dict)
async def ingest_file(
    collection: str = Form(...),
    document_id: str = Form(...),
    file: UploadFile = File(...),
) -> dict:
    content = await file.read()
    try:
        text = content.decode("utf-8", errors="replace")
    except UnicodeDecodeError:
        raise HTTPException(400, {"code": "not_utf8_text"})

    chunks = _chunk(text)
    for i, chunk in enumerate(chunks):
        meta = {"doc_id": document_id, "chunk_idx": i, "filename": file.filename or "?"}
        await _index_chunk(collection, f"{document_id}#{i}", chunk, meta)
    return {
        "ingested": True,
        "collection": collection,
        "document_id": document_id,
        "chunks_indexed": len(chunks),
        "filename": file.filename,
    }


@router.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest) -> QueryResponse:
    hits = await _search(req.collection, req.question, req.top_k)
    if not hits:
        return QueryResponse(
            answer="Non ho trovato informazioni rilevanti nei documenti indicizzati.",
            sources=[],
        )

    ctx_parts: list[str] = []
    sources: list[Source] = []
    for i, h in enumerate(hits):
        meta = h.get("metadata", {})
        ctx_parts.append(f"[Source {i + 1}] {h.get('text', '')}")
        sources.append(Source(
            doc_id=meta.get("doc_id", "?"),
            chunk_idx=meta.get("chunk_idx", -1),
            score=float(h.get("score", 0.0)),
            snippet=h.get("text", "")[:200],
        ))

    context = "\n\n".join(ctx_parts)
    prompt = (
        "You are a helpful assistant. Answer the question using ONLY the provided sources. "
        "If the sources don't contain the answer, say so honestly. Reply in Italian. "
        "Cite source numbers like [1], [2] inline.\n\n"
        f"SOURCES:\n{context}\n\n"
        f"QUESTION: {req.question}\n\n"
        "ANSWER:"
    )
    answer = await _generate(prompt)
    return QueryResponse(answer=answer, sources=sources)


@router.get("/collections", response_model=list[str])
async def collections() -> list[str]:
    async with httpx.AsyncClient(timeout=5.0) as c:
        r = await c.get(f"{SOLEM_URL}/solem/vector/tables")
        if r.status_code == 503:
            return []
        r.raise_for_status()
        return r.json()
