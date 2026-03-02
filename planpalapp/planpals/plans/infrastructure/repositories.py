"""
Plans Infrastructure — Django ORM Repository Implementations

These classes implement the repository interfaces defined in domain/repositories.py
using Django's ORM. The application layer depends on the interface, not on this file.
"""
import logging
from datetime import datetime, date
from typing import Optional, List, Dict, Any
from uuid import UUID

from django.db.models import Q, Sum, Count, Avg, F
from django.utils import timezone

from planpals.plans.domain.repositories import PlanRepository, PlanActivityRepository
from planpals.plans.infrastructure.models import Plan, PlanActivity

logger = logging.getLogger(__name__)


class DjangoPlanRepository(PlanRepository):
    """Django ORM implementation of PlanRepository."""

    def get_by_id(self, plan_id: UUID) -> Optional[Plan]:
        try:
            return Plan.objects.select_related('creator', 'group').get(id=plan_id)
        except Plan.DoesNotExist:
            return None

    def get_by_id_with_stats(self, plan_id: UUID) -> Optional[Plan]:
        try:
            return (
                Plan.objects
                .select_related('creator', 'group')
                .with_activity_count()
                .get(id=plan_id)
            )
        except Plan.DoesNotExist:
            return None

    def exists(self, plan_id: UUID) -> bool:
        return Plan.objects.filter(id=plan_id).exists()

    def get_plans_for_user(self, user_id: UUID, plan_type: str = 'all') -> Any:
        qs = Plan.objects.for_user(user_id).select_related('creator', 'group')
        if plan_type == 'personal':
            qs = qs.filter(plan_type='personal')
        elif plan_type == 'group':
            qs = qs.filter(plan_type='group')
        return qs.with_activity_count().order_by('-created_at')

    def get_joined_plans(self, user_id: UUID) -> Any:
        return (
            Plan.objects
            .filter(collaborators=user_id)
            .select_related('creator', 'group')
            .with_activity_count()
            .order_by('-created_at')
        )

    def get_public_plans(self, exclude_user_id: UUID = None) -> Any:
        qs = Plan.objects.filter(is_public=True).select_related('creator', 'group')
        if exclude_user_id:
            qs = qs.exclude(creator_id=exclude_user_id)
        return qs.with_activity_count().order_by('-created_at')

    def get_group_plans(self, group_id: UUID) -> Any:
        return (
            Plan.objects
            .filter(group_id=group_id)
            .select_related('creator', 'group')
            .with_activity_count()
            .order_by('-created_at')
        )

    def save(self, plan: Plan) -> Plan:
        plan.save()
        return plan

    def save_new(self, command) -> Plan:
        """Create a new Plan from a CreatePlanCommand."""
        plan = Plan(
            creator_id=command.creator_id,
            title=command.title,
            description=command.description,
            plan_type=command.plan_type,
            group_id=command.group_id,
            start_date=command.start_date,
            end_date=command.end_date,
            is_public=command.is_public,
            cover_image=command.cover_image or '',
            destination=command.destination,
            budget=command.budget,
            notes=command.notes,
        )
        plan.save()
        return plan

    def delete(self, plan_id: UUID) -> bool:
        deleted_count, _ = Plan.objects.filter(id=plan_id).delete()
        return deleted_count > 0

    def add_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        try:
            plan = Plan.objects.get(id=plan_id)
            plan.collaborators.add(user_id)
            return True
        except Plan.DoesNotExist:
            return False

    def remove_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        try:
            plan = Plan.objects.get(id=plan_id)
            plan.collaborators.remove(user_id)
            return True
        except Plan.DoesNotExist:
            return False

    def is_collaborator(self, plan_id: UUID, user_id: UUID) -> bool:
        return Plan.objects.filter(id=plan_id, collaborators=user_id).exists()

    def update_status(self, plan_id: UUID, new_status: str) -> Plan:
        plan = Plan.objects.get(id=plan_id)
        plan.status = new_status
        if new_status == 'in_progress':
            plan.actual_start_date = timezone.now().date()
        elif new_status == 'completed':
            plan.actual_end_date = timezone.now().date()
        plan.save()
        return plan


class DjangoPlanActivityRepository(PlanActivityRepository):
    """Django ORM implementation of PlanActivityRepository."""

    def get_by_id(self, activity_id: UUID) -> Optional[PlanActivity]:
        try:
            return PlanActivity.objects.select_related('plan', 'plan__group').get(id=activity_id)
        except PlanActivity.DoesNotExist:
            return None

    def get_activities_for_plan(self, plan_id: UUID) -> Any:
        return (
            PlanActivity.objects
            .filter(plan_id=plan_id)
            .select_related('plan')
            .order_by('start_time', 'created_at')
        )

    def get_activities_by_date(self, plan_id: UUID, target_date: date) -> Any:
        return (
            PlanActivity.objects
            .filter(plan_id=plan_id, start_time__date=target_date)
            .select_related('plan')
            .order_by('start_time')
        )

    def get_activities_by_date_range(
        self, plan_id: UUID, start_date: date, end_date: date
    ) -> Any:
        return (
            PlanActivity.objects
            .filter(
                plan_id=plan_id,
                start_time__date__gte=start_date,
                start_time__date__lte=end_date,
            )
            .select_related('plan')
            .order_by('start_time')
        )

    def save(self, activity: PlanActivity) -> PlanActivity:
        activity.save()
        return activity

    def save_new(self, command) -> PlanActivity:
        """Create a new PlanActivity from an AddActivityCommand."""
        activity = PlanActivity(
            plan_id=command.plan_id,
            title=command.title,
            activity_type=command.activity_type,
            description=command.description,
            start_time=command.start_time,
            end_time=command.end_time,
            location_name=command.location_name,
            location_address=command.location_address,
            latitude=command.latitude,
            longitude=command.longitude,
            estimated_cost=command.estimated_cost,
            notes=command.notes,
        )
        if command.place_id:
            activity.place_id = command.place_id
        activity.save()
        return activity

    def delete(self, activity_id: UUID) -> bool:
        deleted_count, _ = PlanActivity.objects.filter(id=activity_id).delete()
        return deleted_count > 0

    def check_time_conflicts(
        self, plan_id: UUID, start_time: datetime, end_time: datetime,
        exclude_activity_id: UUID = None,
    ) -> List[PlanActivity]:
        qs = PlanActivity.objects.filter(
            plan_id=plan_id,
            start_time__lt=end_time,
            end_time__gt=start_time,
        )
        if exclude_activity_id:
            qs = qs.exclude(id=exclude_activity_id)
        return list(qs)

    def get_plan_statistics(self, plan_id: UUID) -> Dict[str, Any]:
        activities = PlanActivity.objects.filter(plan_id=plan_id)
        stats = activities.aggregate(
            total_activities=Count('id'),
            completed_activities=Count('id', filter=Q(is_completed=True)),
            total_estimated_cost=Sum('estimated_cost'),
            avg_estimated_cost=Avg('estimated_cost'),
        )

        total = stats['total_activities'] or 0
        completed = stats['completed_activities'] or 0

        return {
            'total_activities': total,
            'completed_activities': completed,
            'pending_activities': total - completed,
            'completion_percentage': round((completed / total * 100), 1) if total > 0 else 0,
            'total_estimated_cost': float(stats['total_estimated_cost'] or 0),
            'average_cost_per_activity': float(stats['avg_estimated_cost'] or 0),
        }
