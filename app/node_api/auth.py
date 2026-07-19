"""Bearer-token authorization for /nodes.

Fail-closed: when API_TOKEN is not configured the endpoint refuses to serve
rather than serving unauthenticated. Tokens are compared in constant time and
never logged.
"""

import hmac

from fastapi import HTTPException, Request


def require_token(request: Request) -> None:
    expected = request.app.state.settings.api_token
    if not expected:
        raise HTTPException(status_code=503, detail="authentication is not configured")
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not hmac.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="invalid or missing token")
