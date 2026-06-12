from decimal import Decimal
from datetime import timedelta
import re
import csv
import math
import os
import uuid

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.sessions.models import Session
from django.db import transaction
from django.db.models import F, Sum, Q
from django.http import HttpResponse
from django.utils import timezone
from django.core.files.storage import default_storage
from rest_framework import viewsets
from rest_framework.authentication import SessionAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.authentication import JWTAuthentication

from .models import (
    Customer,
    Product,
    Sale,
    SaleItem,
    StockMovement,
    SupplierConversation,
    SupplierProduct,
    SupplierProfile,
    SupplierMessage,
    SupplierOrder,
    SupplierOrderItem,
    SupplierCallSession,
)
from .kinshasa_locations import KINSHASA_LOCATIONS
from .serializers import (
    CustomerSerializer,
    ProductSerializer,
    AiSaleDraftSerializer,
    QuickSaleCreateSerializer,
    SaleSerializer,
    StockAddSerializer,
    SupplierProductSerializer,
    SupplierProfileSerializer,
    SupplierOrderCreateSerializer,
    SupplierQuickOrderSerializer,
    SupplierOrderSerializer,
    SupplierOrderStatusSerializer,
    SupplierCallStartSerializer,
    SupplierCallEndSerializer,
    SupplierConversationSerializer,
    SupplierConversationCreateSerializer,
    SupplierMessageSerializer,
)
from apps.users.permissions import IsSeller, IsSellerDataOwner, IsSuperAdmin

User = get_user_model()


def _sanitize_tenant_part(raw):
    value = (raw or "").strip().lower()
    if not value:
        return "default"
    return re.sub(r"[^a-z0-9_]+", "_", value)


def _tenant_id_for_user(user):
    category = _sanitize_tenant_part(getattr(user, "business_category", "") or "default")
    company_name = (getattr(user, "company_name", "") or "").strip()
    scope = _sanitize_tenant_part(company_name) if company_name else f"user_{user.id}"
    return f"{category}_{scope}"


def _tenant_candidate_users():
    return User.objects.filter(role__in=["admin", "seller", "cashier", "super_admin"]).order_by("id")


def _tenant_groups():
    groups = {}
    for user in _tenant_candidate_users():
        tenant_id = _tenant_id_for_user(user)
        groups.setdefault(tenant_id, []).append(user)
    return groups


def _tenant_snapshot(tenant_id, users):
    today = timezone.localdate()
    seller_ids = [u.id for u in users if (u.role or "").lower() == "seller"]
    tenant_sales = Sale.objects.filter(seller_id__in=seller_ids) if seller_ids else Sale.objects.none()
    total_revenue = tenant_sales.aggregate(v=Sum("total")).get("v") or Decimal("0")
    today_revenue = tenant_sales.filter(created_at__date=today).aggregate(v=Sum("total")).get("v") or Decimal("0")
    sales_count = tenant_sales.count()
    products_count = Product.objects.filter(seller_id__in=seller_ids).count() if seller_ids else 0
    customers_count = Customer.objects.filter(seller_id__in=seller_ids).count() if seller_ids else 0
    last_sale = tenant_sales.order_by("-created_at").values_list("created_at", flat=True).first()

    owner = next((u for u in users if (u.role or "").lower() == "admin"), users[0])
    is_suspended = all(not u.is_active for u in users)

    return {
        "tenant_id": tenant_id,
        "company_name": owner.company_name or f"Tenant {tenant_id}",
        "company_trade_name": owner.company_trade_name or "",
        "business_category": owner.business_category or "",
        "company_phone": owner.company_phone or owner.phone or "",
        "company_email": owner.company_email or owner.email or "",
        "company_country": owner.company_country or "",
        "company_province": owner.company_province or "",
        "company_city": owner.company_city or "",
        "company_commune": owner.company_commune or "",
        "company_quarter": owner.company_quarter or "",
        "company_avenue": owner.company_avenue or "",
        "company_number": owner.company_number or "",
        "legal_form": owner.legal_form or "",
        "rccm": owner.rccm or "",
        "idnat": owner.idnat or "",
        "nif": owner.nif or "",
        "users_count": len(users),
        "sellers_count": len([u for u in users if (u.role or "").lower() == "seller"]),
        "cashiers_count": len([u for u in users if (u.role or "").lower() == "cashier"]),
        "admins_count": len([u for u in users if (u.role or "").lower() in {"admin", "super_admin"}]),
        "products_count": products_count,
        "customers_count": customers_count,
        "sales_count": sales_count,
        "revenue_total": float(total_revenue),
        "revenue_today": float(today_revenue),
        "last_sale_at": last_sale.isoformat() if last_sale else None,
        "is_suspended": is_suspended,
    }


def _seller_category(user):
    return (getattr(user, "business_category", "") or "boutique").lower()


def _cost_ratio_for_category(category):
    if category == "restaurant":
        # Restauration: marge moyenne plus élevée.
        return Decimal("0.40")
    if category == "pharmacie":
        # Pharmacie: marges souvent plus serrées.
        return Decimal("0.78")
    return Decimal("0.70")


def _sale_reference(sale):
    if not sale or not sale.created_at:
        return ""
    date_part = sale.created_at.strftime("%Y%m%d")
    return f"REC-{date_part}-{sale.id:06d}"


def _haversine_distance_km(lat1, lng1, lat2, lng2):
    radius_km = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radius_km * c


def _supplier_profile_defaults_from_user(user):
    business_name = (getattr(user, "company_name", "") or "").strip() or (user.username or "")
    phone = (getattr(user, "company_phone", "") or "").strip() or (getattr(user, "phone", "") or "").strip()
    commune = (getattr(user, "company_commune", "") or "").strip()
    quarter = (getattr(user, "company_quarter", "") or "").strip()
    avenue = (getattr(user, "company_avenue", "") or "").strip()
    return {
        "business_name": business_name,
        "phone": phone,
        "commune": commune,
        "quarter": quarter,
        "avenue": avenue,
    }


def _public_media_url(request, saved_path):
    relative_url = f"{settings.MEDIA_URL}{saved_path}".replace("\\", "/")
    public_base = (getattr(settings, "PUBLIC_BASE_URL", "") or "").strip().rstrip("/")
    if public_base:
        return f"{public_base}{relative_url}"
    return request.build_absolute_uri(relative_url)


def _merchant_identity_payload(user):
    phone = (getattr(user, "phone", "") or "").strip()
    company_phone = (getattr(user, "company_phone", "") or "").strip()
    commune = (getattr(user, "company_commune", "") or "").strip()
    quarter = (getattr(user, "company_quarter", "") or "").strip()
    avenue = (getattr(user, "company_avenue", "") or "").strip()
    number = (getattr(user, "company_number", "") or "").strip()
    company_name = (getattr(user, "company_name", "") or "").strip()
    return {
        "name": company_name or user.username,
        "phone": company_phone or phone,
        "commune": commune,
        "quarter": quarter,
        "avenue": avenue,
        "number": number,
    }


def getNearbySuppliers(
    user_lat,
    user_lng,
    product_name=None,
    commune=None,
    business_domain=None,
    exclude_user_id=None,
):
    """
    Retourne la liste des fournisseurs actifs tries du plus proche au plus loin.
    - Si `product_name` est renseigne, filtre sur les produits disponibles correspondants.
    - Si GPS absent, le fallback `commune` est utilise pour restreindre la recherche.
    """
    suppliers = (
        SupplierProfile.objects.filter(is_active=True)
        .select_related("user")
        .prefetch_related("products")
    )
    if exclude_user_id is not None:
        suppliers = suppliers.exclude(user_id=exclude_user_id)
    search = (product_name or "").strip()
    if search:
        suppliers = suppliers.filter(
            products__is_available=True,
            products__name__icontains=search,
        ).distinct()
    domain = (business_domain or "").strip().lower()
    if domain:
        suppliers = suppliers.filter(business_domain=domain)

    commune_fallback = (commune or "").strip().lower()
    if (user_lat is None or user_lng is None) and commune_fallback:
        suppliers = suppliers.filter(commune__iexact=commune_fallback)

    rows = []
    for supplier in suppliers:
        available_products = [
            {
                "id": p.id,
                "name": p.name,
                "price": float(p.price),
                "is_available": p.is_available,
                "image_url": p.image_url,
            }
            for p in supplier.products.all()
            if p.is_available and (not search or search.lower() in p.name.lower())
        ]
        if search and not available_products:
            continue

        distance_km = None
        if (
            user_lat is not None
            and user_lng is not None
            and supplier.latitude is not None
            and supplier.longitude is not None
        ):
            distance_km = _haversine_distance_km(
                user_lat,
                user_lng,
                float(supplier.latitude),
                float(supplier.longitude),
            )

        rows.append(
            {
                "id": supplier.id,
                "user_id": supplier.user_id,
                "business_name": supplier.business_name,
                "description": supplier.description,
                "phone": supplier.phone,
                "is_active": supplier.is_active,
                "latitude": supplier.latitude,
                "longitude": supplier.longitude,
                "commune": supplier.commune,
                "quarter": supplier.quarter,
                "avenue": supplier.avenue,
                "business_domain": supplier.business_domain,
                "profile_image_url": supplier.profile_image_url,
                "cover_image_url": supplier.cover_image_url,
                "support_whatsapp": supplier.support_whatsapp,
                "distance_km": round(distance_km, 2) if distance_km is not None else None,
                "products": available_products,
            }
        )

    rows.sort(
        key=lambda row: (
            row["distance_km"] is None,
            row["distance_km"] if row["distance_km"] is not None else 999999.0,
            row["business_name"].lower(),
        )
    )
    return rows


