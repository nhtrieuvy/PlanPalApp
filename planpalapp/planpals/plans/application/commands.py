"""
Plans Application — Commands

Immutable data transfer objects for all plan mutations.
Commands carry all data needed for an operation WITHOUT any Django/DRF dependency.
"""
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from uuid import UUID
from datetime import datetime, date

from planpals.shared.interfaces import BaseCommand


# ============================================================================
# Plan Commands
# ============================================================================

@dataclass(frozen=True)
class CreatePlanCommand(BaseCommand):
    """Command to create a new plan."""
    creator_id: UUID
    title: str
    description: str = ''
    plan_type: str = 'personal'  # personal | group
    group_id: Optional[UUID] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    is_public: bool = False
    cover_image: Optional[str] = None
    destination: str = ''
    budget: Optional[float] = None
    notes: str = ''


@dataclass(frozen=True)
class UpdatePlanCommand(BaseCommand):
    """Command to update an existing plan."""
    plan_id: UUID
    user_id: UUID  # who is performing the update
    title: Optional[str] = None
    description: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    is_public: Optional[bool] = None
    cover_image: Optional[str] = None
    destination: Optional[str] = None
    budget: Optional[float] = None
    notes: Optional[str] = None


@dataclass(frozen=True)
class ChangePlanStatusCommand(BaseCommand):
    """Command to change plan status (start trip, complete, cancel)."""
    plan_id: UUID
    user_id: UUID
    new_status: str  # in_progress | completed | cancelled


@dataclass(frozen=True)
class DeletePlanCommand(BaseCommand):
    plan_id: UUID
    user_id: UUID


@dataclass(frozen=True)
class JoinPlanCommand(BaseCommand):
    """Command for a user to join a public plan."""
    plan_id: UUID
    user_id: UUID


# ============================================================================
# Activity Commands
# ============================================================================

@dataclass(frozen=True)
class AddActivityCommand(BaseCommand):
    """Command to add an activity to a plan."""
    plan_id: UUID
    user_id: UUID  # who is adding
    title: str
    activity_type: str = 'other'
    description: str = ''
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    location_name: str = ''
    location_address: str = ''
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    estimated_cost: Optional[float] = None
    notes: str = ''
    place_id: Optional[str] = None


@dataclass(frozen=True)
class UpdateActivityCommand(BaseCommand):
    activity_id: UUID
    user_id: UUID
    title: Optional[str] = None
    description: Optional[str] = None
    activity_type: Optional[str] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    location_name: Optional[str] = None
    location_address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    estimated_cost: Optional[float] = None
    notes: Optional[str] = None


@dataclass(frozen=True)
class RemoveActivityCommand(BaseCommand):
    activity_id: UUID
    user_id: UUID


@dataclass(frozen=True)
class ToggleActivityCompletionCommand(BaseCommand):
    activity_id: UUID
    user_id: UUID
