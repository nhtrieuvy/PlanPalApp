"""
Plans Infrastructure — Django ORM Models

These are Django ORM model definitions (persistence concern).
They live in the infrastructure layer because they depend on Django's ORM.

The domain layer (entities.py, repositories.py, events.py) is pure Python.
"""
from uuid import UUID
from collections import defaultdict
from decimal import Decimal
from datetime import datetime, timedelta, date
from typing import Dict, List, Optional, Any, Union, Tuple

from django.db import models, transaction
from django.db.models import QuerySet, Q, F, Count, Sum
from django.utils import timezone
from django.core.exceptions import ValidationError

from celery import current_app

from planpals.shared.base_models import BaseModel


class PlanQuerySet(models.QuerySet['Plan']):
    
    def personal(self) -> 'PlanQuerySet':
        return self.filter(plan_type='personal')
    
    def group_plans(self) -> 'PlanQuerySet':
        return self.filter(plan_type='group')
    
    def public(self) -> 'PlanQuerySet':
        return self.filter(is_public=True)
    
    def upcoming(self) -> 'PlanQuerySet':
        return self.filter(status='upcoming')
    
    def ongoing(self) -> 'PlanQuerySet':
        return self.filter(status='ongoing')
    
    def completed(self) -> 'PlanQuerySet':
        return self.filter(status='completed')
    
    def active(self) -> 'PlanQuerySet':
        return self.exclude(status__in=['cancelled', 'completed'])
    
    def for_user(self, user: Union['User', UUID]) -> 'PlanQuerySet':
        return self.filter(
            Q(creator=user) |  # Own plans
            Q(group__members=user) |  # Group plans
            Q(is_public=True)  # Public plans
        ).distinct()
    
    def with_activity_count(self) -> 'PlanQuerySet':
        return self.annotate(
            activity_count_annotated=Count('activities', distinct=True)
        )
    
    def with_total_cost(self) -> 'PlanQuerySet':
        return self.annotate(
            total_cost_annotated=Sum('activities__estimated_cost')
        )
    
    def with_stats(self) -> 'PlanQuerySet':
        return self.with_activity_count().with_total_cost()
    
    def in_date_range(self, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None) -> 'PlanQuerySet':
        queryset = self
        if start_date:
            queryset = queryset.filter(start_date__gte=start_date)
        if end_date:
            queryset = queryset.filter(end_date__lte=end_date)
        return queryset
    
    def plans_need_status_update(self) -> 'PlanQuerySet':
        now = timezone.now()
        return self.filter(
            Q(
                status='upcoming',
                start_date__lte=now
            ) | Q(
                status='ongoing',
                end_date__lt=now
            )
        )
    

