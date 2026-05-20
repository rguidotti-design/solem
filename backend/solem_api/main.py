"""SOLEM API — backend di sistema (Layer 1-4 stub).

Servizio FastAPI separato da GAVIO. Espone:
  - /health                   liveness
  - /solem/manifest           identità + stato runtime di SOLEM
  - /solem/capabilities       cosa SOLEM sa fare (auto-discovery)
  - /solem/identity/me        L1 Identity Engine (placeholder Step 0)

Filosofia AI-first: output sempre JSON/Pydantic, errori machine-readable,
schema OpenAPI completo auto-generato dal codice.

Avviato come systemd service da nixos/modules/solem-api.nix sulla porta 8001.
"""
from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

# Layer modules (router FastAPI montati sotto /solem/)
from .layers import identity as l1_identity
from .layers import context as l2_context
from .layers import events as l3_events
from .layers import capabilities as l4_capabilities
from .layers import memory as l5_memory
from .layers import interop as l6_interop
from .layers import extensions as l7_extensions
from .layers import agents as agents_mod
from .layers import users as users_mod
from .layers import system as system_mod
from .layers import metrics as metrics_mod
from .layers import migrations as migrations_mod
from .layers import hal_api as hal_api_mod
from .layers import constitution as constitution_mod
from .layers import panic as panic_mod
from .layers import mcp as mcp_mod
from .layers import voice as voice_mod
from .layers import health as health_mod
from .layers import auth_keys as auth_keys_mod
from .layers import vector_store as vector_store_mod
from .layers import federated as federated_mod
from .layers import crdt_sync as crdt_mod
from .layers import fs_semantic as fs_semantic_mod
from .layers import ai_router as ai_router_mod
from .layers import updates as updates_mod
from .layers import crash_reporter as crash_mod
from .layers import universal_search as search_mod
from .layers import marketplace as marketplace_mod
from .layers import voice_wake as voice_wake_mod
from .layers import vision as vision_mod
from .layers import summarizer as summarizer_mod
from .layers import rag as rag_mod
from .layers import autoheal as autoheal_mod
from .layers import file_organizer as organizer_mod
from .layers import doc_parser as docparse_mod
from .layers import ai_shell as ai_shell_mod
from .layers import ai_calendar as ai_calendar_mod
from .layers import translate as translate_mod
from .layers import activity as activity_mod
from .layers import meeting_notes as meeting_mod
from .layers import privacy_dash as privacy_mod
from .layers import focus as focus_mod
from .layers import cluster as cluster_mod
from .layers import federation as federation_mod
from .layers import handoff as handoff_mod
from .layers import live_activities as live_mod
from .layers import prefetch as prefetch_mod
from .layers import time_travel as time_travel_mod
from .layers import hpc as hpc_mod
from .layers import quantum as quantum_mod
from .layers import datacenter as datacenter_mod
from .layers.logging_config import setup_logging

# Middleware (single-responsibility ognuno)
from .middleware.rate_limit import RateLimitMiddleware
from .middleware.request_id import RequestIDMiddleware
from .middleware.access_log import AccessLogMiddleware

# Init logging strutturato JSON appena importa main (prima di qualsiasi log)
setup_logging()

# ─── Costanti ─────────────────────────────────────────────────────────────
SOLEM_VERSION = "0.1.0-step0"
MANIFEST_FILE = Path("/etc/solem/manifest.json")
GAVIO_API = os.environ.get("GAVIO_API_URL", "http://127.0.0.1:8000")

# ─── Modelli Pydantic (schema AI-readable) ────────────────────────────────


class HealthStatus(BaseModel):
    status: Literal["ok", "degraded", "down"]
    version: str
    timestamp: str


class ServiceStatus(BaseModel):
    name: str
    active: bool
    sub_state: str | None = None


class LayerStatus(BaseModel):
    layer: str
    name: str
    status: Literal["stub", "partial", "active"]
    description: str


class SolemManifest(BaseModel):
    name: str = "SOLEM"
    version: str
    description: str
    primary_ai: str
    step: int
    profile: str = Field("minimal", description="minimal/developer/creator/server/desktop")
    layers: list[LayerStatus]
    services: dict[str, str]
    runtime: dict[str, object]
    modules: dict[str, bool] = Field(default_factory=dict, description="Moduli opt-in attivi/disabili")


