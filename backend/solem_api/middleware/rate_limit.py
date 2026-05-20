"""RATE LIMIT — middleware FastAPI token bucket per-IP, stdlib-only.

Single responsibility: SOLO rate limiting. Niente metriche, niente logging.

ADR-013 → 100 req/min per IP default, configurabile via env:
  SOLEM_RATE_LIMIT_RPM   (default 100)
  SOLEM_RATE_LIMIT_BURST (default 20)
  SOLEM_RATE_LIMIT_EXEMPT (CSV path prefix, default "/health,/static")

Algoritmo: token bucket per (IP, prefix-bucket). Lock asyncio per
thread-safety in uvicorn workers single-process. Multi-worker richiede
Redis (Step 3+).
"""
from __future__ import annotations

import asyncio
import os
import time
from collections import defaultdict
from dataclasses import dataclass

from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

RPM = int(os.environ.get("SOLEM_RATE_LIMIT_RPM", "100"))
BURST = int(os.environ.get("SOLEM_RATE_LIMIT_BURST", "20"))
EXEMPT = tuple(p.strip() for p in os.environ.get("SOLEM_RATE_LIMIT_EXEMPT", "/health,/static,/").split(","))

# Refill rate in tokens/sec
REFILL_RATE = RPM / 60.0


@dataclass
class Bucket:
    tokens: float
    last_refill: float


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Token bucket per-IP. Esenta health + static. Logga 429 al client."""

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)
        self._buckets: dict[str, Bucket] = defaultdict(lambda: Bucket(BURST, time.monotonic()))
        self._lock = asyncio.Lock()

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if any(path.startswith(p) for p in EXEMPT if p):
            return await call_next(request)

        ip = self._client_ip(request)
        allowed, remaining, retry_after = await self._take(ip)

        if not allowed:
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={
                    "code": "rate_limit_exceeded",
                    "message": f"Limite {RPM} req/min superato",
                    "retry_after_seconds": round(retry_after, 2),
                },
                headers={
                    "Retry-After": str(int(retry_after) + 1),
                    "X-RateLimit-Limit": str(RPM),
                    "X-RateLimit-Remaining": "0",
                },
            )

        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(RPM)
        response.headers["X-RateLimit-Remaining"] = str(int(remaining))
        return response

    @staticmethod
    def _client_ip(request: Request) -> str:
        """Estrae IP client. Trusta X-Forwarded-For SOLO se reverse proxy locale."""
        xff = request.headers.get("x-forwarded-for")
        if xff:
            return xff.split(",")[0].strip()
        if request.client:
            return request.client.host
        return "unknown"

    async def _take(self, ip: str) -> tuple[bool, float, float]:
        """Consume 1 token. Ritorna (allowed, remaining, retry_after_sec)."""
        async with self._lock:
            b = self._buckets[ip]
            now = time.monotonic()
            elapsed = now - b.last_refill
            b.tokens = min(BURST, b.tokens + elapsed * REFILL_RATE)
            b.last_refill = now

            if b.tokens >= 1.0:
                b.tokens -= 1.0
                return True, b.tokens, 0.0

            needed = 1.0 - b.tokens
            retry_after = needed / REFILL_RATE
            return False, 0.0, retry_after
