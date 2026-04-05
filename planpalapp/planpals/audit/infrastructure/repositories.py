"""
Audit infrastructure repository implementations.
"""
from __future__ import annotations

import base64
import json
from datetime import datetime
from typing import Optional
from uuid import UUID

from django.db.models import Q, QuerySet

from planpals.audit.application.repositories import (
    AuditLogCreateData,
    AuditLogFilters,
    AuditLogPage,
    AuditLogRepository,
)
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.groups.infrastructure.models import GroupMembership
from planpals.plans.infrastructure.models import Plan


class DjangoAuditLogRepository(AuditLogRepository):
    def create_log(self, data: AuditLogCreateData) -> AuditLog:
        return AuditLog.objects.create(
            user_id=data.user_id,
            action=data.action,
            resource_type=data.resource_type,
            resource_id=data.resource_id,
            metadata=data.metadata,
        )

    def list_logs(self, viewer_id: UUID, filters: AuditLogFilters) -> AuditLogPage:
        queryset = self._base_queryset()
        queryset = self._apply_access_filter(queryset, viewer_id)
        queryset = self._apply_filters(queryset, filters)
        return self._paginate(queryset, filters)

    def get_logs_by_resource(
        self,
        viewer_id: UUID,
        resource_type: str,
        resource_id: UUID,
        filters: AuditLogFilters,
    ) -> AuditLogPage:
        queryset = self._base_queryset().filter(
            resource_type=resource_type,
            resource_id=resource_id,
        )
        queryset = self._apply_access_filter(queryset, viewer_id)
        queryset = self._apply_filters(queryset, filters)
        return self._paginate(queryset, filters)

    def get_logs_by_user(
        self,
        viewer_id: UUID,
        user_id: UUID,
        filters: AuditLogFilters,
    ) -> AuditLogPage:
        merged_filters = AuditLogFilters(
            user_id=user_id,
            action=filters.action,
            resource_type=filters.resource_type,
            date_from=filters.date_from,
            date_to=filters.date_to,
            cursor=filters.cursor,
            page_size=filters.page_size,
        )
        return self.list_logs(viewer_id=viewer_id, filters=merged_filters)

    def can_view_resource(self, viewer_id: UUID, resource_type: str, resource_id: UUID) -> bool:
        normalized_resource_type = (resource_type or '').strip().lower()

        if normalized_resource_type == AuditResourceType.GROUP.value:
            if GroupMembership.objects.filter(group_id=resource_id, user_id=viewer_id).exists():
                return True
            return AuditLog.objects.filter(
                resource_type=normalized_resource_type,
                resource_id=resource_id,
                user_id=viewer_id,
                action=AuditAction.DELETE_GROUP.value,
            ).exists()

        if normalized_resource_type == AuditResourceType.PLAN.value:
            if Plan.objects.filter(id=resource_id).filter(
                Q(creator_id=viewer_id) | Q(group__members__id=viewer_id)
            ).exists():
                return True
            return AuditLog.objects.filter(
                resource_type=normalized_resource_type,
                resource_id=resource_id,
                user_id=viewer_id,
                action=AuditAction.DELETE_PLAN.value,
            ).exists()

        return AuditLog.objects.filter(
            resource_type=normalized_resource_type,
            resource_id=resource_id,
            user_id=viewer_id,
        ).exists()

    def _base_queryset(self) -> QuerySet[AuditLog]:
        return AuditLog.objects.select_related('user').order_by('-created_at', '-id')

    def _apply_access_filter(self, queryset: QuerySet[AuditLog], viewer_id: UUID) -> QuerySet[AuditLog]:
        group_ids = GroupMembership.objects.filter(user_id=viewer_id).values('group_id')
        plan_ids = Plan.objects.filter(
            Q(creator_id=viewer_id) | Q(group__members__id=viewer_id)
        ).values('id')

        return queryset.filter(
            Q(user_id=viewer_id)
            | Q(resource_type=AuditResourceType.GROUP.value, resource_id__in=group_ids)
            | Q(resource_type=AuditResourceType.PLAN.value, resource_id__in=plan_ids)
        ).distinct()

    def _apply_filters(self, queryset: QuerySet[AuditLog], filters: AuditLogFilters) -> QuerySet[AuditLog]:
        if filters.user_id:
            queryset = queryset.filter(user_id=filters.user_id)
        if filters.action:
            queryset = queryset.filter(action=filters.action)
        if filters.resource_type:
            queryset = queryset.filter(resource_type=filters.resource_type)
        if filters.date_from:
            queryset = queryset.filter(created_at__gte=filters.date_from)
        if filters.date_to:
            queryset = queryset.filter(created_at__lte=filters.date_to)

        created_at, last_id = self._decode_cursor(filters.cursor)
        if created_at and last_id:
            queryset = queryset.filter(
                Q(created_at__lt=created_at)
                | Q(created_at=created_at, id__lt=last_id)
            )
        return queryset

    def _paginate(self, queryset: QuerySet[AuditLog], filters: AuditLogFilters) -> AuditLogPage:
        page_size = filters.page_size or 20
        items = list(queryset[: page_size + 1])
        has_more = len(items) > page_size
        if has_more:
            items = items[:page_size]

        next_cursor = None
        if has_more and items:
            last_item = items[-1]
            next_cursor = self._encode_cursor(last_item.created_at, last_item.id)

        return AuditLogPage(
            items=items,
            next_cursor=next_cursor,
            has_more=has_more,
            page_size=page_size,
        )

    @staticmethod
    def _encode_cursor(created_at: datetime, item_id: UUID) -> str:
        raw = json.dumps({'created_at': created_at.isoformat(), 'id': str(item_id)})
        return base64.urlsafe_b64encode(raw.encode('utf-8')).decode('ascii')

    @staticmethod
    def _decode_cursor(cursor: Optional[str]) -> tuple[Optional[datetime], Optional[UUID]]:
        if not cursor:
            return None, None

        try:
            payload = json.loads(base64.urlsafe_b64decode(cursor.encode('ascii')).decode('utf-8'))
            created_at = datetime.fromisoformat(payload['created_at'])
            item_id = UUID(str(payload['id']))
            return created_at, item_id
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            return None, None
