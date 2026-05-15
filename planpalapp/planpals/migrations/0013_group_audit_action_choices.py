from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0012_add_email_verification'),
    ]

    operations = [
        migrations.AlterField(
            model_name='auditlog',
            name='action',
            field=models.CharField(
                choices=[
                    ('CREATE_GROUP', 'Create Group'),
                    ('UPDATE_GROUP', 'Update Group'),
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
                    ('ADD_MEMBER', 'Add Member'),
                    ('REMOVE_MEMBER', 'Remove Member'),
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
