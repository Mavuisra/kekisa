"""Livraison OTP gratuite : email SMTP, SMS (optionnel), console (dev)."""

from __future__ import annotations

from django.conf import settings

from .email_delivery import EmailDeliveryError, is_email_configured, send_otp_email
from .sms import SmsDeliveryError, send_sms


class OtpDeliveryError(Exception):
    """Aucun canal OTP disponible."""


def otp_delivery_enabled() -> bool:
    if settings.DEBUG:
        return True
    if getattr(settings, "OTP_SMS_ENABLED", False):
        return True
    if getattr(settings, "OTP_EMAIL_ENABLED", False) and is_email_configured():
        return True
    return False


def deliver_otp_code(
    *,
    code: str,
    phone: str = "",
    email: str = "",
    purpose: str = "verification",
) -> str:
    """
    Envoie le code OTP. Retourne le canal utilise : sms, email, console.
    Priorite : auto = email gratuit si pas de SMS, sinon SMS.
    """
    mode = (getattr(settings, "OTP_DELIVERY", "auto") or "auto").lower()
    phone = (phone or "").strip()
    email = (email or "").strip()
    sms_ok = getattr(settings, "OTP_SMS_ENABLED", False)
    email_ok = getattr(settings, "OTP_EMAIL_ENABLED", True) and is_email_configured()

    if mode == "console" or (settings.DEBUG and mode == "auto" and not sms_ok and not email_ok):
        send_sms(phone or "dev", f"[console] Code Tekisa {code}")
        return "console"

    if mode in {"sms", "auto"} and sms_ok and phone:
        try:
            send_sms(phone, f"Code Tekisa ({purpose}): {code}")
            return "sms"
        except SmsDeliveryError:
            if mode == "sms":
                raise OtpDeliveryError(
                    "SMS indisponible. Essayez OTP_DELIVERY=email dans .env."
                ) from None

    if mode in {"email", "auto"} and email_ok and email:
        try:
            send_otp_email(to_email=email, code=code, purpose=purpose)
            return "email"
        except EmailDeliveryError as exc:
            if mode == "email":
                raise OtpDeliveryError(str(exc)) from exc

    if settings.DEBUG and phone:
        send_sms(phone, f"[dev] Code Tekisa: {code}")
        return "console"

    raise OtpDeliveryError(
        "Aucun canal OTP gratuit disponible. Configurez EMAIL_HOST (Gmail SMTP) "
        "ou OTP_SMS_ENABLED avec un fournisseur SMS."
    )
