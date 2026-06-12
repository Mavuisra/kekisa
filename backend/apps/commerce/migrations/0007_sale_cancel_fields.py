from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("commerce", "0006_supplier_product_source_product"),
    ]

    operations = [
        migrations.AddField(
            model_name="sale",
            name="cancel_reason",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddField(
            model_name="sale",
            name="canceled_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
