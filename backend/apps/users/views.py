from datetime import timedelta
from hashlib import sha256
from secrets import randbelow

from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone as dj_timezone
from django.conf import settings
from rest_framework import generics, status, viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import PhoneOTP
from .permissions import IsSuperAdmin
from .serializers import (
    LoginSerializer,
    RegisterSerializer,
    RequestOTPSerializer,
    UserSerializer,
    VerifyOTPSerializer,
)

User = get_user_model()


class LoginView(generics.GenericAPIView):
    """Login username/password → JWT access + refresh (sans OTP)."""
    permission_classes = [AllowAny]
    serializer_class = LoginSerializer

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data["username"]
        password = serializer.validated_data["password"]

        # Connexion robuste: accepte username OU numéro de téléphone.
        login_value = (username or "").strip()
        resolved_username = login_value
        if login_value:
            matched = User.objects.filter(phone=login_value).order_by("id").first()
            if matched is not None:
                resolved_username = matched.username

        user = authenticate(request, username=resolved_username, password=password)
        if user is None:
            return Response(
                {"detail": "Identifiants incorrects."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        if not user.is_active:
            return Response(
                {"detail": "Compte désactivé. Contactez l'administrateur."},
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": UserSerializer(user).data,
        }, status=status.HTTP_200_OK)


class RegisterView(generics.GenericAPIView):
    """Création de compte vendeur → JWT access + refresh."""
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data["username"]
        password = serializer.validated_data["password"]
        phone = serializer.validated_data["phone"]
        full_name = serializer.validated_data.get("full_name") or username
        business_category = serializer.validated_data.get("business_category") or User.BusinessCategory.BOUTIQUE
        company_name = serializer.validated_data.get("company_name", "")
        company_trade_name = serializer.validated_data.get("company_trade_name", "")
        legal_form = serializer.validated_data.get("legal_form", "")
        rccm = serializer.validated_data.get("rccm", "")
        idnat = serializer.validated_data.get("idnat", "")
        nif = serializer.validated_data.get("nif", "")
        company_email = serializer.validated_data.get("company_email", "")
        company_phone = serializer.validated_data.get("company_phone", "")
        company_country = serializer.validated_data.get("company_country", "RDC")
        company_province = serializer.validated_data.get("company_province", "")
        company_city = serializer.validated_data.get("company_city", "")
        company_commune = serializer.validated_data.get("company_commune", "")
        company_quarter = serializer.validated_data.get("company_quarter", "")
        company_avenue = serializer.validated_data.get("company_avenue", "")
        company_number = serializer.validated_data.get("company_number", "")

        user = User.objects.create_user(
            username=username,
            password=password,
            phone=phone,
            role=User.Role.SELLER,
            business_category=business_category,
            company_name=company_name,
            company_trade_name=company_trade_name,
            legal_form=legal_form,
            rccm=rccm,
            idnat=idnat,
            nif=nif,
            company_email=company_email,
            company_phone=company_phone,
            company_country=company_country,
            company_province=company_province,
            company_city=company_city,
            company_commune=company_commune,
            company_quarter=company_quarter,
            company_avenue=company_avenue,
            company_number=company_number,
        )
        # Compatibilité existante : profil parent optionnel non créé en mode vendeur.

        refresh = RefreshToken.for_user(user)
        return Response({
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": UserSerializer(user).data,
        }, status=status.HTTP_201_CREATED)


class UserViewSet(viewsets.ModelViewSet):
    """
    Accès restreint : chaque utilisateur ne voit/modifie que son compte.
    Liste globale réservée au super-admin plateforme.
    """

    serializer_class = UserSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "patch", "head", "options"]

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser or (getattr(user, "role", "") or "").lower() == "super_admin":
            return User.objects.all().order_by("id")
        return User.objects.filter(pk=user.pk)

    def get_permissions(self):
        if self.action == "list":
            return [IsAuthenticated(), IsSuperAdmin()]
        return super().get_permissions()


class RequestOTPView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = RequestOTPSerializer

    def post(self, request, *args, **kwargs):
        if not getattr(settings, "OTP_SMS_ENABLED", False):
            return Response(
                {"detail": "Connexion OTP désactivée. Utilisez mot de passe."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]

        code = f"{randbelow(1000000):06d}"
        code_hash = sha256(code.encode("utf-8")).hexdigest()
        expires_at = dj_timezone.now() + timedelta(seconds=300)

        PhoneOTP.objects.create(
            phone=phone,
            code_hash=code_hash,
            expires_at=expires_at,
        )

        # TODO: Send SMS asynchronously via Celery and SMS provider abstraction.

        return Response({"detail": "OTP sent"}, status=status.HTTP_200_OK)


class VerifyOTPView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = VerifyOTPSerializer

    def post(self, request, *args, **kwargs):
        if not getattr(settings, "OTP_SMS_ENABLED", False):
            return Response(
                {"detail": "Connexion OTP désactivée. Utilisez mot de passe."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        code = serializer.validated_data["code"]

        now = dj_timezone.now()
        otp_qs = (
            PhoneOTP.objects.filter(phone=phone, is_used=False)
            .order_by("-created_at")
            .first()
        )
        if not otp_qs or otp_qs.expires_at < now:
            return Response(
                {"detail": "OTP expired or invalid"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        expected_hash = sha256(code.encode("utf-8")).hexdigest()
        if otp_qs.code_hash != expected_hash:
            otp_qs.attempts += 1
            otp_qs.save(update_fields=["attempts"])
            return Response(
                {"detail": "Invalid code"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if otp_qs.attempts >= 5:
            return Response(
                {"detail": "Trop de tentatives. Demandez un nouveau code."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        otp_qs.is_used = True
        otp_qs.save(update_fields=["is_used"])

        user = User.objects.filter(phone=phone).order_by("id").first()
        if user is None:
            return Response(
                {"detail": "Aucun compte associé à ce numéro."},
                status=status.HTTP_404_NOT_FOUND,
            )
        if not user.is_active:
            return Response(
                {"detail": "Compte désactivé."},
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)
        data = {
            "access": str(refresh.access_token),
            "refresh": str(refresh),
        }
        return Response(data, status=status.HTTP_200_OK)

