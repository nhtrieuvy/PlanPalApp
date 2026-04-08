"""
Audit application repository contracts.

The application layer depends on these interfaces instead of Django ORM.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional, Sequence
from uuid import UUID


@dataclass(frozen=True)
class AuditLogCreateData:
    user_id: Optional[UUID]
    action: str
    resource_type: str
    resource_id: Optional[UUID]
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class AuditLogFilters:
    user_id: Optional[UUID] = None
    action: Optional[str] = None
    resource_type: Optional[str] = None
    date_from: Optional[datetime] = None
    date_to: Optional[datetime] = None
    cursor: Optional[str] = None
    page_size: int = 20


@dataclass(frozen=True)
class AuditLogPage:
    items: Sequence[Any]
    next_cursor: Optional[str]
    has_more: bool
    page_size: int


class AuditLogRepository(ABC):
    @abstractmethod
    def create_log(self, data: AuditLogCreateData) -> Any:
        """Persist a new audit log entry."""
        ...

    @abstractmethod
    def list_logs(self, viewer_id: UUID, filters: AuditLogFilters) -> AuditLogPage:
        """List audit logs visible to the requesting viewer."""
        ...

    @abstractmethod
    def get_logs_by_resource(
        self,
        viewer_id: UUID,
        resource_type: str,
        resource_id: UUID,
        filters: AuditLogFilters,
    ) -> AuditLogPage:
        """List audit logs for a resource visible to the requesting viewer."""
        ...

    @abstractmethod
    def get_logs_by_user(
        self,
        viewer_id: UUID,
        user_id: UUID,
        filters: AuditLogFilters,
    ) -> AuditLogPage:
        """List audit logs for an actor visible to the requesting viewer."""
        ...

    @abstractmethod
    def can_view_resource(self, viewer_id: UUID, resource_type: str, resource_id: UUID) -> bool:
        """Check whether the viewer is allowed to inspect a resource audit trail."""
        ...
