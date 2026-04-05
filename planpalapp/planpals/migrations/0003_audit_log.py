from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0002_db_performance_indexes'),
    ]

    operations = [
        migrations.CreateModel(
            name='AuditLog',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('action', models.CharField(choices=[('CREATE_PLAN', 'Create Plan'), ('UPDATE_PLAN', 'Update Plan'), ('DELETE_PLAN', 'Delete Plan'), ('JOIN_GROUP', 'Join Group'), ('LEAVE_GROUP', 'Leave Group'), ('CHANGE_ROLE', 'Change Role'), ('DELETE_GROUP', 'Delete Group')], db_index=True, help_text='Normalized audit action name', max_length=50)),
                ('resource_type', models.CharField(help_text='Logical resource type such as plan or group', max_length=50)),
                ('resource_id', models.UUIDField(blank=True, help_text='Identifier of the affected resource', null=True)),
                ('metadata', models.JSONField(blank=True, default=dict, help_text='Additional structured context for the audit record')),
                ('created_at', models.DateTimeField(auto_now_add=True, db_index=True, help_text='Creation timestamp')),
                ('user', models.ForeignKey(blank=True, help_text='Actor who performed the action', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='audit_logs', to='planpals.user')),
            ],
            options={
                'db_table': 'planpal_audit_logs',
                'ordering': ['-created_at', '-id'],
            },
        ),
        migrations.AddIndex(
            model_name='auditlog',
            index=models.Index(fields=['user', 'created_at'], name='audit_user_created_idx'),
        ),
        migrations.AddIndex(
            model_name='auditlog',
            index=models.Index(fields=['resource_type', 'resource_id'], name='audit_resource_idx'),
        ),
        migrations.AddIndex(
            model_name='auditlog',
            index=models.Index(fields=['action'], name='audit_action_idx'),
        ),
        migrations.AddIndex(
            model_name='auditlog',
            index=models.Index(fields=['created_at', 'id'], name='audit_created_id_idx'),
        ),
    ]
