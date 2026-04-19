"""
Plans Infrastructure — Django ORM Repository Implementations

These classes implement the repository interfaces defined in domain/repositories.py
using Django's ORM. The application layer depends on the interface, not on this file.
"""
import logging
from datetime import datetime, date
from typing import Optional, List, Dict, Any, Tuple
from uuid import UUID

from django.db import transaction
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
                .with_stats()
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
        return qs.with_stats().order_by('-created_at')

    def get_joined_group_plans(self, user_id: UUID, search: str = None) -> Any:
        qs = Plan.objects.filter(
            plan_type='group',
            group__members=user_id,
        ).exclude(creator_id=user_id).distinct().select_related('creator', 'group')
        if search:
            qs = qs.filter(
                Q(title__icontains=search) | Q(description__icontains=search)
            )
        return qs.order_by('-created_at')

    def get_public_plans(self, exclude_user_id: UUID = None, search: str = None) -> Any:
        qs = Plan.objects.filter(
            is_public=True,
            status__in=['upcoming', 'ongoing'],
        ).select_related('creator', 'group')
        if exclude_user_id:
            qs = qs.exclude(creator_id=exclude_user_id)
            qs = qs.exclude(plan_type='group', group__members=exclude_user_id)
        if search:
            qs = qs.filter(
                Q(title__icontains=search) | Q(description__icontains=search)
            )
        return qs.order_by('-created_at')

    def get_group_plans(self, group_id: UUID) -> Any:
        return (
            Plan.objects
            .filter(group_id=group_id)
            .select_related('creator', 'group')
            .prefetch_related('activities')
            .order_by('-created_at')
        )

    def get_plans_needing_status_update(self) -> Any:
        return Plan.objects.plans_need_status_update()

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

    def update_status_atomic(
        self, plan_id: UUID, expected_status: str, new_status: str
    ) -> Tuple[bool, Optional[Plan]]:
        with transaction.atomic():
            updated_count = Plan.objects.filter(
                pk=plan_id,
                status=expected_status,
            ).update(
                status=new_status,
                updated_at=timezone.now(),
            )
            if updated_count == 0:
                try:
                    plan = Plan.objects.get(pk=plan_id)
                    logger.warning(
                        f"update_status_atomic: expected={expected_status} "
                        f"but db_status={plan.status} for plan {plan_id}"
                    )
                except Plan.DoesNotExist:
                    pass
                return False, None
            plan = Plan.objects.select_related('creator', 'group').get(pk=plan_id)
            return True, plan

    def update_fields(self, plan_id: UUID, **fields) -> bool:
        updated = Plan.objects.filter(pk=plan_id).update(**fields)
        return updated > 0

    def update_scheduled_task_ids(
        self, plan_id: UUID,
        start_task_id: str = None, end_task_id: str = None,
        expected_start_task_id: str = None, expected_end_task_id: str = None,
    ) -> bool:
        filters = {'pk': plan_id}
        if expected_start_task_id is not None:
            filters['scheduled_start_task_id'] = expected_start_task_id
        if expected_end_task_id is not None:
            filters['scheduled_end_task_id'] = expected_end_task_id

        updates = {}
        if start_task_id is not None:
            updates['scheduled_start_task_id'] = start_task_id
        if end_task_id is not None:
            updates['scheduled_end_task_id'] = end_task_id

        if not updates:
            return True
        return Plan.objects.filter(**filters).update(**updates) > 0

    def clear_scheduled_task_ids(self, plan_id: UUID) -> bool:
        return Plan.objects.filter(pk=plan_id).update(
            scheduled_start_task_id=None,
            scheduled_end_task_id=None,
        ) > 0

    def refresh(self, plan: Any) -> Plan:
        plan.refresh_from_db()
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

    def save_new_from_dict(self, plan_id: UUID, data: Dict[str, Any]) -> PlanActivity:
        """Create a new PlanActivity from a dict (for add_activity_with_place)."""
        allowed_fields = {
            'title', 'description', 'activity_type', 'start_time', 'end_time',
            'location_name', 'location_address', 'latitude', 'longitude',
            'estimated_cost', 'notes',
        }
        filtered = {k: v for k, v in data.items() if k in allowed_fields}
        activity = PlanActivity(plan_id=plan_id, **filtered)
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

    def count_completed(self, plan_id: UUID) -> int:
        return PlanActivity.objects.filter(plan_id=plan_id, is_completed=True).count()

    def count_total(self, plan_id: UUID) -> int:
        return PlanActivity.objects.filter(plan_id=plan_id).count()
