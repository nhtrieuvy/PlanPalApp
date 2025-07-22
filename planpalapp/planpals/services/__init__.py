"""
PlanPal Services Package

Chứa các service classes để tích hợp với external APIs và xử lý business logic phức tạp.
"""

from .base_service import BaseService
from .google_places_service import GooglePlacesService
from .notification_service import NotificationService

# Export các service instances để sử dụng dễ dàng
google_places_service = GooglePlacesService()
notification_service = NotificationService()

__all__ = [
    'BaseService',
    'GooglePlacesService', 
    'NotificationService',
    'google_places_service',
    'notification_service'
]
