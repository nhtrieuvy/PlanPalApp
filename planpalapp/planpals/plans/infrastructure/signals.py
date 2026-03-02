"""
Django signals for plan and activity real-time event publishing
"""
import logging
from django.db import transaction
from django.db.models.signals import post_save, post_delete, pre_save
from django.dispatch import receiver

from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.shared.events import EventType
from planpals.plans.infrastructure.publishers import (
    publish_plan_created,
    publish_plan_updated,
    publish_plan_status_changed,
    publish_plan_deleted,
    publish_activity_created,
    publish_activity_updated,
    publish_activity_completed,
    publish_activity_deleted,
)

logger = logging.getLogger(__name__)


@receiver(pre_save, sender=Plan)
def plan_pre_save(sender, instance, **kwargs):
    """Capture old plan status before saving"""
    if instance.pk:
        try:
            old_instance = Plan.objects.get(pk=instance.pk)
            instance._old_status = old_instance.status
        except Plan.DoesNotExist:
            instance._old_status = None
    else:
        instance._old_status = None


@receiver(post_save, sender=Plan)
def plan_post_save(sender, instance, created, **kwargs):
    """Publish plan events after save"""
    try:
        if created:
            # New plan created
            def _publish_plan_created():
                publish_plan_created(
                    plan_id=str(instance.id),
                    title=instance.title,
                    plan_type=instance.plan_type,
                    status=instance.status,
                    creator_id=str(instance.creator_id),
                    group_id=str(instance.group_id) if instance.group_id else None,
                    is_public=instance.is_public,
                    start_date=instance.start_date.isoformat() if instance.start_date else None,
                    end_date=instance.end_date.isoformat() if instance.end_date else None
                )
            transaction.on_commit(_publish_plan_created)
            
        else:
            # Plan updated
            old_status = getattr(instance, '_old_status', None)
            
            # Check if status changed
            if old_status and old_status != instance.status:
                def _publish_status_change():
                    publish_plan_status_changed(
                        plan_id=str(instance.id),
                        old_status=old_status,
                        new_status=instance.status,
                        title=instance.title
                    )
                transaction.on_commit(_publish_status_change)
            
            # General plan update event (for non-status changes)
            elif not old_status or old_status == instance.status:
                def _publish_plan_update():
                    publish_plan_updated(
                        plan_id=str(instance.id),
                        title=instance.title,
                        status=instance.status,
                        last_updated=instance.updated_at.isoformat()
                    )
                transaction.on_commit(_publish_plan_update)
                
    except Exception as e:
        logger.error(f"Error publishing plan event: {e}")


@receiver(post_delete, sender=Plan)
def plan_post_delete(sender, instance, **kwargs):
    """Publish plan deletion event"""
    try:
        def _publish_plan_deleted():
            publish_plan_deleted(
                plan_id=str(instance.id),
                title=instance.title
            )
        transaction.on_commit(_publish_plan_deleted)
        
    except Exception as e:
        logger.error(f"Error publishing plan deletion event: {e}")


@receiver(post_save, sender=PlanActivity)
def activity_post_save(sender, instance, created, **kwargs):
    """Publish activity events after save"""
    try:
        if created:
            # New activity created
            def _publish_activity_created():
                publish_activity_created(
                    plan_id=str(instance.plan_id),
                    activity_id=str(instance.id),
                    title=instance.title,
                    activity_type=instance.activity_type,
                    start_time=instance.start_time.isoformat() if instance.start_time else None,
                    end_time=instance.end_time.isoformat() if instance.end_time else None,
                    location_name=instance.location_name,
                    estimated_cost=float(instance.estimated_cost) if instance.estimated_cost else None
                )
            transaction.on_commit(_publish_activity_created)
            
        else:
            # Activity updated
            # Check if completion status changed
            if hasattr(instance, '_state') and instance._state.adding is False:
                try:
                    old_instance = PlanActivity.objects.get(pk=instance.pk)
                    if not old_instance.is_completed and instance.is_completed:
                        # Activity just completed
                        def _publish_activity_completed():
                            publish_activity_completed(
                                plan_id=str(instance.plan_id),
                                activity_id=str(instance.id),
                                title=instance.title
                            )
                        transaction.on_commit(_publish_activity_completed)
                        return
                except PlanActivity.DoesNotExist:
                    pass
            
            # General activity update
            def _publish_activity_updated():
                publish_activity_updated(
                    plan_id=str(instance.plan_id),
                    activity_id=str(instance.id),
                    title=instance.title,
                    is_completed=instance.is_completed,
                    last_updated=instance.updated_at.isoformat()
                )
            transaction.on_commit(_publish_activity_updated)
            
    except Exception as e:
        logger.error(f"Error publishing activity event: {e}")


@receiver(post_delete, sender=PlanActivity)
def activity_post_delete(sender, instance, **kwargs):
    """Publish activity deletion event"""
    try:
        def _publish_activity_deleted():
            publish_activity_deleted(
                plan_id=str(instance.plan_id),
                activity_id=str(instance.id),
                title=instance.title
            )
        transaction.on_commit(_publish_activity_deleted)
        
    except Exception as e:
        logger.error(f"Error publishing activity deletion event: {e}")
