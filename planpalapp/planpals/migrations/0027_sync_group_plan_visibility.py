from django.db import migrations


def sync_group_plan_visibility(apps, schema_editor):
    Plan = apps.get_model('planpals', 'Plan')
    Plan.objects.filter(plan_type='group', group__visibility='private').update(
        is_public=False
    )
    Plan.objects.filter(plan_type='group', group__visibility='public').update(
        is_public=True
    )


class Migration(migrations.Migration):
    dependencies = [('planpals', '0026_planpublication_friendtripinvitation')]

    operations = [migrations.RunPython(sync_group_plan_visibility, migrations.RunPython.noop)]