class Plan(BaseModel):
    title = models.CharField(
        max_length=200,
        help_text="Title of the plan"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Detailed description of the plan"
    )
    
    group = models.ForeignKey(
        'planpals.Group',
        on_delete=models.CASCADE,
        related_name='plans',
        blank=True,
        null=True,
        help_text="Group associated with the plan (null for personal plans)"
    )
    
    creator = models.ForeignKey(
        'planpals.User',
        on_delete=models.CASCADE,
        related_name='created_plans',
        help_text="Creator/owner of the plan"
    )
    
    PLAN_TYPES = [
        ('personal', 'Cá nhân'),
        ('group', 'Nhóm'),
    ]
    
    plan_type = models.CharField(
        max_length=20,
        choices=PLAN_TYPES,
        default='personal',
        db_index=True,
        help_text="Type of plan: personal or group"
    )
    
    start_date = models.DateTimeField(
        help_text="Start date of the trip"
    )
    
    end_date = models.DateTimeField(
        help_text="End date of the trip"
    )
    
    # Trạng thái công khai
    is_public = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Is the plan public?"
    )
    
    STATUS_CHOICES = [
        ('upcoming', 'Sắp bắt đầu'),
        ('ongoing', 'Đang diễn ra'),
        ('completed', 'Đã hoàn thành'),
        ('cancelled', 'Đã hủy'),
    ]
    
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='upcoming',
        db_index=True,
        help_text="Current status of the plan"
    )

    scheduled_start_task_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        help_text="Celery task id scheduled to start this plan"
    )

    scheduled_end_task_id = models.CharField(
        max_length=255,
        null=True,
        blank=True,
        help_text="Celery task id scheduled to complete this plan"
    )
    
    objects = PlanQuerySet.as_manager()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_plans'
        
        indexes = [
            *BaseModel.Meta.indexes,
            models.Index(fields=['creator', 'plan_type', 'status']),
            models.Index(fields=['group', 'status']),
            models.Index(fields=['start_date', 'end_date']),
            models.Index(fields=['is_public', 'plan_type', 'status']),
            # For plans_need_status_update Celery task:
            #   Q(status='upcoming', start_date__lte=now) | Q(status='ongoing', end_date__lt=now)
            models.Index(fields=['status', 'start_date']),
            models.Index(fields=['status', 'end_date']),
        ]

    def __str__(self) -> str:
        if self.is_personal():
            return f"{self.title} (Personal - {self.creator.username})"
        return f"{self.title} ({self.group.name})"

    def clean(self) -> None:   
        # Validate date
        if self.start_date and self.end_date:
            if self.end_date <= self.start_date:
                raise ValidationError("End date must be after start date")

        # Validate plan type consistency
        if self.plan_type == 'personal' and self.group is not None:
            raise ValidationError("Personal plan cannot have a group")

        if self.plan_type == 'group' and self.group is None:
            raise ValidationError("Group plan must have a group")

    def _auto_status(self) -> bool:
        if not (self.start_date and self.end_date):
            return False
            
        now = timezone.now()
        original_status = self.status
        
        if self.status == 'upcoming' and now >= self.start_date:
            self.status = 'ongoing'
            
        elif self.status == 'ongoing' and now > self.end_date:
            self.status = 'completed'
        
        return self.status != original_status

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.plan_type = 'personal' if self.group is None else 'group'
        status_changed = self._auto_status()
        # True khi chưa được lưu vào DB, kiểm tra xem đang xử lý plan mới hay cập nhật plan cũ
        is_new = self._state.adding
        
        dates_changed = False
        if not is_new and self.pk:
            update_fields = kwargs.get('update_fields', None)
            if update_fields is None or 'start_date' in update_fields or 'end_date' in update_fields:
                try:
                    old_plan = Plan.objects.only('start_date', 'end_date').get(pk=self.pk)
                    dates_changed = (
                        old_plan.start_date != self.start_date or 
                        old_plan.end_date != self.end_date
                    )
                except Plan.DoesNotExist:
                    is_new = True
                    dates_changed = False
        
        self.clean()
        super().save(*args, **kwargs)
        
        if is_new or dates_changed:
            if self.status == 'upcoming':
                try:
                    self.schedule_celery_tasks()
                except Exception:
                    pass
        
        if status_changed:
            pass  # Could add logging/notifications here

    def is_personal(self) -> bool:
        return self.plan_type == 'personal'

    def is_group_plan(self) -> bool:
        return self.plan_type == 'group'


    @property
    def collaborators(self) -> List:
        if self.is_personal():
            return [self.creator]
        elif self.is_group_plan() and self.group:
            return list(self.group.members.all())
        return []

    
    @property
    def duration_days(self) -> int:
        if self.start_date and self.end_date:
            return (self.end_date.date() - self.start_date.date()).days + 1
        return 0

    @property
    def activities_count(self) -> int:
        if hasattr(self, 'activity_count_annotated'):
            return self.activity_count_annotated
        return self.activities.count()

    @property
    def total_estimated_cost(self) -> Decimal:
        if hasattr(self, 'total_cost_annotated'):
            return self.total_cost_annotated or Decimal('0')
        
        result = self.activities.aggregate(
            total=Sum('estimated_cost')
        )['total']
        return result or Decimal('0')

    def get_members(self) -> QuerySet:
        from planpals.models import User
        if self.is_personal():
            return User.objects.filter(id=self.creator_id).select_related()
        if self.group_id:
            return self.group.members.select_related()
        return User.objects.none()


    @property
    def activities_by_date(self) -> Dict[date, List['PlanActivity']]:
        activities = self.activities.order_by('start_time').select_related()
        result = defaultdict(list)
        
        for activity in activities:
            date_key = activity.start_time.date()
            result[date_key].append(activity)
        
        return dict(result)

    def get_activities_by_date(self, date: date) -> QuerySet['PlanActivity']:
        return self.activities.filter(
            start_time__date=date
        ).order_by('start_time')

    def check_activity_overlap(self, start_time: datetime, end_time: datetime, exclude_id: Optional[str] = None) -> Optional['PlanActivity']:
        queryset = self.activities.filter(
            start_time__lt=end_time,
            end_time__gt=start_time
        )
        
        if exclude_id:
            queryset = queryset.exclude(id=exclude_id)
            
        return queryset.first()

    def has_time_conflict(self, start_time: datetime, end_time: datetime, exclude_activity: Optional['PlanActivity'] = None) -> bool:
        queryset = self.activities.filter(
            start_time__lt=end_time,
            end_time__gt=start_time 
        )
        
        if exclude_activity:
            queryset = queryset.exclude(id=exclude_activity.id)
            
        return queryset.exists()


