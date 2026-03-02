"""
Plans Domain — Domain Events

Pure data objects representing things that happened in the plans domain.
These are raised by command handlers and consumed by infrastructure
(WebSocket publishers, push notifications, etc.)

Domain events must NOT depend on Django or any infrastructure framework.
"""
from dataclasses import dataclass, field
from typing import Optional, Dict, Any
from uuid import UUID

from planpals.shared.interfaces import DomainEvent


# ============================================================================
# Plan Events
# ============================================================================

@dataclass(frozen=True)
class PlanCreated(DomainEvent):
    plan_id: str
    title: str
    plan_type: str
    status: str
    creator_id: str
    group_id: Optional[str] = None
    is_public: bool = False
    start_date: Optional[str] = None
    end_date: Optional[str] = None


@dataclass(frozen=True)
class PlanUpdated(DomainEvent):
    plan_id: str
    title: str
    status: str
    last_updated: str


@dataclass(frozen=True)
class PlanStatusChanged(DomainEvent):
    plan_id: str
    title: str
    old_status: str
    new_status: str
    initiator_id: Optional[str] = None


@dataclass(frozen=True)
class PlanDeleted(DomainEvent):
    plan_id: str
    title: str


# ============================================================================
# Activity Events
# ============================================================================

@dataclass(frozen=True)
class ActivityCreated(DomainEvent):
    plan_id: str
    activity_id: str
    title: str
    activity_type: str
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    location_name: Optional[str] = None
    estimated_cost: Optional[float] = None


@dataclass(frozen=True)
class ActivityUpdated(DomainEvent):
    plan_id: str
    activity_id: str
    title: str
    is_completed: bool
    last_updated: str


@dataclass(frozen=True)
class ActivityCompleted(DomainEvent):
    plan_id: str
    activity_id: str
    title: str
    completed_by: Optional[str] = None


@dataclass(frozen=True)
class ActivityDeleted(DomainEvent):
    plan_id: str
    activity_id: str
    title: str
