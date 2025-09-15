# Manual migration to add missing conversation FK to ChatMessage
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('planpals', '0002_add_group_field'),
    ]

    operations = [
        migrations.AddField(
            model_name='chatmessage',
            name='conversation',
            field=models.ForeignKey(
                to='planpals.Conversation',
                on_delete=django.db.models.deletion.CASCADE,
                null=True,
                blank=True,
                related_name='messages',
                help_text='The conversation contains this message'
            ),
        ),
    ]
