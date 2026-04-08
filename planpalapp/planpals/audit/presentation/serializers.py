from rest_framework import serializers

from planpals.audit.domain.entities import AuditAction
from planpals.audit.infrastructure.models import AuditLog
from planpals.auth.presentation.serializers import UserSummarySerializer


class AuditLogSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    user_id = serializers.UUIDField(read_only=True, allow_null=True)

    class Meta:
        model = AuditLog
        fields = [
            'id',
            'user_id',
            'user',
            'action',
            'resource_type',
            'resource_id',
            'metadata',
            'created_at',
        ]
        read_only_fields = fields


class AuditLogFilterSerializer(serializers.Serializer):
    user_id = serializers.UUIDField(required=False)
    action = serializers.ChoiceField(
        choices=[(value, value) for value in AuditAction.values()],
        required=False,
    )
    resource_type = serializers.CharField(required=False)
    date_from = serializers.DateTimeField(required=False)
    date_to = serializers.DateTimeField(required=False)
    cursor = serializers.CharField(required=False, allow_blank=False)
    page_size = serializers.IntegerField(required=False, min_value=1, max_value=100, default=20)

    def validate(self, attrs):
        date_from = attrs.get('date_from')
        date_to = attrs.get('date_to')
        if date_from and date_to and date_from > date_to:
            raise serializers.ValidationError('date_from must be earlier than or equal to date_to')
        return attrs
