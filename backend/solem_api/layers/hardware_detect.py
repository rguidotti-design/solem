"""HARDWARE DETECT — inventory hardware locale (CPU/GPU/WiFi/storage).

Single responsibility: SOLO leggere /proc, /sys, output `lspci|lsusb|lscpu|
ip link|smartctl` e ritornare un manifest. Niente install driver (sta in
solem-drivers.nix).

Usato da:
  - solem-init per scegliere profile sensato
  - cluster.py per popolare capabilities
  - troubleshooting (cosa abbiamo riconosciuto)
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/hardware", tags=["hardware-detect"])


class CPUInfo(BaseModel):
    model: str = "?"
    cores: int = 1
    threads: int = 1
    arch: str = "x86_64"
    vendor: str = "?"
    mhz: float = 0.0


class GPUInfo(BaseModel):
    vendor: str = "?"
    model: str = "?"
    driver: str | None = None
    kind: str = "none"  # nvidia|amd|intel|integrated|unknown


class MemoryInfo(BaseModel):
    total_gb: float = 0.0
    available_gb: float = 0.0
    swap_total_gb: float = 0.0


class StorageDevice(BaseModel):
    device: str
    size_gb: float
    rotational: bool
    model: str = "?"
    fstype: str | None = None
    mountpoint: str | None = None


class NetworkInterface(BaseModel):
    name: str
    type: str  # ethernet|wifi|loopback|virtual
    mac: str | None = None
    state: str  # up|down


class HWManifest(BaseModel):
    cpu: CPUInfo
    gpus: list[GPUInfo]
    memory: MemoryInfo
    storage: list[StorageDevice]
    network: list[NetworkInterface]
    firmware_needed: list[str] = Field(default_factory=list, description="Pacchetti firmware suggeriti")
    has_tpm: bool = False
    has_secure_boot: bool = False
    detected_at: str


# ─── Detect helpers ───────────────────────────────────────────────────


def _read(path: str) -> str:
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ""


def _cpu() -> CPUInfo:
    info = {"model": "?", "vendor": "?", "mhz": 0.0}
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name") and info["model"] == "?":
                info["model"] = line.split(":", 1)[1].strip()
            elif line.startswith("vendor_id") and info["vendor"] == "?":
                info["vendor"] = line.split(":", 1)[1].strip()
            elif line.startswith("cpu MHz") and info["mhz"] == 0.0:
                try:
                    info["mhz"] = float(line.split(":", 1)[1].strip())
                except (ValueError, IndexError):
                    pass
    except OSError:
        pass
    cores = os.cpu_count() or 1
    return CPUInfo(
        model=info["model"], cores=cores, threads=cores,
        arch=os.uname().machine, vendor=info["vendor"], mhz=info["mhz"],
    )


def _gpus() -> list[GPUInfo]:
    out: list[GPUInfo] = []
    # NVIDIA
    nvidia_smi = shutil.which("nvidia-smi")
    if nvidia_smi:
        try:
            r = subprocess.run(
                [nvidia_smi, "--query-gpu=name,driver_version",
                 "--format=csv,noheader"],
                capture_output=True, text=True, timeout=3, check=False,
            )
            if r.returncode == 0:
                for line in r.stdout.strip().splitlines():
                    parts = [p.strip() for p in line.split(",")]
                    out.append(GPUInfo(
                        vendor="NVIDIA", model=parts[0],
                        driver=parts[1] if len(parts) > 1 else None,
                        kind="nvidia",
                    ))
        except subprocess.SubprocessError:
            pass

    # AMD ROCm
    rocm_smi = shutil.which("rocm-smi")
    if rocm_smi and not out:
        try:
            r = subprocess.run([rocm_smi, "--showproductname"],
                               capture_output=True, text=True, timeout=3, check=False)
            if r.returncode == 0 and "GPU" in r.stdout:
                out.append(GPUInfo(vendor="AMD", model="ROCm GPU", kind="amd"))
        except subprocess.SubprocessError:
            pass

    # Intel via lspci
    lspci = shutil.which("lspci")
    if lspci and not out:
        try:
            r = subprocess.run([lspci], capture_output=True, text=True, timeout=3, check=False)
            for line in r.stdout.splitlines():
                low = line.lower()
                if "vga" in low or "3d" in low or "display" in low:
                    if "intel" in low:
                        out.append(GPUInfo(vendor="Intel", model=line.split(":", 2)[-1].strip(), kind="integrated"))
                    elif "nvidia" in low and not any(g.vendor == "NVIDIA" for g in out):
                        out.append(GPUInfo(vendor="NVIDIA", model=line.split(":", 2)[-1].strip(), kind="nvidia"))
                    elif "amd" in low or "ati" in low or "radeon" in low:
                        out.append(GPUInfo(vendor="AMD", model=line.split(":", 2)[-1].strip(), kind="amd"))
        except subprocess.SubprocessError:
            pass

    if not out:
        out.append(GPUInfo(vendor="?", model="(none detected)", kind="none"))
    return out


def _memory() -> MemoryInfo:
    info = {"MemTotal": 0, "MemAvailable": 0, "SwapTotal": 0}
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            for k in info:
                if line.startswith(k + ":"):
                    info[k] = int(line.split()[1])
    except OSError:
        pass
    return MemoryInfo(
        total_gb=round(info["MemTotal"] / (1024 * 1024), 2),
        available_gb=round(info["MemAvailable"] / (1024 * 1024), 2),
        swap_total_gb=round(info["SwapTotal"] / (1024 * 1024), 2),
    )


def _storage() -> list[StorageDevice]:
    lsblk = shutil.which("lsblk")
    if not lsblk:
        return []
    try:
        import json as _j
        r = subprocess.run([lsblk, "-b", "-J", "-o", "NAME,SIZE,ROTA,MODEL,FSTYPE,MOUNTPOINT,TYPE"],
                           capture_output=True, text=True, timeout=3, check=False)
        if r.returncode != 0:
            return []
        data = _j.loads(r.stdout)
    except (subprocess.SubprocessError, ValueError):
        return []

    out: list[StorageDevice] = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") not in ("disk", "part"):
            continue
        out.append(StorageDevice(
            device=f"/dev/{dev['name']}",
            size_gb=round((dev.get("size", 0) or 0) / (1024**3), 2),
            rotational=dev.get("rota", False),
            model=dev.get("model") or "?",
            fstype=dev.get("fstype"),
            mountpoint=dev.get("mountpoint"),
        ))
    return out


def _network() -> list[NetworkInterface]:
    out: list[NetworkInterface] = []
    sys_net = Path("/sys/class/net")
    if not sys_net.exists():
        return []
    for iface in sys_net.iterdir():
        name = iface.name
        try:
            state = _read(str(iface / "operstate")) or "unknown"
            mac = _read(str(iface / "address")) or None
            # Detect type
            if name == "lo":
                t = "loopback"
            elif (iface / "wireless").exists() or (iface / "phy80211").exists():
                t = "wifi"
            elif (iface / "device").exists():
                t = "ethernet"
            else:
                t = "virtual"
            out.append(NetworkInterface(name=name, type=t, mac=mac, state=state))
        except OSError:
            continue
    return out


def _firmware_needed() -> list[str]:
    """Suggerisce pacchetti firmware proprietari (Broadcom WiFi, Intel iwlwifi)."""
    suggested: list[str] = []
    lspci = shutil.which("lspci")
    lsusb = shutil.which("lsusb")
    lines: list[str] = []
    if lspci:
        try:
            r = subprocess.run([lspci], capture_output=True, text=True, timeout=3, check=False)
            lines.extend(r.stdout.splitlines())
        except subprocess.SubprocessError:
            pass
    if lsusb:
        try:
            r = subprocess.run([lsusb], capture_output=True, text=True, timeout=3, check=False)
            lines.extend(r.stdout.splitlines())
        except subprocess.SubprocessError:
            pass

    low = "\n".join(lines).lower()
    if "broadcom" in low and "wireless" in low:
        suggested.append("broadcom-bt-firmware")
    if "intel" in low and ("wireless" in low or "network" in low):
        suggested.append("linux-firmware (iwlwifi)")
    if "realtek" in low and ("wireless" in low or "rtl" in low):
        suggested.append("rtl-firmware")
    if "nvidia" in low:
        suggested.append("nvidia-x11 (proprietary)")
    if "amd" in low and ("graphics" in low or "vga" in low):
        suggested.append("amdgpu-firmware")

    return sorted(set(suggested))


def _has_tpm() -> bool:
    return Path("/dev/tpm0").exists() or Path("/dev/tpmrm0").exists() or Path("/sys/class/tpm").exists()


def _has_secure_boot() -> bool:
    sb_var = Path("/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c")
    if not sb_var.exists():
        return False
    try:
        # Ultimo byte = 1 se SecureBoot enabled
        return sb_var.read_bytes()[-1] == 1
    except OSError:
        return False


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def hw_health() -> dict:
    return {
        "lspci_available": shutil.which("lspci") is not None,
        "lsblk_available": shutil.which("lsblk") is not None,
        "nvidia_smi_available": shutil.which("nvidia-smi") is not None,
    }


@router.get("/manifest", response_model=HWManifest)
async def manifest() -> HWManifest:
    from datetime import datetime, timezone
    return HWManifest(
        cpu=_cpu(),
        gpus=_gpus(),
        memory=_memory(),
        storage=_storage(),
        network=_network(),
        firmware_needed=_firmware_needed(),
        has_tpm=_has_tpm(),
        has_secure_boot=_has_secure_boot(),
        detected_at=datetime.now(timezone.utc).isoformat(),
    )
