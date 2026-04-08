"""
Audit application factories.
"""
from planpals.audit.application.services import AuditLogService
from planpals.audit.infrastructure.repositories import DjangoAuditLogRepository
from planpals.notifications.application.factories import (
    get_audit_log_notification_dispatcher,
)


def get_audit_log_repo() -> DjangoAuditLogRepository:
    return DjangoAuditLogRepository()


def get_audit_log_service() -> AuditLogService:
    return AuditLogService(
        audit_log_repo=get_audit_log_repo(),
        audit_log_notification_dispatcher=get_audit_log_notification_dispatcher(),
    )
