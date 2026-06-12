import json
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import authenticate, login, logout
from django.db import transaction
from django.db.models import Avg, Count, Q, Sum
from django.http import HttpResponseForbidden
from django.shortcuts import redirect
from django.utils import timezone
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.views.generic import TemplateView

from apps.commerce.models import (
    Customer,
    Product,
    Sale,
    SaleItem,
    StockMovement,
    SaleItem,
    SupplierConversation,
    SupplierOrder,
    SupplierProduct,
    SupplierProfile,
)
from apps.users.models import User


class _WebDataMixin:
    def _sales_queryset(self):
        if not self.request.user.is_authenticated:
            return Sale.objects.none()
        return Sale.objects.filter(seller=self.request.user)

    def _products_queryset(self):
        if not self.request.user.is_authenticated:
            return Product.objects.none()
        return Product.objects.filter(seller=self.request.user)

    def _customers_queryset(self):
        if not self.request.user.is_authenticated:
            return Customer.objects.none()
        return Customer.objects.filter(seller=self.request.user)


class WebAuthRequiredMixin(LoginRequiredMixin):
    login_url = "/web/login/"


class WebHomeView(WebAuthRequiredMixin, _WebDataMixin, TemplateView):
    template_name = "web/dashboard.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        today = timezone.localdate()
        sales = self._sales_queryset()
        products = self._products_queryset()
        sales_today = sales.filter(created_at__date=today)
        agg_today = sales_today.aggregate(
            revenue=Sum("total"),
            transactions=Count("id"),
            avg_ticket=Avg("total"),
        )
        top_item = (
            SaleItem.objects.filter(sale__in=sales)
            .values("product__name")
            .annotate(total_qty=Sum("quantity"))
            .order_by("-total_qty")
            .first()
        )
        context["page_title"] = "Assistant boutique"
        context["active_menu"] = "dashboard"
        context["revenue_today"] = round(float(agg_today["revenue"] or 0), 2)
        context["transactions_today"] = int(agg_today["transactions"] or 0)
        context["avg_ticket_today"] = round(float(agg_today["avg_ticket"] or 0), 2)
        context["critical_stock"] = products.filter(
            stock_quantity__lte=0
        ).count() + products.filter(stock_quantity__lte=5, stock_quantity__gt=0).count()
        context["top_product"] = top_item["product__name"] if top_item else "—"
        context["inactive_customers"] = self._customers_queryset().filter(
            Q(sales__isnull=True) | Q(sales__created_at__lt=timezone.now() - timedelta(days=30))
        ).distinct().count()
        return context


class WebLoginView(TemplateView):
    template_name = "web/login.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Connexion"
        context["error_message"] = kwargs.get("error_message")
        context["success_message"] = kwargs.get("success_message")
        context["username_value"] = kwargs.get("username_value", "")
        context["auth_bg_image"] = "images/loginimage.jpg"
        return context

    def post(self, request, *args, **kwargs):
        username_input = (request.POST.get("username") or "").strip()
        password = request.POST.get("password") or ""
        resolved_username = username_input
        if username_input.startswith("+") or username_input.isdigit():
            user = User.objects.filter(phone=username_input).first()
            if user:
                resolved_username = user.username
        user = authenticate(request, username=resolved_username, password=password)
        if user is None:
            context = self.get_context_data(
                error_message="Identifiants invalides.",
                username_value=username_input,
            )
            return self.render_to_response(context)
        if not user.is_active:
            context = self.get_context_data(
                error_message="Compte désactivé.",
                username_value=username_input,
            )
            return self.render_to_response(context)
        login(request, user)
        return redirect("web-dashboard")


class WebRegisterView(TemplateView):
    template_name = "web/register.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Creation de compte"
        context["error_message"] = kwargs.get("error_message")
        context["success_message"] = kwargs.get("success_message")
        context["auth_bg_image"] = "images/register_intro.png"
        return context

    def post(self, request, *args, **kwargs):
        username = (request.POST.get("username") or "").strip()
        display_name = (request.POST.get("display_name") or "").strip()
        company_name = (request.POST.get("company_name") or "").strip()
        phone = (request.POST.get("phone") or "").strip()
        password = request.POST.get("password") or ""
        if not username or not phone or not password:
            context = self.get_context_data(
                error_message="Username, téléphone et mot de passe sont obligatoires."
            )
            return self.render_to_response(context)
        role = User.Role.SELLER
        if User.objects.filter(username=username).exists():
            context = self.get_context_data(error_message="Ce username existe déjà.")
            return self.render_to_response(context)
        if User.objects.filter(phone=phone).exists():
            context = self.get_context_data(error_message="Ce téléphone existe déjà.")
            return self.render_to_response(context)
        user = User.objects.create_user(
            username=username,
            password=password,
            phone=phone,
            role=role,
            first_name=display_name,
            company_name=company_name,
        )
        login(request, user)
        return redirect("web-dashboard")


