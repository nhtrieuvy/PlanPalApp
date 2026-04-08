from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0003_audit_log'),
    ]

    operations = [
        migrations.CreateModel(
            name='Notification',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('type', models.CharField(choices=[('PLAN_REMINDER', 'Plan Reminder'), ('GROUP_JOIN', 'Group Join'), ('GROUP_INVITE', 'Group Invite'), ('ROLE_CHANGED', 'Role Changed'), ('PLAN_UPDATED', 'Plan Updated'), ('NEW_MESSAGE', 'New Message')], db_index=True, max_length=50)),
                ('title', models.CharField(max_length=255)),
                ('message', models.TextField()),
                ('data', models.JSONField(blank=True, default=dict)),
                ('is_read', models.BooleanField(db_index=True, default=False)),
                ('read_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True, db_index=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='notifications', to='planpals.user')),
            ],
            options={
                'db_table': 'planpal_notifications',
                'ordering': ['-created_at', '-id'],
            },
        ),
        migrations.CreateModel(
            name='UserDeviceToken',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('token', models.CharField(max_length=255, unique=True)),
                ('platform', models.CharField(choices=[('android', 'Android'), ('ios', 'iOS'), ('web', 'Web')], max_length=20)),
                ('is_active', models.BooleanField(db_index=True, default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('last_seen_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='device_tokens', to='planpals.user')),
            ],
            options={
                'db_table': 'planpal_user_device_tokens',
            },
        ),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['user', 'is_read'], name='notif_user_read_idx'),
        ),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['created_at'], name='notif_created_idx'),
        ),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['type'], name='notif_type_idx'),
        ),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['user', 'created_at'], name='notif_user_created_idx'),
        ),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['created_at', 'id'], name='notif_cursor_idx'),
        ),
        migrations.AddIndex(
            model_name='userdevicetoken',
            index=models.Index(fields=['user', 'is_active'], name='notif_token_user_idx'),
        ),
        migrations.AddIndex(
            model_name='userdevicetoken',
            index=models.Index(fields=['platform', 'is_active'], name='notif_token_platform_idx'),
        ),
    ]
