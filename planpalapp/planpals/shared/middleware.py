"""HTTP request correlation middleware."""

from __future__ import annotations

import re
from uuid import uuid4

from planpals.shared.observability import request_id_context


_REQUEST_ID_PATTERN = re.compile(r'^[A-Za-z0-9._-]{8,128}$')


class RequestCorrelationMiddleware:
    """Propagate a safe request id through logs and the HTTP response."""

    header_name = 'HTTP_X_REQUEST_ID'
    response_header = 'X-Request-ID'

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        supplied_id = request.META.get(self.header_name, '')
        request_id = (
            supplied_id
            if _REQUEST_ID_PATTERN.fullmatch(supplied_id)
            else uuid4().hex
        )
        token = request_id_context.set(request_id)
        request.request_id = request_id
        try:
            response = self.get_response(request)
            response[self.response_header] = request_id
            return response
        finally:
            request_id_context.reset(token)
