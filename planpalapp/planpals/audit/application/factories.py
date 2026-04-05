"""
Audit application factories.
"""
from planpals.audit.application.services import AuditLogService
from planpals.audit.infrastructure.repositories import DjangoAuditLogRepository


def get_audit_log_repo() -> DjangoAuditLogRepository:
    return DjangoAuditLogRepository()


def get_audit_log_service() -> AuditLogService:
    return AuditLogService(audit_log_repo=get_audit_log_repo())