class ProductViewSet(viewsets.ModelViewSet):
    serializer_class = ProductSerializer
    permission_classes = [IsAuthenticated, IsSeller, IsSellerDataOwner]

    def get_queryset(self):
        return Product.objects.filter(seller=self.request.user).order_by("name")

    def perform_create(self, serializer):
        validated = getattr(serializer, "validated_data", {})
        unit_price = Decimal(str(validated.get("unit_price", 0) or 0))
        cost_price = validated.get("cost_price")
        stock_quantity = int(validated.get("stock_quantity", 0) or 0)
        category = _seller_category(self.request.user)
        ratio = _cost_ratio_for_category(category)
        if cost_price in (None, "", 0):
            product = serializer.save(seller=self.request.user, cost_price=(unit_price * ratio))
        else:
            product = serializer.save(seller=self.request.user)

        if stock_quantity > 0:
            StockMovement.objects.create(
                seller=self.request.user,
                product=product,
                movement_type=StockMovement.MovementType.IN,
                quantity=stock_quantity,
                reason="initial_stock",
                balance_after=product.stock_quantity,
                reference=f"create:{self.request.user.username}",
            )


class CustomerViewSet(viewsets.ModelViewSet):
    serializer_class = CustomerSerializer
    permission_classes = [IsAuthenticated, IsSeller, IsSellerDataOwner]

    def get_queryset(self):
        return Customer.objects.filter(seller=self.request.user).order_by("full_name")

    def perform_create(self, serializer):
        serializer.save(seller=self.request.user)


class SupplierProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        profile = (
            SupplierProfile.objects.filter(user=request.user)
            .prefetch_related("products")
            .first()
        )
        defaults = _supplier_profile_defaults_from_user(request.user)
        if profile is None:
            payload = {
                "id": 0,
                "user_id": request.user.id,
                "business_name": defaults["business_name"],
                "description": "",
                "phone": defaults["phone"],
                "is_active": False,
                "business_domain": "other",
                "latitude": None,
                "longitude": None,
                "commune": defaults["commune"],
                "quarter": defaults["quarter"],
                "avenue": defaults["avenue"],
                "profile_image_url": "",
                "cover_image_url": "",
                "support_whatsapp": defaults["phone"],
                "products": [],
            }
            return Response(payload)
        data = SupplierProfileSerializer(profile).data
        data["business_name"] = defaults["business_name"] or data.get("business_name", "")
        data["phone"] = defaults["phone"] or data.get("phone", "")
        data["commune"] = defaults["commune"] or data.get("commune", "")
        data["quarter"] = defaults["quarter"] or data.get("quarter", "")
        data["avenue"] = defaults["avenue"] or data.get("avenue", "")
        if not data.get("support_whatsapp"):
            data["support_whatsapp"] = data["phone"]
        return Response(data)

    def put(self, request):
        profile = SupplierProfile.objects.filter(user=request.user).first()
        created = profile is None
        defaults = _supplier_profile_defaults_from_user(request.user)
        payload = request.data.copy()
        payload["business_name"] = defaults["business_name"] or payload.get("business_name", "")
        payload["phone"] = defaults["phone"] or payload.get("phone", "")
        payload["commune"] = defaults["commune"] or payload.get("commune", "")
        payload["quarter"] = defaults["quarter"] or payload.get("quarter", "")
        payload["avenue"] = defaults["avenue"] or payload.get("avenue", "")
        if not (payload.get("support_whatsapp") or "").strip():
            payload["support_whatsapp"] = payload["phone"]
        serializer = SupplierProfileSerializer(profile, data=payload, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save(user=request.user)
        status_code = 201 if created else 200
        return Response(serializer.data, status=status_code)


class SupplierProductListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        profile = SupplierProfile.objects.filter(user=request.user).first()
        if profile is None:
            return Response([])
        products = SupplierProduct.objects.filter(supplier=profile).order_by("name")
        return Response(SupplierProductSerializer(products, many=True).data)

    def post(self, request):
        profile = SupplierProfile.objects.filter(user=request.user).first()
        if profile is None:
            defaults = _supplier_profile_defaults_from_user(request.user)
            profile = SupplierProfile.objects.create(
                user=request.user,
                business_name=defaults["business_name"],
                description="",
                phone=defaults["phone"],
                is_active=True,
                business_domain="other",
                commune=defaults["commune"],
                quarter=defaults["quarter"],
                avenue=defaults["avenue"],
                support_whatsapp=defaults["phone"],
            )
        supplier_product_id = request.data.get("supplier_product_id")
        if supplier_product_id not in (None, ""):
            try:
                target = SupplierProduct.objects.filter(
                    supplier=profile,
                    id=int(supplier_product_id),
                ).first()
            except (TypeError, ValueError):
                target = None
            if target is None:
                return Response({"detail": "Produit fournisseur introuvable."}, status=404)

            raw_available = request.data.get("is_available")
            if raw_available is not None:
                target.is_available = str(raw_available).strip().lower() in {
                    "1",
                    "true",
                    "yes",
                    "oui",
                    "on",
                }
            price_raw = request.data.get("price")
            if price_raw not in (None, ""):
                try:
                    target.price = Decimal(str(price_raw).replace(",", "."))
                except Exception:
                    return Response({"detail": "Prix invalide."}, status=400)
            image_url = (request.data.get("image_url") or "").strip()
            if image_url:
                target.image_url = image_url
            target.save()
            return Response(SupplierProductSerializer(target).data, status=200)

        source_product_id = request.data.get("source_product_id")
        source_product = None
        if source_product_id in (None, ""):
            return Response({"detail": "Choisissez un produit du stock a publier."}, status=400)
        try:
            source_product = Product.objects.filter(
                seller=request.user,
                id=int(source_product_id),
            ).first()
        except (TypeError, ValueError):
            source_product = None
        if source_product is None:
            return Response({"detail": "Produit de stock introuvable."}, status=404)

        price_raw = request.data.get("price")
        try:
            price_value = (
                Decimal(str(price_raw).replace(",", "."))
                if price_raw not in (None, "")
                else Decimal(str(source_product.unit_price))
            )
        except Exception:
            return Response({"detail": "Prix invalide."}, status=400)
        existing_supplier_product = SupplierProduct.objects.filter(
            supplier=profile,
            source_product=source_product,
        ).first()
        image_url = (request.data.get("image_url") or "").strip()
        if not image_url and existing_supplier_product is not None:
            image_url = existing_supplier_product.image_url
        is_available = str(request.data.get("is_available", "true")).strip().lower() in {"1", "true", "yes", "oui", "on"}

        supplier_product, _ = SupplierProduct.objects.update_or_create(
            supplier=profile,
            source_product=source_product,
            defaults={
                "name": source_product.name,
                "price": price_value,
                "is_available": is_available,
                "image_url": image_url,
            },
        )
        return Response(SupplierProductSerializer(supplier_product).data, status=201)


class NearbySuppliersView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat_raw = request.query_params.get("lat")
        lng_raw = request.query_params.get("lng")
        product_name = request.query_params.get("product_name")
        commune = request.query_params.get("commune")
        business_domain = request.query_params.get("business_domain")

        lat = None
        lng = None
        if lat_raw not in (None, "") and lng_raw not in (None, ""):
            try:
                lat = float(lat_raw)
                lng = float(lng_raw)
            except (TypeError, ValueError):
                return Response({"detail": "Coordonnees GPS invalides."}, status=400)

        if lat is None and lng is None and not (commune or "").strip():
            return Response(
                {
                    "detail": "Fournir une position GPS ou une commune pour la recherche."
                },
                status=400,
            )

        rows = getNearbySuppliers(
            user_lat=lat,
            user_lng=lng,
            product_name=product_name,
            commune=commune,
            business_domain=business_domain,
            exclude_user_id=request.user.id,
        )
        return Response(rows)


class SupplierMarketplaceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        query = (request.query_params.get("q") or "").strip().lower()
        commune = (request.query_params.get("commune") or "").strip().lower()
        business_domain = (request.query_params.get("business_domain") or "").strip().lower()

        suppliers = (
            SupplierProfile.objects.filter(is_active=True)
            .exclude(user_id=request.user.id)
            .select_related("user")
            .prefetch_related("products")
        )
        if business_domain:
            suppliers = suppliers.filter(business_domain=business_domain)
        if commune:
            suppliers = suppliers.filter(commune__iexact=commune)

        rows = []
        for supplier in suppliers:
            products = []
            for p in supplier.products.all():
                if not p.is_available:
                    continue
                if query and query not in p.name.lower():
                    continue
                products.append(
                    {
                        "id": p.id,
                        "name": p.name,
                        "price": float(p.price),
                        "is_available": p.is_available,
                        "image_url": p.image_url,
                    }
                )
            if query and not products:
                continue
            if not products:
                continue
            rows.append(
                {
                    "id": supplier.id,
                    "user_id": supplier.user_id,
                    "business_name": supplier.business_name,
                    "description": supplier.description,
                    "phone": supplier.phone,
                    "is_active": supplier.is_active,
                    "latitude": supplier.latitude,
                    "longitude": supplier.longitude,
                    "commune": supplier.commune,
                    "quarter": supplier.quarter,
                    "avenue": supplier.avenue,
                    "business_domain": supplier.business_domain,
                    "profile_image_url": supplier.profile_image_url,
                    "cover_image_url": supplier.cover_image_url,
                    "support_whatsapp": supplier.support_whatsapp,
                    "distance_km": None,
                    "products": products,
                }
            )

        rows.sort(key=lambda row: row["business_name"].lower())
        return Response(rows)


class KinshasaLocationsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        rows = [{"commune": commune, "quarters": quarters} for commune, quarters in KINSHASA_LOCATIONS.items()]
        rows.sort(key=lambda row: row["commune"])
        return Response(rows)


class SupplierOrderListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        scope = (request.query_params.get("scope") or "all").strip().lower()
        as_supplier = SupplierProfile.objects.filter(user=request.user).first()
        qs = SupplierOrder.objects.select_related(
            "merchant",
            "supplier",
        ).prefetch_related("items")

        if scope == "sent":
            qs = qs.filter(merchant=request.user)
        elif scope == "received":
            if as_supplier is None:
                return Response([])
            qs = qs.filter(supplier=as_supplier)
        else:
            if as_supplier is None:
                qs = qs.filter(merchant=request.user)
            else:
                qs = qs.filter(Q(merchant=request.user) | Q(supplier=as_supplier))

        rows = qs.order_by("-created_at")[:200]
        return Response(SupplierOrderSerializer(rows, many=True).data)

    def post(self, request):
        serializer = SupplierOrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        supplier = SupplierProfile.objects.filter(
            id=data["supplier_id"],
            is_active=True,
        ).first()
        if supplier is None:
            return Response({"detail": "Fournisseur introuvable ou inactif."}, status=404)
        if supplier.user_id == request.user.id:
            return Response({"detail": "Vous ne pouvez pas commander votre propre profil."}, status=400)

        raw_items = data["items"]
        product_ids = [row["supplier_product_id"] for row in raw_items]
        products = {
            p.id: p
            for p in SupplierProduct.objects.filter(
                supplier=supplier,
                is_available=True,
                id__in=product_ids,
            )
        }
        if len(products) != len(set(product_ids)):
            return Response({"detail": "Produit fournisseur indisponible."}, status=400)

        with transaction.atomic():
            order = SupplierOrder.objects.create(
                merchant=request.user,
                supplier=supplier,
                notes=(data.get("notes") or "").strip(),
                delivery_commune=(data.get("delivery_commune") or "").strip(),
                status=SupplierOrder.Status.PENDING,
            )
            total = Decimal("0")
            for row in raw_items:
                product = products[row["supplier_product_id"]]
                qty = int(row["quantity"])
                line_total = Decimal(str(product.price)) * qty
                SupplierOrderItem.objects.create(
                    order=order,
                    supplier_product=product,
                    product_name=product.name,
                    unit_price=product.price,
                    quantity=qty,
                    line_total=line_total,
                )
                total += line_total
            order.total_amount = total
            order.save(update_fields=["total_amount"])

        order = SupplierOrder.objects.select_related(
            "merchant",
            "supplier",
        ).prefetch_related("items").get(id=order.id)
        return Response(SupplierOrderSerializer(order).data, status=201)


class SupplierOrderStatusUpdateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, order_id):
        serializer = SupplierOrderStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        next_status = serializer.validated_data["status"]

        order = SupplierOrder.objects.select_related("supplier", "merchant").filter(id=order_id).first()
        if order is None:
            return Response({"detail": "Commande introuvable."}, status=404)

        supplier_profile = SupplierProfile.objects.filter(user=request.user).first()
        is_supplier_owner = supplier_profile is not None and order.supplier_id == supplier_profile.id
        is_merchant_owner = order.merchant_id == request.user.id
        if not is_supplier_owner and not is_merchant_owner:
            return Response({"detail": "Acces refuse."}, status=403)

        if is_merchant_owner and next_status not in {
            SupplierOrder.Status.CANCELED,
            SupplierOrder.Status.PENDING,
        }:
            return Response(
                {"detail": "Le marchand peut seulement marquer en attente ou annuler."},
                status=400,
            )
        if is_supplier_owner and next_status == SupplierOrder.Status.CANCELED:
            return Response({"detail": "Le fournisseur ne peut pas annuler cote marchand."}, status=400)

        order.status = next_status
        order.save(update_fields=["status", "updated_at"])
        order = SupplierOrder.objects.select_related(
            "merchant",
            "supplier",
            "supplier__user",
        ).prefetch_related("items").get(id=order.id)

        from apps.users.models import InAppNotification
        from apps.users.notifications import notify_user

        status_label = dict(SupplierOrder.Status.choices).get(next_status, next_status)
        if is_supplier_owner:
            notify_user(
                order.merchant,
                title="Commande fournisseur",
                body=f"Statut mis a jour : {status_label}",
                category=InAppNotification.Category.ORDER,
                payload={"order_id": order.id, "status": next_status},
            )
        elif is_merchant_owner:
            notify_user(
                order.supplier.user,
                title="Commande client",
                body=f"Statut mis a jour : {status_label}",
                category=InAppNotification.Category.ORDER,
                payload={"order_id": order.id, "status": next_status},
            )

        return Response(SupplierOrderSerializer(order).data)


class SupplierCallStartView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = SupplierCallStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        supplier_id = serializer.validated_data["supplier_id"]

        supplier = SupplierProfile.objects.filter(id=supplier_id, is_active=True).first()
        if supplier is None:
            return Response({"detail": "Fournisseur introuvable ou inactif."}, status=404)

        # Purge automatique des sessions actives trop anciennes.
        stale_threshold = timezone.now() - timedelta(minutes=30)
        SupplierCallSession.objects.filter(
            status=SupplierCallSession.Status.ACTIVE,
            created_at__lt=stale_threshold,
        ).update(
            status=SupplierCallSession.Status.ENDED,
            ended_at=timezone.now(),
        )

        active_calls = SupplierCallSession.objects.filter(
            status=SupplierCallSession.Status.ACTIVE
        ).count()
        if active_calls >= 20:
            return Response(
                {
                    "detail": "Capacite atteinte: 20 appels simultanes. Reessayez dans quelques instants."
                },
                status=429,
            )

        session = SupplierCallSession.objects.create(
            caller=request.user,
            supplier=supplier,
            status=SupplierCallSession.Status.ACTIVE,
        )
        return Response(
            {
                "session_id": session.id,
                "supplier_phone": supplier.phone,
                "active_calls": active_calls + 1,
            },
            status=201,
        )


class SupplierCallEndView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = SupplierCallEndSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        session_id = serializer.validated_data["session_id"]
        session = SupplierCallSession.objects.filter(id=session_id).first()
        if session is None:
            return Response({"detail": "Session introuvable."}, status=404)
        if session.caller_id != request.user.id and session.supplier.user_id != request.user.id:
            return Response({"detail": "Acces refuse."}, status=403)
        session.status = SupplierCallSession.Status.ENDED
        session.ended_at = timezone.now()
        session.save(update_fields=["status", "ended_at", "updated_at"])
        return Response({"detail": "Appel cloture."})


class SupplierImageUploadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        image_file = request.FILES.get("image")
        if image_file is None:
            return Response({"detail": "Image manquante."}, status=400)
        content_type = (getattr(image_file, "content_type", "") or "").lower()
        if not content_type.startswith("image/"):
            return Response({"detail": "Fichier invalide. Utilisez une image."}, status=400)
        max_size = 5 * 1024 * 1024
        if image_file.size > max_size:
            return Response({"detail": "Image trop lourde (max 5MB)."}, status=400)

        ext = os.path.splitext(image_file.name)[1].lower()
        if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
            ext = ".jpg"
        path = f"supplier_images/{request.user.id}/{uuid.uuid4().hex}{ext}"
        saved_path = default_storage.save(path, image_file)
        absolute_url = _public_media_url(request, saved_path)
        return Response(
            {
                "url": absolute_url,
                "path": saved_path,
            },
            status=201,
        )


class SupplierAudioUploadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        audio_file = request.FILES.get("audio")
        if audio_file is None:
            return Response({"detail": "Audio manquant."}, status=400)
        max_size = 10 * 1024 * 1024
        if audio_file.size > max_size:
            return Response({"detail": "Audio trop lourd (max 10MB)."}, status=400)
        ext = os.path.splitext(audio_file.name)[1].lower()
        if ext not in {".mp3", ".m4a", ".aac", ".ogg", ".wav"}:
            ext = ".m4a"
        path = f"supplier_audio/{request.user.id}/{uuid.uuid4().hex}{ext}"
        saved_path = default_storage.save(path, audio_file)
        absolute_url = _public_media_url(request, saved_path)
        return Response(
            {
                "url": absolute_url,
                "path": saved_path,
            },
            status=201,
        )


class SupplierFileUploadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        uploaded = request.FILES.get("file")
        if uploaded is None:
            return Response({"detail": "Fichier manquant."}, status=400)

        max_size = 20 * 1024 * 1024
        if uploaded.size > max_size:
            return Response({"detail": "Fichier trop lourd (max 20MB)."}, status=400)

        ext = os.path.splitext(uploaded.name)[1].lower()
        allowed_ext = {
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp",
            ".pdf",
            ".xlsx",
            ".xls",
            ".doc",
            ".docx",
            ".txt",
            ".csv",
            ".m4a",
            ".mp3",
            ".wav",
            ".ogg",
        }
        if ext not in allowed_ext:
            return Response(
                {"detail": "Type de fichier non autorise."},
                status=400,
            )
        path = f"supplier_files/{request.user.id}/{uuid.uuid4().hex}{ext}"
        saved_path = default_storage.save(path, uploaded)
        absolute_url = _public_media_url(request, saved_path)
        return Response(
            {
                "url": absolute_url,
                "path": saved_path,
                "name": uploaded.name,
                "size": uploaded.size,
                "content_type": getattr(uploaded, "content_type", "") or "",
            },
            status=201,
        )


class SupplierConversationListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        supplier_profile = SupplierProfile.objects.filter(user=request.user).first()
        qs = SupplierConversation.objects.select_related("supplier", "merchant")
        if supplier_profile is None:
            qs = qs.filter(merchant=request.user)
        else:
            qs = qs.filter(Q(merchant=request.user) | Q(supplier=supplier_profile))
        rows = qs.order_by("-updated_at")[:200]
        return Response(SupplierConversationSerializer(rows, many=True).data)

    def post(self, request):
        serializer = SupplierConversationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        supplier = SupplierProfile.objects.filter(
            id=serializer.validated_data["supplier_id"],
            is_active=True,
        ).first()
        if supplier is None:
            return Response({"detail": "Fournisseur introuvable ou inactif."}, status=404)
        # 1) Conversation "normale" : marchand courant -> fournisseur cible.
        convo = SupplierConversation.objects.filter(
            merchant=request.user,
            supplier=supplier,
        ).first()

        if convo is None:
            # 2) Si l'utilisateur courant est aussi fournisseur, essayer de
            # retrouver une conversation inverse déjà existante (évite A->B et B->A).
            my_supplier_profile = SupplierProfile.objects.filter(user=request.user).first()
            if my_supplier_profile is not None:
                convo = SupplierConversation.objects.filter(
                    merchant=supplier.user,
                    supplier=my_supplier_profile,
                ).first()

        if convo is None:
            convo = SupplierConversation.objects.create(
                merchant=request.user,
                supplier=supplier,
            )
        return Response(SupplierConversationSerializer(convo).data, status=201)


class SupplierConversationMessagesView(APIView):
    permission_classes = [IsAuthenticated]

    def _conversation_for_user(self, request, conversation_id):
        convo = SupplierConversation.objects.select_related("supplier", "merchant").filter(id=conversation_id).first()
        if convo is None:
            return None, Response({"detail": "Conversation introuvable."}, status=404)
        supplier_profile = SupplierProfile.objects.filter(user=request.user).first()
        is_merchant = convo.merchant_id == request.user.id
        is_supplier = supplier_profile is not None and convo.supplier_id == supplier_profile.id
        if not is_merchant and not is_supplier:
            return None, Response({"detail": "Acces refuse."}, status=403)
        return convo, None

    def get(self, request, conversation_id):
        convo, error = self._conversation_for_user(request, conversation_id)
        if error is not None:
            return error
        rows = convo.messages.select_related("sender").order_by("created_at")[:500]
        return Response(SupplierMessageSerializer(rows, many=True).data)

    def post(self, request, conversation_id):
        convo, error = self._conversation_for_user(request, conversation_id)
        if error is not None:
            return error
        serializer = SupplierMessageSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        message = serializer.save(conversation=convo, sender=request.user)
        preview = (message.content or "").strip()
        if message.message_type == SupplierMessage.MessageType.VOICE:
            preview = "Message vocal"
        convo.last_message_preview = preview[:240]
        convo.save(update_fields=["last_message_preview", "updated_at"])
        return Response(SupplierMessageSerializer(message).data, status=201)


class SupplierQuickOrderCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = SupplierQuickOrderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        supplier_product = (
            SupplierProduct.objects.select_related("supplier", "supplier__user")
            .filter(id=data["supplier_product_id"], is_available=True)
            .first()
        )
        if supplier_product is None:
            return Response({"detail": "Produit fournisseur introuvable ou indisponible."}, status=404)
        supplier = supplier_product.supplier
        if not supplier.is_active:
            return Response({"detail": "Fournisseur inactif."}, status=400)
        if supplier.user_id == request.user.id:
            return Response({"detail": "Vous ne pouvez pas commander votre propre produit."}, status=400)

        qty = int(data["quantity"])
        line_total = Decimal(str(supplier_product.price)) * qty

        with transaction.atomic():
            order = SupplierOrder.objects.create(
                merchant=request.user,
                supplier=supplier,
                notes=(data.get("notes") or "").strip(),
                delivery_commune=(getattr(request.user, "company_commune", "") or "").strip(),
                status=SupplierOrder.Status.PENDING,
                total_amount=line_total,
            )
            SupplierOrderItem.objects.create(
                order=order,
                supplier_product=supplier_product,
                product_name=supplier_product.name,
                unit_price=supplier_product.price,
                quantity=qty,
                line_total=line_total,
            )
            conversation, _ = SupplierConversation.objects.get_or_create(
                merchant=request.user,
                supplier=supplier,
            )
            merchant = _merchant_identity_payload(request.user)
            order_message = (
                f"Nouvelle commande\n"
                f"- Produit: {supplier_product.name}\n"
                f"- Quantite: {qty}\n"
                f"- Total: {float(line_total):.2f}\n"
                f"- Client: {merchant['name']}\n"
                f"- Telephone: {merchant['phone']}\n"
                f"- Adresse: {merchant['commune']} {merchant['quarter']} {merchant['avenue']} {merchant['number']}\n"
            ).strip()
            message = SupplierMessage.objects.create(
                conversation=conversation,
                sender=request.user,
                message_type=SupplierMessage.MessageType.TEXT,
                content=order_message,
            )
            conversation.last_message_preview = f"Commande: {supplier_product.name} x{qty}"
            conversation.save(update_fields=["last_message_preview", "updated_at"])

        order = SupplierOrder.objects.select_related(
            "merchant",
            "supplier",
        ).prefetch_related("items").get(id=order.id)
        return Response(
            {
                "order": SupplierOrderSerializer(order).data,
                "conversation_id": conversation.id,
                "message_id": message.id,
            },
            status=201,
        )


