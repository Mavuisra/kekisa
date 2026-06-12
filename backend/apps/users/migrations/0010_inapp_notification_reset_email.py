from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("users", "0009_password_reset_push_device"),
    ]

    operations = [
        migrations.AddField(
            model_name="passwordresetotp",
            name="email",
            field=models.EmailField(blank=True, default=""),
        ),
        migrations.AlterField(
            model_name="passwordresetotp",
            name="phone",
            field=models.CharField(blank=True, db_index=True, default="", max_length=32),
        ),
        migrations.CreateModel(
            name="InAppNotification",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("title", models.CharField(max_length=120)),
                ("body", models.TextField()),
                (
                    "category",
                    models.CharField(
                        choices=[
                            ("system", "System"),
                            ("order", "Order"),
                            ("stock", "Stock"),
                            ("sale", "Sale"),
                        ],
                        default="system",
                        max_length=32,
                    ),
                ),
                ("is_read", models.BooleanField(default=False)),
                ("payload", models.JSONField(blank=True, default=dict)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="in_app_notifications",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ("-created_at",),
                "indexes": [
                    models.Index(
                        fields=["user", "is_read", "created_at"],
                        name="users_inapp_user_id_7c2fae_idx",
                    )
                ],
            },
        ),
    ]