class Capability(BaseModel):
    id: str = Field(..., description="ID univoco capability, formato 'domain.action'")
    name: str
    description: str
    permission_required: str = "user"
    invokable: bool = False
    source: Literal["solem", "gavio", "extension"]


class CapabilitiesResponse(BaseModel):
    total: int
    capabilities: list[Capability]


class IdentityStub(BaseModel):
    user_id: str
    name: str
    email: str
    roles: list[str]
    note: str = "Stub Step 0. L1 Identity Engine completo arriverà Step 2."


# ─── Pairing (mesh + zero-trust device onboarding) ────────────────────────


class PairingStart(BaseModel):
    pin: str = Field(..., description="PIN BBM-style 8-hex, scade in 10 minuti")
    expires_at: str = Field(..., description="ISO timestamp scadenza")
    coordinator_endpoint: str = Field(..., description="endpoint:porta del coordinator mesh")
    instructions: str


class PairingConfirmRequest(BaseModel):
    pin: str = Field(..., min_length=8, max_length=8)
    device_name: str = Field(..., min_length=1, max_length=64)
    device_pubkey_wg: str = Field(..., description="Chiave pubblica WireGuard del device")
    device_pubkey_mtls: str | None = Field(None, description="CSR per cert mTLS")


class PairingConfirmResponse(BaseModel):
    device_id: str
    assigned_ip: str = Field(..., description="IP nella subnet mesh, es. 10.42.0.42/32")
    coordinator_pubkey_wg: str
    ca_cert_pem: str | None = Field(None, description="CA cert per validare server mTLS")
    client_cert_pem: str | None = Field(None, description="Cert client mTLS firmato")
    mesh_subnet: str = "10.42.0.0/24"
    dns_server: str = "10.42.0.1"


# ─── App ──────────────────────────────────────────────────────────────────

app = FastAPI(
    title="SOLEM API",
    version=SOLEM_VERSION,
    description=(
        "API di sistema di SOLEM — l'OS AI-native che ospita GAVIO e (in "
        "futuro) altre AI. Progettata per essere consumata da AI prima che "
        "da umani: schemi JSON strutturati, errori machine-readable, "
        "OpenAPI completo, output deterministici."
    ),
)

# ── Middleware stack (ordine: ultimo aggiunto = primo eseguito) ──
# 1. RequestID (più esterno: l'ID deve esserci anche se rate limit blocca)
# 2. AccessLog (logga prima del rate-limit-block per visibilità)
# 3. RateLimit (più interno: nega prima di hit l'app)
app.add_middleware(RateLimitMiddleware)
app.add_middleware(AccessLogMiddleware)
app.add_middleware(RequestIDMiddleware)

# ─── Static UI ───────────────────────────────────────────────────────
# Web dashboard SOLEM servita da "/" — distinta dal frontend GAVIO (:8000).
# File in backend/solem_api/static/.
_STATIC_DIR = Path(__file__).parent / "static"
if _STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")

    @app.get("/", include_in_schema=False)
    async def root() -> FileResponse:
        return FileResponse(_STATIC_DIR / "index.html")

