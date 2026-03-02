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
    def get_joined_plans(self, user_id: UUID) -> Any:
        """Get plans the user has joined (public plans)."""
        ...

    @abstractmethod
    def get_public_plans(self, exclude_user_id: UUID = None) -> Any:
        """Get all public plans, optionally excluding a user's own plans."""
        ...

    @abstractmethod
    def get_group_plans(self, group_id: UUID) -> Any:
        """Get all plans for a group."""
        ...

    # ---------- Mutations ----------
    @abstractmethod
    def save(self, plan: Any) -> Any:
        """Create or update a plan."""
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
