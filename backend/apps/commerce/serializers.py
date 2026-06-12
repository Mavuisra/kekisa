from rest_framework import serializers

from .models import (
    Customer,
    Product,
    Sale,
    SaleItem,
    SupplierCallSession,
    SupplierConversation,
    SupplierMessage,
    SupplierOrder,
    SupplierOrderItem,
    SupplierProduct,
    SupplierProfile,
)


class CustomerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Customer
        fields = [
            "id",
            "full_name",
            "phone",
            "email",
            "segment",
            "notes",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = [
            "id",
            "name",
            "sku",
            "unit_price",
            "cost_price",
            "stock_quantity",
            "reorder_threshold",
            "is_active",
        ]
        read_only_fields = ["id"]


class SaleItemCreateSerializer(serializers.Serializer):
    product_id = serializers.IntegerField()
    quantity = serializers.IntegerField(min_value=1)


class QuickSaleCreateSerializer(serializers.Serializer):
    items = SaleItemCreateSerializer(many=True, allow_empty=False)
    discount_rate = serializers.FloatField(required=False, min_value=0, max_value=100, default=0)
    payment_method = serializers.CharField(required=False, default="cash")
    customer_name = serializers.CharField(required=False, allow_blank=True)


class AiSaleDraftSerializer(serializers.Serializer):
    prompt = serializers.CharField(allow_blank=False)


class StockAddSerializer(serializers.Serializer):
    product_id = serializers.IntegerField()
    quantity = serializers.IntegerField(min_value=1)
    reason = serializers.CharField(required=False, allow_blank=True, max_length=120)


class SaleItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source="product.name", read_only=True)

    class Meta:
        model = SaleItem
        fields = ["id", "product", "product_name", "quantity", "unit_price", "line_total"]


class SaleSerializer(serializers.ModelSerializer):
    items = SaleItemSerializer(many=True, read_only=True)

    class Meta:
        model = Sale
        fields = [
            "id",
            "subtotal",
            "discount_amount",
            "total",
            "payment_method",
            "status",
            "cancel_reason",
            "canceled_at",
            "created_at",
            "items",
        ]


class SupplierProductSerializer(serializers.ModelSerializer):
    source_product_id = serializers.IntegerField(read_only=True)
    stock_quantity = serializers.IntegerField(source="source_product.stock_quantity", read_only=True)

    class Meta:
        model = SupplierProduct
        fields = [
            "id",
            "source_product_id",
            "name",
            "price",
            "is_available",
            "image_url",
            "stock_quantity",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class SupplierProfileSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(read_only=True)
    products = SupplierProductSerializer(many=True, read_only=True)

    class Meta:
        model = SupplierProfile
        fields = [
            "id",
            "user_id",
            "business_name",
            "description",
            "phone",
            "is_active",
            "business_domain",
            "latitude",
            "longitude",
            "commune",
            "quarter",
            "avenue",
            "profile_image_url",
            "cover_image_url",
            "support_whatsapp",
            "products",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "user_id", "products", "created_at", "updated_at"]

    def validate(self, attrs):
        lat = attrs.get("latitude", getattr(self.instance, "latitude", None))
        lng = attrs.get("longitude", getattr(self.instance, "longitude", None))
        if (lat is None) ^ (lng is None):
            raise serializers.ValidationError(
                "Latitude et longitude doivent etre renseignees ensemble."
            )
        return attrs


class SupplierOrderItemInputSerializer(serializers.Serializer):
    supplier_product_id = serializers.IntegerField()
    quantity = serializers.IntegerField(min_value=1)


class SupplierOrderCreateSerializer(serializers.Serializer):
    supplier_id = serializers.IntegerField()
    items = SupplierOrderItemInputSerializer(many=True, allow_empty=False)
    notes = serializers.CharField(required=False, allow_blank=True)
    delivery_commune = serializers.CharField(required=False, allow_blank=True)


class SupplierQuickOrderSerializer(serializers.Serializer):
    supplier_product_id = serializers.IntegerField()
    quantity = serializers.IntegerField(min_value=1, default=1)
    notes = serializers.CharField(required=False, allow_blank=True)


class SupplierOrderItemSerializer(serializers.ModelSerializer):
    supplier_product_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = SupplierOrderItem
        fields = [
            "id",
            "supplier_product_id",
            "product_name",
            "unit_price",
            "quantity",
            "line_total",
        ]


class SupplierOrderSerializer(serializers.ModelSerializer):
    merchant_id = serializers.IntegerField(read_only=True)
    merchant_phone = serializers.CharField(source="merchant.phone", read_only=True)
    supplier_id = serializers.IntegerField(read_only=True)
    supplier_name = serializers.CharField(source="supplier.business_name", read_only=True)
    supplier_phone = serializers.CharField(source="supplier.phone", read_only=True)
    items = SupplierOrderItemSerializer(many=True, read_only=True)

    class Meta:
        model = SupplierOrder
        fields = [
            "id",
            "merchant_id",
            "merchant_phone",
            "supplier_id",
            "supplier_name",
            "supplier_phone",
            "status",
            "notes",
            "delivery_commune",
            "total_amount",
            "items",
            "created_at",
            "updated_at",
        ]


class SupplierOrderStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(
        choices=[
            SupplierOrder.Status.PENDING,
            SupplierOrder.Status.ACCEPTED,
            SupplierOrder.Status.REJECTED,
            SupplierOrder.Status.CANCELED,
            SupplierOrder.Status.FULFILLED,
        ]
    )


class SupplierCallStartSerializer(serializers.Serializer):
    supplier_id = serializers.IntegerField()


class SupplierCallEndSerializer(serializers.Serializer):
    session_id = serializers.IntegerField()


class SupplierConversationSerializer(serializers.ModelSerializer):
    supplier_name = serializers.CharField(source="supplier.business_name", read_only=True)
    supplier_phone = serializers.CharField(source="supplier.phone", read_only=True)
    supplier_image_url = serializers.CharField(source="supplier.profile_image_url", read_only=True)

    class Meta:
        model = SupplierConversation
        fields = [
            "id",
            "merchant",
            "supplier",
            "supplier_name",
            "supplier_phone",
            "supplier_image_url",
            "last_message_preview",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "merchant", "created_at", "updated_at"]


class SupplierConversationCreateSerializer(serializers.Serializer):
    supplier_id = serializers.IntegerField()


class SupplierMessageSerializer(serializers.ModelSerializer):
    sender_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = SupplierMessage
        fields = [
            "id",
            "sender_id",
            "message_type",
            "content",
            "voice_url",
            "created_at",
        ]
        read_only_fields = ["id", "sender_id", "created_at"]

    def validate(self, attrs):
        message_type = attrs.get("message_type", SupplierMessage.MessageType.TEXT)
        content = (attrs.get("content") or "").strip()
        voice_url = (attrs.get("voice_url") or "").strip()
        if message_type == SupplierMessage.MessageType.TEXT and not content:
            raise serializers.ValidationError("Le message texte ne peut pas etre vide.")
        if message_type == SupplierMessage.MessageType.VOICE and not voice_url:
            raise serializers.ValidationError("Le message vocal doit contenir une URL audio.")
        return attrs
