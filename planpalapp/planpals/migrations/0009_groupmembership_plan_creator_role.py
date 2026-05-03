from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0008_chatmessage_attachment_resource_type'),
    ]

    operations = [
        migrations.AlterField(
            model_name='groupmembership',
            name='role',
            field=models.CharField(
                choices=[
                    ('admin', 'Administrator'),
                    ('plan_creator', 'Plan creator'),
                    ('member', 'Member'),
                ],
                db_index=True,
                default='member',
                help_text='Role',
                max_length=20,
            ),
        ),
    ]
