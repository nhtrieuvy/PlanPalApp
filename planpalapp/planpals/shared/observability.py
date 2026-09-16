"""Small, dependency-free logging helpers for production observability."""

from __future__ import annotations

import json
import logging
import re
from contextvars import ContextVar
from datetime import datetime, timezone


request_id_context: ContextVar[str] = ContextVar('request_id', default='-')

_SENSITIVE_PATTERNS = (
    re.compile(r'(?i)(authorization["\']?\s*[:=]\s*["\']?bearer\s+)[^\s,"\']+'),
    re.compile(r'(?i)((?:access|refresh)_token["\']?\s*[:=]\s*["\']?)[^\s,"\']+'),
    re.compile(r'(?i)(password["\']?\s*[:=]\s*["\']?)[^\s,"\']+'),
)


def sanitize_log_message(value: object) -> str:
    """Mask common credentials before they reach stdout or an error tracker."""
    message = str(value)
    for pattern in _SENSITIVE_PATTERNS:
        message = pattern.sub(r'\1[REDACTED]', message)
    return message


class RequestContextFilter(logging.Filter):
    """Attach correlation metadata and sanitize the rendered log message."""

    def filter(self, record: logging.LogRecord) -> bool:
        request = getattr(record, 'request', None)
        record.request_id = (
            getattr(request, 'request_id', None) or request_id_context.get()
        )
        record.msg = sanitize_log_message(record.getMessage())
        record.args = ()
        return True


class JsonFormatter(logging.Formatter):
    """Emit one JSON object per line for container log aggregation."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'request_id': getattr(record, 'request_id', '-'),
        }
        if record.exc_info:
            payload['exception'] = sanitize_log_message(
                self.formatException(record.exc_info)
            )
        return json.dumps(payload, ensure_ascii=True, default=str)
