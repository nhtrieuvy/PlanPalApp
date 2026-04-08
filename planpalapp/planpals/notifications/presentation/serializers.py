"""
Notification presentation serializers.
"""
from __future__ import annotations

from rest_framework import serializers

from planpals.notifications.infrastructure.models import Notification


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