class WebIntroView(TemplateView):
    template_name = "web/intro.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Bienvenue"
        context["auth_bg_image"] = "images/register_intro.png"
        return context


class WebAppDownloadView(TemplateView):
    template_name = "web/app_download.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Mise à jour terminée"
        context["play_store_url"] = (
            getattr(settings, "PLAY_STORE_URL", "") or "https://play.google.com/store"
        )
        context["app_store_url"] = (
            getattr(settings, "APP_STORE_URL", "") or "https://www.apple.com/app-store/"
        )
        context["apk_direct_url"] = (
            getattr(settings, "ANDROID_APK_URL", "") or "#"
        )
        return context


class WebSalesView(WebAuthRequiredMixin, _WebDataMixin, TemplateView):
    template_name = "web/sales.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        today = timezone.localdate()
        sales = self._sales_queryset()
        agg = sales.aggregate(
            total_revenue=Sum("total"),
            avg_ticket=Avg("total"),
            sales_count=Count("id"),
        )
        context["page_title"] = "Ventes"
        context["active_menu"] = "ventes"
        context["sales_today"] = sales.filter(created_at__date=today).count()
        context["sales_count"] = int(agg["sales_count"] or 0)
        context["total_revenue"] = round(float(agg["total_revenue"] or 0), 2)
        context["avg_ticket"] = round(float(agg["avg_ticket"] or 0), 2)
        context["canceled_sales"] = sales.filter(status__iexact="canceled").count()
        context["products"] = self._products_queryset().filter(is_active=True).order_by("name")[:300]
        context["customers"] = self._customers_queryset().order_by("full_name")[:300]
        date_str = (self.request.GET.get("date") or "").strip()
        if not date_str:
            date_str = today.isoformat()
        day_sales_qs = sales.filter(created_at__date=date_str).select_related("customer").order_by("-created_at")[:150]
        context["selected_date"] = date_str
        context["day_sales"] = day_sales_qs
        context["flash_success"] = kwargs.get("flash_success")
        context["flash_error"] = kwargs.get("flash_error")
        return context

    def post(self, request, *args, **kwargs):
        if not request.user.is_authenticated:
            return redirect("web-login")
        items_raw = (request.POST.get("items_json") or "").strip()
        customer_name_raw = (request.POST.get("customer_name") or "").strip()
        payment_method = (request.POST.get("payment_method") or "cash").strip().lower()
        if payment_method not in {"cash", "mobile_money", "card"}:
            payment_method = "cash"
        customer_id_raw = (request.POST.get("customer_id") or "").strip()
        try:
            items_rows = json.loads(items_raw) if items_raw else []
        except Exception:
            items_rows = []
        normalized = []
        for row in items_rows:
            try:
                product_id = int(row.get("product_id"))
                quantity = int(row.get("quantity"))
            except Exception:
                continue
            if quantity <= 0:
                continue
            normalized.append({"product_id": product_id, "quantity": quantity})
        if not normalized:
            context = self.get_context_data(flash_error="Ajoutez au moins un article avant d'encaisser.")
            return self.render_to_response(context)
        with transaction.atomic():
            product_ids = [r["product_id"] for r in normalized]
            products = {
                p.id: p
                for p in Product.objects.select_for_update().filter(
                    seller=request.user, is_active=True, id__in=product_ids
                )
            }
            if len(products) != len(set(product_ids)):
                context = self.get_context_data(flash_error="Un produit du panier est introuvable.")
                return self.render_to_response(context)
            subtotal = Decimal("0")
            sale_lines = []
            for row in normalized:
                product = products[row["product_id"]]
                qty = int(row["quantity"])
                if product.stock_quantity < qty:
                    context = self.get_context_data(
                        flash_error=f"Stock insuffisant pour {product.name}."
                    )
                    return self.render_to_response(context)
                unit_price = Decimal(str(product.unit_price))
                line_total = unit_price * qty
                subtotal += line_total
                sale_lines.append((product, qty, unit_price, line_total))
            customer = None
            if customer_id_raw:
                try:
                    customer = Customer.objects.filter(
                        seller=request.user,
                        id=int(customer_id_raw),
                    ).first()
                except Exception:
                    customer = None
            if customer is None and customer_name_raw:
                customer, _ = Customer.objects.get_or_create(
                    seller=request.user,
                    full_name=customer_name_raw,
                    defaults={"segment": "regular"},
                )
            sale = Sale.objects.create(
                seller=request.user,
                customer=customer,
                subtotal=subtotal,
                discount_amount=Decimal("0"),
                total=subtotal,
                payment_method=payment_method,
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
                    reason="sale_web",
                    balance_after=product.stock_quantity,
                    reference=f"sale:{sale.id}",
                )
        return redirect("web-ventes")