# ─── Layer routers (backend OS reale) ────────────────────────────────
# Ogni layer è un modulo Python isolato che persiste su SQLite (layers/db.py).
# Schema multi-tenant by design: ogni tabella ha user_id, anche se Step 0
# è single-user. Step 2: filtraggio per JWT.
app.include_router(l1_identity.router,    prefix="/solem")
app.include_router(l2_context.router,     prefix="/solem")
app.include_router(l3_events.router,      prefix="/solem")
app.include_router(l4_capabilities.router, prefix="/solem")  # SOSTITUISCE stub vecchio
app.include_router(l5_memory.router,      prefix="/solem")
app.include_router(l6_interop.router,     prefix="/solem")
app.include_router(l7_extensions.router,  prefix="/solem")
app.include_router(agents_mod.router,     prefix="/solem")
app.include_router(users_mod.router,      prefix="/solem")
app.include_router(system_mod.router,     prefix="/solem")
app.include_router(metrics_mod.router,    prefix="/solem")
app.include_router(migrations_mod.router, prefix="/solem")
app.include_router(hal_api_mod.router,    prefix="/solem")
app.include_router(constitution_mod.router, prefix="/solem")
app.include_router(panic_mod.router,        prefix="/solem")
app.include_router(mcp_mod.router,          prefix="/solem")
app.include_router(voice_mod.router,        prefix="/solem")
app.include_router(auth_keys_mod.router,    prefix="/solem")
app.include_router(vector_store_mod.router, prefix="/solem")
app.include_router(federated_mod.router,    prefix="/solem")
app.include_router(crdt_mod.router,         prefix="/solem")
app.include_router(fs_semantic_mod.router,  prefix="/solem")
app.include_router(ai_router_mod.router,    prefix="/solem")
app.include_router(updates_mod.router,      prefix="/solem")
app.include_router(crash_mod.router,        prefix="/solem")
app.include_router(search_mod.router,       prefix="/solem")
app.include_router(marketplace_mod.router,  prefix="/solem")
app.include_router(voice_wake_mod.router,   prefix="/solem")
app.include_router(vision_mod.router,       prefix="/solem")
app.include_router(summarizer_mod.router,   prefix="/solem")
app.include_router(rag_mod.router,          prefix="/solem")
app.include_router(autoheal_mod.router,     prefix="/solem")
app.include_router(organizer_mod.router,    prefix="/solem")
app.include_router(docparse_mod.router,     prefix="/solem")
app.include_router(ai_shell_mod.router,     prefix="/solem")
app.include_router(ai_calendar_mod.router,  prefix="/solem")
app.include_router(translate_mod.router,    prefix="/solem")
app.include_router(activity_mod.router,     prefix="/solem")
app.include_router(meeting_mod.router,      prefix="/solem")
app.include_router(privacy_mod.router,      prefix="/solem")
app.include_router(focus_mod.router,        prefix="/solem")
app.include_router(cluster_mod.router,      prefix="/solem")
app.include_router(federation_mod.router,   prefix="/solem")
app.include_router(handoff_mod.router,      prefix="/solem")
app.include_router(live_mod.router,         prefix="/solem")
app.include_router(prefetch_mod.router,     prefix="/solem")
app.include_router(time_travel_mod.router,  prefix="/solem")
app.include_router(hpc_mod.router,          prefix="/solem")
app.include_router(quantum_mod.router,      prefix="/solem")
app.include_router(datacenter_mod.router,   prefix="/solem")
# health_mod ha prefix /health (sub /live /ready /deep), NON sotto /solem
app.include_router(health_mod.router)

# Auto-apply pending migrations al boot (no-op se DB nuovo)
@app.on_event("startup")
async def _run_migrations() -> None:
    migrations_mod.auto_apply_at_startup()


# ─── Endpoints ────────────────────────────────────────────────────────────


@app.get("/health", response_model=HealthStatus, tags=["meta"])
async def health() -> HealthStatus:
    return HealthStatus(
        status="ok",
        version=SOLEM_VERSION,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.get("/solem/manifest", response_model=SolemManifest, tags=["solem"])
async def manifest() -> SolemManifest:
    """Manifest live di SOLEM: identità + stato dei layer + servizi attivi."""
    static = _load_static_manifest()
    services = _check_systemd_services([
        "gavio", "ollama", "docker", "solem-api", "caddy",
        "fail2ban", "auditd", "wireguard-wg-solem",
    ])
    return SolemManifest(
        version=static.get("version", SOLEM_VERSION),
        description=static.get("description", "OS AI-native"),
        primary_ai=static.get("primary_ai", "gavio"),
        step=static.get("step", 0),
        profile=_read_profile(),
        layers=_layer_status(),
        services=static.get("services", {}),
        runtime={
            "uptime_seconds": _read_uptime(),
            "active_services": [s.name for s in services if s.active],
            "memory_mb": _read_memory_mb(),
            "disk_free_gb": _read_disk_free_gb("/"),
        },
        modules=_modules_status(),
    )


def _read_profile() -> str:
    """Legge /etc/solem/profile (scritto da solem-profiles.nix)."""
    try:
        return Path("/etc/solem/profile").read_text().strip()
    except OSError:
        return "minimal"


def _modules_status() -> dict[str, bool]:
    """Mappa moduli opt-in → attivo (basata su servizi systemd attivi)."""
    services = {s.name: s.active for s in _check_systemd_services([
        "gavio", "ollama", "docker", "solem-api", "solem-backup.timer",
        "caddy", "wireguard-wg-solem", "fail2ban", "auditd",
    ])}
    return {
        "gavio":           services.get("gavio", False),
        "ollama":          services.get("ollama", False),
        "docker":          services.get("docker", False),
        "solem-api":       services.get("solem-api", False),
        "backup-timer":    services.get("solem-backup.timer", False),
        "zero-trust":      services.get("caddy", False),
        "mesh":            services.get("wireguard-wg-solem", False),
        "fail2ban":        services.get("fail2ban", False),
        "audit":           services.get("auditd", False),
    }


# NB: /solem/capabilities è ora servito dal router L4 in layers/capabilities.py
# (registry dichiarativo + invoke + filtri). Lo stub vecchio è stato rimosso.


# NB: l'endpoint /solem/identity/me è ora servito da layers/identity.py
# (versione SQLite-backed, multi-sezione, versionata). Stub rimosso.


# ─── Pairing endpoints (mesh device onboarding) ───────────────────────────
# Step 0: storage in-memory (perso al restart). Step 2: persiste su Supabase.

_PAIRING_PENDING: dict[str, dict] = {}
_PAIRED_DEVICES: dict[str, dict] = {}
_NEXT_PEER_OCTET = 10  # 10.42.0.10, .11, ... ; .1 = coordinator


@app.post("/solem/pairing/start", response_model=PairingStart, tags=["pairing"])
async def pairing_start() -> PairingStart:
    """Genera un PIN BBM-style per pairing nuovo device.

    Il PIN scade in 10 minuti. Il device deve chiamare /pairing/confirm
    entro la scadenza con il proprio nome + pubkey WireGuard.
    """
    pin = secrets.token_hex(4).upper()  # 8 hex chars, BBM-style
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)
    _PAIRING_PENDING[pin] = {"expires_at": expires}

    return PairingStart(
        pin=pin,
        expires_at=expires.isoformat(),
        coordinator_endpoint=os.environ.get("SOLEM_COORDINATOR_ENDPOINT", "solem.local:51820"),
        instructions=(
            f"Sul nuovo device, esegui:\n"
            f"  solem-join --pin {pin} --coordinator solem.local:8001\n"
            f"o usa l'app companion → 'Aggiungi questo device' → inserisci PIN."
        ),
    )