class StockOverviewView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        products = Product.objects.filter(seller=request.user, is_active=True).order_by("name")
        out = []
        for p in products:
            is_critical = p.stock_quantity <= p.reorder_threshold
            velocity = "critical" if is_critical else "stable"
            last_in = (
                p.stock_movements.filter(movement_type=StockMovement.MovementType.IN)
                .order_by("-created_at")
                .first()
            )
            out.append(
                {
                    "id": p.id,
                    "name": p.name,
                    "sku": p.sku,
                    "stock_quantity": p.stock_quantity,
                    "reorder_threshold": p.reorder_threshold,
                    "is_critical": is_critical,
                    "velocity": velocity,
                    "last_stock_add_at": last_in.created_at.isoformat() if last_in else None,
                    "last_stock_add_by": last_in.seller.username if last_in else None,
                    "last_stock_add_qty": abs(int(last_in.quantity)) if last_in else 0,
                }
            )
        return Response(out)


class StockAddView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def post(self, request):
        serializer = StockAddSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        product_id = data["product_id"]
        quantity = int(data["quantity"])
        reason = (data.get("reason") or "").strip() or "manual_restock"

        with transaction.atomic():
            product = Product.objects.select_for_update().filter(
                seller=request.user,
                id=product_id,
                is_active=True,
            ).first()
            if product is None:
                return Response({"detail": "Produit introuvable."}, status=404)

            product.stock_quantity += quantity
            product.save(update_fields=["stock_quantity"])

            movement = StockMovement.objects.create(
                seller=request.user,
                product=product,
                movement_type=StockMovement.MovementType.IN,
                quantity=quantity,
                reason=reason,
                balance_after=product.stock_quantity,
                reference=f"restock:{request.user.username}",
            )

        return Response(
            {
                "detail": "Stock mis a jour.",
                "product_id": product.id,
                "product_name": product.name,
                "added_quantity": quantity,
                "stock_quantity": product.stock_quantity,
                "trace": {
                    "added_by": request.user.username,
                    "added_at": movement.created_at.isoformat(),
                    "reason": reason,
                },
            }
        )


class StockMovementsView(APIView):
    """
    GET /api/v1/commerce/stock/movements/?product_id=1&date=YYYY-MM-DD&added_by=user
    Historique des mouvements de stock avec filtres.
    """

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        qs = StockMovement.objects.filter(seller=request.user).select_related("product", "seller").order_by("-created_at")

        product_id = request.query_params.get("product_id")
        if product_id:
            qs = qs.filter(product_id=product_id)

        date_str = request.query_params.get("date")
        if date_str:
            qs = qs.filter(created_at__date=date_str)

        added_by = (request.query_params.get("added_by") or "").strip()
        if added_by:
            qs = qs.filter(seller__username__icontains=added_by)

        out = []
        for m in qs[:200]:
            out.append(
                {
                    "id": m.id,
                    "product_id": m.product_id,
                    "product_name": m.product.name if m.product else "",
                    "sku": m.product.sku if m.product else "",
                    "movement_type": m.movement_type,
                    "quantity": m.quantity,
                    "reason": m.reason,
                    "balance_after": m.balance_after,
                    "added_by": m.seller.username if m.seller else "",
                    "created_at": m.created_at.isoformat() if m.created_at else None,
                    "reference": m.reference,
                }
            )
        return Response(out)


class SalesSummaryView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        today = timezone.localdate()
        today_sales = Sale.objects.filter(seller=request.user, created_at__date=today)
        aggregate = today_sales.aggregate(
            total=Sum("total"),
            margin=Sum("discount_amount"),
        )
        transactions = today_sales.count()
        total = aggregate.get("total") or Decimal("0")
        avg_ticket = total / transactions if transactions else Decimal("0")
        return Response(
            {
                "today_revenue": float(total),
                "transactions": transactions,
                "average_ticket": float(avg_ticket),
            }
        )


class AiSaleDraftView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def _build_rule_based_draft(self, user, prompt):
        products = list(
            Product.objects.filter(seller=user, is_active=True).order_by("name")
        )
        if not products:
            return {
                "prompt": prompt,
                "items": [],
                "unmatched": [],
                "warnings": ["Aucun produit actif dans votre stock."],
                "payment_method": "cash",
                "customer_name": "",
                "total": 0.0,
            }

        draft_items = []
        unmatched = []
        warnings = []
        total = Decimal("0")

        lowered = prompt.lower()
        payment_method = "cash"
        if any(k in lowered for k in ["mobile money", "mpesa", "airtel", "orange money"]):
            payment_method = "mobile_money"
        elif any(k in lowered for k in ["carte", "card", "visa", "mastercard"]):
            payment_method = "card"

        customer_name = ""
        customer_match = re.search(
            r"(?:client|patient)\s+([a-zA-ZÀ-ÿ0-9\-\s]{2,60})",
            prompt,
            flags=re.IGNORECASE,
        )
        if customer_match:
            customer_name = customer_match.group(1).strip(" .,:;")

        segments = [
            seg.strip()
            for seg in re.split(r",|;|\bet\b|\n", prompt, flags=re.IGNORECASE)
            if seg.strip()
        ]
        if not segments:
            segments = [prompt]

        for seg in segments:
            clean = seg.lower().strip()
            if not clean:
                continue
            if any(
                x in clean
                for x in [
                    "cash",
                    "espèce",
                    "carte",
                    "mobile money",
                    "mpesa",
                    "orange money",
                    "airtel",
                ]
            ):
                continue
            qty_match = re.search(r"(\d+)", clean)
            qty = int(qty_match.group(1)) if qty_match else 1
            clean_name = re.sub(
                r"\b(?:vends|vente|vend|prendre|prends|ajoute|ajouter|client|patient)\b",
                " ",
                clean,
            )
            clean_name = re.sub(r"\d+", " ", clean_name)
            clean_name = re.sub(r"\s+", " ", clean_name).strip()
            if not clean_name:
                continue

            target = None
            best_score = 0
            tokens = [t for t in re.split(r"\s+", clean_name) if len(t) > 1]
            for p in products:
                p_name = (p.name or "").lower()
                p_sku = (p.sku or "").lower()
                score = 0
                if clean_name in p_name or p_name in clean_name:
                    score += 5
                if clean_name in p_sku:
                    score += 4
                for t in tokens:
                    if t in p_name:
                        score += 1
                    if t in p_sku:
                        score += 1
                if score > best_score:
                    best_score = score
                    target = p

            if target is None or best_score <= 0:
                unmatched.append({"text": seg, "quantity": qty})
                continue

            if target.stock_quantity <= 0:
                warnings.append(f"{target.name}: stock épuisé.")
                continue
            if qty > target.stock_quantity:
                warnings.append(
                    f"{target.name}: quantité demandée {qty}, stock disponible {target.stock_quantity}. Ajustée."
                )
                qty = target.stock_quantity

            line_total = Decimal(str(target.unit_price)) * qty
            total += line_total
            draft_items.append(
                {
                    "product_id": target.id,
                    "name": target.name,
                    "sku": target.sku,
                    "quantity": qty,
                    "unit_price": float(target.unit_price),
                    "line_total": float(line_total),
                    "stock_quantity": target.stock_quantity,
                }
            )

        if not draft_items and not unmatched:
            unmatched.append({"text": prompt, "quantity": 1})

        return {
            "prompt": prompt,
            "items": draft_items,
            "unmatched": unmatched,
            "warnings": warnings,
            "payment_method": payment_method,
            "customer_name": customer_name,
            "total": float(total),
        }

    def _build_draft_for_prompt(self, user, prompt):
        return self._build_rule_based_draft(user, prompt)

    def post(self, request):
        audio = request.FILES.get("audio")
        if audio is not None:
            return Response(
                {
                    "detail": "Transcription audio indisponible: mode sans LLM activé. Utilisez la saisie texte."
                },
                status=400,
            )

        serializer = AiSaleDraftSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        prompt = serializer.validated_data["prompt"].strip()
        return Response(self._build_draft_for_prompt(request.user, prompt))


