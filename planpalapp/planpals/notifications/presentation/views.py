from urllib.parse import urlencode

from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from planpals.notifications.application.factories import get_notification_service
from planpals.notifications.application.repositories import NotificationFilters
from planpals.notifications.presentation.serializers import (
    NotificationFilterSerializer,
    NotificationSerializer,
)


class NotificationViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        service = get_notification_service()
        filters = self._validated_filters(request)
        page = service.list_notifications(request.user, filters)
        return self._build_response(request, page)

    @action(detail=False, methods=['get'], url_path='unread-count')
    def unread_count(self, request):
        service = get_notification_service()
        return Response(
            {'unread_count': service.get_unread_count(request.user)},
            status=status.HTTP_200_OK,
        )

    @action(detail=True, methods=['patch'], url_path='read')
    def mark_read(self, request, pk=None):
        service = get_notification_service()
        updated = service.mark_as_read(request.user, pk)
        if not updated:
            return Response(
                {'error': 'Notification not found'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response({'message': 'Notification marked as read'}, status=status.HTTP_200_OK)

    @action(detail=False, methods=['patch'], url_path='read-all')
    def mark_all_read(self, request):
        service = get_notification_service()
        updated_count = service.mark_all_as_read(request.user)
        return Response(
            {'message': 'Notifications marked as read', 'updated_count': updated_count},
            status=status.HTTP_200_OK,
        )

    def _validated_filters(self, request) -> NotificationFilters:
        serializer = NotificationFilterSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        return NotificationFilters(**serializer.validated_data)

    def _build_response(self, request, page):
        serializer = NotificationSerializer(page.items, many=True, context={'request': request})
        return Response(
            {
                'next': self._build_next_link(request, page.next_cursor) if page.has_more else None,
                'previous': None,
                'has_more': page.has_more,
                'page_size': page.page_size,
                'unread_count': page.unread_count,
                'results': serializer.data,
            },
            status=status.HTTP_200_OK,
        )

    def _build_next_link(self, request, next_cursor: str | None) -> str | None:
        if not next_cursor:
            return None

        params = request.query_params.copy()
        params['cursor'] = next_cursor
        query_string = urlencode(params, doseq=True)
        return request.build_absolute_uri(f'{request.path}?{query_string}')
