from django.contrib.auth.models import AbstractUser
from django.db import models

from apps.core.models import TimeStampedModel


class User(AbstractUser):
    # Django demandera le téléphone pendant `createsuperuser`,
    # évitant l'insertion de valeurs vides dupliquées sur un champ unique.
    REQUIRED_FIELDS = ["phone"]

    class Role(models.TextChoices):
        ADMIN = "admin", "Admin"
        SELLER = "seller", "Seller"
        CASHIER = "cashier", "Cashier"

    class BusinessCategory(models.TextChoices):
        RESTAURANT = "restaurant", "Restaurant"
        BOUTIQUE = "boutique", "Boutique"
        PHARMACIE = "pharmacie", "Pharmacie"
        SALON_COIFFURE = "salon_coiffure", "Salon de coiffure"

    phone = models.CharField(max_length=32, unique=True)
    role = models.CharField(
        max_length=32,
        choices=Role.choices,
        default=Role.SELLER,
    )
    business_category = models.CharField(
        max_length=32,
        choices=BusinessCategory.choices,
        default=BusinessCategory.BOUTIQUE,
    )
    company_name = models.CharField(max_length=255, blank=True, default="")
    company_trade_name = models.CharField(max_length=255, blank=True, default="")
    legal_form = models.CharField(max_length=64, blank=True, default="")
    rccm = models.CharField(max_length=64, blank=True, default="")
    idnat = models.CharField(max_length=64, blank=True, default="")
    nif = models.CharField(max_length=64, blank=True, default="")
    company_email = models.EmailField(blank=True, default="")
    company_phone = models.CharField(max_length=32, blank=True, default="")
    company_country = models.CharField(max_length=64, blank=True, default="RDC")
    company_province = models.CharField(max_length=128, blank=True, default="")
    company_city = models.CharField(max_length=128, blank=True, default="")
    company_commune = models.CharField(max_length=128, blank=True, default="")
    company_quarter = models.CharField(max_length=128, blank=True, default="")
    company_avenue = models.CharField(max_length=128, blank=True, default="")
    company_number = models.CharField(max_length=64, blank=True, default="")

    def __str__(self) -> str:
        return f"{self.username} ({self.phone})"


class PhoneOTP(TimeStampedModel):
    phone = models.CharField(max_length=32, db_index=True)
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    attempts = models.PositiveIntegerField(default=0)

    class Meta:
        indexes = [
            models.Index(fields=["phone", "expires_at"]),
        ]


class PasswordResetOTP(TimeStampedModel):
    phone = models.CharField(max_length=32, db_index=True, blank=True, default="")
    email = models.EmailField(blank=True, default="")
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    attempts = models.PositiveIntegerField(default=0)

    class Meta:
        indexes = [
            models.Index(fields=["phone", "expires_at"]),
        ]


class InAppNotification(TimeStampedModel):
    """Notifications in-app gratuites (sans Firebase)."""

    class Category(models.TextChoices):
        SYSTEM = "system", "System"
        ORDER = "order", "Order"
        STOCK = "stock", "Stock"
        SALE = "sale", "Sale"

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="in_app_notifications",
    )
    title = models.CharField(max_length=120)
    body = models.TextField()
    category = models.CharField(
        max_length=32,
        choices=Category.choices,
        default=Category.SYSTEM,
    )
    is_read = models.BooleanField(default=False)
    payload = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ("-created_at",)
        indexes = [
            models.Index(fields=["user", "is_read", "created_at"]),
        ]


class PushDevice(TimeStampedModel):
    class Platform(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="push_devices",
    )
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(
        max_length=16,
        choices=Platform.choices,
        default=Platform.ANDROID,
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "is_active"]),
        ]

