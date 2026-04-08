"""
Notification infrastructure ORM models.
"""
from __future__ import annotations

from uuid import uuid4

from django.conf import settings
from django.db import models

from planpals.notifications.domain.entities import NotificationType


class Notification(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    type = models.CharField(
        max_length=50,
        choices=NotificationType.choices(),
        db_index=True,
    )
    title = models.CharField(max_length=255)
    message = models.TextField()
    data = models.JSONField(default=dict, blank=True)
    is_read = models.BooleanField(default=False, db_index=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_notifications'
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['user', 'is_read'], name='notif_user_read_idx'),
            models.Index(fields=['created_at'], name='notif_created_idx'),
            models.Index(fields=['type'], name='notif_type_idx'),
            models.Index(fields=['user', 'created_at'], name='notif_user_created_idx'),
            models.Index(fields=['created_at', 'id'], name='notif_cursor_idx'),
        ]

    def __str__(self) -> str:
        return f'{self.user_id} - {self.type}'


class UserDeviceToken(models.Model):
    PLATFORM_ANDROID = 'android'
    PLATFORM_IOS = 'ios'
    PLATFORM_WEB = 'web'
    PLATFORM_CHOICES = [
        (PLATFORM_ANDROID, 'Android'),
        (PLATFORM_IOS, 'iOS'),
        (PLATFORM_WEB, 'Web'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES)
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_user_device_tokens'
        indexes = [
            models.Index(fields=['user', 'is_active'], name='notif_token_user_idx'),
            models.Index(fields=['platform', 'is_active'], name='notif_token_platform_idx'),
        ]

    def __str__(self) -> str:
        return f'{self.user_id} - {self.platform}'
