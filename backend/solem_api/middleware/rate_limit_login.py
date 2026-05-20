"""RATE LIMIT LOGIN — middleware specifico per /solem/federation/login.

Single responsibility: SOLO sliding-window rate limit sulle tentativi
login PER USERNAME (oltre al rate limit globale per IP). Protegge da
brute-force su username noti.

Politica:
  - max 5 tentativi per username in 60 sec
  - max 20 tentativi per IP in 60 sec
  - Risposta 429 con Retry-After header
"""
from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque

from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

WINDOW_SEC = 60
MAX_PER_USERNAME = 5
MAX_PER_IP = 20


class LoginRateLimitMiddleware(BaseHTTPMiddleware):
    """Sliding window solo su /solem/federation/login.

    Le altre route passano direttamente al RateLimitMiddleware globale.
    """

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)
        self._by_user: dict[str, deque[float]] = defaultdict(deque)
        self._by_ip: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        # Solo login endpoint
        if path != "/solem/federation/login":
            return await call_next(request)

        # Estrai username (body è JSON)
        try:
            body = await request.body()
            import json
            payload = json.loads(body) if body else {}
            username = payload.get("username", "?")
        except (json.JSONDecodeError, ValueError):
            username = "?"

        ip = request.client.host if request.client else "unknown"
        now = time.monotonic()

        async with self._lock:
            self._prune(self._by_user[username], now)
            self._prune(self._by_ip[ip], now)

            if len(self._by_user[username]) >= MAX_PER_USERNAME:
                retry = WINDOW_SEC - (now - self._by_user[username][0])
                return self._too_many(retry, "username")
            if len(self._by_ip[ip]) >= MAX_PER_IP:
                retry = WINDOW_SEC - (now - self._by_ip[ip][0])
                return self._too_many(retry, "ip")

            self._by_user[username].append(now)
            self._by_ip[ip].append(now)

        # Re-iniettiamo il body perché lo abbiamo già consumato
        request._body = body  # type: ignore[attr-defined]
        return await call_next(request)

    @staticmethod
    def _prune(d: deque[float], now: float) -> None:
        while d and (now - d[0]) > WINDOW_SEC:
            d.popleft()

    @staticmethod
    def _too_many(retry_sec: float, scope: str) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content={
                "code": "login_rate_limit_exceeded",
                "scope": scope,
                "retry_after_seconds": round(max(1.0, retry_sec), 1),
                "hint": "Troppi tentativi login. Aspetta o cambia approccio.",
            },
            headers={"Retry-After": str(int(retry_sec) + 1)},
        )
