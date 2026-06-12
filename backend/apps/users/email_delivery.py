"""Envoi email OTP / alertes — gratuit via SMTP Django."""

from __future__ import annotations

import logging

from django.conf import settings
from django.core.mail import send_mail

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Echec d'envoi email."""


def is_email_configured() -> bool:
    backend = (getattr(settings, "EMAIL_BACKEND", "") or "").lower()
    if "locmem" in backend or "filebased" in backend:
        return True
    if "console" in backend:
        return settings.DEBUG
    host = getattr(settings, "EMAIL_HOST", "") or ""
    return bool(host)


def send_otp_email(*, to_email: str, code: str, purpose: str = "connexion") -> None:
    email = (to_email or "").strip()
    if not email:
        raise EmailDeliveryError("Adresse email vide.")
    if not is_email_configured():
        raise EmailDeliveryError(
            "Email non configure. Definissez EMAIL_HOST dans .env (Gmail SMTP gratuit)."
        )

    subject = f"Tekisa — code {purpose}"
    message = (
        f"Votre code Tekisa ({purpose}) : {code}\n\n"
        f"Ne partagez ce code avec personne.\n"
        f"Valide {getattr(settings, 'OTP_SMS_EXPIRY_SECONDS', 300) // 60} minutes."
    )
    from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "Tekisa <noreply@tekisa.local>")
    try:
        send_mail(
            subject=subject,
            message=message,
            from_email=from_email,
            recipient_list=[email],
            fail_silently=False,
        )
        logger.info("Email OTP envoye vers %s", email)
    except Exception as exc:
        raise EmailDeliveryError(f"Envoi email impossible: {exc}") from exc
