import pytest
from fastapi.testclient import TestClient

TEST_TOKEN = "test-token-123"


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setenv("API_TOKEN", TEST_TOKEN)
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("NODE_NAME", "node-b")
    monkeypatch.setenv("NODES_CACHE_TTL_SECONDS", "60")
    # Prometheus default registry is process-global; rebuild the app but keep
    # instrumentation idempotent by clearing collectors between app instances.
    from prometheus_client import REGISTRY

    for collector in list(REGISTRY._collector_to_names):
        try:
            REGISTRY.unregister(collector)
        except KeyError:
            pass

    from node_api.main import create_app

    app = create_app(start_metrics=False)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def auth_header():
    return {"Authorization": f"Bearer {TEST_TOKEN}"}