class QuickSaleCreateView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def post(self, request):
        serializer = QuickSaleCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            item_rows = data["items"]
            product_ids = [row["product_id"] for row in item_rows]
            products = {
                p.id: p
                for p in Product.objects.select_for_update().filter(
                    seller=request.user,
                    id__in=product_ids,
                    is_active=True,
                )
            }

            if len(products) != len(set(product_ids)):
                return Response({"detail": "Produit introuvable."}, status=404)

            subtotal = Decimal("0")
            sale_lines = []
            for row in item_rows:
                product = products[row["product_id"]]
                qty = int(row["quantity"])
                if product.stock_quantity < qty:
                    return Response(
                        {"detail": f"Stock insuffisant pour {product.name}."},
                        status=400,
                    )
                unit_price = Decimal(str(product.unit_price))
                line_total = unit_price * qty
                subtotal += line_total
                sale_lines.append((product, qty, unit_price, line_total))

            discount_rate = Decimal(str(data.get("discount_rate", 0)))
            discount_amount = (subtotal * discount_rate) / Decimal("100")
            total = subtotal - discount_amount

            customer = None
            customer_name = (data.get("customer_name") or "").strip()
            if customer_name:
                customer, _ = Customer.objects.get_or_create(
                    seller=request.user,
                    full_name=customer_name,
                    defaults={"segment": "regular"},
                )

            sale = Sale.objects.create(
                seller=request.user,
                customer=customer,
                subtotal=subtotal,
                discount_amount=discount_amount,
                total=total,
                payment_method=data.get("payment_method", "cash"),
                status="completed",
            )

            for product, qty, unit_price, line_total in sale_lines:
                SaleItem.objects.create(
                    sale=sale,
                    product=product,
                    quantity=qty,
                    unit_price=unit_price,
                    line_total=line_total,
                )
                product.stock_quantity -= qty
                product.save(update_fields=["stock_quantity"])
                StockMovement.objects.create(
                    seller=request.user,
                    product=product,
                    movement_type=StockMovement.MovementType.OUT,
                    quantity=-qty,
                    reason="sale",
                    balance_after=product.stock_quantity,
                    reference=f"sale:{sale.id}",
                )

        return Response(SaleSerializer(sale).data, status=201)


class SalesListView(APIView):
    """
    GET /api/v1/commerce/sales/list/?date=YYYY-MM-DD
    Liste des ventes du vendeur, filtrables par date.
    """

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        date_str = request.query_params.get("date")
        qs = Sale.objects.filter(seller=request.user).select_related("customer").order_by("-created_at")
        if date_str:
            qs = qs.filter(created_at__date=date_str)

        out = []
        for s in qs[:200]:
            out.append(
                {
                    "id": s.id,
                    "date": s.created_at.date().isoformat() if s.created_at else None,
                    "time": s.created_at.strftime("%H:%M") if s.created_at else "",
                    "customer_name": s.customer.full_name if s.customer else "",
                    "payment_method": s.payment_method,
                    "items_count": s.items.count(),
                    "subtotal": float(s.subtotal),
                    "discount_amount": float(s.discount_amount),
                    "total": float(s.total),
                    "status": s.status,
                }
            )
        return Response(out)


def _sale_receipt_payload(sale):
    data = SaleSerializer(sale).data
    data["customer_name"] = sale.customer.full_name if sale.customer else ""
    data["reference"] = _sale_reference(sale)
    if sale.created_at:
        data["created_at"] = sale.created_at.isoformat()
    if sale.canceled_at:
        data["canceled_at"] = sale.canceled_at.isoformat()
    return data


class SaleDetailView(APIView):
    """GET /api/v1/commerce/sales/<id>/ — détail reçu vente."""

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request, sale_id: int):
        sale = (
            Sale.objects.filter(seller=request.user, id=sale_id)
            .select_related("customer")
            .prefetch_related("items__product")
            .first()
        )
        if sale is None:
            return Response({"detail": "Vente introuvable."}, status=404)
        return Response(_sale_receipt_payload(sale))


class SaleCancelView(APIView):
    """POST /api/v1/commerce/sales/<id>/cancel/ — annulation avec restitution stock."""

    permission_classes = [IsAuthenticated, IsSeller]

    def post(self, request, sale_id: int):
        reason = (request.data.get("reason") or "").strip()
        if not reason:
            return Response({"detail": "Motif d'annulation obligatoire."}, status=400)

        with transaction.atomic():
            sale = (
                Sale.objects.select_for_update()
                .filter(seller=request.user, id=sale_id)
                .select_related("customer")
                .first()
            )
            if sale is None:
                return Response({"detail": "Vente introuvable."}, status=404)
            if sale.status in {"cancelled", "canceled"}:
                return Response(
                    {"detail": "Cette vente est déjà annulée.", "receipt": _sale_receipt_payload(sale)},
                    status=400,
                )

            items = list(
                SaleItem.objects.filter(sale=sale).select_related("product").select_for_update()
            )
            for row in items:
                product = row.product
                product.stock_quantity += row.quantity
                product.save(update_fields=["stock_quantity"])
                StockMovement.objects.create(
                    seller=request.user,
                    product=product,
                    movement_type=StockMovement.MovementType.IN,
                    quantity=row.quantity,
                    reason="sale_cancel",
                    balance_after=product.stock_quantity,
                    reference=f"sale_cancel:{sale.id}",
                )

            sale.status = "cancelled"
            sale.cancel_reason = reason[:255]
            sale.canceled_at = timezone.now()
            sale.save(update_fields=["status", "cancel_reason", "canceled_at", "updated_at"])

        payload = _sale_receipt_payload(sale)
        return Response({"receipt": payload}, status=200)


class ReceiptVerifyView(APIView):
    """
    GET /api/v1/commerce/sales/receipt-verify/?reference=REC-YYYYMMDD-000001
    Ou avec payload QR:
    GET /api/v1/commerce/sales/receipt-verify/?payload=REF:REC-...;RECU:...;...
    """

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        reference = (request.query_params.get("reference") or "").strip()
        payload = (request.query_params.get("payload") or "").strip()

        if not reference and payload:
            for part in payload.split(";"):
                if part.startswith("REF:"):
                    reference = part.replace("REF:", "", 1).strip()
                    break

        if not reference:
            return Response({"valid": False, "detail": "Reference manquante."}, status=400)

        if not reference.startswith("REC-"):
            return Response({"valid": False, "detail": "Format de reference invalide."}, status=400)

        chunks = reference.split("-")
        if len(chunks) != 3:
            return Response({"valid": False, "detail": "Format de reference invalide."}, status=400)

        date_part = chunks[1]
        sale_id_part = chunks[2]
        if len(date_part) != 8 or not date_part.isdigit() or not sale_id_part.isdigit():
            return Response({"valid": False, "detail": "Format de reference invalide."}, status=400)

        sale_id = int(sale_id_part)
        sale = Sale.objects.filter(seller=request.user, id=sale_id).select_related("customer").first()
        if sale is None:
            return Response({"valid": False, "detail": "Recu introuvable pour ce compte."}, status=404)

        expected_reference = _sale_reference(sale)
        if expected_reference != reference:
            return Response({"valid": False, "detail": "Reference non valide."}, status=400)

        data = SaleSerializer(sale).data
        data["customer_name"] = sale.customer.full_name if sale.customer else ""
        data["reference"] = expected_reference
        data["verified_at"] = timezone.now().isoformat()
        return Response({"valid": True, "detail": "Recu verifie.", "receipt": data}, status=200)


class CustomersSummaryView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        customers = Customer.objects.filter(seller=request.user).order_by("full_name")
        out = []
        for c in customers:
            sales_qs = c.sales.all()
            sales_count = sales_qs.count()
            total_spent = sales_qs.aggregate(total=Sum("total")).get("total") or Decimal("0")
            last_sale = sales_qs.order_by("-created_at").values_list("created_at", flat=True).first()
            out.append(
                {
                    "id": c.id,
                    "full_name": c.full_name,
                    "phone": c.phone,
                    "segment": c.segment,
                    "sales_count": sales_count,
                    "total_spent": float(total_spent),
                    "last_purchase_at": last_sale.isoformat() if last_sale else None,
                }
            )
        return Response(out)


