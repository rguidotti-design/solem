"""DATACENTER — inventory + power management nodi via IPMI / Redfish.

Single responsibility: SOLO API per:
  - inventory dei nodi (BMC IP + ruolo + status power)
  - on/off/cycle remoto via ipmitool o Redfish
  - sensori (temp, fan, voltaggio)
  - SEL (System Event Log)

Niente provisioning (PXE/iPXE in modulo separato futuro).
Niente UI rack visual (PWA opzionale).

Provider abstraction:
  - ipmi    → `ipmitool -H <bmc> -U <user> -P <pass>`
  - redfish → HTTP REST `/redfish/v1/...`
  - mock    → inventory statico (test/dev)

Step 0: scaffold. Credenziali BMC in /var/lib/solem-secrets/bmc/*.json,
mode 0600 root. Mai in clear text negli endpoint.

ADR-023 → Data center come capability scalabile. Da single-box a 100+
nodi. GAVIO può chiedere "spegni il rack 4" → SOLEM esegue IPMI cycle
sui nodi del rack.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/datacenter", tags=["datacenter"])

INVENTORY_FILE = Path("/var/lib/solem/datacenter_inventory.json")
BMC_CREDS_DIR = Path("/var/lib/solem-secrets/bmc")


class Node(BaseModel):
    name: str
    bmc_ip: str
    bmc_protocol: Literal["ipmi", "redfish", "mock"] = "ipmi"
    rack: str = "default"
    rack_unit: int = 1
    role: Literal["compute", "storage", "gpu", "network", "controller"] = "compute"
    tags: list[str] = Field(default_factory=list)
    power_state: Literal["on", "off", "unknown"] = "unknown"
    last_seen_iso: str | None = None


class PowerAction(BaseModel):
    action: Literal["on", "off", "cycle", "reset", "status"] = "status"


class Sensor(BaseModel):
    name: str
    value: float
    unit: str
    status: Literal["ok", "warning", "critical", "unknown"] = "unknown"


class RackSummary(BaseModel):
    rack: str
    total_nodes: int
    powered_on: int
    by_role: dict[str, int]


# ─── Storage helpers ──────────────────────────────────────────────────


def _load_inventory() -> dict:
    if not INVENTORY_FILE.exists():
        return {"nodes": {}}
    try:
        return json.loads(INVENTORY_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"nodes": {}}


def _save_inventory(state: dict) -> None:
    INVENTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    INVENTORY_FILE.write_text(json.dumps(state, indent=2))


def _bmc_creds(node_name: str) -> dict | None:
    """Legge file JSON {user, password} per il BMC. Mai esposto via API."""
    f = BMC_CREDS_DIR / f"{node_name}.json"
    if not f.exists():
        return None
    try:
        return json.loads(f.read_text())
    except (OSError, json.JSONDecodeError):
        return None


# ─── IPMI driver ──────────────────────────────────────────────────────


def _ipmi_run(node: Node, *args) -> tuple[int, str, str]:
    ipmitool = shutil.which("ipmitool")
    if not ipmitool:
        return -1, "", "ipmitool not installed"
    creds = _bmc_creds(node.name)
    if not creds:
        return -2, "", f"missing credentials at {BMC_CREDS_DIR / (node.name + '.json')}"
    cmd = [ipmitool, "-H", node.bmc_ip,
           "-U", creds.get("user", "admin"),
           "-P", creds.get("password", "admin"),
           *args]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15, check=False)
        return r.returncode, r.stdout, r.stderr
    except subprocess.SubprocessError as e:
        return -3, "", str(e)


def _ipmi_power_action(node: Node, action: str) -> str:
    actions = {"on": "on", "off": "off", "cycle": "cycle", "reset": "reset", "status": "status"}
    if action not in actions:
        raise HTTPException(400, {"code": "invalid_action"})
    rc, out, err = _ipmi_run(node, "chassis", "power", actions[action])
    if rc != 0:
        return f"error: {err}"
    return out.strip() or "ok"


def _ipmi_sensors(node: Node) -> list[Sensor]:
    rc, out, err = _ipmi_run(node, "sensor", "list")
    if rc != 0:
        return []
    sensors: list[Sensor] = []
    for line in out.splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 4:
            continue
        try:
            val = float(parts[1])
        except ValueError:
            continue
        sensors.append(Sensor(
            name=parts[0], value=val, unit=parts[2],
            status="ok" if parts[3] == "ok" else "warning",
        ))
    return sensors[:50]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def dc_health() -> dict:
    inv = _load_inventory()
    return {
        "ipmitool_available": shutil.which("ipmitool") is not None,
        "redfish_available": False,  # implementabile via httpx (Step 1)
        "total_nodes_registered": len(inv.get("nodes", {})),
        "bmc_creds_dir": str(BMC_CREDS_DIR),
        "step": "scaffold (Step 0) — installa solem-datacenter.nix per ipmitool",
    }


@router.post("/nodes", response_model=Node)
async def register_node(node: Node) -> Node:
    inv = _load_inventory()
    node.last_seen_iso = datetime.now(timezone.utc).isoformat()
    inv["nodes"][node.name] = node.model_dump()
    _save_inventory(inv)
    return node


@router.get("/nodes", response_model=list[Node])
async def list_nodes(rack: str | None = None, role: str | None = None) -> list[Node]:
    inv = _load_inventory()
    nodes = [Node(**v) for v in inv["nodes"].values()]
    if rack:
        nodes = [n for n in nodes if n.rack == rack]
    if role:
        nodes = [n for n in nodes if n.role == role]
    return nodes


@router.get("/nodes/{name}", response_model=Node)
async def get_node(name: str) -> Node:
    inv = _load_inventory()
    if name not in inv["nodes"]:
        raise HTTPException(404, {"code": "node_not_found"})
    return Node(**inv["nodes"][name])


@router.post("/nodes/{name}/power", response_model=dict)
async def power(name: str, action: PowerAction) -> dict:
    inv = _load_inventory()
    if name not in inv["nodes"]:
        raise HTTPException(404, {"code": "node_not_found"})
    node = Node(**inv["nodes"][name])
    if node.bmc_protocol == "mock":
        if action.action in ("on", "off"):
            node.power_state = action.action  # type: ignore
            inv["nodes"][name] = node.model_dump()
            _save_inventory(inv)
        return {"node": name, "action": action.action, "result": "mock-ok"}
    if node.bmc_protocol == "ipmi":
        result = _ipmi_power_action(node, action.action)
        return {"node": name, "action": action.action, "result": result}
    raise HTTPException(503, {"code": "protocol_not_supported", "protocol": node.bmc_protocol})


@router.get("/nodes/{name}/sensors", response_model=list[Sensor])
async def sensors(name: str) -> list[Sensor]:
    inv = _load_inventory()
    if name not in inv["nodes"]:
        raise HTTPException(404, {"code": "node_not_found"})
    node = Node(**inv["nodes"][name])
    if node.bmc_protocol == "ipmi":
        return _ipmi_sensors(node)
    if node.bmc_protocol == "mock":
        return [
            Sensor(name="CPU1 Temp", value=42.5, unit="degrees C", status="ok"),
            Sensor(name="FAN1", value=4200, unit="RPM", status="ok"),
            Sensor(name="PSU1 Power", value=380, unit="W", status="ok"),
        ]
    return []


@router.delete("/nodes/{name}")
async def remove_node(name: str) -> dict:
    inv = _load_inventory()
    if name not in inv["nodes"]:
        raise HTTPException(404, {"code": "node_not_found"})
    del inv["nodes"][name]
    _save_inventory(inv)
    return {"removed": True, "name": name}


@router.get("/racks", response_model=list[RackSummary])
async def racks() -> list[RackSummary]:
    inv = _load_inventory()
    by_rack: dict[str, list[Node]] = {}
    for v in inv["nodes"].values():
        n = Node(**v)
        by_rack.setdefault(n.rack, []).append(n)
    out = []
    for rack_name, nodes in sorted(by_rack.items()):
        roles: dict[str, int] = {}
        for n in nodes:
            roles[n.role] = roles.get(n.role, 0) + 1
        out.append(RackSummary(
            rack=rack_name,
            total_nodes=len(nodes),
            powered_on=sum(1 for n in nodes if n.power_state == "on"),
            by_role=roles,
        ))
    return out
