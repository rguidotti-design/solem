"""METRICS — endpoint Prometheus + audit log strutturato.

Espone metriche sistema in formato Prometheus text/plain per scraping da
Grafana/Prometheus. Step 0: counter base + gauge runtime. Step 2+: histograms
latency + counter requests per endpoint.

Endpoint:
  GET  /metrics                — Prometheus text format
  GET  /metrics/audit          — Audit log strutturato (jsonl tail)
"""
from __future__ import annotations

import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Query
from fastapi.responses import PlainTextResponse

from .db import get_conn

router = APIRouter(prefix="/metrics", tags=["metrics"])

AUDIT_LOG = Path("/var/log/solem/audit.jsonl")


def _read_uptime() -> int:
    try:
        return int(float(Path("/proc/uptime").read_text().split()[0]))
    except (OSError, ValueError):
        return 0


def _read_meminfo() -> dict[str, int]:
    try:
        info = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[0].endswith(":"):
                key = parts[0].rstrip(":")
                try:
                    info[key] = int(parts[1])
                except ValueError:
                    pass
        return info
    except OSError:
        return {}


def _read_loadavg() -> tuple[float, float, float]:
    try:
        parts = Path("/proc/loadavg").read_text().split()
        return float(parts[0]), float(parts[1]), float(parts[2])
    except (OSError, ValueError, IndexError):
        return 0.0, 0.0, 0.0


def _db_counts() -> dict[str, int]:
    """Conteggi righe per tabella principali."""
    try:
        c = get_conn()
        tables = ["identities", "context_snapshots", "events", "solem_memory",
                  "user_universe_memory", "paired_devices", "users", "sessions"]
        counts = {}
        for t in tables:
            try:
                r = c.execute(f"SELECT COUNT(*) FROM {t}").fetchone()
                counts[t] = r[0]
            except Exception:
                counts[t] = 0
        return counts
    except Exception:
        return {}


@router.get("", response_class=PlainTextResponse)
async def metrics() -> str:
    """Prometheus text format. Scrape ogni 15-60s da Prometheus/Grafana."""
    lines = []

    # ── Uptime
    uptime = _read_uptime()
    lines.append("# HELP solem_uptime_seconds Process uptime in seconds.")
    lines.append("# TYPE solem_uptime_seconds counter")
    lines.append(f"solem_uptime_seconds {uptime}")

    # ── Memory
    meminfo = _read_meminfo()
    if "MemTotal" in meminfo:
        lines.append("# HELP solem_memory_total_bytes Total system memory in bytes.")
        lines.append("# TYPE solem_memory_total_bytes gauge")
        lines.append(f"solem_memory_total_bytes {meminfo['MemTotal'] * 1024}")
    if "MemAvailable" in meminfo:
        lines.append("# HELP solem_memory_available_bytes Available memory in bytes.")
        lines.append("# TYPE solem_memory_available_bytes gauge")
        lines.append(f"solem_memory_available_bytes {meminfo['MemAvailable'] * 1024}")

    # ── Load average
    l1, l5, l15 = _read_loadavg()
    lines.append("# HELP solem_load_average System load average.")
    lines.append("# TYPE solem_load_average gauge")
    lines.append(f"solem_load_average{{period=\"1m\"}} {l1}")
    lines.append(f"solem_load_average{{period=\"5m\"}} {l5}")
    lines.append(f"solem_load_average{{period=\"15m\"}} {l15}")

    # ── Disk
    try:
        usage = shutil.disk_usage("/")
        lines.append("# HELP solem_disk_total_bytes Total disk space root partition.")
        lines.append("# TYPE solem_disk_total_bytes gauge")
        lines.append(f"solem_disk_total_bytes {usage.total}")
        lines.append("# HELP solem_disk_free_bytes Free disk space root partition.")
        lines.append("# TYPE solem_disk_free_bytes gauge")
        lines.append(f"solem_disk_free_bytes {usage.free}")
    except OSError:
        pass

    # ── DB row counts
    counts = _db_counts()
    if counts:
        lines.append("# HELP solem_db_rows Number of rows per table.")
        lines.append("# TYPE solem_db_rows gauge")
        for table, count in counts.items():
            lines.append(f"solem_db_rows{{table=\"{table}\"}} {count}")

    # ── Build info (constant gauge with labels)
    lines.append("# HELP solem_build_info Build/version info.")
    lines.append("# TYPE solem_build_info gauge")
    lines.append("solem_build_info{version=\"0.1.0-step0\",step=\"0\"} 1")

    lines.append("")  # trailing newline
    return "\n".join(lines)


@router.get("/audit")
async def audit_tail(
    limit: int = Query(100, ge=1, le=1000),
    topic: str | None = Query(None, description="filtra topic prefix"),
) -> dict:
    """Ultimi N record audit (eventi bus L3) come stream JSON."""
    try:
        c = get_conn()
        if topic:
            rows = c.execute(
                "SELECT ts, source, topic, payload FROM events WHERE topic LIKE ? ORDER BY ts DESC LIMIT ?",
                (topic + "%", limit),
            ).fetchall()
        else:
            rows = c.execute(
                "SELECT ts, source, topic, payload FROM events ORDER BY ts DESC LIMIT ?",
                (limit,),
            ).fetchall()
        events = [
            {
                "ts": r["ts"],
                "source": r["source"],
                "topic": r["topic"],
                "payload": json.loads(r["payload"]),
            }
            for r in rows
        ]
        return {"total": len(events), "events": events}
    except Exception as e:
        return {"error": str(e), "total": 0, "events": []}
