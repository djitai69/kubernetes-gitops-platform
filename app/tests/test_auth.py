def test_nodes_requires_token(client):
    assert client.get("/nodes").status_code == 401


def test_nodes_rejects_bad_token(client):
    resp = client.get("/nodes", headers={"Authorization": "Bearer wrong"})
    assert resp.status_code == 401


def test_nodes_rejects_non_bearer_scheme(client):
    resp = client.get("/nodes", headers={"Authorization": "Basic dXNlcjpwYXNz"})
    assert resp.status_code == 401


def test_nodes_fails_closed_without_configured_token(client):
    client.app.state.settings = type(client.app.state.settings)(api_token="")
    resp = client.get("/nodes", headers={"Authorization": "Bearer anything"})
    assert resp.status_code == 503
