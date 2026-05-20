"""LOGGING CONFIG — formatter JSON strutturato stdlib.

Single responsibility: SOLO formattare i log in JSON one-line.
Nessun handler custom, nessun trasporto remoto.

Usage:
    from .layers.logging_config import setup_logging
    setup_logging()  # chiamato una volta da main.py al boot

Output: stdout (catturato da journald in systemd). Format:
    {"ts":"2026-05-20T...","level":"info","logger":"solem.x","msg":"...","extra":...}
"""
from __future__ import annotations

import json
import logging
import os
import sys
from datetime import datetime, timezone

LOG_LEVEL = os.environ.get("SOLEM_LOG_LEVEL", "INFO").upper()


class JSONFormatter(logging.Formatter):
    """Formatter one-line JSON: ts/level/logger/msg + extra fields."""

    # Campi standard di LogRecord che NON vogliamo duplicare in extra
    _STD_FIELDS = {
        "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
        "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
        "created", "msecs", "relativeCreated", "thread", "threadName",
        "processName", "process", "taskName", "message",
    }

    def format(self, record: logging.LogRecord) -> str:
        payload: dict = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)

        for k, v in record.__dict__.items():
            if k not in self._STD_FIELDS and not k.startswith("_"):
                try:
                    json.dumps(v)
                    payload[k] = v
                except (TypeError, ValueError):
                    payload[k] = repr(v)

        return json.dumps(payload, ensure_ascii=False)


def setup_logging(level: str | None = None) -> None:
    """Configura il root logger con JSONFormatter su stdout. Idempotente."""
    target_level = level or LOG_LEVEL
    root = logging.getLogger()

    # Rimuovi handlers preesistenti per evitare duplicati
    for h in list(root.handlers):
        root.removeHandler(h)

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    root.addHandler(handler)
    root.setLevel(target_level)

    # Silenzia uvicorn access log di default (lo facciamo via middleware)
    logging.getLogger("uvicorn.access").handlers = []
    logging.getLogger("uvicorn.access").propagate = False