class WebStockView(WebAuthRequiredMixin, _WebDataMixin, TemplateView):
    template_name = "web/stock.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        products = self._products_queryset()
        context["page_title"] = "Stock"
        context["active_menu"] = "stock"
        context["products_total"] = products.count()
        context["critical_stock"] = products.filter(stock_quantity__lte=5).count()
        context["out_of_stock"] = products.filter(stock_quantity__lte=0).count()
        context["to_reorder"] = products.filter(
            stock_quantity__lte=5, stock_quantity__gt=0
        ).count()
        return context


class WebCustomersView(WebAuthRequiredMixin, _WebDataMixin, TemplateView):
    template_name = "web/customers.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        customers = self._customers_queryset()
        now = timezone.now()
        context["page_title"] = "Clients"
        context["active_menu"] = "clients"
        context["customers_total"] = customers.count()
        context["customers_active"] = customers.filter(
            sales__created_at__gte=now - timedelta(days=30)
        ).distinct().count()
        context["customers_inactive"] = customers.filter(
            Q(sales__isnull=True) | Q(sales__created_at__lt=now - timedelta(days=30))
        ).distinct().count()
        context["customers_new_month"] = customers.filter(
            created_at__gte=now - timedelta(days=30)
        ).count()
        return context


class WebSuppliersView(WebAuthRequiredMixin, TemplateView):
    template_name = "web/suppliers.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Reseau fournisseurs"
        context["active_menu"] = "fournisseurs"
        context["suppliers_active"] = SupplierProfile.objects.filter(is_active=True).count()
        context["marketplace_products"] = SupplierProduct.objects.filter(
            is_available=True
        ).count()
        if self.request.user.is_authenticated:
            context["active_conversations"] = SupplierConversation.objects.filter(
                merchant=self.request.user
            ).count()
            context["orders_in_progress"] = SupplierOrder.objects.filter(
                merchant=self.request.user,
                status__in=[SupplierOrder.Status.PENDING, SupplierOrder.Status.ACCEPTED],
            ).count()
        else:
            context["active_conversations"] = SupplierConversation.objects.count()
            context["orders_in_progress"] = SupplierOrder.objects.filter(
                status__in=[SupplierOrder.Status.PENDING, SupplierOrder.Status.ACCEPTED]
            ).count()
        return context


class WebAdminView(LoginRequiredMixin, UserPassesTestMixin, TemplateView):
    template_name = "web/administration.html"
    login_url = "/web/login/"

    def test_func(self):
        user = self.request.user
        if not user.is_authenticated:
            return False
        role = (getattr(user, "role", "") or "").lower()
        return user.is_superuser or role == "super_admin"

    def handle_no_permission(self):
        if self.request.user.is_authenticated:
            return HttpResponseForbidden("Acces refuse.")
        return super().handle_no_permission()

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        sales = Sale.objects.all()
        context["global_revenue"] = round(float(sales.aggregate(v=Sum("total"))["v"] or 0), 2)
        context["sellers_count"] = User.objects.filter(
            role__in=[User.Role.ADMIN, User.Role.SELLER, User.Role.CASHIER]
        ).count()
        context["products_count"] = Product.objects.count()
        context["sales_count"] = sales.count()
        context["page_title"] = "Administration"
        context["active_menu"] = "administration"
        return context


class WebSettingsView(WebAuthRequiredMixin, TemplateView):
    template_name = "web/settings.html"

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context["page_title"] = "Parametres"
        context["active_menu"] = "parametres"
        user = self.request.user if self.request.user.is_authenticated else None
        context["company_name"] = getattr(user, "company_name", "") or "—"
        context["phone"] = getattr(user, "phone", "") or "—"
        context["province"] = getattr(user, "company_province", "") or "—"
        context["commune"] = getattr(user, "company_commune", "") or "—"
        return context


class WebLogoutView(TemplateView):
    def get(self, request, *args, **kwargs):
        logout(request)
        return redirect("web-login")


class SuperAdminDashboardView(LoginRequiredMixin, UserPassesTestMixin, TemplateView):
    template_name = "super_admin/dashboard.html"
    login_url = "/admin/login/"

    def test_func(self):
        user = self.request.user
        if not user.is_authenticated:
            return False
        role = (getattr(user, "role", "") or "").lower()
        return user.is_superuser or role == "super_admin"

    def handle_no_permission(self):
        if self.request.user.is_authenticated:
            return HttpResponseForbidden("Acces refuse.")
        return super().handle_no_permission()


class SuperAdminTenantDetailPageView(LoginRequiredMixin, UserPassesTestMixin, TemplateView):
    template_name = "super_admin/tenant_detail.html"
    login_url = "/admin/login/"

    def test_func(self):
        user = self.request.user
        if not user.is_authenticated:
            return False
        role = (getattr(user, "role", "") or "").lower()
        return user.is_superuser or role == "super_admin"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["tenant_id"] = self.kwargs.get("tenant_id", "")
        return ctx

    def handle_no_permission(self):
        if self.request.user.is_authenticated:
            return HttpResponseForbidden("Acces refuse.")
        return super().handle_no_permission()
