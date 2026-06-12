from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import (
    ChangePasswordView,
    InAppNotificationListView,
    InAppNotificationMarkAllReadView,
    InAppNotificationMarkReadView,
    InAppNotificationUnreadCountView,
    LoginView,
    PasswordResetConfirmView,
    PasswordResetRequestView,
    RegisterPushDeviceView,
    RegisterView,
    RequestOTPView,
    UserViewSet,
    VerifyOTPView,
)

router = DefaultRouter()
router.register("users", UserViewSet, basename="user")

urlpatterns = [
    path("auth/login/", LoginView.as_view(), name="login"),
    path("auth/register/", RegisterView.as_view(), name="register"),
    path("auth/request-otp/", RequestOTPView.as_view(), name="request-otp"),
    path("auth/verify-otp/", VerifyOTPView.as_view(), name="verify-otp"),
    path(
        "auth/password-reset/request/",
        PasswordResetRequestView.as_view(),
        name="password-reset-request",
    ),
    path(
        "auth/password-reset/confirm/",
        PasswordResetConfirmView.as_view(),
        name="password-reset-confirm",
    ),
    path("auth/change-password/", ChangePasswordView.as_view(), name="change-password"),
    path("push-devices/", RegisterPushDeviceView.as_view(), name="push-devices"),
    path("notifications/", InAppNotificationListView.as_view(), name="notifications"),
    path(
        "notifications/unread-count/",
        InAppNotificationUnreadCountView.as_view(),
        name="notifications-unread-count",
    ),
    path(
        "notifications/read-all/",
        InAppNotificationMarkAllReadView.as_view(),
        name="notifications-read-all",
    ),
    path(
        "notifications/<int:notification_id>/read/",
        InAppNotificationMarkReadView.as_view(),
        name="notification-read",
    ),
]

urlpatterns += router.urls

