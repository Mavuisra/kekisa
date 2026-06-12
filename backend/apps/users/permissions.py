from rest_framework.permissions import BasePermission

from .models import User


def _has_role(user: User, allowed_roles: set[str]) -> bool:
    if not user or not user.is_authenticated:
        return False
    role = (getattr(user, "role", "") or "").lower()
    return role in allowed_roles


class IsSuperAdmin(BasePermission):
    """Plateforme uniquement — pas les admins tenant (role=admin)."""

    def has_permission(self, request, view) -> bool:
        user: User = request.user  # type: ignore[assignment]
        return bool(user and (user.is_superuser or _has_role(user, {"super_admin"})))


class IsSchoolAdmin(BasePermission):
    def has_permission(self, request, view) -> bool:
        user: User = request.user  # type: ignore[assignment]
        return _has_role(user, {"school_admin", "admin"})


class IsTeacher(BasePermission):
    def has_permission(self, request, view) -> bool:
        user: User = request.user  # type: ignore[assignment]
        return _has_role(user, {"teacher"})


class IsParent(BasePermission):
    def has_permission(self, request, view) -> bool:
        user: User = request.user  # type: ignore[assignment]
        return _has_role(user, {"parent"})


class IsCommerceOperator(BasePermission):
    """
    Rôles autorisés sur le périmètre commerce.
    seller/admin/cashier/super_admin.
    """

    allowed_roles = {"seller", "admin", "cashier", "super_admin"}

    def has_permission(self, request, view) -> bool:
        user: User = request.user  # type: ignore[assignment]
        return _has_role(user, self.allowed_roles)


class IsSeller(IsCommerceOperator):
    """
    Alias backward-compatible.
    Historiquement utilisé dans les vues commerce.
    """

    def has_permission(self, request, view) -> bool:
        return super().has_permission(request, view)


class IsSellerDataOwner(BasePermission):
    """
    Object-level guard for commerce resources.
    Ensures a seller can only access objects attached to their own account.
    """

    message = "Acces refuse: donnee d'un autre compte."

    def has_object_permission(self, request, view, obj) -> bool:
        user: User = request.user  # type: ignore[assignment]
        if not user or not user.is_authenticated:
            return False
        seller_id = getattr(obj, "seller_id", None)
        return seller_id == user.id

