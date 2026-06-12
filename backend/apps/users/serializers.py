from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import InAppNotification, PhoneOTP

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            "id",
            "username",
            "phone",
            "email",
            "role",
            "business_category",
            "company_name",
            "company_trade_name",
            "legal_form",
            "rccm",
            "idnat",
            "nif",
            "company_email",
            "company_phone",
            "company_country",
            "company_province",
            "company_city",
            "company_commune",
            "company_quarter",
            "company_avenue",
            "company_number",
        ]
        read_only_fields = ["id", "role"]


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150, write_only=True)
    password = serializers.CharField(max_length=128, write_only=True, style={"input_type": "password"})


class RegisterSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150, write_only=True)
    password = serializers.CharField(max_length=128, write_only=True, style={"input_type": "password"}, min_length=6)
    phone = serializers.CharField(max_length=32, write_only=True)
    full_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    business_category = serializers.ChoiceField(
        choices=[choice[0] for choice in User.BusinessCategory.choices],
        required=False,
        default=User.BusinessCategory.BOUTIQUE,
    )
    company_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    company_trade_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default="")
    legal_form = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")
    rccm = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")
    idnat = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")
    nif = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")
    company_email = serializers.EmailField(required=False, allow_blank=True, default="")
    company_phone = serializers.CharField(max_length=32, required=False, allow_blank=True, default="")
    company_country = serializers.CharField(max_length=64, required=False, allow_blank=True, default="RDC")
    company_province = serializers.CharField(max_length=128, required=False, allow_blank=True, default="")
    company_city = serializers.CharField(max_length=128, required=False, allow_blank=True, default="")
    company_commune = serializers.CharField(max_length=128, required=False, allow_blank=True, default="")
    company_quarter = serializers.CharField(max_length=128, required=False, allow_blank=True, default="")
    company_avenue = serializers.CharField(max_length=128, required=False, allow_blank=True, default="")
    company_number = serializers.CharField(max_length=64, required=False, allow_blank=True, default="")

    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("Ce nom d'utilisateur est déjà pris.")
        return value

    def validate_phone(self, value):
        if User.objects.filter(phone=value).exists():
            raise serializers.ValidationError("Ce numéro de téléphone est déjà utilisé.")
        return value

    def validate(self, attrs):
        company_name = (attrs.get("company_name") or "").strip()
        if not company_name:
            raise serializers.ValidationError({"company_name": "La raison sociale de l'entreprise est requise."})
        return attrs


class RequestOTPSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32)


class VerifyOTPSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32)
    code = serializers.CharField(max_length=8)

    def validate(self, attrs):
        # Detailed verification logic will live in the view/service layer.
        return attrs


class PhoneOTPSerializer(serializers.ModelSerializer):
    class Meta:
        model = PhoneOTP
        fields = ["phone", "expires_at", "is_used"]


class PasswordResetRequestSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)

    def validate(self, attrs):
        phone = (attrs.get("phone") or "").strip()
        email = (attrs.get("email") or "").strip().lower()
        if not phone and not email:
            raise serializers.ValidationError(
                "Indiquez un numero de telephone ou une adresse email."
            )
        attrs["phone"] = phone
        attrs["email"] = email
        return attrs


class PasswordResetConfirmSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=32, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)
    code = serializers.CharField(max_length=8)
    new_password = serializers.CharField(
        max_length=128,
        write_only=True,
        style={"input_type": "password"},
        min_length=6,
    )

    def validate(self, attrs):
        phone = (attrs.get("phone") or "").strip()
        email = (attrs.get("email") or "").strip().lower()
        if not phone and not email:
            raise serializers.ValidationError(
                "Indiquez un numero de telephone ou une adresse email."
            )
        attrs["phone"] = phone
        attrs["email"] = email
        return attrs


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(
        max_length=128,
        write_only=True,
        style={"input_type": "password"},
    )
    new_password = serializers.CharField(
        max_length=128,
        write_only=True,
        style={"input_type": "password"},
        min_length=6,
    )


class RegisterPushDeviceSerializer(serializers.Serializer):
    token = serializers.CharField(max_length=512)
    platform = serializers.ChoiceField(
        choices=["android", "ios", "web"],
        default="android",
    )


class InAppNotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = InAppNotification
        fields = [
            "id",
            "title",
            "body",
            "category",
            "is_read",
            "payload",
            "created_at",
        ]
        read_only_fields = fields