@app.post("/solem/pairing/confirm", response_model=PairingConfirmResponse, tags=["pairing"])
async def pairing_confirm(req: PairingConfirmRequest) -> PairingConfirmResponse:
    """Completa il pairing del nuovo device.

    Verifica PIN, assegna IP nella subnet mesh, ritorna config WireGuard
    + cert mTLS (se zero-trust attivo). Il PIN è consumato dopo l'uso.
    """
    global _NEXT_PEER_OCTET

    pending = _PAIRING_PENDING.get(req.pin)
    if not pending:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail={"code": "pin_unknown", "message": "PIN sconosciuto o già usato"})

    if datetime.now(timezone.utc) > pending["expires_at"]:
        del _PAIRING_PENDING[req.pin]
        raise HTTPException(status.HTTP_410_GONE, detail={"code": "pin_expired", "message": "PIN scaduto, richiedine uno nuovo"})

    # Consuma il PIN (one-shot)
    del _PAIRING_PENDING[req.pin]

    # Assegna IP mesh
    octet = _NEXT_PEER_OCTET
    _NEXT_PEER_OCTET += 1
    assigned_ip = f"10.42.0.{octet}/32"
    device_id = secrets.token_urlsafe(16)

    _PAIRED_DEVICES[device_id] = {
        "name": req.device_name,
        "wg_pubkey": req.device_pubkey_wg,
        "assigned_ip": assigned_ip,
        "paired_at": datetime.now(timezone.utc).isoformat(),
    }

    # Pubkey coordinator (letta dal filesystem se mesh attiva)
    coord_pubkey = _read_coordinator_pubkey()

    # CA cert (se zero-trust attivo)
    ca_cert = _read_ca_cert()

    return PairingConfirmResponse(
        device_id=device_id,
        assigned_ip=assigned_ip,
        coordinator_pubkey_wg=coord_pubkey,
        ca_cert_pem=ca_cert,
        client_cert_pem=None,  # Step 1+: firma CSR del device qui
    )


@app.get("/solem/pairing/devices", tags=["pairing"])
async def pairing_list_devices() -> dict:
    """Lista device paired (solo per debug/UI Step 0)."""
    return {
        "total": len(_PAIRED_DEVICES),
        "devices": [
            {"id": k, **v} for k, v in _PAIRED_DEVICES.items()
        ],
    }


# ─── Helpers ──────────────────────────────────────────────────────────────


