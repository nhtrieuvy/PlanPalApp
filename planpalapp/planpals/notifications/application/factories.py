"""
Notification application factories.
"""
from __future__ import annotations

from planpals.notifications.application.services import NotificationService
from planpals.notifications.infrastructure.publishers import ChannelsNotificationPublisher
from planpals.notifications.infrastructure.push import FCMPushService
from planpals.notifications.infrastructure.repositories import (
    DjangoDeviceTokenRepository,
    DjangoNotificationRepository,
)


def get_notification_repo() -> DjangoNotificationRepository:
    return DjangoNotificationRepository()


def get_device_token_repo() -> DjangoDeviceTokenRepository:
    return DjangoDeviceTokenRepository()


def get_push_service() -> FCMPushService:
    return FCMPushService(device_token_repo=get_device_token_repo())


def get_notification_publisher() -> ChannelsNotificationPublisher:
    return ChannelsNotificationPublisher()


def get_notification_service() -> NotificationService:
    from planpals.audit.application.factories import get_audit_log_service

    return NotificationService(
        notification_repo=get_notification_repo(),
        device_token_repo=get_device_token_repo(),
        push_service=get_push_service(),
        publisher=get_notification_publisher(),
        audit_service=get_audit_log_service(),
    )


def get_audit_log_notification_dispatcher():
    from planpals.notifications.infrastructure.tasks import (
        process_audit_log_notification_task,
    )
    from planpals.audit.domain.entities import AuditAction

    def dispatch(audit_log):
        if audit_log.action not in {
            AuditAction.CREATE_PLAN.value,
            AuditAction.UPDATE_PLAN.value,
            AuditAction.DELETE_PLAN.value,
            AuditAction.JOIN_GROUP.value,
            AuditAction.LEAVE_GROUP.value,
            AuditAction.CHANGE_ROLE.value,
            AuditAction.DELETE_GROUP.value,
        }:
            return
        process_audit_log_notification_task.delay(str(audit_log.id))

    return dispatch
