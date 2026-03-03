"""
Plans Domain — Repository Interfaces

These abstract interfaces define WHAT data access operations the plans
bounded context needs, without specifying HOW they are implemented.

Application layer depends on these interfaces.
Infrastructure layer provides Django ORM implementations.
"""
from abc import ABC, abstractmethod
from datetime import datetime, date
from typing import Optional, List, Tuple, Any, Dict
from uuid import UUID


class PlanRepository(ABC):
    """Repository interface for Plan aggregate root."""

    # ---------- Queries ----------
    @abstractmethod
    def get_by_id(self, plan_id: UUID) -> Optional[Any]:
        """Get a plan by ID."""
        ...

    @abstractmethod
    def get_by_id_with_stats(self, plan_id: UUID) -> Optional[Any]:
        """Get a plan with annotated statistics (activity count, etc.)."""
        ...

    @abstractmethod
    def exists(self, plan_id: UUID) -> bool:
        ...

    @abstractmethod
    def get_plans_for_user(self, user_id: UUID, plan_type: str = 'all') -> Any:
        """Get all plans visible to a user (personal + group plans)."""
        ...

    @abstractmethod
    def get_joined_group_plans(self, user_id: UUID, search: str = None) -> Any:
        """Get group plans the user is a member of (excluding own plans)."""
        ...

    @abstractmethod
    def get_public_plans(self, exclude_user_id: UUID = None, search: str = None) -> Any:
        """Get all public plans, optionally excluding a user's own plans, with optional search."""
        ...

    @abstractmethod
    def get_group_plans(self, group_id: UUID) -> Any:
        """Get all plans for a group."""
        ...

    @abstractmethod
    def get_plans_needing_status_update(self) -> Any:
        """Get plans whose status should be auto-updated based on dates."""
        ...

    # ---------- Mutations ----------
    @abstractmethod
    def save(self, plan: Any) -> Any:
        """Create or update a plan."""
        ...

    @abstractmethod
    def save_new(self, command: Any) -> Any:
        """Create a new plan from a command."""
        ...

    @abstractmethod
    def delete(self, plan_id: UUID) -> bool:
        """Delete a plan."""
        ...

    @abstractmethod
    def add_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        """Add a user as collaborator to a plan."""
        ...

    @abstractmethod
    def remove_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        """Remove a collaborator from a plan."""
        ...

    @abstractmethod
    def is_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        """Check if a user is a collaborator of a plan."""
        ...

    # ---------- Status transitions ----------
    @abstractmethod
    def update_status(self, plan_id: UUID, new_status: str) -> Any:
        """Update the plan's status."""
        ...

    @abstractmethod
    def update_status_atomic(
        self, plan_id: UUID, expected_status: str, new_status: str
    ) -> Tuple[bool, Optional[Any]]:
        """
        Atomically update status with optimistic locking.
        Returns (success, refreshed_plan). success=False if expected_status didn't match.
        """
        ...

    @abstractmethod
    def update_fields(self, plan_id: UUID, **fields) -> bool:
        """Update specific fields on a plan by ID. Returns True if updated."""
        ...

    @abstractmethod
    def update_scheduled_task_ids(
        self, plan_id: UUID,
        start_task_id: str = None, end_task_id: str = None,
        expected_start_task_id: str = None, expected_end_task_id: str = None,
    ) -> bool:
        """Atomically update Celery task IDs with optimistic locking."""
        ...

    @abstractmethod
    def clear_scheduled_task_ids(self, plan_id: UUID) -> bool:
        """Clear both scheduled task IDs."""
        ...

    @abstractmethod
    def refresh(self, plan: Any) -> Any:
        """Refresh a plan instance from the database."""
        ...


class PlanActivityRepository(ABC):
    """Repository interface for PlanActivity entities."""

    @abstractmethod
    def get_by_id(self, activity_id: UUID) -> Optional[Any]:
        ...

    @abstractmethod
    def get_activities_for_plan(self, plan_id: UUID) -> Any:
        """Get all activities for a plan, ordered by start_time."""
        ...

    @abstractmethod
    def get_activities_by_date(self, plan_id: UUID, target_date: date) -> Any:
        """Get activities for a plan on a specific date."""
        ...

    @abstractmethod
    def get_activities_by_date_range(
        self, plan_id: UUID, start_date: date, end_date: date
    ) -> Any:
        ...

    @abstractmethod
    def save(self, activity: Any) -> Any:
        """Create or update an activity."""
        ...

    @abstractmethod
    def save_new(self, command: Any) -> Any:
        """Create a new activity from a command."""
        ...

    @abstractmethod
    def save_new_from_dict(self, plan_id: UUID, data: Dict[str, Any]) -> Any:
        """Create a new activity from a plain dictionary."""
        ...

    @abstractmethod
    def delete(self, activity_id: UUID) -> bool:
        ...

    @abstractmethod
    def check_time_conflicts(
        self, plan_id: UUID, start_time: datetime, end_time: datetime,
        exclude_activity_id: UUID = None,
    ) -> List[Any]:
        """Return conflicting activities for the given time window."""
        ...

    @abstractmethod
    def get_plan_statistics(self, plan_id: UUID) -> Dict[str, Any]:
        """Compute aggregate statistics for a plan's activities."""
        ...

    @abstractmethod
    def count_completed(self, plan_id: UUID) -> int:
        """Count completed activities for a plan."""
        ...

    @abstractmethod
    def count_total(self, plan_id: UUID) -> int:
        """Count total activities for a plan."""
        ...
