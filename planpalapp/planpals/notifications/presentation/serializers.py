"""
Notification presentation serializers.
"""
from __future__ import annotations

from rest_framework import serializers

from planpals.notifications.infrastructure.models import (
    Notification,
    NotificationPreference,
)


class NotificationSerializer(serializers.ModelSerializer):
    user_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = Notification
        fields = [
            'id',
            'user_id',
            'type',
            'title',
            'message',
            'data',
            'is_read',
            'read_at',
            'created_at',
        ]
        read_only_fields = fields


class NotificationFilterSerializer(serializers.Serializer):
    is_read = serializers.BooleanField(required=False)
    cursor = serializers.CharField(required=False, allow_blank=False)
    page_size = serializers.IntegerField(required=False, min_value=1, max_value=100, default=20)


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = [
            'push_enabled',
            'quiet_hours_enabled',
            'quiet_hours_start',
            'quiet_hours_end',
            'timezone',
            'daily_digest_enabled',
            'daily_digest_hour',
        ]
        extra_kwargs = {
            'daily_digest_hour': {'min_value': 0, 'max_value': 23},
        }
