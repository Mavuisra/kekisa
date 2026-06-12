from django.conf import settings
from django.db import models

from apps.core.models import TimeStampedModel
from .kinshasa_locations import BUSINESS_DOMAINS


class Customer(TimeStampedModel):
    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="commerce_customers",
    )
    full_name = models.CharField(max_length=150)
    phone = models.CharField(max_length=32, blank=True)
    email = models.EmailField(blank=True)
    segment = models.CharField(max_length=32, default="regular")
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ("full_name",)


class Product(TimeStampedModel):
    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="commerce_products",
    )
    name = models.CharField(max_length=150)
    sku = models.CharField(max_length=64)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    cost_price = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    stock_quantity = models.IntegerField(default=0)
    reorder_threshold = models.IntegerField(default=5)
    is_active = models.BooleanField(default=True)

    class Meta:
        unique_together = ("seller", "sku")
        ordering = ("name",)


class Sale(TimeStampedModel):
    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="commerce_sales",
    )
    customer = models.ForeignKey(
        Customer,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="sales",
    )
    subtotal = models.DecimalField(max_digits=12, decimal_places=2)
    discount_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total = models.DecimalField(max_digits=12, decimal_places=2)
    payment_method = models.CharField(max_length=32, default="cash")
    status = models.CharField(max_length=32, default="completed")
    cancel_reason = models.CharField(max_length=255, blank=True, default="")
    canceled_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)


class SaleItem(models.Model):
    sale = models.ForeignKey(
        Sale,
        on_delete=models.CASCADE,
        related_name="items",
    )
    product = models.ForeignKey(
        Product,
        on_delete=models.PROTECT,
        related_name="sale_items",
    )
    quantity = models.PositiveIntegerField()
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    line_total = models.DecimalField(max_digits=12, decimal_places=2)


class StockMovement(TimeStampedModel):
    class MovementType(models.TextChoices):
        IN = "in", "In"
        OUT = "out", "Out"
        ADJUSTMENT = "adjustment", "Adjustment"

    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="stock_movements",
    )
    product = models.ForeignKey(
        Product,
        on_delete=models.CASCADE,
        related_name="stock_movements",
    )
    movement_type = models.CharField(max_length=20, choices=MovementType.choices)
    quantity = models.IntegerField()
    reason = models.CharField(max_length=120, blank=True)
    balance_after = models.IntegerField()
    reference = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ("-created_at",)


class SupplierProfile(TimeStampedModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="supplier_profile",
    )
    business_name = models.CharField(max_length=180)
    description = models.TextField(blank=True)
    phone = models.CharField(max_length=32)
    is_active = models.BooleanField(default=False)
    business_domain = models.CharField(max_length=32, choices=BUSINESS_DOMAINS, default="other")
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    commune = models.CharField(max_length=128, blank=True)
    quarter = models.CharField(max_length=128, blank=True)
    avenue = models.CharField(max_length=128, blank=True)
    profile_image_url = models.URLField(blank=True)
    cover_image_url = models.URLField(blank=True)
    support_whatsapp = models.CharField(max_length=32, blank=True)

    class Meta:
        ordering = ("business_name",)


class SupplierProduct(TimeStampedModel):
    supplier = models.ForeignKey(
        SupplierProfile,
        on_delete=models.CASCADE,
        related_name="products",
    )
    source_product = models.ForeignKey(
        Product,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="supplier_publications",
    )
    name = models.CharField(max_length=150)
    price = models.DecimalField(max_digits=12, decimal_places=2)
    is_available = models.BooleanField(default=True)
    image_url = models.URLField(blank=True)

    class Meta:
        ordering = ("name",)


class SupplierOrder(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"
        CANCELED = "canceled", "Canceled"
        FULFILLED = "fulfilled", "Fulfilled"

    merchant = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="supplier_orders_made",
    )
    supplier = models.ForeignKey(
        SupplierProfile,
        on_delete=models.CASCADE,
        related_name="received_orders",
    )
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.PENDING)
    notes = models.TextField(blank=True)
    delivery_commune = models.CharField(max_length=128, blank=True)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    class Meta:
        ordering = ("-created_at",)


class SupplierOrderItem(models.Model):
    order = models.ForeignKey(
        SupplierOrder,
        on_delete=models.CASCADE,
        related_name="items",
    )
    supplier_product = models.ForeignKey(
        SupplierProduct,
        on_delete=models.PROTECT,
        related_name="order_items",
    )
    product_name = models.CharField(max_length=150)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    quantity = models.PositiveIntegerField()
    line_total = models.DecimalField(max_digits=12, decimal_places=2)


class SupplierCallSession(TimeStampedModel):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        ENDED = "ended", "Ended"
        REJECTED = "rejected", "Rejected"

    caller = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="supplier_calls_started",
    )
    supplier = models.ForeignKey(
        SupplierProfile,
        on_delete=models.CASCADE,
        related_name="call_sessions",
    )
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.ACTIVE)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)


class SupplierConversation(TimeStampedModel):
    merchant = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="supplier_conversations_started",
    )
    supplier = models.ForeignKey(
        SupplierProfile,
        on_delete=models.CASCADE,
        related_name="conversations",
    )
    last_message_preview = models.CharField(max_length=240, blank=True)

    class Meta:
        ordering = ("-updated_at",)
        unique_together = ("merchant", "supplier")


class SupplierMessage(TimeStampedModel):
    class MessageType(models.TextChoices):
        TEXT = "text", "Text"
        VOICE = "voice", "Voice"

    conversation = models.ForeignKey(
        SupplierConversation,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="supplier_messages_sent",
    )
    message_type = models.CharField(max_length=16, choices=MessageType.choices, default=MessageType.TEXT)
    content = models.TextField(blank=True)
    voice_url = models.URLField(blank=True)

    class Meta:
        ordering = ("created_at",)
