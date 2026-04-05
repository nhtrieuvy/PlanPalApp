"""
Audit infrastructure ORM models.
"""
from uuid import uuid4

from django.conf import settings
from django.db import models

from planpals.audit.domain.entities import AuditAction


class AuditLog(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='audit_logs',
        help_text='Actor who performed the action',
    )
    action = models.CharField(
        max_length=50,
        choices=AuditAction.choices(),
        db_index=True,
        help_text='Normalized audit action name',
    )
    resource_type = models.CharField(
        max_length=50,
        help_text='Logical resource type such as plan or group',
    )
    resource_id = models.UUIDField(
        null=True,
        blank=True,
        help_text='Identifier of the affected resource',
    )
    metadata = models.JSONField(
        default=dict,
        blank=True,
        help_text='Additional structured context for the audit record',
    )
    created_at = models.DateTimeField(
        auto_now_add=True,
        db_index=True,
        help_text='Creation timestamp',
    )

    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_audit_logs'
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['user', 'created_at'], name='audit_user_created_idx'),
            models.Index(fields=['resource_type', 'resource_id'], name='audit_resource_idx'),
            models.Index(fields=['action'], name='audit_action_idx'),
            models.Index(fields=['created_at', 'id'], name='audit_created_id_idx'),
        ]

    def __str__(self) -> str:
        return f'{self.action} on {self.resource_type}:{self.resource_id}'
