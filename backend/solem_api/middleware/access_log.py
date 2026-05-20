"""ACCESS LOG — middleware JSON structured log (stdlib).

Single responsibility: SOLO log accessi HTTP. Niente trace, niente metriche.

Output stdout in JSON one-line per request: timestamp + method + path +
status + duration_ms + request_id + client_ip + user_agent.

Si integra con journald (systemd) → JSON resta navigabile via journalctl
-u solem-api -o cat | jq.
"""
from __future__ import annotations

import json
import logging
import sys
import time
from datetime import datetime, timezone

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

_logger = logging.getLogger("solem.access")
if not _logger.handlers:
    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(logging.Formatter("%(message)s"))
    _logger.addHandler(h)
    _logger.setLevel(logging.INFO)
    _logger.propagate = False


class AccessLogMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next):
        t0 = time.perf_counter()
        response = await call_next(request)
        dt = (time.perf_counter() - t0) * 1000.0

        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": "info",
            "kind": "access",
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "duration_ms": round(dt, 2),
            "request_id": getattr(request.state, "request_id", None),
            "client_ip": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent"),
        }
        _logger.info(json.dumps(record, ensure_ascii=False))
        return response
