"""
Analytics application factories.
"""
from __future__ import annotations

from planpals.analytics.application.services import AnalyticsService
from planpals.analytics.infrastructure.repositories import DjangoAnalyticsRepository
from planpals.shared.cache_infrastructure import DjangoCacheService


def get_analytics_repo() -> DjangoAnalyticsRepository:
    return DjangoAnalyticsRepository()


def get_analytics_cache_service() -> DjangoCacheService:
    return DjangoCacheService()


def get_analytics_service() -> AnalyticsService:
    return AnalyticsService(
        analytics_repo=get_analytics_repo(),
        cache_service=get_analytics_cache_service(),
    )
