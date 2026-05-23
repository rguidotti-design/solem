"""DOTFILES SYNC — sincronizza ~/.config tra device del cluster.

Single responsibility: SOLO snapshot incrementale + diff sync via cluster
federation. Reuse vector_clock di memory_federation.

Strategia:
  - Whitelist file: .bashrc, .zshrc, .gitconfig, .config/{git,nvim,fish,...}
  - Hash SHA256 di ogni file + mtime
  - Diff endpoint ritorna file modificati dopo last_sync_ts
  - Apply patch dietro conferma utente (overwrite remoto → locale)

Endpoint:
  GET  /dotfiles/manifest        — hash+mtime di ogni file whitelistato
  GET  /dotfiles/diff?since=ts   — file modificati
  POST /dotfiles/push            — pull da peer (con conferma)
  POST /dotfiles/restore/{hash}  — rollback a snapshot precedente
"""
from __future__ import annotations

import hashlib
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/dotfiles", tags=["dotfiles-sync"])

HOME = Path(os.environ.get("HOME", "/home/gavio"))
SNAPSHOT_DIR = Path("/var/lib/solem/dotfiles-snapshots")

# Whitelist file/dir relativi a $HOME
WHITELIST = [
    ".bashrc", ".zshrc", ".profile", ".bash_profile",
    ".gitconfig", ".gitignore_global",
    ".vimrc", ".tmux.conf",
    ".config/git", ".config/nvim", ".config/fish",
    ".config/alacritty", ".config/foot", ".config/kitty",
    ".config/hypr", ".config/waybar", ".config/mako",
    ".config/starship.toml",
    ".ssh/config",  # NON includere chiavi private
]


class DotfileEntry(BaseModel):
    path: str
    sha256: str
    size: int
    mtime: float


class DotfilesManifest(BaseModel):
    device_id: str
    generated_at: str
    files: list[DotfileEntry]


class SnapshotMeta(BaseModel):
    snapshot_id: str
    created_at: str
    file_count: int
    total_size_kb: float


def _device_id() -> str:
    if id_env := os.environ.get("SOLEM_DEVICE_ID"):
        return id_env
    try:
        return os.uname().nodename
    except AttributeError:
        # Windows non ha os.uname()
        import socket
        return socket.gethostname()


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            while chunk := f.read(65536):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


def _enumerate() -> list[DotfileEntry]:
    out: list[DotfileEntry] = []
    for item in WHITELIST:
        p = HOME / item
        if not p.exists():
            continue
        if p.is_file():
            try:
                st = p.stat()
                out.append(DotfileEntry(
                    path=item, sha256=_hash_file(p), size=st.st_size, mtime=st.st_mtime,
                ))
            except OSError:
                continue
        elif p.is_dir():
            for f in p.rglob("*"):
                if not f.is_file():
                    continue
                # Skip secrets specifici (id_rsa, *.key, *.pem)
                if any(f.name.endswith(s) for s in (".key", ".pem", "_rsa", "_ed25519", "_ecdsa")):
                    continue
                try:
                    st = f.stat()
                    rel = f.relative_to(HOME).as_posix()
                    out.append(DotfileEntry(
                        path=rel, sha256=_hash_file(f), size=st.st_size, mtime=st.st_mtime,
                    ))
                except OSError:
                    continue
    return out


@router.get("/health", response_model=dict)
async def health() -> dict:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    return {
        "home_dir": str(HOME),
        "device_id": _device_id(),
        "whitelist": WHITELIST,
        "snapshot_dir": str(SNAPSHOT_DIR),
        "snapshot_count": len(list(SNAPSHOT_DIR.glob("*.tar.gz"))),
    }


@router.get("/manifest", response_model=DotfilesManifest)
async def manifest() -> DotfilesManifest:
    return DotfilesManifest(
        device_id=_device_id(),
        generated_at=datetime.now(timezone.utc).isoformat(),
        files=_enumerate(),
    )


@router.post("/snapshot", response_model=SnapshotMeta)
async def take_snapshot() -> SnapshotMeta:
    """Crea tar.gz dei dotfiles correnti in SNAPSHOT_DIR."""
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    import tarfile
    sid = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    snap = SNAPSHOT_DIR / f"{sid}.tar.gz"
    files = _enumerate()
    total = 0
    with tarfile.open(snap, "w:gz") as tar:
        for entry in files:
            p = HOME / entry.path
            if p.exists():
                tar.add(p, arcname=entry.path)
                total += entry.size
    return SnapshotMeta(
        snapshot_id=sid,
        created_at=datetime.now(timezone.utc).isoformat(),
        file_count=len(files),
        total_size_kb=round(total / 1024, 1),
    )


@router.get("/snapshots", response_model=list[SnapshotMeta])
async def list_snapshots() -> list[SnapshotMeta]:
    SNAPSHOT_DIR.mkdir(parents=True, exist_ok=True)
    out: list[SnapshotMeta] = []
    for snap in sorted(SNAPSHOT_DIR.glob("*.tar.gz"), reverse=True):
        try:
            sid = snap.stem.replace(".tar", "")
            st = snap.stat()
            out.append(SnapshotMeta(
                snapshot_id=sid,
                created_at=datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat(),
                file_count=0,  # lazy: extract per dettaglio
                total_size_kb=round(st.st_size / 1024, 1),
            ))
        except OSError:
            continue
    return out


@router.post("/restore/{snapshot_id}", response_model=dict)
async def restore(snapshot_id: str, dry_run: bool = True) -> dict:
    """Restore a snapshot precedente.

    Default dry_run=True: lista solo i file che verrebbero sovrascritti.
    Per applicare davvero: dry_run=false.
    """
    snap = SNAPSHOT_DIR / f"{snapshot_id}.tar.gz"
    if not snap.exists():
        raise HTTPException(404, {"code": "snapshot_not_found"})

    import tarfile
    members = []
    with tarfile.open(snap, "r:gz") as tar:
        for m in tar.getmembers():
            if m.isfile():
                members.append(m.name)

    if dry_run:
        return {"would_restore": members, "dry_run": True, "count": len(members)}

    # Backup pre-restore
    backup_meta = await take_snapshot()
    with tarfile.open(snap, "r:gz") as tar:
        tar.extractall(HOME, filter="data")

    return {
        "restored": True,
        "count": len(members),
        "pre_restore_backup": backup_meta.snapshot_id,
    }
