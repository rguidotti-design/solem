"""VPN STATUS — verifica stato doppia VPN runtime (mesh + tunnel esterno).

Single responsibility: SOLO ispezione delle interfacce WireGuard `wg-solem`
(layer 1 mesh) e `wg-solem-out` (layer 2 tunnel esterno) tramite `wg show`.
Niente provisioning (è nei moduli NixOS).

Endpoint:
  GET /vpn/status     — stato complessivo entrambi i layer
  GET /vpn/peers      — peers attivi sul mesh
  GET /vpn/leak-check — verifica DNS leak (è dietro il tunnel?)
"""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import httpx
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/vpn", tags=["vpn-status"])

MESH_IFACE = "wg-solem"
TUNNEL_IFACE = "wg-solem-out"
DOUBLE_VPN_CONFIG = Path("/etc/solem/double-vpn-config.json")


class InterfaceStatus(BaseModel):
    iface: str
    up: bool
    public_key: str | None = None
    listen_port: int | None = None
    peers: int = 0
    rx_bytes: int = 0
    tx_bytes: int = 0


class VpnStatus(BaseModel):
    layer1_mesh: InterfaceStatus
    layer2_tunnel: InterfaceStatus
    double_vpn_active: bool
    config_present: bool


class PeerInfo(BaseModel):
    public_key: str
    endpoint: str | None = None
    allowed_ips: list[str] = Field(default_factory=list)
    latest_handshake_iso: str | None = None
    rx_bytes: int = 0
    tx_bytes: int = 0
    persistent_keepalive_sec: int = 0


# ─── Helpers ──────────────────────────────────────────────────────────


def _wg_show(iface: str) -> dict | None:
    wg = shutil.which("wg")
    if not wg:
        return None
    try:
        r = subprocess.run([wg, "show", iface, "dump"],
                           capture_output=True, text=True, timeout=3, check=False)
        if r.returncode != 0:
            return None
        return _parse_wg_dump(r.stdout)
    except subprocess.SubprocessError:
        return None


def _parse_wg_dump(text: str) -> dict:
    """Format `wg show <iface> dump`:
    Line 1: <privkey> <pubkey> <listen_port> <fwmark>
    Line N: <peer_pubkey> <preshared> <endpoint> <allowed_ips> <handshake_ts> <rx> <tx> <keepalive>
    """
    lines = [l for l in text.strip().splitlines() if l]
    if not lines:
        return {}
    first = lines[0].split("\t")
    out: dict = {
        "pubkey": first[1] if len(first) > 1 else None,
        "listen_port": int(first[2]) if len(first) > 2 and first[2].isdigit() else None,
        "peers": [],
    }
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        out["peers"].append({
            "public_key": parts[0],
            "endpoint": None if parts[2] == "(none)" else parts[2],
            "allowed_ips": parts[3].split(",") if parts[3] else [],
            "latest_handshake_ts": int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0,
            "rx": int(parts[5]) if len(parts) > 5 and parts[5].isdigit() else 0,
            "tx": int(parts[6]) if len(parts) > 6 and parts[6].isdigit() else 0,
            "keepalive": int(parts[7]) if len(parts) > 7 and parts[7].lstrip("-").isdigit() else 0,
        })
    return out


def _iface_status(iface: str) -> InterfaceStatus:
    info = _wg_show(iface)
    if not info:
        return InterfaceStatus(iface=iface, up=False)
    return InterfaceStatus(
        iface=iface,
        up=True,
        public_key=info.get("pubkey"),
        listen_port=info.get("listen_port"),
        peers=len(info.get("peers", [])),
        rx_bytes=sum(p["rx"] for p in info.get("peers", [])),
        tx_bytes=sum(p["tx"] for p in info.get("peers", [])),
    )


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def vpn_health() -> dict:
    return {
        "wg_available": shutil.which("wg") is not None,
        "config_file": str(DOUBLE_VPN_CONFIG),
        "config_present": DOUBLE_VPN_CONFIG.exists(),
    }


@router.get("/status", response_model=VpnStatus)
async def status() -> VpnStatus:
    mesh = _iface_status(MESH_IFACE)
    tunnel = _iface_status(TUNNEL_IFACE)
    config_present = DOUBLE_VPN_CONFIG.exists()
    return VpnStatus(
        layer1_mesh=mesh,
        layer2_tunnel=tunnel,
        double_vpn_active=mesh.up and tunnel.up,
        config_present=config_present,
    )


@router.get("/peers", response_model=list[PeerInfo])
async def peers(iface: str = MESH_IFACE) -> list[PeerInfo]:
    from datetime import datetime, timezone
    info = _wg_show(iface)
    if not info:
        return []
    out: list[PeerInfo] = []
    for p in info.get("peers", []):
        hs_iso = None
        if p["latest_handshake_ts"]:
            hs_iso = datetime.fromtimestamp(p["latest_handshake_ts"], tz=timezone.utc).isoformat()
        out.append(PeerInfo(
            public_key=p["public_key"],
            endpoint=p["endpoint"],
            allowed_ips=p["allowed_ips"],
            latest_handshake_iso=hs_iso,
            rx_bytes=p["rx"],
            tx_bytes=p["tx"],
            persistent_keepalive_sec=p["keepalive"],
        ))
    return out


@router.get("/leak-check", response_model=dict)
async def leak_check() -> dict:
    """Verifica che l'IP esterno passi per il tunnel (NON il tuo IP casa)."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as c:
            r = await c.get("https://ifconfig.me/ip")
            external_ip = r.text.strip() if r.status_code == 200 else "unreachable"
    except httpx.HTTPError as e:
        return {"checked": False, "error": str(e)}

    tunnel = _iface_status(TUNNEL_IFACE)
    return {
        "checked": True,
        "external_ip": external_ip,
        "tunnel_active": tunnel.up,
        "tunnel_peer": tunnel.public_key,
        "interpretation": (
            "Se tunnel è up, external_ip DEVE essere quello del peer esterno, "
            "non il tuo IP residenziale. Verifica con `ip route get 8.8.8.8`."
        ),
    }
