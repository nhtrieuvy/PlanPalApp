from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from planpals.shared.base_models import BaseModel


class GroupPoll(BaseModel):
    group = models.ForeignKey(
        'planpals.Group', on_delete=models.CASCADE, related_name='group_polls'
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='created_group_polls',
    )
    question = models.CharField(max_length=240)
    allow_multiple = models.BooleanField(default=False)
    closes_at = models.DateTimeField(null=True, blank=True, db_index=True)
    is_closed = models.BooleanField(default=False, db_index=True)
    client_mutation_id = models.CharField(
        max_length=100, null=True, blank=True, unique=True
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_group_polls'
        ordering = ['-created_at', '-id']
        indexes = [models.Index(fields=['group', 'is_closed', 'created_at'])]


class GroupPollOption(BaseModel):
    poll = models.ForeignKey(
        GroupPoll, on_delete=models.CASCADE, related_name='options'
    )
    text = models.CharField(max_length=160)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_group_poll_options'
        ordering = ['order', 'created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['poll', 'text'], name='unique_group_poll_option_text'
            )
        ]


class GroupPollVote(BaseModel):
    poll = models.ForeignKey(
        GroupPoll, on_delete=models.CASCADE, related_name='votes'
    )
    option = models.ForeignKey(
        GroupPollOption, on_delete=models.CASCADE, related_name='votes'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='group_poll_votes',
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_group_poll_votes'
        constraints = [
            models.UniqueConstraint(
                fields=['option', 'user'], name='unique_group_poll_option_vote'
            )
        ]
        indexes = [
            models.Index(fields=['poll', 'user']),
            models.Index(fields=['option', 'created_at']),
        ]

    def clean(self):
        if self.option_id and self.poll_id and self.option.poll_id != self.poll_id:
            raise ValidationError('Option must belong to the same poll.')


class LiveLocationShare(BaseModel):
    conversation = models.ForeignKey(
        'planpals.Conversation',
        on_delete=models.CASCADE,
        related_name='live_location_shares',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='live_location_shares',
    )
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    accuracy_meters = models.DecimalField(
        max_digits=8, decimal_places=2, null=True, blank=True
    )
    consent_granted_at = models.DateTimeField()
    expires_at = models.DateTimeField(db_index=True)
    stopped_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    client_mutation_id = models.CharField(
        max_length=100, null=True, blank=True, unique=True
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_live_location_shares'
        ordering = ['-updated_at']
        indexes = [
            models.Index(
                fields=['conversation', 'is_active', 'expires_at'],
                name='live_location_scope_idx',
            ),
            models.Index(
                fields=['user', 'is_active'], name='live_location_user_idx'
            ),
        ]

    def clean(self):
        if not -90 <= float(self.latitude) <= 90:
            raise ValidationError('Latitude must be between -90 and 90.')
        if not -180 <= float(self.longitude) <= 180:
            raise ValidationError('Longitude must be between -180 and 180.')
