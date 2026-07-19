"""Kubernetes API access: in-cluster ServiceAccount auth, node listing, TTL cache.

RBAC grants only `list` on `nodes`. Calls use a short timeout so a slow or
unreachable API server degrades /nodes (503) without affecting readiness.
"""

import logging
import threading
import time
from dataclasses import dataclass
from typing import Optional

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException

from .metrics import kubernetes_api_failures

logger = logging.getLogger("node_api.k8s")


class KubernetesUnavailableError(Exception):
    """Raised when node information cannot be retrieved."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass
class NodeInfo:
    name: str
    ready: bool
    roles: list
    kubelet_version: str
    current_node: bool

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "ready": self.ready,
            "roles": self.roles,
            "kubelet_version": self.kubelet_version,
            "current_node": self.current_node,
        }


def _node_roles(labels: dict) -> list:
    prefix = "node-role.kubernetes.io/"
    roles = sorted(k[len(prefix):] for k in (labels or {}) if k.startswith(prefix))
    return roles or ["worker"]


def _node_ready(node) -> bool:
    for cond in (node.status.conditions or []):
        if cond.type == "Ready":
            return cond.status == "True"
    return False


class NodeLister:
    """Lists cluster nodes with a small TTL cache to bound API load."""

    def __init__(self, timeout_seconds: int, cache_ttl_seconds: int, node_name: str) -> None:
        self._timeout = timeout_seconds
        self._ttl = cache_ttl_seconds
        self._node_name = node_name
        self._lock = threading.Lock()
        self._cached: Optional[list] = None
        self._cached_at: float = 0.0
        self._api: Optional[client.CoreV1Api] = None

    def _core_api(self) -> client.CoreV1Api:
        if self._api is None:
            try:
                config.load_incluster_config()
            except config.ConfigException:
                # Local development fallback only; in-cluster is the normal path.
                try:
                    config.load_kube_config()
                except config.ConfigException as exc:
                    raise KubernetesUnavailableError("no_kubernetes_configuration") from exc
            self._api = client.CoreV1Api()
        return self._api

    def list_nodes(self) -> dict:
        now = time.monotonic()
        with self._lock:
            if self._cached is not None and (now - self._cached_at) < self._ttl:
                return {"nodes": self._cached, "count": len(self._cached), "cached": True}

        try:
            api = self._core_api()
            result = api.list_node(_request_timeout=self._timeout)
        except KubernetesUnavailableError as exc:
            kubernetes_api_failures.labels(reason=exc.reason).inc()
            logger.error("kubernetes api unavailable", extra={"reason": exc.reason})
            raise
        except ApiException as exc:
            reason = f"api_error_{exc.status}"
            kubernetes_api_failures.labels(reason=reason).inc()
            logger.error(
                "kubernetes api error",
                extra={"reason": reason, "status": exc.status},
            )
            raise KubernetesUnavailableError(reason) from exc
        except Exception as exc:  # timeout, connection, TLS, DNS errors
            reason = type(exc).__name__
            kubernetes_api_failures.labels(reason=reason).inc()
            logger.error("kubernetes api call failed", extra={"reason": reason})
            raise KubernetesUnavailableError(reason) from exc

        nodes = [
            NodeInfo(
                name=item.metadata.name,
                ready=_node_ready(item),
                roles=_node_roles(item.metadata.labels),
                kubelet_version=item.status.node_info.kubelet_version,
                current_node=(item.metadata.name == self._node_name),
            ).to_dict()
            for item in result.items
        ]
        with self._lock:
            self._cached = nodes
            self._cached_at = time.monotonic()
        return {"nodes": nodes, "count": len(nodes), "cached": False}
