from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.commerce.models import Product, Sale, StockMovement

User = get_user_model()


class SalesE2ETestCase(APITestCase):
    def setUp(self):
        self.seller = User.objects.create_user(
            username="seller_e2e",
            password="pass1234",
            phone="+243811111111",
            role=User.Role.SELLER,
            company_name="E2E Shop",
        )
        self.product = Product.objects.create(
            seller=self.seller,
            name="Savon",
            sku="SAV-001",
            unit_price=1000,
            stock_quantity=10,
            reorder_threshold=2,
        )
        self.client.force_authenticate(user=self.seller)

    def test_quick_sale_decrements_stock(self):
        response = self.client.post(
            "/api/v1/commerce/sales/quick/",
            {
                "items": [{"product_id": self.product.id, "quantity": 2}],
                "discount_rate": 5,
                "payment_method": "cash",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 8)
        self.assertEqual(Sale.objects.filter(seller=self.seller).count(), 1)

    def test_sale_detail_and_cancel_restores_stock(self):
        create = self.client.post(
            "/api/v1/commerce/sales/quick/",
            {"items": [{"product_id": self.product.id, "quantity": 3}]},
            format="json",
        )
        sale_id = create.data["id"]

        detail = self.client.get(f"/api/v1/commerce/sales/{sale_id}/")
        self.assertEqual(detail.status_code, status.HTTP_200_OK)
        self.assertEqual(len(detail.data["items"]), 1)

        cancel = self.client.post(
            f"/api/v1/commerce/sales/{sale_id}/cancel/",
            {"reason": "Erreur caisse"},
            format="json",
        )
        self.assertEqual(cancel.status_code, status.HTTP_200_OK)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 10)
        self.assertEqual(
            StockMovement.objects.filter(
                seller=self.seller, reason="sale_cancel"
            ).count(),
            1,
        )

    def test_sales_export_returns_xlsx(self):
        self.client.post(
            "/api/v1/commerce/sales/quick/",
            {"items": [{"product_id": self.product.id, "quantity": 1}]},
            format="json",
        )
        response = self.client.get("/api/v1/commerce/sales/export.xlsx")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn(
            "spreadsheetml",
            response["Content-Type"],
        )
        self.assertGreater(len(response.content), 100)

    def test_stock_export_returns_xlsx(self):
        response = self.client.get("/api/v1/commerce/stock/export.xlsx")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreater(len(response.content), 100)
