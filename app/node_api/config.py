"""Application configuration loaded from environment variables.

Non-secret operational values come from a ConfigMap; API_TOKEN comes from a
Kubernetes Secret (materialized by External Secrets Operator in AWS).
Authentication for /nodes is always required and is intentionally not
configurable (fail-closed when the token is absent).
"""

import os
from dataclasses import dataclass, field


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name, "")
    try:
        return int(raw)
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    app_env: str = field(default_factory=lambda: os.getenv("APP_ENV", "local"))
    log_level: str = field(default_factory=lambda: os.getenv("LOG_LEVEL", "INFO"))
    request_timeout_seconds: int = field(
        default_factory=lambda: _int_env("KUBERNETES_REQUEST_TIMEOUT_SECONDS", 2)
    )
    nodes_cache_ttl_seconds: int = field(
        default_factory=lambda: _int_env("NODES_CACHE_TTL_SECONDS", 10)
    )
    node_name: str = field(default_factory=lambda: os.getenv("NODE_NAME", ""))
    api_token: str = field(default_factory=lambda: os.getenv("API_TOKEN", ""))
    metrics_port: int = field(default_factory=lambda: _int_env("METRICS_PORT", 9000))


def load_settings() -> Settings:
    return Settings()
