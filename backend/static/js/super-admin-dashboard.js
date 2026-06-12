(function () {
  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  const ENDPOINTS = {
    overview: "/api/v1/commerce/admin/overview/",
    sellerActivity: "/api/v1/commerce/admin/sellers-activity/",
    tenants: "/api/v1/commerce/admin/tenants/",
    tenantStatus: (tenantId) => `/api/v1/commerce/admin/tenants/${encodeURIComponent(tenantId)}/status/`,
    forceLogout: "/api/v1/commerce/admin/force-logout/",
    exportTenantsCsv: "/api/v1/commerce/admin/export/tenants.csv",
  };

  const state = {
    tenants: [],
    selectedTenantId: null,
  };

  const el = {
    refreshBtn: document.getElementById("refresh-dashboard"),
    errorBanner: document.getElementById("error-banner"),
    activeUsers: document.getElementById("kpi-active-users"),
    activeTenants: document.getElementById("kpi-active-tenants"),
    revenue: document.getElementById("kpi-revenue"),
    syncErrors: document.getElementById("kpi-sync-errors"),
    sellersTableBody: document.getElementById("sellers-table-body"),
    tenantsTableBody: document.getElementById("tenants-table-body"),
    selectedTenantLabel: document.getElementById("selected-tenant-label"),
    actionToggleTenantBtn: document.getElementById("action-toggle-tenant"),
    actionForceLogoutBtn: document.getElementById("action-force-logout"),
    actionExportReportBtn: document.getElementById("action-export-report"),
    tenantCoreDetails: document.getElementById("tenant-core-details"),
    tenantCompanyDetails: document.getElementById("tenant-company-details"),
    tenantUsersBody: document.getElementById("tenant-users-body"),
    tenantSalesBody: document.getElementById("tenant-sales-body"),
    systemStatus: document.getElementById("system-status"),
    activityFeed: document.getElementById("activity-feed"),
  };

  function formatMoney(value) {
    const safe = Number(value || 0);
    return `${safe.toLocaleString("fr-FR")} CDF`;
  }

  function showError(message) {
    el.errorBanner.textContent = message;
    el.errorBanner.classList.remove("hidden");
  }

  function clearError() {
    el.errorBanner.textContent = "";
    el.errorBanner.classList.add("hidden");
  }

  function getCookie(name) {
    const prefix = `${name}=`;
    const cookies = document.cookie ? document.cookie.split(";") : [];
    for (const item of cookies) {
      const value = item.trim();
      if (value.startsWith(prefix)) {
        return decodeURIComponent(value.slice(prefix.length));
      }
    }
    return "";
  }

  async function apiGet(url) {
    const response = await fetch(url, {
      method: "GET",
      headers: { Accept: "application/json" },
      credentials: "same-origin",
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} sur ${url}`);
    }
    return response.json();
  }

  async function apiPost(url, payload) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRFToken": getCookie("csrftoken"),
      },
      credentials: "same-origin",
      body: JSON.stringify(payload || {}),
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} sur ${url}`);
    }
    return response.json();
  }

  function getSelectedTenant() {
    if (!state.selectedTenantId) return null;
    return state.tenants.find((t) => t.tenant_id === state.selectedTenantId) || null;
  }

  function updateActionPanel() {
    const tenant = getSelectedTenant();
    if (!tenant) {
      el.selectedTenantLabel.textContent = "Tenant selectionne: aucun";
      el.actionToggleTenantBtn.textContent = "Suspendre un tenant";
      return;
    }
    const statusLabel = tenant.is_suspended ? "Suspendu" : "Actif";
    el.selectedTenantLabel.textContent = `Tenant selectionne: ${tenant.company_name || tenant.tenant_id} (${statusLabel})`;
    el.actionToggleTenantBtn.textContent = tenant.is_suspended ? "Réactiver ce tenant" : "Suspendre ce tenant";
  }

  function renderOverview(data) {
    el.activeUsers.textContent = (data.active_users_today ?? data.total_users ?? 0).toString();
    el.activeTenants.textContent = (data.active_tenants ?? data.total_tenants ?? 0).toString();
    el.revenue.textContent = formatMoney(data.total_revenue_today ?? data.total_revenue ?? 0);
    el.syncErrors.textContent = (data.sync_errors ?? 0).toString();

    const statusItems = [
      ["API", "En ligne"],
      ["Derniere synchronisation", new Date().toLocaleString("fr-FR")],
      ["Latence moyenne", `${data.avg_latency_ms ?? "--"} ms`],
      ["Erreurs 5xx (24h)", `${data.errors_5xx_24h ?? 0}`],
    ];
    el.systemStatus.innerHTML = statusItems
      .map(
        ([label, value]) =>
          `<li class="flex items-center justify-between rounded-tekisa bg-slate-50 px-3 py-2">
            <span class="text-slate-600">${label}</span>
            <span class="font-semibold text-slate-900">${value}</span>
          </li>`,
      )
      .join("");
  }

  function renderSellers(rows) {
    if (!Array.isArray(rows) || rows.length === 0) {
      el.sellersTableBody.innerHTML =
        '<tr><td colspan="4" class="py-4 text-center text-slate-500">Aucune activité vendeur.</td></tr>';
      return;
    }

    el.sellersTableBody.innerHTML = rows
      .map((row) => {
        const name = row.seller_name || row.username || "Inconnu";
        const sales = Number(row.sales_count || row.sales || 0);
        const revenue = Number(row.revenue || row.total_revenue || 0);
        const avgTicket = sales > 0 ? revenue / sales : 0;
        return `<tr>
          <td class="py-2 pr-3 font-medium text-slate-800">${escapeHtml(name)}</td>
          <td class="py-2 pr-3">${sales}</td>
          <td class="py-2 pr-3">${formatMoney(revenue)}</td>
          <td class="py-2 pr-3">${formatMoney(avgTicket)}</td>
        </tr>`;
      })
      .join("");
  }

  function renderTenants(rows) {
    if (!Array.isArray(rows) || rows.length === 0) {
      el.tenantsTableBody.innerHTML =
        '<tr><td colspan="7" class="py-4 text-center text-slate-500">Aucun tenant trouvé.</td></tr>';
      return;
    }
    el.tenantsTableBody.innerHTML = rows
      .map((tenant) => {
        const isSelected = tenant.tenant_id === state.selectedTenantId;
        const statusBadge = tenant.is_suspended
          ? '<span class="rounded-tekisa bg-rose-100 px-2 py-1 text-xs font-semibold text-rose-700">Suspendu</span>'
          : '<span class="rounded-tekisa bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-700">Actif</span>';
        return `<tr data-tenant-id="${tenant.tenant_id}" class="${
          isSelected ? "bg-cyan-50" : "hover:bg-slate-50"
        } cursor-pointer">
          <td class="py-2 pr-3 font-medium text-slate-800">
            <a href="/super-admin/tenant/${encodeURIComponent(
              tenant.tenant_id,
            )}/" class="text-tekisa hover:underline">
              ${escapeHtml(tenant.company_name || tenant.tenant_id)}
            </a>
          </td>
          <td class="py-2 pr-3">${escapeHtml(tenant.business_category || "-")}</td>
          <td class="py-2 pr-3">${statusBadge}</td>
          <td class="py-2 pr-3">${tenant.users_count || 0}</td>
          <td class="py-2 pr-3">${tenant.sales_count || 0}</td>
          <td class="py-2 pr-3">${formatMoney(tenant.revenue_total || 0)}</td>
          <td class="py-2 pr-3">${tenant.last_sale_at ? new Date(tenant.last_sale_at).toLocaleString("fr-FR") : "-"}</td>
        </tr>`;
      })
      .join("");
  }

  function detailChip(label, value) {
    return `<div class="rounded-tekisa border border-slate-200 bg-slate-50 px-3 py-2">
      <p class="text-xs uppercase tracking-wide text-slate-500">${escapeHtml(label)}</p>
      <p class="font-semibold text-slate-800">${escapeHtml(value || "-")}</p>
    </div>`;
  }

  function renderTenantDetail(data) {
    const tenant = data.tenant || {};
    const kpis = data.kpis || {};

    el.tenantCoreDetails.innerHTML = `
      <div class="flex items-center justify-between"><dt class="text-slate-500">Tenant ID</dt><dd class="font-semibold">${escapeHtml(tenant.tenant_id || "-")}</dd></div>
      <div class="flex items-center justify-between"><dt class="text-slate-500">Entreprise</dt><dd class="font-semibold">${escapeHtml(tenant.company_name || "-")}</dd></div>
      <div class="flex items-center justify-between"><dt class="text-slate-500">Categorie</dt><dd class="font-semibold">${escapeHtml(tenant.business_category || "-")}</dd></div>
      <div class="flex items-center justify-between"><dt class="text-slate-500">CA Total</dt><dd class="font-semibold">${formatMoney(kpis.revenue_total || 0)}</dd></div>
      <div class="flex items-center justify-between"><dt class="text-slate-500">Ventes</dt><dd class="font-semibold">${kpis.sales_count || 0}</dd></div>
      <div class="flex items-center justify-between"><dt class="text-slate-500">Ticket moyen</dt><dd class="font-semibold">${formatMoney(kpis.average_ticket || 0)}</dd></div>
    `;

    el.tenantCompanyDetails.innerHTML = [
      detailChip("Raison sociale", tenant.company_name),
      detailChip("Nom commercial", tenant.company_trade_name),
      detailChip("Forme legale", tenant.legal_form),
      detailChip("RCCM", tenant.rccm),
      detailChip("IDNAT", tenant.idnat),
      detailChip("NIF", tenant.nif),
      detailChip("Telephone", tenant.company_phone),
      detailChip("Email", tenant.company_email),
      detailChip("Pays", tenant.company_country),
      detailChip("Province", tenant.company_province),
      detailChip("Ville", tenant.company_city),
      detailChip("Commune", tenant.company_commune),
      detailChip("Quartier", tenant.company_quarter),
      detailChip("Avenue", tenant.company_avenue),
      detailChip("Numero", tenant.company_number),
      detailChip("Date creation", tenant.created_at ? new Date(tenant.created_at).toLocaleString("fr-FR") : "-"),
    ].join("");

    const users = Array.isArray(data.users) ? data.users : [];
    el.tenantUsersBody.innerHTML =
      users.length === 0
        ? '<tr><td colspan="6" class="py-4 text-center text-slate-500">Aucun utilisateur.</td></tr>'
        : users
            .map(
              (u) => `<tr>
              <td class="py-2 pr-3 font-medium">${u.username || "-"}</td>
              <td class="py-2 pr-3">${u.role || "-"}</td>
              <td class="py-2 pr-3">${u.phone || "-"}</td>
              <td class="py-2 pr-3">${u.email || "-"}</td>
              <td class="py-2 pr-3">${u.last_login ? new Date(u.last_login).toLocaleString("fr-FR") : "-"}</td>
              <td class="py-2 pr-3">${u.is_active ? "Oui" : "Non"}</td>
            </tr>`,
            )
            .join("");

    const sales = Array.isArray(data.recent_sales) ? data.recent_sales : [];
    el.tenantSalesBody.innerHTML =
      sales.length === 0
        ? '<tr><td colspan="6" class="py-4 text-center text-slate-500">Aucune vente.</td></tr>'
        : sales
            .map(
              (s) => `<tr>
              <td class="py-2 pr-3">${s.created_at ? new Date(s.created_at).toLocaleString("fr-FR") : "-"}</td>
              <td class="py-2 pr-3">${s.seller_username || "-"}</td>
              <td class="py-2 pr-3">${s.customer_name || "-"}</td>
              <td class="py-2 pr-3">${s.payment_method || "-"}</td>
              <td class="py-2 pr-3">${formatMoney(s.total || 0)}</td>
              <td class="py-2 pr-3">${s.status || "-"}</td>
            </tr>`,
            )
            .join("");
  }

  function renderActivityFeed(overview, sellers) {
    const now = new Date().toLocaleString("fr-FR");
    const feed = [
      {
        title: "Dashboard actualise",
        detail: `Chargement termine a ${now}.`,
      },
      {
        title: "Revenu du jour",
        detail: `Le revenu global actuel est ${formatMoney(overview.total_revenue_today ?? overview.total_revenue ?? 0)}.`,
      },
      {
        title: "Top vendeur",
        detail: sellers[0]
          ? `${sellers[0].seller_name || sellers[0].username || "Inconnu"} domine l'activité actuelle.`
          : "Aucune donnée vendeur disponible.",
      },
    ];

    el.activityFeed.innerHTML = feed
      .map(
        (item) => `<div class="rounded-tekisa border border-slate-200 bg-slate-50 px-3 py-2">
          <p class="text-sm font-semibold text-slate-800">${item.title}</p>
          <p class="text-xs text-slate-600">${item.detail}</p>
        </div>`,
      )
      .join("");
  }

  async function loadTenantDetail(tenantId) {
    const data = await apiGet(`${ENDPOINTS.tenants}${encodeURIComponent(tenantId)}/`);
    renderTenantDetail(data || {});
  }

  function bindTenantRowClick() {
    el.tenantsTableBody.querySelectorAll("tr[data-tenant-id]").forEach((row) => {
      row.addEventListener("click", async (event) => {
        if (event && event.target && event.target.closest("a")) {
          return;
        }
        const tenantId = row.getAttribute("data-tenant-id");
        if (!tenantId) return;
        state.selectedTenantId = tenantId;
        renderTenants(state.tenants);
        updateActionPanel();
        try {
          await loadTenantDetail(tenantId);
        } catch (error) {
          showError(`Impossible de charger le detail du tenant ${tenantId}: ${error.message}`);
        }
      });
    });
  }

  async function refreshDashboard() {
    try {
      clearError();
      const [overviewData, sellerActivityData, tenantsData] = await Promise.all([
        apiGet(ENDPOINTS.overview),
        apiGet(ENDPOINTS.sellerActivity),
        apiGet(ENDPOINTS.tenants),
      ]);
      const sellers = Array.isArray(sellerActivityData)
        ? sellerActivityData
        : sellerActivityData.results || [];
      const tenants = Array.isArray(tenantsData) ? tenantsData : tenantsData.results || [];
      state.tenants = tenants;
      if (!state.selectedTenantId && tenants[0]) {
        state.selectedTenantId = tenants[0].tenant_id;
      }
      renderOverview(overviewData || {});
      renderSellers(sellers);
      renderTenants(tenants);
      updateActionPanel();
      renderActivityFeed(overviewData || {}, sellers);
      bindTenantRowClick();
      if (state.selectedTenantId) {
        await loadTenantDetail(state.selectedTenantId);
      }
    } catch (error) {
      if (String(error.message || "").includes("HTTP 401")) {
        showError("Session expirée. Reconnecte-toi sur /admin/login/ puis recharge cette page.");
        return;
      }
      showError(`Chargement impossible: ${error.message}`);
    }
  }

  function bindEvents() {
    // Nettoyage de l'ancien mode JWT dans le navigateur.
    localStorage.removeItem("tekisa_superadmin_token");
    el.refreshBtn.addEventListener("click", refreshDashboard);
    el.actionToggleTenantBtn.addEventListener("click", async () => {
      const tenant = getSelectedTenant();
      if (!tenant) {
        showError("Selectionne d'abord un tenant.");
        return;
      }
      const targetActive = !!tenant.is_suspended;
      const actionLabel = targetActive ? "réactiver" : "suspendre";
      if (!confirm(`Confirmer: ${actionLabel} le tenant "${tenant.company_name || tenant.tenant_id}" ?`)) {
        return;
      }
      try {
        clearError();
        await apiPost(ENDPOINTS.tenantStatus(tenant.tenant_id), { active: targetActive });
        await refreshDashboard();
      } catch (error) {
        showError(`Action tenant impossible: ${error.message}`);
      }
    });

    el.actionForceLogoutBtn.addEventListener("click", async () => {
      if (!confirm("Confirmer la révocation globale des sessions utilisateur ?")) {
        return;
      }
      try {
        clearError();
        const result = await apiPost(ENDPOINTS.forceLogout, {});
        showError(`Logout global exécuté: ${result.sessions_deleted || 0} session(s) supprimée(s).`);
      } catch (error) {
        showError(`Force logout impossible: ${error.message}`);
      }
    });

    el.actionExportReportBtn.addEventListener("click", () => {
      window.open(ENDPOINTS.exportTenantsCsv, "_blank");
    });
  }

  bindEvents();
  refreshDashboard();
})();