class PlanActivity(BaseModel):    
    # Các loại hoạt động cụ thể hơn
    ACTIVITY_TYPES = [
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
    
    # Thuộc về plan nào
    plan = models.ForeignKey(
        Plan,
        on_delete=models.CASCADE,
        related_name='activities',
        help_text="Plan of this activity"
    )
    
    # Thông tin cơ bản
    title = models.CharField(
        max_length=200,
        help_text="Activity name"
    )
    
    description = models.TextField(
        blank=True,
        help_text="Activity description"
    )
    
    # Loại hoạt động
    activity_type = models.CharField(
        max_length=20,
        choices=ACTIVITY_TYPES,
        default='other',
        db_index=True,
        help_text="Activity type"
    )
    
    # Thời gian
    start_time = models.DateTimeField(
        help_text="Start time of the activity"
    )
    
    end_time = models.DateTimeField(
        help_text="End time of the activity"
    )
    
    # Thông tin địa điểm
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text="Name of the location"
    )
    
    location_address = models.TextField(
        blank=True,
        help_text="Detailed address"
    )
    
    # Tọa độ GPS
    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True, 
        null=True,
        help_text="Latitude"
    )
    
    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        blank=True, 
        null=True,
        help_text="Longitude"
    )
    
    goong_place_id = models.CharField(
        max_length=200,
        blank=True,
        help_text="Goong Map API place ID"
    )
    
    # Chi phí dự kiến
    estimated_cost = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        blank=True, 
        null=True,
        help_text="Estimated cost (VND)"
    )
    
    # Ghi chú
    notes = models.TextField(
        blank=True,
        help_text="Additional notes"
    )
    
    # Thứ tự trong ngày
    order = models.PositiveIntegerField(
        default=0,
        help_text="Order of activity in the day"
    )
    
    # Trạng thái hoàn thành
    is_completed = models.BooleanField(
        default=False,
        help_text="Has the activity been completed?"
    )
    
    # Version field cho optimistic locking
    version = models.PositiveIntegerField(
        default=1,
        help_text="Version cho conflict detection"
    )
    
    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_plan_activities'
        ordering = ['start_time']  # Đơn giản, chỉ theo thời gian
        
        indexes = [
            *BaseModel.Meta.indexes,
            # Index cho query activities của plan
            models.Index(fields=['plan', 'start_time']),
            # Index cho query theo loại hoạt động
            models.Index(fields=['activity_type', 'start_time']),
            # Index cho time conflict detection
            models.Index(fields=['plan', 'start_time', 'end_time']),
        ]

    def __str__(self) -> str:
        return f"{self.plan.title} - {self.title} ({self.start_time.strftime('%H:%M')})"

    def clean(self) -> None:
        super().clean()
        self._validate_time_bounds()
        self._validate_within_plan_timeline()
        self._validate_coordinates()
        self._validate_estimated_cost()

    def _validate_time_bounds(self) -> None:
        if self.start_time and self.end_time:
            if self.end_time <= self.start_time:
                raise ValidationError("End time must be after start time")

            duration = self.end_time - self.start_time
            if duration.total_seconds() > 24 * 3600:
                raise ValidationError("Activity duration must not exceed 24 hours")

    def _validate_within_plan_timeline(self) -> None:
        if self.plan_id and self.start_time and self.end_time:
            plan = self.plan
            if self.start_time.date() < plan.start_date.date():
                raise ValidationError("Activity cannot start before plan start date")
            if self.end_time.date() > plan.end_date.date():
                raise ValidationError("Activity cannot end after plan end date")

    def _validate_coordinates(self) -> None:
        if self.latitude is not None and not (-90 <= self.latitude <= 90):
            raise ValidationError("Latitude must be between -90 and 90")

        if self.longitude is not None and not (-180 <= self.longitude <= 180):
            raise ValidationError("Longitude must be between -180 and 180")

    def _validate_estimated_cost(self) -> None:
        if self.estimated_cost is not None and self.estimated_cost < 0:
            raise ValidationError("Estimated cost must be non-negative")

    def save(self, *args: Any, **kwargs: Any) -> None:        
        self.clean()
        
        is_creating = self._state.adding
        if not is_creating:  # This is an update
            self.version = F('version') + 1
        
        super(BaseModel, self).save(*args, **kwargs)
        
        if not is_creating:
            self.refresh_from_db(fields=['version'])

    def check_time_conflict(self, exclude_self: bool = True) -> QuerySet['PlanActivity']:
        conflicts = self.plan.activities.filter(
            start_time__lt=self.end_time,
            end_time__gt=self.start_time
        )
        
        if exclude_self and self.pk:
            conflicts = conflicts.exclude(pk=self.pk)
        
        return conflicts

    @property
    def duration_hours(self) -> int:
        if self.start_time and self.end_time:
            return int((self.end_time - self.start_time).total_seconds() / 60)
        return 0

    @property
    def is_today(self) -> bool:
        if self.start_time:
            return self.start_time.date() == timezone.now().date()
        return False

    @property
    def can_complete(self) -> bool:
        return self.start_time <= timezone.now() if self.start_time else False

    @property
    def has_location(self) -> bool:
        if self.latitude is not None and self.longitude is not None:
            return True
        if self.goong_place_id:
            return bool(str(self.goong_place_id).strip())
        if self.location_name:
            return bool(str(self.location_name).strip())
        return False
