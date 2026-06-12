"""Helpers notifications in-app (gratuit, sans FCM)."""

from __future__ import annotations

from django.contrib.auth import get_user_model

from .models import InAppNotification

User = get_user_model()


def notify_user(
    user: User,
    *,
    title: str,
    body: str,
    category: str = InAppNotification.Category.SYSTEM,
    payload: dict | None = None,
) -> InAppNotification:
    return InAppNotification.objects.create(
        user=user,
        title=title[:120],
        body=body,
        category=category,
        payload=payload or {},
    )
