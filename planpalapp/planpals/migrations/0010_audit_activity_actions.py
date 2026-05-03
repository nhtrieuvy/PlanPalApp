# Generated manually for activity audit-log actions.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0009_groupmembership_plan_creator_role'),
    ]

    operations = [
        migrations.AlterField(
            model_name='auditlog',
            name='action',
            field=models.CharField(
                choices=[
                    ('CREATE_PLAN', 'Create Plan'),
                    ('UPDATE_PLAN', 'Update Plan'),
                    ('DELETE_PLAN', 'Delete Plan'),
                    ('COMPLETE_PLAN', 'Complete Plan'),
                    ('CREATE_ACTIVITY', 'Create Activity'),
                    ('UPDATE_ACTIVITY', 'Update Activity'),
                    ('UPDATE_BUDGET', 'Update Budget'),
                    ('CREATE_EXPENSE', 'Create Expense'),
                    ('JOIN_GROUP', 'Join Group'),
                    ('LEAVE_GROUP', 'Leave Group'),
                    ('CHANGE_ROLE', 'Change Role'),
                    ('DELETE_GROUP', 'Delete Group'),
                    ('NOTIFICATION_OPENED', 'Notification Opened'),
                ],
                db_index=True,
                help_text='Normalized audit action name',
                max_length=50,
            ),
        ),
    ]