class InsightsView(APIView):
    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        today = timezone.localdate()

        weekly = []
        for idx in range(6, -1, -1):
            day = today - timedelta(days=idx)
            day_total = (
                Sale.objects.filter(seller=request.user, created_at__date=day)
                .aggregate(total=Sum("total"))
                .get("total")
                or Decimal("0")
            )
            weekly.append({"date": day.isoformat(), "revenue": float(day_total)})

        top_products_qs = (
            SaleItem.objects.filter(sale__seller=request.user)
            .values("product__name")
            .annotate(qty=Sum("quantity"), revenue=Sum("line_total"))
            .order_by("-qty")[:5]
        )
        top_products = [
            {
                "name": row["product__name"] or "",
                "qty": int(row["qty"] or 0),
                "revenue": float(row["revenue"] or Decimal("0")),
            }
            for row in top_products_qs
        ]

        critical_count = Product.objects.filter(
            seller=request.user,
            is_active=True,
            stock_quantity__lte=0,
        ).count()
        # Seuil d'alerte réel (stock <= reorder_threshold)
        critical_count += Product.objects.filter(
            seller=request.user,
            is_active=True,
            stock_quantity__gt=0,
            stock_quantity__lte=F("reorder_threshold"),
        ).count()

        customers = Customer.objects.filter(seller=request.user)
        inactive_count = 0
        limit_date = timezone.now() - timedelta(days=30)
        for c in customers:
            last = c.sales.order_by("-created_at").values_list("created_at", flat=True).first()
            if not last or last < limit_date:
                inactive_count += 1

        decisions = [
            {
                "title": "Réapprovisionnement prioritaire",
                "subtitle": f"{critical_count} produit(s) proche(s) de rupture.",
            },
            {
                "title": "Relance clients inactifs",
                "subtitle": f"{inactive_count} client(s) sans achat depuis 30+ jours.",
            },
            {
                "title": "Booster le top produit",
                "subtitle": (
                    f"{top_products[0]['name']} est votre meilleure vente."
                    if top_products
                    else "Aucune vente enregistrée pour le moment."
                ),
            },
        ]

        return Response(
            {
                "weekly_revenue": weekly,
                "top_products": top_products,
                "decisions": decisions,
            }
        )


class AccountingReportsView(APIView):
    """
    GET /api/v1/commerce/accounting/reports/?days=30
    Rapports comptables essentiels alignés SYCOHADA (version PME):
    - Journal
    - Balance générale
    - Compte de résultat
    - Bilan simplifié
    - Flux de trésorerie simplifié
    """

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        try:
            days = int(request.query_params.get("days", 30))
        except (TypeError, ValueError):
            days = 30
        days = max(1, min(days, 365))

        end_date = timezone.localdate()
        start_date = end_date - timedelta(days=days - 1)

        sales_qs = Sale.objects.filter(
            seller=request.user,
            status="completed",
            created_at__date__gte=start_date,
            created_at__date__lte=end_date,
        )
        sale_items_qs = SaleItem.objects.filter(sale__in=sales_qs).select_related("product", "sale")

        gross_sales = sales_qs.aggregate(v=Sum("subtotal")).get("v") or Decimal("0")
        discounts = sales_qs.aggregate(v=Sum("discount_amount")).get("v") or Decimal("0")
        net_sales = sales_qs.aggregate(v=Sum("total")).get("v") or Decimal("0")

        cogs = Decimal("0")
        for item in sale_items_qs:
            cost = Decimal(str(item.product.cost_price or 0))
            cogs += cost * item.quantity

        gross_profit = net_sales - cogs
        operating_expenses = Decimal("0")
        net_result = gross_profit - operating_expenses

        inventory_value = Decimal("0")
        for p in Product.objects.filter(seller=request.user, is_active=True):
            inventory_value += Decimal(str(p.cost_price or 0)) * Decimal(str(max(0, p.stock_quantity)))

        cash_balance = net_sales
        receivables = Decimal("0")
        payables = Decimal("0")
        equity = max(Decimal("0"), net_result)

        trial_balance = [
            {
                "account": "57",
                "label": "Caisse",
                "debit": float(net_sales),
                "credit": 0.0,
            },
            {
                "account": "70",
                "label": "Ventes de marchandises",
                "debit": 0.0,
                "credit": float(net_sales),
            },
            {
                "account": "60",
                "label": "Coût des ventes",
                "debit": float(cogs),
                "credit": 0.0,
            },
            {
                "account": "31",
                "label": "Stock de marchandises",
                "debit": 0.0,
                "credit": float(cogs),
            },
        ]

        journal = []
        for sale in sales_qs.order_by("-created_at")[:50]:
            sale_cogs = Decimal("0")
            for item in sale.items.select_related("product").all():
                sale_cogs += Decimal(str(item.product.cost_price or 0)) * item.quantity
            lines = [
                {
                    "account": "57",
                    "label": "Caisse",
                    "debit": float(sale.total),
                    "credit": 0.0,
                },
                {
                    "account": "70",
                    "label": "Ventes de marchandises",
                    "debit": 0.0,
                    "credit": float(sale.total),
                },
            ]
            if sale_cogs > 0:
                lines.extend(
                    [
                        {
                            "account": "60",
                            "label": "Coût des ventes",
                            "debit": float(sale_cogs),
                            "credit": 0.0,
                        },
                        {
                            "account": "31",
                            "label": "Stock de marchandises",
                            "debit": 0.0,
                            "credit": float(sale_cogs),
                        },
                    ]
                )
            journal.append(
                {
                    "date": sale.created_at.date().isoformat(),
                    "piece": f"VTE-{sale.id}",
                    "description": "Vente comptabilisée",
                    "lines": lines,
                }
            )

        data = {
            "period": {
                "days": days,
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat(),
            },
            "kpis": {
                "gross_sales": float(gross_sales),
                "discounts": float(discounts),
                "net_sales": float(net_sales),
                "cogs": float(cogs),
                "gross_profit": float(gross_profit),
                "net_result": float(net_result),
            },
            "income_statement": {
                "gross_sales": float(gross_sales),
                "discounts": float(discounts),
                "net_sales": float(net_sales),
                "cost_of_goods_sold": float(cogs),
                "gross_profit": float(gross_profit),
                "operating_expenses": float(operating_expenses),
                "net_result": float(net_result),
            },
            "balance_sheet": {
                "assets": {
                    "cash": float(cash_balance),
                    "inventory": float(inventory_value),
                    "receivables": float(receivables),
                },
                "liabilities": {
                    "payables": float(payables),
                },
                "equity": {
                    "retained_earnings": float(equity),
                },
            },
            "cashflow": {
                "operating_inflows": float(net_sales),
                "operating_outflows": float(cogs + operating_expenses),
                "net_operating_cashflow": float(net_sales - cogs - operating_expenses),
                "investing_cashflow": 0.0,
                "financing_cashflow": 0.0,
                "net_cashflow": float(net_sales - cogs - operating_expenses),
            },
            "trial_balance": trial_balance,
            "journal": journal,
            "sycohada_reference": {
                "classes": [
                    {"code": "1", "label": "Ressources durables"},
                    {"code": "2", "label": "Actif immobilisé"},
                    {"code": "3", "label": "Stocks"},
                    {"code": "4", "label": "Tiers"},
                    {"code": "5", "label": "Trésorerie"},
                    {"code": "6", "label": "Charges"},
                    {"code": "7", "label": "Produits"},
                    {"code": "8", "label": "Autres charges/produits"},
                ]
            },
        }
        return Response(data)


class AdminPlatformOverviewView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def get(self, request):
        sellers = User.objects.filter(role="seller")
        sales = Sale.objects.all()
        aggregate = sales.aggregate(revenue=Sum("total"))
        tenant_ids = {_tenant_id_for_user(u) for u in sellers}
        active_today = set(
            Sale.objects.filter(created_at__date=timezone.localdate())
            .values_list("seller_id", flat=True)
        )
        return Response(
            {
                "sellers_count": sellers.count(),
                "active_users_today": len(active_today),
                "active_tenants": len(tenant_ids),
                "products_count": Product.objects.count(),
                "sales_count": sales.count(),
                "revenue_total": float(aggregate.get("revenue") or Decimal("0")),
                "total_revenue_today": float(
                    Sale.objects.filter(created_at__date=timezone.localdate()).aggregate(
                        revenue=Sum("total")
                    ).get("revenue")
                    or Decimal("0")
                ),
                "sync_errors": 0,
                "avg_latency_ms": 0,
                "errors_5xx_24h": 0,
            }
        )


class AdminSellersActivityView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def get(self, request):
        out = []
        sellers = User.objects.filter(role="seller").order_by("username")
        for seller in sellers:
            seller_sales = Sale.objects.filter(seller=seller)
            revenue = seller_sales.aggregate(revenue=Sum("total")).get("revenue") or Decimal("0")
            out.append(
                {
                    "seller_id": seller.id,
                    "seller_name": seller.username,
                    "username": seller.username,
                    "phone": seller.phone,
                    "tenant_id": _tenant_id_for_user(seller),
                    "company_name": seller.company_name or "",
                    "business_category": seller.business_category or "",
                    "products_count": Product.objects.filter(seller=seller).count(),
                    "sales_count": seller_sales.count(),
                    "revenue": float(revenue),
                }
            )
        return Response(out)


class AdminTenantsListView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def get(self, request):
        out = [_tenant_snapshot(tenant_id, users) for tenant_id, users in _tenant_groups().items()]
        out.sort(key=lambda row: row["revenue_total"], reverse=True)
        return Response(out)


