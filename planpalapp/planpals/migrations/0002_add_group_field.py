# Generated manual migration to ensure Conversation.group column exists
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='conversation',
            name='group',
            field=models.OneToOneField(
                to='planpals.Group',
                on_delete=django.db.models.deletion.CASCADE,
                null=True,
                blank=True,
                related_name='conversation',
                help_text='Group (only for group conversations)'
            ),
        ),
    ]
