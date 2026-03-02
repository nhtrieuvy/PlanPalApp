"""
Plans Domain — Pure Python Entities, Value Objects & Constants

This file is the innermost layer of Clean Architecture.
NO Django imports, NO ORM, NO REST framework — Pure Python only.

All bounded contexts and external layers may depend on these definitions,
but this file must NEVER import from application, infrastructure, or presentation.
"""
from enum import Enum
from dataclasses import dataclass
from typing import Optional
from datetime import datetime, date, timedelta
from decimal import Decimal


# ============================================================================
# Enums / Constants
# ============================================================================

class PlanType(str, Enum):
    PERSONAL = 'personal'
    GROUP = 'group'

    CHOICES = [
        ('personal', 'Cá nhân'),
        ('group', 'Nhóm'),
    ]


class PlanStatus(str, Enum):
    UPCOMING = 'upcoming'
    ONGOING = 'ongoing'
    COMPLETED = 'completed'
    CANCELLED = 'cancelled'

    CHOICES = [
        ('upcoming', 'Sắp bắt đầu'),
        ('ongoing', 'Đang diễn ra'),
        ('completed', 'Đã hoàn thành'),
        ('cancelled', 'Đã hủy'),
    ]

    TERMINAL = frozenset({'completed', 'cancelled'})


class ActivityType(str, Enum):
    EATING = 'eating'
    RESTING = 'resting'
    MOVING = 'moving'
    SIGHTSEEING = 'sightseeing'
    SHOPPING = 'shopping'
    ENTERTAINMENT = 'entertainment'
    EVENT = 'event'
    SPORT = 'sport'
    STUDY = 'study'
    WORK = 'work'
    OTHER = 'other'

    CHOICES = [
        ('eating', 'Ăn uống'),
        ('resting', 'Nghỉ ngơi'),
        ('moving', 'Di chuyển'),
        ('sightseeing', 'Tham quan'),
        ('shopping', 'Mua sắm'),
        ('entertainment', 'Giải trí'),
        ('event', 'Sự kiện'),
        ('sport', 'Thể thao'),
        ('study', 'Học tập'),
        ('work', 'Công việc'),
        ('other', 'Khác'),
    ]


# ============================================================================
# Pure validation functions (domain rules, no ORM)
# ============================================================================

def validate_plan_dates(start_date: datetime, end_date: datetime) -> Optional[str]:
    """Returns error message or None if valid."""
    if end_date <= start_date:
        return "End date must be after start date"
    return None


def validate_activity_times(start_time: datetime, end_time: datetime) -> Optional[str]:
    """Returns error message or None if valid."""
    if end_time <= start_time:
        return "End time must be after start time"
    duration = end_time - start_time
    if duration.total_seconds() > 24 * 3600:
        return "Activity duration must not exceed 24 hours"
    return None


def validate_activity_within_plan(
    activity_start: datetime, activity_end: datetime,
    plan_start: datetime, plan_end: datetime,
) -> Optional[str]:
    """Returns error message or None if valid."""
    if activity_start.date() < plan_start.date():
        return "Activity cannot start before plan start date"
    if activity_end.date() > plan_end.date():
        return "Activity cannot end after plan end date"
    return None


def validate_coordinates(latitude: Optional[Decimal], longitude: Optional[Decimal]) -> Optional[str]:
    """Returns error message or None if valid."""
    if latitude is not None and not (-90 <= latitude <= 90):
        return "Latitude must be between -90 and 90"
    if longitude is not None and not (-180 <= longitude <= 180):
        return "Longitude must be between -180 and 180"
    return None


def validate_estimated_cost(cost: Optional[Decimal]) -> Optional[str]:
    """Returns error message or None if valid."""
    if cost is not None and cost < 0:
        return "Estimated cost must be non-negative"
    return None


def validate_plan_type_group_consistency(plan_type: str, has_group: bool) -> Optional[str]:
    """Returns error message or None if valid."""
    if plan_type == PlanType.PERSONAL and has_group:
        return "Personal plan cannot have a group"
    if plan_type == PlanType.GROUP and not has_group:
        return "Group plan must have a group"
    return None


def compute_auto_status(current_status: str, start_date: datetime, end_date: datetime, now: datetime) -> Optional[str]:
    """Returns new status if transition should happen, else None."""
    if current_status == PlanStatus.UPCOMING and now >= start_date:
        return PlanStatus.ONGOING
    if current_status == PlanStatus.ONGOING and now > end_date:
        return PlanStatus.COMPLETED
    return None


def compute_duration_days(start_date: datetime, end_date: datetime) -> int:
    """Compute trip duration in days."""
    return (end_date.date() - start_date.date()).days + 1
