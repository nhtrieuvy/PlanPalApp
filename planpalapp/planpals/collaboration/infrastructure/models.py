from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from planpals.collaboration.domain.entities import (
    AvailabilityStatus,
    WorkItemStatus,
    WorkItemType,
)
from planpals.shared.base_models import BaseModel


class AvailabilityPoll(BaseModel):
    group = models.ForeignKey(
        'planpals.Group', on_delete=models.CASCADE, related_name='availability_polls'
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='created_availability_polls',
    )
    title = models.CharField(max_length=200)
    closes_at = models.DateTimeField(null=True, blank=True, db_index=True)
    is_closed = models.BooleanField(default=False, db_index=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_availability_polls'
        ordering = ['-created_at']
        indexes = [models.Index(fields=['group', 'is_closed', 'created_at'])]


class AvailabilityOption(BaseModel):
    poll = models.ForeignKey(
        AvailabilityPoll, on_delete=models.CASCADE, related_name='options'
    )
    label = models.CharField(max_length=120, blank=True)
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_availability_options'
        ordering = ['start_at']
        constraints = [
            models.UniqueConstraint(
                fields=['poll', 'start_at', 'end_at'],
                name='unique_poll_time_option',
            )
        ]
        indexes = [models.Index(fields=['poll', 'start_at'])]

    def clean(self):
        if self.start_at and self.end_at and self.end_at <= self.start_at:
            raise ValidationError('Option end time must be after start time.')


class AvailabilityVote(BaseModel):
    option = models.ForeignKey(
        AvailabilityOption, on_delete=models.CASCADE, related_name='votes'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='availability_votes',
    )
    status = models.CharField(
        max_length=20,
        choices=[(value, value) for value in AvailabilityStatus.values()],
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_availability_votes'
        constraints = [models.UniqueConstraint(
            fields=['option', 'user'], name='unique_availability_vote'
        )]
        indexes = [
            models.Index(fields=['option', 'status']),
            models.Index(fields=['user', 'created_at']),
        ]


class PlanWorkItem(BaseModel):
    plan = models.ForeignKey(
        'planpals.Plan', on_delete=models.CASCADE, related_name='work_items'
    )
    activity = models.ForeignKey(
        'planpals.PlanActivity', on_delete=models.CASCADE,
        related_name='work_items', null=True, blank=True,
    )
    title = models.CharField(max_length=200)
    details = models.TextField(blank=True)
    item_type = models.CharField(
        max_length=20,
        choices=[(value, value) for value in WorkItemType.values()],
        default=WorkItemType.TASK.value, db_index=True,
    )
    status = models.CharField(
        max_length=20,
        choices=[(value, value) for value in WorkItemStatus.values()],
        default=WorkItemStatus.TODO.value, db_index=True,
    )
    assignee = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        related_name='assigned_plan_work_items', null=True, blank=True,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='created_plan_work_items',
    )
    due_at = models.DateTimeField(null=True, blank=True, db_index=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_work_items'
        ordering = ['status', 'due_at', 'order', 'created_at']
        indexes = [
            models.Index(fields=['plan', 'item_type', 'status']),
            models.Index(fields=['assignee', 'status', 'due_at']),
        ]

    def clean(self):
        if self.activity_id and self.plan_id and self.activity.plan_id != self.plan_id:
            raise ValidationError('Activity must belong to the same plan.')


class PlanComment(BaseModel):
    plan = models.ForeignKey(
        'planpals.Plan', on_delete=models.CASCADE, related_name='comments'
    )
    activity = models.ForeignKey(
        'planpals.PlanActivity', on_delete=models.CASCADE,
        related_name='comments', null=True, blank=True,
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='plan_comments',
    )
    parent = models.ForeignKey(
        'self', on_delete=models.CASCADE, related_name='replies',
        null=True, blank=True,
    )
    body = models.TextField(max_length=4000)
    is_pinned = models.BooleanField(default=False, db_index=True)
    pinned_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        related_name='pinned_plan_comments', null=True, blank=True,
    )
    pinned_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_comments'
        ordering = ['-is_pinned', '-created_at']
        indexes = [
            models.Index(fields=['plan', 'is_pinned', 'created_at']),
            models.Index(fields=['activity', 'created_at']),
        ]

    def clean(self):
        if self.activity_id and self.plan_id and self.activity.plan_id != self.plan_id:
            raise ValidationError('Activity must belong to the same plan.')
        if self.parent_id and self.parent.plan_id != self.plan_id:
            raise ValidationError('Reply must belong to the same plan.')


class CommentMention(BaseModel):
    comment = models.ForeignKey(
        PlanComment, on_delete=models.CASCADE, related_name='mentions'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='comment_mentions',
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_comment_mentions'
        constraints = [models.UniqueConstraint(
            fields=['comment', 'user'], name='unique_comment_mention'
        )]
        indexes = [models.Index(fields=['user', 'created_at'])]


class CommentReaction(BaseModel):
    comment = models.ForeignKey(
        PlanComment, on_delete=models.CASCADE, related_name='reactions'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='comment_reactions',
    )
    reaction = models.CharField(max_length=20)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_comment_reactions'
        constraints = [models.UniqueConstraint(
            fields=['comment', 'user'], name='one_reaction_per_comment_user'
        )]
        indexes = [models.Index(fields=['comment', 'reaction'])]
