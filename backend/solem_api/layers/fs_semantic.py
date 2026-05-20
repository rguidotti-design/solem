"""FS SEMANTIC — indicizzazione + ricerca semantica filesystem locale.

Single responsibility: SOLO indicizzare contenuti file e cercare via
testo + embedding. Niente UI, niente trasporto.

Architettura ibrida:
  - SQLite FTS5 → ricerca testuale veloce (lexical)
  - vector_store → ricerca semantica (cosine)
  - Hybrid score = α·lex + (1-α)·sem

Endpoint:
  POST /fs/index       — indicizza file/cartella (ricorsivo opzionale)
  POST /fs/search      — ricerca ibrida (testo + semantica)
  GET  /fs/stats       — totale file indicizzati, dimensione index
  DELETE /fs/index/{path} — rimuove path dall'index

Path roots whitelisted via env SOLEM_FS_INDEX_ROOTS (CSV).
Default: ~/Documents,~/Desktop (no /etc, no /proc, no /sys).
"""
from __future__ import annotations

import hashlib
import mimetypes
import os
import sqlite3
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/fs", tags=["fs-semantic"])

INDEX_DB = Path(os.environ.get("SOLEM_FS_INDEX_DB", "/var/lib/solem/fs_index.db"))

DEFAULT_ROOTS = [str(Path.home() / "Documents"), str(Path.home() / "Desktop")]
ROOTS = [Path(p).resolve() for p in os.environ.get("SOLEM_FS_INDEX_ROOTS", ",".join(DEFAULT_ROOTS)).split(",") if p.strip()]

# Filtri MIME accettati (espandibile via env)
TEXT_MIMES = {
    "text/plain", "text/markdown", "text/csv", "text/html",
    "application/json", "application/xml", "application/yaml",
    "application/x-python", "application/javascript",
}
MAX_FILE_BYTES = int(os.environ.get("SOLEM_FS_MAX_BYTES", str(10 * 1024 * 1024)))  # 10 MB


class IndexRequest(BaseModel):
    path: str
    recursive: bool = False


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1)
    limit: int = Field(20, ge=1, le=100)
    alpha: float = Field(0.5, ge=0.0, le=1.0, description="Pesos lex (1) vs semantic (0)")


class SearchHit(BaseModel):
    path: str
    score: float
    snippet: str
    mime: str


class IndexStats(BaseModel):
    total_files: int
    total_bytes: int
    db_size_bytes: int
    roots: list[str]


# ─── DB ───────────────────────────────────────────────────────────────


def _conn() -> sqlite3.Connection:
    INDEX_DB.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(INDEX_DB)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("""
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY,
            mime TEXT,
            size INTEGER,
            sha256 TEXT,
            indexed_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    """)
    c.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(
            path UNINDEXED,
            content,
            tokenize='unicode61'
        )
    """)
    return c


def _is_allowed(path: Path) -> bool:
    rp = path.resolve()
    return any(str(rp).startswith(str(root)) for root in ROOTS)


def _read_text(path: Path) -> str | None:
    if path.stat().st_size > MAX_FILE_BYTES:
        return None
    mime, _ = mimetypes.guess_type(str(path))
    if mime and mime not in TEXT_MIMES and not mime.startswith("text/"):
        return None
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _sha256(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8", errors="replace")).hexdigest()


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def fs_health() -> dict:
    return {
        "roots": [str(r) for r in ROOTS],
        "index_db": str(INDEX_DB),
        "max_bytes": MAX_FILE_BYTES,
        "step": "scaffold (Step 0) — embedding semantic via vector_store futuro",
    }


@router.get("/stats", response_model=IndexStats)
async def stats() -> IndexStats:
    c = _conn()
    try:
        row = c.execute("SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS s FROM files").fetchone()
        return IndexStats(
            total_files=row["n"],
            total_bytes=row["s"],
            db_size_bytes=INDEX_DB.stat().st_size if INDEX_DB.exists() else 0,
            roots=[str(r) for r in ROOTS],
        )
    finally:
        c.close()


@router.post("/index", response_model=dict)
async def index_path(req: IndexRequest) -> dict:
    p = Path(req.path).expanduser().resolve()
    if not _is_allowed(p):
        raise HTTPException(403, {"code": "path_not_allowed", "roots": [str(r) for r in ROOTS]})
    if not p.exists():
        raise HTTPException(404, {"code": "path_not_found"})

    targets = []
    if p.is_file():
        targets.append(p)
    elif p.is_dir() and req.recursive:
        targets.extend(f for f in p.rglob("*") if f.is_file())
    elif p.is_dir():
        targets.extend(f for f in p.iterdir() if f.is_file())

    c = _conn()
    indexed = 0
    skipped = 0
    try:
        for f in targets:
            content = _read_text(f)
            if content is None:
                skipped += 1
                continue
            mime, _ = mimetypes.guess_type(str(f))
            digest = _sha256(content)
            c.execute(
                "INSERT OR REPLACE INTO files(path,mime,size,sha256) VALUES (?,?,?,?)",
                (str(f), mime or "text/plain", f.stat().st_size, digest),
            )
            c.execute("DELETE FROM fts WHERE path = ?", (str(f),))
            c.execute("INSERT INTO fts(path,content) VALUES (?,?)", (str(f), content))
            indexed += 1
        c.commit()
    finally:
        c.close()

    return {"indexed": indexed, "skipped": skipped, "total_targets": len(targets)}


@router.post("/search", response_model=list[SearchHit])
async def search(req: SearchRequest) -> list[SearchHit]:
    c = _conn()
    try:
        # MATCH FTS5: scape doppi apici
        q = req.query.replace('"', '""')
        rows = c.execute(
            """
            SELECT f.path, f.mime, snippet(fts, 1, '«', '»', '…', 16) AS snip,
                   bm25(fts) AS lex_score
            FROM fts JOIN files f ON f.path = fts.path
            WHERE fts MATCH ?
            ORDER BY lex_score
            LIMIT ?
            """,
            (f'"{q}"', req.limit),
        ).fetchall()
    except sqlite3.OperationalError as e:
        raise HTTPException(400, {"code": "fts_query_error", "message": str(e)})
    finally:
        c.close()

    # Step 0: solo lexical; semantic blending Step 1+ via vector_store
    out: list[SearchHit] = []
    for r in rows:
        # bm25 più basso = match migliore → normalizziamo a 0-1
        score = 1.0 / (1.0 + max(0.0, r["lex_score"]))
        out.append(SearchHit(
            path=r["path"],
            score=round(score, 4),
            snippet=r["snip"] or "",
            mime=r["mime"] or "text/plain",
        ))
    return out


@router.delete("/index")
async def delete_path(path: str) -> dict:
    p = Path(path).expanduser().resolve()
    c = _conn()
    try:
        c.execute("DELETE FROM files WHERE path = ?", (str(p),))
        c.execute("DELETE FROM fts WHERE path = ?", (str(p),))
        c.commit()
    finally:
        c.close()
    return {"deleted": True, "path": str(p)}