class AdminTenantDetailView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def get(self, request, tenant_id):
        candidate_users = User.objects.filter(role__in=["admin", "seller", "cashier", "super_admin"]).order_by("id")
        users = [u for u in candidate_users if _tenant_id_for_user(u) == tenant_id]
        if not users:
            return Response({"detail": "Tenant introuvable."}, status=404)

        owner = next((u for u in users if (u.role or "").lower() == "admin"), users[0])
        seller_ids = [u.id for u in users if (u.role or "").lower() == "seller"]
        tenant_sales = Sale.objects.filter(seller_id__in=seller_ids).select_related("seller", "customer").order_by("-created_at")
        sales_aggregate = tenant_sales.aggregate(total=Sum("total"))
        total_revenue = sales_aggregate.get("total") or Decimal("0")
        sales_count = tenant_sales.count()
        avg_ticket = (total_revenue / sales_count) if sales_count else Decimal("0")

        users_payload = []
        for u in users:
            users_payload.append(
                {
                    "id": u.id,
                    "username": u.username,
                    "phone": u.phone,
                    "email": u.email,
                    "role": u.role,
                    "is_active": u.is_active,
                    "is_superuser": u.is_superuser,
                    "date_joined": u.date_joined.isoformat() if u.date_joined else None,
                    "last_login": u.last_login.isoformat() if u.last_login else None,
                }
            )

        sales_payload = []
        for sale in tenant_sales[:100]:
            sales_payload.append(
                {
                    "id": sale.id,
                    "created_at": sale.created_at.isoformat() if sale.created_at else None,
                    "seller_username": sale.seller.username if sale.seller else "",
                    "customer_name": sale.customer.full_name if sale.customer else "",
                    "payment_method": sale.payment_method,
                    "status": sale.status,
                    "subtotal": float(sale.subtotal),
                    "discount_amount": float(sale.discount_amount),
                    "total": float(sale.total),
                }
            )

        return Response(
            {
                "tenant": {
                    "tenant_id": tenant_id,
                    "company_name": owner.company_name or f"Tenant {tenant_id}",
                    "company_trade_name": owner.company_trade_name or "",
                    "business_category": owner.business_category or "",
                    "company_phone": owner.company_phone or owner.phone or "",
                    "company_email": owner.company_email or owner.email or "",
                    "company_country": owner.company_country or "",
                    "company_province": owner.company_province or "",
                    "company_city": owner.company_city or "",
                    "company_commune": owner.company_commune or "",
                    "company_quarter": owner.company_quarter or "",
                    "company_avenue": owner.company_avenue or "",
                    "company_number": owner.company_number or "",
                    "legal_form": owner.legal_form or "",
                    "rccm": owner.rccm or "",
                    "idnat": owner.idnat or "",
                    "nif": owner.nif or "",
                    "created_at": owner.date_joined.isoformat() if owner.date_joined else None,
                },
                "kpis": {
                    "users_count": len(users_payload),
                    "sellers_count": len([u for u in users if (u.role or "").lower() == "seller"]),
                    "cashiers_count": len([u for u in users if (u.role or "").lower() == "cashier"]),
                    "admins_count": len([u for u in users if (u.role or "").lower() in {"admin", "super_admin"}]),
                    "products_count": Product.objects.filter(seller_id__in=seller_ids).count() if seller_ids else 0,
                    "customers_count": Customer.objects.filter(seller_id__in=seller_ids).count() if seller_ids else 0,
                    "sales_count": sales_count,
                    "revenue_total": float(total_revenue),
                    "average_ticket": float(avg_ticket),
                },
                "users": users_payload,
                "recent_sales": sales_payload,
            }
        )


class AdminTenantStatusUpdateView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def post(self, request, tenant_id):
        raw_active = request.data.get("active", False)
        if isinstance(raw_active, bool):
            active = raw_active
        else:
            active = str(raw_active).strip().lower() in {"1", "true", "yes", "oui", "on"}

        users = [u for u in _tenant_candidate_users() if _tenant_id_for_user(u) == tenant_id]
        if not users:
            return Response({"detail": "Tenant introuvable."}, status=404)

        # Protection: on évite de se désactiver soi-même.
        updated_count = 0
        protected_count = 0
        for user in users:
            if user.id == request.user.id:
                protected_count += 1
                continue
            if user.is_active != active:
                user.is_active = active
                user.save(update_fields=["is_active"])
                updated_count += 1

        return Response(
            {
                "detail": "Tenant mis a jour.",
                "tenant_id": tenant_id,
                "active": active,
                "updated_users": updated_count,
                "protected_users": protected_count,
            }
        )


class AdminForceLogoutGlobalView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def post(self, request):
        sessions_deleted = Session.objects.count()
        Session.objects.all().delete()
        return Response(
            {
                "detail": "Sessions globales revoquees.",
                "sessions_deleted": sessions_deleted,
            }
        )


class AdminTenantsCsvExportView(APIView):
    authentication_classes = [JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated, IsSuperAdmin]

    def get(self, request):
        rows = [_tenant_snapshot(tenant_id, users) for tenant_id, users in _tenant_groups().items()]
        rows.sort(key=lambda row: row["revenue_total"], reverse=True)

        response = HttpResponse(content_type="text/csv; charset=utf-8")
        response["Content-Disposition"] = 'attachment; filename="tekisa_tenants_report.csv"'

        writer = csv.writer(response)
        writer.writerow(
            [
                "tenant_id",
                "company_name",
                "business_category",
                "users_count",
                "sellers_count",
                "cashiers_count",
                "admins_count",
                "products_count",
                "customers_count",
                "sales_count",
                "revenue_total",
                "revenue_today",
                "is_suspended",
                "last_sale_at",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row.get("tenant_id", ""),
                    row.get("company_name", ""),
                    row.get("business_category", ""),
                    row.get("users_count", 0),
                    row.get("sellers_count", 0),
                    row.get("cashiers_count", 0),
                    row.get("admins_count", 0),
                    row.get("products_count", 0),
                    row.get("customers_count", 0),
                    row.get("sales_count", 0),
                    row.get("revenue_total", 0),
                    row.get("revenue_today", 0),
                    row.get("is_suspended", False),
                    row.get("last_sale_at", ""),
                ]
            )

        return response


class SalesExportView(APIView):
    """GET /api/v1/commerce/sales/export.xlsx/?date=YYYY-MM-DD"""

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        from io import BytesIO

        from openpyxl import Workbook

        date_str = request.query_params.get("date")
        qs = Sale.objects.filter(seller=request.user).select_related("customer").order_by("-created_at")
        if date_str:
            qs = qs.filter(created_at__date=date_str)

        wb = Workbook()
        ws = wb.active
        ws.title = "Ventes"
        ws.append(
            [
                "ID",
                "Date",
                "Heure",
                "Client",
                "Articles",
                "Paiement",
                "Statut",
                "Sous-total",
                "Remise",
                "Total",
            ]
        )
        for sale in qs[:2000]:
            ws.append(
                [
                    sale.id,
                    sale.created_at.date().isoformat() if sale.created_at else "",
                    sale.created_at.strftime("%H:%M") if sale.created_at else "",
                    sale.customer.full_name if sale.customer else "",
                    sale.items.count(),
                    sale.payment_method,
                    sale.status,
                    float(sale.subtotal),
                    float(sale.discount_amount),
                    float(sale.total),
                ]
            )

        buffer = BytesIO()
        wb.save(buffer)
        buffer.seek(0)
        filename = f"tekisa-ventes-{date_str or 'all'}.xlsx"
        response = HttpResponse(
            buffer.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        return response


class StockExportView(APIView):
    """GET /api/v1/commerce/stock/export.xlsx/"""

    permission_classes = [IsAuthenticated, IsSeller]

    def get(self, request):
        from io import BytesIO

        from openpyxl import Workbook

        products = Product.objects.filter(seller=request.user, is_active=True).order_by("name")

        wb = Workbook()
        ws = wb.active
        ws.title = "Stock"
        ws.append(
            [
                "ID",
                "Nom",
                "SKU",
                "Prix unitaire",
                "Cout",
                "Stock",
                "Seuil alerte",
            ]
        )
        for product in products:
            ws.append(
                [
                    product.id,
                    product.name,
                    product.sku,
                    float(product.unit_price),
                    float(product.cost_price),
                    product.stock_quantity,
                    product.reorder_threshold,
                ]
            )

        buffer = BytesIO()
        wb.save(buffer)
        buffer.seek(0)
        response = HttpResponse(
            buffer.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = 'attachment; filename="tekisa-stock.xlsx"'
        return response
