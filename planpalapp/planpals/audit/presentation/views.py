from urllib.parse import urlencode

from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from planpals.audit.application.factories import get_audit_log_service
from planpals.audit.application.repositories import AuditLogFilters
from planpals.audit.presentation.serializers import AuditLogFilterSerializer, AuditLogSerializer


class AuditLogViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        filters = self._validated_filters(request)
        service = get_audit_log_service()
        page = service.list_logs(request.user, filters)
        return self._build_response(request, page)

    @action(
        detail=False,
        methods=['get'],
        url_path=r'resource/(?P<resource_type>[^/.]+)/(?P<resource_id>[^/.]+)',
    )
    def resource(self, request, resource_type=None, resource_id=None):
        filters = self._validated_filters(request)
        service = get_audit_log_service()
        page = service.get_logs_by_resource(
            viewer=request.user,
            resource_type=resource_type,
            resource_id=resource_id,
            filters=filters,
        )
        return self._build_response(
            request,
            page,
            extra={
                'resource_type': resource_type,
                'resource_id': resource_id,
            },
        )

    def _validated_filters(self, request) -> AuditLogFilters:
        serializer = AuditLogFilterSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        return AuditLogFilters(**serializer.validated_data)

    def _build_response(self, request, page, extra=None):
        serializer = AuditLogSerializer(page.items, many=True, context={'request': request})
        payload = {
            'next': self._build_next_link(request, page.next_cursor) if page.has_more else None,
            'previous': None,
            'has_more': page.has_more,
            'page_size': page.page_size,
            'results': serializer.data,
        }
        if extra:
            payload.update(extra)
        return Response(payload, status=status.HTTP_200_OK)

    def _build_next_link(self, request, next_cursor: str | None) -> str | None:
        if not next_cursor:
            return None

        params = request.query_params.copy()
        params['cursor'] = next_cursor
        query_string = urlencode(params, doseq=True)
        return request.build_absolute_uri(f'{request.path}?{query_string}')