def _load_static_manifest() -> dict:
    if not MANIFEST_FILE.exists():
        return {}
    try:
        return json.loads(MANIFEST_FILE.read_text())
    except json.JSONDecodeError:
        return {}


def _layer_status() -> list[LayerStatus]:
    return [
        LayerStatus(layer="L1", name="Identity Engine", status="stub",
                    description="Placeholder hardcoded; estrazione Step 2"),
        LayerStatus(layer="L2", name="Context Engine", status="stub",
                    description="Snapshot 5min — Step 2"),
        LayerStatus(layer="L3", name="Orchestration + Event Bus", status="partial",
                    description="Orchestrator vive in GAVIO; bus dedicato Step 2"),
        LayerStatus(layer="L4", name="Capabilities Pool", status="partial",
                    description="9 nodi GAVIO + native SOLEM"),
        LayerStatus(layer="L5", name="Memory & Knowledge", status="partial",
                    description="memory.py + wiki.py in GAVIO; 3 livelli Step 3"),
        LayerStatus(layer="L6", name="Interop", status="stub",
                    description="Email/calendar/IoT — Step 3"),
        LayerStatus(layer="L7", name="Extensions Marketplace", status="stub",
                    description="Plugin loader — Step 4+"),
    ]


def _check_systemd_services(names: list[str]) -> list[ServiceStatus]:
    out: list[ServiceStatus] = []
    systemctl = shutil.which("systemctl")
    if not systemctl:
        return out
    for n in names:
        try:
            r = subprocess.run(
                [systemctl, "is-active", n],
                capture_output=True, text=True, timeout=2, check=False,
            )
            state = r.stdout.strip() or "unknown"
            out.append(ServiceStatus(name=n, active=(state == "active"), sub_state=state))
        except subprocess.SubprocessError:
            out.append(ServiceStatus(name=n, active=False, sub_state="error"))
    return out


def _read_uptime() -> int:
    try:
        return int(float(Path("/proc/uptime").read_text().split()[0]))
    except (OSError, ValueError):
        return 0


def _read_memory_mb() -> int:
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                return int(line.split()[1]) // 1024
    except OSError:
        pass
    return 0


def _read_disk_free_gb(path: str) -> int:
    try:
        usage = shutil.disk_usage(path)
        return usage.free // (1024**3)
    except OSError:
        return 0


def _native_capabilities() -> list[Capability]:
    return [
        Capability(id="solem.system.status", name="System status",
                   description="Stato runtime SOLEM (servizi, risorse)",
                   permission_required="user", invokable=True, source="solem"),
        Capability(id="solem.identity.read", name="Read identity",
                   description="Leggi identità utente corrente",
                   permission_required="user", invokable=True, source="solem"),
        Capability(id="solem.capabilities.discover", name="Discover capabilities",
                   description="Lista capabilities disponibili nel sistema",
                   permission_required="user", invokable=True, source="solem"),
    ]


def _read_coordinator_pubkey() -> str:
    """Pubkey WireGuard del coordinator (generata da solem-mesh.nix)."""
    pub = Path("/var/lib/wireguard/wg-solem.pub")
    if pub.exists():
        return pub.read_text().strip()
    return ""


def _read_ca_cert() -> str | None:
    """CA cert PEM (generata da solem-zero-trust.nix)."""
    ca = Path("/var/lib/solem-ca/ca.crt")
    if ca.exists():
        try:
            return ca.read_text()
        except PermissionError:
            return None
    return None


async def _gavio_capabilities() -> list[Capability]:
    """Discovery automatica: prova a leggere GAVIO OpenAPI per estrarre i suoi
    endpoint come capabilities. Fallback silenzioso se GAVIO è giù."""
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.get(f"{GAVIO_API}/openapi.json")
            if r.status_code != 200:
                return []
            spec = r.json()
    except (httpx.HTTPError, json.JSONDecodeError):
        return []

    caps: list[Capability] = []
    for path, methods in spec.get("paths", {}).items():
        for method, op in methods.items():
            if method.upper() not in {"GET", "POST", "PUT", "DELETE", "PATCH"}:
                continue
            op_id = op.get("operationId") or f"{method}_{path}"
            cap_id = f"gavio.{op_id.lower()}"
            caps.append(Capability(
                id=cap_id,
                name=op.get("summary") or op_id,
                description=op.get("description") or f"{method.upper()} {path}",
                permission_required="user",
                invokable=True,
                source="gavio",
            ))
    return caps
