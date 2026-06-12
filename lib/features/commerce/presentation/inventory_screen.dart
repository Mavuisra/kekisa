library;

import 'package:flutter/material.dart';

import '../../../core/business/business_category_profile.dart';
import '../../../core/config/env_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/commerce_remote_datasource.dart';
import '../../../core/utils/file_export_helper.dart';
import '../../../data/models/commerce_models.dart';
import '../../auth/data/django_auth_service.dart';
import '../../auth/presentation/auth_router.dart';
import '../../settings/presentation/commerce_settings_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _authLocal = AuthLocalDataSource();
  BusinessCategoryProfile _profile = BusinessCategoryProfiles.boutique;
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<CommerceProductModel> _products = [];
  List<StockOverviewItemModel> _items = [];
  List<StockMovementTraceModel> _movements = [];
  bool _loadingMovements = false;
  int? _historyProductId;
  DateTime? _historyDate;
  final _historyUserController = TextEditingController();
  String get _itemSingularLabel {
    return _profile.itemLabelSingular;
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CommerceSettingsScreen()));
  }

  Future<void> _logout() async {
    await djangoAuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthRouter()),
      (_) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    final user = _authLocal.getUser();
    _profile = BusinessCategoryProfiles.fromKey(user?.businessCategory);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _historyUserController.dispose();
    super.dispose();
  }

  List<StockOverviewItemModel> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.sku.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<CommerceRemoteDataSource?> _source() async {
    final token = await _authLocal.getAccessToken();
    if (token == null || token.isEmpty) return null;
    final client = DioClient(
      baseUrl: EnvConfig.apiBaseUrl,
      accessToken: token,
      getRefreshToken: () => _authLocal.getRefreshToken(),
      saveAccessToken: (t) => _authLocal.setAccessToken(t),
    );
    return CommerceRemoteDataSource(client);
  }

  Future<void> _exportStock() async {
    final source = await _source();
    if (source == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connexion requise pour exporter.')),
      );
      return;
    }
    try {
      final bytes = await source.downloadStockExport();
      await FileExportHelper.shareBytes(
        bytes: bytes,
        filename: 'tekisa-stock.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final source = await _source();
    if (source == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expirée.';
      });
      return;
    }
    try {
      final products = await source.getProducts();
      final data = await source.getStockOverview();
      final movements = await source.getStockMovements(
        productId: _historyProductId,
        date: _historyDate != null ? _toApiDate(_historyDate!) : null,
        addedBy: _historyUserController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.isActive).toList();
        _items = data;
        _movements = movements;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openCreateProductSheet() async {
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    final thresholdCtrl = TextEditingController(text: '5');
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _profile.createItemLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nom du $_itemSingularLabel',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: skuCtrl,
                      decoration: InputDecoration(
                        labelText: _profile.key == 'restaurant'
                            ? 'Reference menu / Code'
                            : _profile.key == 'pharmacie'
                            ? 'Code CIP / SKU'
                            : _profile.key == 'salon_coiffure'
                            ? 'Code prestation / SKU'
                            : 'SKU / Code',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _profile.key == 'restaurant'
                            ? 'Prix de vente (CDF)'
                            : _profile.key == 'pharmacie'
                            ? 'Prix public (CDF)'
                            : _profile.key == 'salon_coiffure'
                            ? 'Tarif prestation (CDF)'
                            : 'Prix unitaire (CDF)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Coût d\'achat (CDF) - optionnel',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stock initial',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: thresholdCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seuil alerte',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final sku = skuCtrl.text.trim();
                              final price = double.tryParse(
                                priceCtrl.text.trim(),
                              );
                              final cost = double.tryParse(
                                costCtrl.text.trim(),
                              );
                              final stock = int.tryParse(stockCtrl.text.trim());
                              final threshold = int.tryParse(
                                thresholdCtrl.text.trim(),
                              );

                              if (name.isEmpty ||
                                  sku.isEmpty ||
                                  price == null ||
                                  stock == null ||
                                  threshold == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Renseignez correctement tous les champs.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final source = await _source();
                              if (source == null) return;

                              setModalState(() => saving = true);
                              try {
                                await source.createProduct(
                                  name: name,
                                  sku: sku,
                                  unitPrice: price,
                                  costPrice: cost,
                                  stockQuantity: stock,
                                  reorderThreshold: threshold,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                if (!mounted) return;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${_itemSingularLabel[0].toUpperCase()}${_itemSingularLabel.substring(1)} cree.',
                                    ),
                                  ),
                                );
                                await _load();
                              } catch (e) {
                                if (!context.mounted) return;
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  CommerceProductModel? _productById(int id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _openEditProductSheet(StockOverviewItemModel item) async {
    final existing = _productById(item.id);
    final nameCtrl = TextEditingController(text: existing?.name ?? item.name);
    final skuCtrl = TextEditingController(text: existing?.sku ?? item.sku);
    final priceCtrl = TextEditingController(
      text: (existing?.unitPrice ?? 0).toStringAsFixed(0),
    );
    final costCtrl = TextEditingController(
      text: (existing?.costPrice ?? 0).toStringAsFixed(0),
    );
    final stockCtrl = TextEditingController(
      text: '${existing?.stockQuantity ?? item.stockQuantity}',
    );
    final thresholdCtrl = TextEditingController(
      text: '${existing?.reorderThreshold ?? item.reorderThreshold}',
    );
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Modifier le produit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: skuCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SKU / Code',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Prix unitaire (CDF)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Coût d\'achat (CDF)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stock',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: thresholdCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Seuil alerte',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final sku = skuCtrl.text.trim();
                              final price = double.tryParse(
                                priceCtrl.text.trim(),
                              );
                              final cost = double.tryParse(
                                costCtrl.text.trim(),
                              );
                              final stock = int.tryParse(stockCtrl.text.trim());
                              final threshold = int.tryParse(
                                thresholdCtrl.text.trim(),
                              );
                              if (name.isEmpty ||
                                  sku.isEmpty ||
                                  price == null ||
                                  stock == null ||
                                  threshold == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Renseignez correctement les champs obligatoires.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final source = await _source();
                              if (source == null) return;
                              setModalState(() => saving = true);
                              try {
                                await source.updateProduct(
                                  productId: item.id,
                                  name: name,
                                  sku: sku,
                                  unitPrice: price,
                                  costPrice: cost,
                                  stockQuantity: stock,
                                  reorderThreshold: threshold,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                if (!mounted) return;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Produit modifie avec succes.',
                                    ),
                                  ),
                                );
                                await _load();
                              } catch (e) {
                                if (!context.mounted) return;
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_outlined),
                      label: Text(saving ? 'Enregistrement...' : 'Enregistrer'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteProduct(StockOverviewItemModel item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le produit'),
        content: Text(
          'Confirmez-vous la suppression de "${item.name}" ? Cette action est irreversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final source = await _source();
    if (source == null) return;
    try {
      await source.deleteProduct(productId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit supprime avec succes.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openAddStockSheet(StockOverviewItemModel item) async {
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Reassort manuel');
    bool saving = false;
    final rootMessenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ajouter du stock: ${item.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantite a ajouter',
                        hintText: 'ex: 20',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motif (trace)',
                        hintText: 'ex: reception fournisseur',
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final qty = int.tryParse(qtyCtrl.text.trim());
                              if (qty == null || qty <= 0) {
                                rootMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Saisissez une quantite valide (>0).',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final source = await _source();
                              if (source == null) return;
                              setModalState(() => saving = true);
                              try {
                                await source.addStock(
                                  productId: item.id,
                                  quantity: qty,
                                  reason: reasonCtrl.text.trim(),
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                await _load();
                                rootMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Stock ajoute: +$qty sur ${item.name}.',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                setModalState(() => saving = false);
                                rootMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(saving ? 'Ajout...' : 'Ajouter la quantite'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadMovements() async {
    final source = await _source();
    if (source == null) return;
    setState(() => _loadingMovements = true);
    try {
      final movements = await source.getStockMovements(
        productId: _historyProductId,
        date: _historyDate != null ? _toApiDate(_historyDate!) : null,
        addedBy: _historyUserController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
        _loadingMovements = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMovements = false);
    }
  }

  Future<void> _pickHistoryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _historyDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _historyDate = picked);
    await _loadMovements();
  }

  String _toApiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final criticalCount = _items.where((e) => e.isCritical).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile.inventoryTitle),
        actions: [
          IconButton(
            onPressed: _exportStock,
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Exporter Excel',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Parametres',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Deconnexion',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surface : _profile.softColor,
                borderRadius: BorderRadius.circular(12),
                border: isDark
                    ? Border.all(color: theme.dividerColor)
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _profile.accentColor.withValues(
                      alpha: 0.16,
                    ),
                    child: Icon(
                      _profile.heroIcon,
                      size: 17,
                      color: _profile.accentColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _profile.subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surface
                    : _profile.softColor.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: isDark
                    ? Border.all(color: theme.dividerColor)
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: _profile.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$criticalCount ${_profile.itemLabelPlural} proches de la rupture. Reassort conseille.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? Colors.white : _profile.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Filtrer par ${_profile.itemLabelPlural}',
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_filtered.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aucun ${_profile.itemLabelPlural} pour le moment.'),
                ],
              )
            else
              ..._filtered.map(
                (e) => _StockRow(
                  item: e,
                  profile: _profile,
                  onAddStock: () => _openAddStockSheet(e),
                  onEdit: () => _openEditProductSheet(e),
                  onDelete: () => _deleteProduct(e),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openCreateProductSheet,
              icon: const Icon(Icons.add_box_outlined),
              label: Text(
                _profile.key == 'restaurant'
                    ? 'Ajouter un plat'
                    : _profile.key == 'pharmacie'
                    ? 'Ajouter un medicament'
                    : _profile.key == 'salon_coiffure'
                    ? 'Ajouter une prestation'
                    : 'Ajouter un produit',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Historique des mouvements',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _historyProductId,
                    decoration: const InputDecoration(
                      labelText: 'Produit',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Tous les produits'),
                      ),
                      ..._items.map(
                        (p) => DropdownMenuItem<int?>(
                          value: p.id,
                          child: Text(p.name),
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      setState(() => _historyProductId = value);
                      await _loadMovements();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickHistoryDate,
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(
                    _historyDate == null ? 'Date' : _formatDate(_historyDate!),
                  ),
                ),
                if (_historyDate != null)
                  IconButton(
                    onPressed: () async {
                      setState(() => _historyDate = null);
                      await _loadMovements();
                    },
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Effacer date',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _historyUserController,
                    decoration: const InputDecoration(
                      labelText: 'Ajoute par (utilisateur)',
                      hintText: 'ex: vendeur1',
                      prefixIcon: Icon(Icons.person_search_rounded),
                    ),
                    onSubmitted: (_) => _loadMovements(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loadMovements,
                  child: const Text('Filtrer'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingMovements)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_movements.isEmpty)
              const Text('Aucun mouvement trouve pour ces filtres.')
            else
              ..._movements
                  .take(50)
                  .map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: isDark
                            ? Border.all(color: theme.dividerColor)
                            : Border.all(color: Colors.transparent),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text('${m.productName} (${m.sku})'),
                        subtitle: Text(
                          '${m.movementType.toUpperCase()} • ${m.reason.isNotEmpty ? m.reason : 'n/a'}\n'
                          'Par ${m.addedBy} • ${_friendlyDateTime(m.createdAt)}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${m.quantity > 0 ? '+' : ''}${m.quantity}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: m.quantity >= 0
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB91C1C),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Solde: ${m.balanceAfter}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateProductSheet,
        icon: const Icon(Icons.add_box_outlined),
        label: Text(
          _profile.key == 'restaurant'
              ? 'Ajouter un plat'
              : _profile.key == 'pharmacie'
              ? 'Ajouter un médicament'
              : _profile.key == 'salon_coiffure'
              ? 'Ajouter une prestation'
              : 'Ajouter un produit',
        ),
      ),
    );
  }

  String _friendlyDateTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year} $hh:$mn';
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.item,
    required this.profile,
    required this.onAddStock,
    required this.onEdit,
    required this.onDelete,
  });

  final StockOverviewItemModel item;
  final BusinessCategoryProfile profile;
  final VoidCallback onAddStock;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final left = item.stockQuantity;
    final threshold = item.reorderThreshold;
    final isCritical = left <= threshold;
    final velocity = item.velocity == 'critical' ? 'Critique' : 'Stable';
    final lastAddedBy = item.lastStockAddBy;
    final lastAddedQty = item.lastStockAddQty;
    final lastAddedAt = _formatLast(item.lastStockAddAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(color: theme.dividerColor)
            : Border.all(color: Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.name, style: theme.textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCritical
                      ? const Color(0xFFFFE8E8)
                      : const Color(0xFFEAFBF4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  velocity,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCritical
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'edit', child: Text('Modifier')),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('SKU: ${item.sku}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (left / (threshold * 2)).clamp(0, 1).toDouble(),
            backgroundColor: const Color(0xFFF3F4F6),
            color: isCritical ? const Color(0xFFEF4444) : profile.accentColor,
            minHeight: 7,
          ),
          const SizedBox(height: 6),
          Text(
            'Disponible: $left  •  Seuil: $threshold',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            lastAddedBy == null
                ? 'Aucune trace d\'ajout pour le moment.'
                : 'Dernier ajout: +$lastAddedQty par $lastAddedBy ($lastAddedAt)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onAddStock,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter stock'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLast(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${local.year} $hh:$mn';
  }
}
