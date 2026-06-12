from hashlib import sha256

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import InAppNotification, PasswordResetOTP

User = get_user_model()


@override_settings(OTP_SMS_ENABLED=True, SMS_PROVIDER="console", OTP_DELIVERY="auto")
class AuthE2ETestCase(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="vendeur01",
            password="secret123",
            phone="+243800000001",
            email="vendeur@example.com",
            role=User.Role.SELLER,
            company_name="Boutique Test",
        )

    def test_login_returns_jwt(self):
        response = self.client.post(
            "/api/v1/users/auth/login/",
            {"username": "vendeur01", "password": "secret123"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)
        self.assertIn("refresh", response.data)

    def test_register_creates_seller(self):
        response = self.client.post(
            "/api/v1/users/auth/register/",
            {
                "username": "nouveau",
                "password": "pass1234",
                "phone": "+243800000002",
                "company_name": "Ma boutique",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        created = User.objects.get(username="nouveau")
        self.assertEqual(created.role, User.Role.SELLER)

    def test_user_cannot_list_other_accounts(self):
        User.objects.create_user(
            username="autre",
            password="pass1234",
            phone="+243800000003",
        )
        self.client.force_authenticate(user=self.user)
        response = self.client.get("/api/v1/users/users/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_password_reset_flow(self):
        response = self.client.post(
            "/api/v1/users/auth/password-reset/request/",
            {"phone": "+243800000001"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        otp = PasswordResetOTP.objects.filter(phone="+243800000001").latest("created_at")
        # Recuperer le code via brute force impossible — on simule avec hash connu en test
        code = "123456"
        otp.code_hash = sha256(code.encode("utf-8")).hexdigest()
        otp.save(update_fields=["code_hash"])

        confirm = self.client.post(
            "/api/v1/users/auth/password-reset/confirm/",
            {
                "phone": "+243800000001",
                "code": code,
                "new_password": "newpass99",
            },
            format="json",
        )
        self.assertEqual(confirm.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("newpass99"))

    @override_settings(
        OTP_SMS_ENABLED=False,
        OTP_EMAIL_ENABLED=True,
        OTP_DELIVERY="email",
        EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
    )
    def test_password_reset_via_email(self):
        mail.outbox.clear()
        response = self.client.post(
            "/api/v1/users/auth/password-reset/request/",
            {"email": "vendeur@example.com"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data.get("channel"), "email")
        self.assertEqual(len(mail.outbox), 1)
        otp = PasswordResetOTP.objects.filter(email="vendeur@example.com").latest(
            "created_at"
        )
        code = "654321"
        otp.code_hash = sha256(code.encode("utf-8")).hexdigest()
        otp.save(update_fields=["code_hash"])

        confirm = self.client.post(
            "/api/v1/users/auth/password-reset/confirm/",
            {
                "email": "vendeur@example.com",
                "code": code,
                "new_password": "emailpass1",
            },
            format="json",
        )
        self.assertEqual(confirm.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("emailpass1"))

    def test_in_app_notifications_api(self):
        InAppNotification.objects.create(
            user=self.user,
            title="Test",
            body="Message test",
            category=InAppNotification.Category.SYSTEM,
        )
        self.client.force_authenticate(user=self.user)
        response = self.client.get("/api/v1/users/notifications/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(len(response.data["results"]), 1)

        count = self.client.get("/api/v1/users/notifications/unread-count/")
        self.assertEqual(count.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(count.data["count"], 1)

    def test_change_password_authenticated(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            "/api/v1/users/auth/change-password/",
            {"old_password": "secret123", "new_password": "changed88"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("changed88"))
