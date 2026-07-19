"""Structured JSON logging to stdout.

Every record is a single JSON line with timestamp, level, message, and any
extra fields (request_id, path, status_code, latency_ms, environment).
Secrets, tokens, and Authorization headers are never logged.
"""

import json
import logging
import sys
from contextvars import ContextVar
from datetime import datetime, timezone

request_id_var: ContextVar[str] = ContextVar("request_id", default="")

_RESERVED = set(
    logging.LogRecord("", 0, "", 0, "", (), None).__dict__.keys()
) | {"message", "asctime", "taskName"}


class JsonFormatter(logging.Formatter):
    def __init__(self, environment: str = "local") -> None:
        super().__init__()
        self.environment = environment

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "environment": self.environment,
        }
        rid = request_id_var.get()
        if rid:
            payload["request_id"] = rid
        for key, value in record.__dict__.items():
            if key not in _RESERVED and not key.startswith("_"):
                payload[key] = value
        if record.exc_info and record.exc_info[0] is not None:
            payload["exception"] = record.exc_info[0].__name__
        return json.dumps(payload, default=str)


def configure_logging(level: str, environment: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(environment=environment))
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper() if level else "INFO")
    # Uvicorn's default access log is replaced by our own request logging.
    logging.getLogger("uvicorn.access").disabled = True
