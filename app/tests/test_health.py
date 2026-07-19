def test_health_minimal(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    # Minimal surface: no node names, versions, or internals.
    assert set(body.keys()) == {"status", "environment"}


def test_liveness(client):
    resp = client.get("/health/live")
    assert resp.status_code == 200
    assert resp.json() == {"status": "alive"}


def test_readiness_after_startup(client):
    resp = client.get("/health/ready")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ready"}


def test_readiness_unavailable_before_startup(client):
    client.app.state.ready = False
    resp = client.get("/health/ready")
    assert resp.status_code == 503


def test_request_id_header(client):
    resp = client.get("/health")
    assert resp.headers.get("X-Request-ID")


def test_kubernetes_failure_does_not_affect_readiness(client, auth_header):
    from node_api.k8s import KubernetesUnavailableError

    def boom():
        raise KubernetesUnavailableError("timeout")

    client.app.state.node_lister.list_nodes = boom
    assert client.get("/nodes", headers=auth_header).status_code == 503
    assert client.get("/health/ready").status_code == 200
