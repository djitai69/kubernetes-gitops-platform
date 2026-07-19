"""Prometheus metrics on a dedicated port.

The metrics listener runs on a separate port (default 9000) so NetworkPolicy
can restrict scraping to the monitoring namespace without exposing /metrics
through the public application port or the Ingress.
"""

from prometheus_client import Counter, start_http_server

kubernetes_api_failures = Counter(
    "node_api_kubernetes_api_failures_total",
    "Failures calling the Kubernetes API from /nodes",
    ["reason"],
)


def start_metrics_server(port: int) -> None:
    start_http_server(port)
