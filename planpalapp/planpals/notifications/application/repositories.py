"""
Notification application repository contracts.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional, Sequence
from uuid import UUID


@dataclass(frozen=True)
class NotificationCreateData:
    id: UUID
    user_id: UUID
    type: str
    title: str
    message: str
    data: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class NotificationFilters:
    is_read: Optional[bool] = None
    cursor: Optional[str] = None
    page_size: int = 20


@dataclass(frozen=True)
class NotificationPage:
    items: Sequence[Any]
    next_cursor: Optional[str]
    has_more: bool
    page_size: int
    unread_count: int


class NotificationRepository(ABC):
    @abstractmethod
    def create_notification(self, data: NotificationCreateData) -> Any:
        ...

    @abstractmethod
    def bulk_create_notifications(
        self,
        items: Sequence[NotificationCreateData],
    ) -> Sequence[Any]:
        ...

    @abstractmethod
    def get_user_notifications(
        self,
        user_id: UUID,
        filters: NotificationFilters,
    ) -> NotificationPage:
        ...

    @abstractmethod
    def get_notification_for_user(self, user_id: UUID, notification_id: UUID) -> Any | None:
        ...

    @abstractmethod
    def mark_as_read(self, user_id: UUID, notification_id: UUID) -> bool:
        ...

    @abstractmethod
    def mark_all_as_read(self, user_id: UUID) -> int:
        ...

    @abstractmethod
    def get_unread_count(self, user_id: UUID) -> int:
        ...

    @abstractmethod
    def get_unread_counts(self, user_ids: Sequence[UUID]) -> dict[UUID, int]:
        ...


class DeviceTokenRepository(ABC):
    @abstractmethod
    def register_device_token(self, user_id: UUID, token: str, platform: str) -> bool:
        ...

    @abstractmethod
    def get_active_tokens(self, user_ids: Sequence[UUID | str]) -> list[str]:
        ...


class PushService(ABC):
    @abstractmethod
    def send_to_users(
        self,
        user_ids: Sequence[UUID | str],
        title: str,
        body: str,
        data: dict[str, Any],
    ) -> dict[str, int]:
        ...


class NotificationPublisher(ABC):
    @abstractmethod
    def publish_notification_created(self, notification: Any, unread_count: int) -> None:
        ...

    @abstractmethod
    def publish_notification_read(
        self,
        user_id: UUID,
        notification_id: UUID,
        unread_count: int,
    ) -> None:
        ...

    @abstractmethod
    def publish_all_read(self, user_id: UUID) -> None:
        ...
