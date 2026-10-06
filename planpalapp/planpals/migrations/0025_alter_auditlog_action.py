from django.db import migrations, models

from planpals.audit.domain.entities import AuditAction


class Migration(migrations.Migration):
    dependencies = [
        ('planpals', '0024_expense_soft_delete'),
    ]

    operations = [
        migrations.AlterField(
            model_name='auditlog',
            name='action',
            field=models.CharField(
                choices=AuditAction.choices(),
                db_index=True,
                help_text='Normalized audit action name',
                max_length=50,
            ),
        ),
    ]
