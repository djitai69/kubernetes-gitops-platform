from types import SimpleNamespace

from kubernetes.client.exceptions import ApiException


def _fake_node(name, ready="True", labels=None, version="v1.30.0"):
    return SimpleNamespace(
        metadata=SimpleNamespace(name=name, labels=labels or {}),
        status=SimpleNamespace(
            conditions=[SimpleNamespace(type="Ready", status=ready)],
            node_info=SimpleNamespace(kubelet_version=version),
        ),
    )


class FakeCoreV1Api:
    def __init__(self, nodes=None, error=None):
        self.nodes = nodes or []
        self.error = error
        self.calls = 0

    def list_node(self, _request_timeout=None):
        self.calls += 1
        if self.error:
            raise self.error
        return SimpleNamespace(items=self.nodes)


def _install_fake_api(client, fake):
    client.app.state.node_lister._api = fake


def test_nodes_marks_current_node(client, auth_header):
    fake = FakeCoreV1Api(
        nodes=[
            _fake_node("node-a", labels={"node-role.kubernetes.io/control-plane": ""}),
            _fake_node("node-b"),
        ]
    )
    _install_fake_api(client, fake)
    resp = client.get("/nodes", headers=auth_header)
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 2
    by_name = {n["name"]: n for n in body["nodes"]}
    assert by_name["node-a"]["current_node"] is False
    assert by_name["node-a"]["roles"] == ["control-plane"]
    assert by_name["node-b"]["current_node"] is True
    assert by_name["node-b"]["roles"] == ["worker"]
    assert by_name["node-b"]["ready"] is True


def test_nodes_cache_hits_within_ttl(client, auth_header):
    fake = FakeCoreV1Api(nodes=[_fake_node("node-a")])
    _install_fake_api(client, fake)
    first = client.get("/nodes", headers=auth_header).json()
    second = client.get("/nodes", headers=auth_header).json()
    assert first["cached"] is False
    assert second["cached"] is True
    assert fake.calls == 1


def test_nodes_api_error_returns_controlled_503(client, auth_header):
    _install_fake_api(client, FakeCoreV1Api(error=ApiException(status=403)))
    resp = client.get("/nodes", headers=auth_header)
    assert resp.status_code == 503
    assert resp.json() == {"error": "kubernetes_api_unavailable"}


def test_nodes_timeout_returns_controlled_503(client, auth_header):
    _install_fake_api(client, FakeCoreV1Api(error=TimeoutError("deadline")))
    resp = client.get("/nodes", headers=auth_header)
    assert resp.status_code == 503
    body = resp.json()
    assert body == {"error": "kubernetes_api_unavailable"}


def test_nodes_unready_node_reported(client, auth_header):
    fake = FakeCoreV1Api(nodes=[_fake_node("node-x", ready="False")])
    _install_fake_api(client, fake)
    body = client.get("/nodes", headers=auth_header).json()
    assert body["nodes"][0]["ready"] is False
