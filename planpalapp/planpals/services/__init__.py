"""
PlanPal Services Package

Chứa các service classes để tích hợp với external APIs và xử lý business logic phức tạp.
"""

from .base_service import BaseService
from .notification_service import NotificationService
from .goong_service import goong_service

# Legacy import for backward compatibility


# Export các service instances để sử dụng dễ dàng
notification_service = NotificationService()



__all__ = [
    'BaseService',
    'NotificationService',
    'notification_service',
    'goong_service'
]
