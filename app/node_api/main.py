"""Application entrypoint and route definitions.

Probe mapping:
  livenessProbe  -> /health/live   (process alive)
  readinessProbe -> /health/ready  (startup + init complete)
  public summary -> /health        (minimal, non-sensitive)
  Prometheus     -> /metrics on the dedicated metrics port

A Kubernetes API outage never makes the pod unready; /nodes returns a
controlled 503 instead.
"""

import logging
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator

from .auth import require_token
from .config import load_settings
from .k8s import KubernetesUnavailableError, NodeLister
from .logging_setup import configure_logging, request_id_var
from .metrics import start_metrics_server

logger = logging.getLogger("node_api")


def create_app(start_metrics: bool = True) -> FastAPI:
    settings = load_settings()
    configure_logging(settings.log_level, settings.app_env)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if start_metrics:
            start_metrics_server(settings.metrics_port)
        app.state.ready = True
        logger.info("startup complete", extra={"node_name": settings.node_name or None})
        yield
        app.state.ready = False
        logger.info("shutdown complete")

    app = FastAPI(title="node-api", docs_url=None, redoc_url=None, lifespan=lifespan)
    app.state.settings = settings
    app.state.ready = False
    app.state.node_lister = NodeLister(
        timeout_seconds=settings.request_timeout_seconds,
        cache_ttl_seconds=settings.nodes_cache_ttl_seconds,
        node_name=settings.node_name,
    )

    # Request metrics are collected here but exposed only via the dedicated
    # metrics port, never on the application port.
    Instrumentator(excluded_handlers=["/health/live", "/health/ready"]).instrument(app)

    @app.middleware("http")
    async def request_logging(request: Request, call_next):
        request_id_var.set(str(uuid.uuid4()))
        started = time.perf_counter()
        response = await call_next(request)
        latency_ms = round((time.perf_counter() - started) * 1000, 2)
        if request.url.path not in ("/health/live", "/health/ready"):
            logger.info(
                "request",
                extra={
                    "path": request.url.path,
                    "method": request.method,
                    "status_code": response.status_code,
                    "latency_ms": latency_ms,
                },
            )
        response.headers["X-Request-ID"] = request_id_var.get()
        return response

    @app.exception_handler(Exception)
    async def unhandled_exception(request: Request, exc: Exception):
        # Never leak stack traces or internals to clients.
        logger.error("unhandled error", extra={"path": request.url.path}, exc_info=exc)
        return JSONResponse(status_code=500, content={"error": "internal_error"})

    @app.get("/health")
    async def health():
        return {"status": "ok", "environment": settings.app_env}

    @app.get("/health/live")
    async def health_live():
        return {"status": "alive"}

    @app.get("/health/ready")
    async def health_ready(request: Request):
        if request.app.state.ready:
            return {"status": "ready"}
        return JSONResponse(status_code=503, content={"status": "not_ready"})

    @app.get("/nodes", dependencies=[Depends(require_token)])
    async def nodes(request: Request):
        try:
            return request.app.state.node_lister.list_nodes()
        except KubernetesUnavailableError:
            return JSONResponse(
                status_code=503,
                content={"error": "kubernetes_api_unavailable"},
            )

    return app


app = create_app()
