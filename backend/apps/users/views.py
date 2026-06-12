from datetime import timedelta
from hashlib import sha256
from secrets import randbelow

from django.contrib.auth import authenticate, get_user_model
from django.utils import timezone as dj_timezone
from django.conf import settings
from rest_framework import generics, status, viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import InAppNotification, PasswordResetOTP, PhoneOTP, PushDevice
from .otp_delivery import OtpDeliveryError, deliver_otp_code, otp_delivery_enabled
from .permissions import IsSuperAdmin
from .serializers import (
    ChangePasswordSerializer,
    LoginSerializer,
    InAppNotificationSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    RegisterPushDeviceSerializer,
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
        if not otp_delivery_enabled():
            return Response(
                {"detail": "Connexion OTP désactivée. Utilisez mot de passe."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]

        code = f"{randbelow(1000000):06d}"
        code_hash = sha256(code.encode("utf-8")).hexdigest()
        expires_at = dj_timezone.now() + timedelta(
            seconds=int(getattr(settings, "OTP_SMS_EXPIRY_SECONDS", 300))
        )

        PhoneOTP.objects.create(
            phone=phone,
            code_hash=code_hash,
            expires_at=expires_at,
        )

        user = User.objects.filter(phone=phone).order_by("id").first()
        user_email = (user.email if user else "") or ""
        try:
            channel = deliver_otp_code(
                code=code,
                phone=phone,
                email=user_email,
                purpose="connexion",
            )
        except OtpDeliveryError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response(
            {"detail": "OTP sent", "channel": channel},
            status=status.HTTP_200_OK,
        )


class VerifyOTPView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = VerifyOTPSerializer

    def post(self, request, *args, **kwargs):
        if not otp_delivery_enabled():
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


class PasswordResetRequestView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = PasswordResetRequestSerializer

    def post(self, request, *args, **kwargs):
        if not otp_delivery_enabled():
            return Response(
                {
                    "detail": (
                        "Reinitialisation indisponible. "
                        "Configurez EMAIL_HOST (gratuit) ou SMS."
                    )
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        email = serializer.validated_data["email"]

        user = None
        if phone:
            user = User.objects.filter(phone=phone).order_by("id").first()
        if user is None and email:
            user = User.objects.filter(email__iexact=email).order_by("id").first()
        if user is None:
            return Response(
                {"detail": "Aucun compte associe a ces identifiants."},
                status=status.HTTP_404_NOT_FOUND,
            )

        phone = phone or (user.phone or "").strip()
        email = email or (user.email or "").strip().lower()

        code = f"{randbelow(1000000):06d}"
        code_hash = sha256(code.encode("utf-8")).hexdigest()
        expires_at = dj_timezone.now() + timedelta(
            seconds=int(getattr(settings, "OTP_SMS_EXPIRY_SECONDS", 300))
        )
        PasswordResetOTP.objects.create(
            phone=phone,
            email=email,
            code_hash=code_hash,
            expires_at=expires_at,
        )
        try:
            channel = deliver_otp_code(
                code=code,
                phone=phone,
                email=email,
                purpose="reinitialisation mot de passe",
            )
        except OtpDeliveryError as exc:
            return Response(
                {"detail": str(exc)},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        return Response(
            {"detail": "Code de reinitialisation envoye.", "channel": channel},
            status=200,
        )


class PasswordResetConfirmView(generics.GenericAPIView):
    permission_classes = [AllowAny]
    serializer_class = PasswordResetConfirmSerializer

    def post(self, request, *args, **kwargs):
        if not otp_delivery_enabled():
            return Response(
                {"detail": "Reinitialisation indisponible."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        email = serializer.validated_data["email"]
        code = serializer.validated_data["code"].strip()
        new_password = serializer.validated_data["new_password"]

        user = None
        if phone:
            user = User.objects.filter(phone=phone).order_by("id").first()
        if user is None and email:
            user = User.objects.filter(email__iexact=email).order_by("id").first()
        if user is None:
            return Response(
                {"detail": "Aucun compte associe a ces identifiants."},
                status=status.HTTP_404_NOT_FOUND,
            )

        phone = phone or (user.phone or "").strip()
        email = email or (user.email or "").strip().lower()

        now = dj_timezone.now()
        otp_qs = PasswordResetOTP.objects.filter(is_used=False)
        if phone:
            otp_qs = otp_qs.filter(phone=phone)
        elif email:
            otp_qs = otp_qs.filter(email__iexact=email)
        otp = otp_qs.order_by("-created_at").first()
        if not otp or otp.expires_at < now:
            return Response(
                {"detail": "Code expire ou invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if otp.attempts >= 5:
            return Response(
                {"detail": "Trop de tentatives. Demandez un nouveau code."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        expected_hash = sha256(code.encode("utf-8")).hexdigest()
        if otp.code_hash != expected_hash:
            otp.attempts += 1
            otp.save(update_fields=["attempts"])
            return Response({"detail": "Code invalide."}, status=400)

        otp.is_used = True
        otp.save(update_fields=["is_used"])
        user.set_password(new_password)
        user.save(update_fields=["password"])
        return Response({"detail": "Mot de passe mis a jour."}, status=200)


class ChangePasswordView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        old_password = serializer.validated_data["old_password"]
        new_password = serializer.validated_data["new_password"]
        user = request.user
        if not user.check_password(old_password):
            return Response(
                {"detail": "Ancien mot de passe incorrect."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(new_password)
        user.save(update_fields=["password"])
        return Response({"detail": "Mot de passe modifie."}, status=200)


class RegisterPushDeviceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = RegisterPushDeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data["token"].strip()
        platform = serializer.validated_data["platform"]
        PushDevice.objects.update_or_create(
            token=token,
            defaults={
                "user": request.user,
                "platform": platform,
                "is_active": True,
            },
        )
        return Response({"detail": "Appareil enregistre."}, status=200)

    def delete(self, request):
        token = (request.data.get("token") or "").strip()
        if not token:
            return Response({"detail": "Token manquant."}, status=400)
        PushDevice.objects.filter(user=request.user, token=token).update(is_active=False)
        return Response(status=status.HTTP_204_NO_CONTENT)


class InAppNotificationListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = InAppNotificationSerializer

    def get_queryset(self):
        return InAppNotification.objects.filter(user=self.request.user)


class InAppNotificationUnreadCountView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        count = InAppNotification.objects.filter(
            user=request.user,
            is_read=False,
        ).count()
        return Response({"count": count})


class InAppNotificationMarkReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, notification_id):
        notification = InAppNotification.objects.filter(
            id=notification_id,
            user=request.user,
        ).first()
        if notification is None:
            return Response({"detail": "Notification introuvable."}, status=404)
        notification.is_read = True
        notification.save(update_fields=["is_read", "updated_at"])
        return Response(InAppNotificationSerializer(notification).data)


class InAppNotificationMarkAllReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        updated = InAppNotification.objects.filter(
            user=request.user,
            is_read=False,
        ).update(is_read=True)
        return Response({"detail": "Toutes les notifications sont lues.", "updated": updated})

