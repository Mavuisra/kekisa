"""Envoi SMS — console (dev), Africa's Talking, Twilio."""

from __future__ import annotations

import logging
import urllib.error
import urllib.parse
import urllib.request

from django.conf import settings

logger = logging.getLogger(__name__)


class SmsDeliveryError(Exception):
    """Echec d'envoi SMS vers le fournisseur."""


def send_sms(phone: str, message: str) -> None:
    """
    Envoie un SMS via le fournisseur configure (SMS_PROVIDER).
    Leve SmsDeliveryError si l'envoi echoue.
    """
    normalized_phone = (phone or "").strip()
    text = (message or "").strip()
    if not normalized_phone or not text:
        raise SmsDeliveryError("Numero ou message SMS vide.")

    provider = (getattr(settings, "SMS_PROVIDER", "console") or "console").lower()
    if provider == "console":
        _send_console(normalized_phone, text)
        return
    if provider == "africastalking":
        _send_africastalking(normalized_phone, text)
        return
    if provider == "twilio":
        _send_twilio(normalized_phone, text)
        return
    raise SmsDeliveryError(f"Fournisseur SMS inconnu: {provider}")


def _send_console(phone: str, message: str) -> None:
    logger.info("[TEKISA SMS console] to=%s message=%s", phone, message)
    if settings.DEBUG:
        print(f"[TEKISA SMS] {phone}: {message}")


def _send_africastalking(phone: str, message: str) -> None:
    username = getattr(settings, "AFRICASTALKING_USERNAME", "") or ""
    api_key = getattr(settings, "AFRICASTALKING_API_KEY", "") or ""
    sender = getattr(settings, "AFRICASTALKING_SENDER", "TEKISA") or "TEKISA"
    if not username or not api_key:
        raise SmsDeliveryError("Africa's Talking non configure (USERNAME/API_KEY).")

    payload = urllib.parse.urlencode(
        {
            "username": username,
            "to": phone,
            "message": message,
            "from": sender,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "https://api.africastalking.com/version1/messaging",
        data=payload,
        method="POST",
        headers={
            "apiKey": api_key,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8", errors="replace")
            if response.status >= 400:
                raise SmsDeliveryError(f"Africa's Talking HTTP {response.status}: {body}")
            logger.info("SMS Africa's Talking envoye vers %s", phone)
    except urllib.error.URLError as exc:
        raise SmsDeliveryError(f"Africa's Talking indisponible: {exc}") from exc


def _send_twilio(phone: str, message: str) -> None:
    account_sid = getattr(settings, "TWILIO_ACCOUNT_SID", "") or ""
    auth_token = getattr(settings, "TWILIO_AUTH_TOKEN", "") or ""
    from_number = getattr(settings, "TWILIO_FROM_NUMBER", "") or ""
    if not account_sid or not auth_token or not from_number:
        raise SmsDeliveryError("Twilio non configure (SID/TOKEN/FROM).")

    url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"
    payload = urllib.parse.urlencode(
        {"To": phone, "From": from_number, "Body": message}
    ).encode("utf-8")
    credentials = f"{account_sid}:{auth_token}".encode("utf-8")
    import base64

    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Basic {base64.b64encode(credentials).decode('ascii')}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status >= 400:
                body = response.read().decode("utf-8", errors="replace")
                raise SmsDeliveryError(f"Twilio HTTP {response.status}: {body}")
            logger.info("SMS Twilio envoye vers %s", phone)
    except urllib.error.URLError as exc:
        raise SmsDeliveryError(f"Twilio indisponible: {exc}") from exc
