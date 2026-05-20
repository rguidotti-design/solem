"""REQUEST ID — middleware FastAPI: header X-Request-ID per tracing.

Single responsibility: SOLO assegnare/propagare request_id. Niente altro.

Usa header inbound se presente (proxy/load balancer), altrimenti genera
uuid4. Espone l'ID anche come `request.state.request_id` per logging.
"""
from __future__ import annotations

import uuid

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

HEADER = "X-Request-ID"


class RequestIDMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next):
        rid = request.headers.get(HEADER) or uuid.uuid4().hex
        request.state.request_id = rid
        response = await call_next(request)
        response.headers[HEADER] = rid
        return response
