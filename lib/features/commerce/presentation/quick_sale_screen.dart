library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/business/business_category_profile.dart';
import '../../../core/config/env_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/commerce_remote_datasource.dart';
import '../../../data/models/commerce_models.dart';
import '../../../data/models/user_model.dart';
import '../../auth/data/django_auth_service.dart';
import '../../auth/presentation/auth_router.dart';
import '../../settings/presentation/commerce_settings_screen.dart';
import 'ai_sale_screen.dart';
import 'receipt_verification_screen.dart';

class QuickSaleScreen extends StatefulWidget {
  const QuickSaleScreen({super.key});

  @override
  State<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends State<QuickSaleScreen> {
  final _authLocal = AuthLocalDataSource();
  BusinessCategoryProfile _profile = BusinessCategoryProfiles.boutique;
  final _searchController = TextEditingController();
  final _customerController = TextEditingController();
  final List<_CartItem> _items = [];
  List<CommerceProductModel> _products = [];
  List<CommerceCustomerModel> _customers = [];
  List<QuickSaleHistoryItemModel> _salesHistory = [];
  int? _selectedCustomerId;
  DateTime _salesFilterDate = DateTime.now();
  String _paymentMethod = 'cash';
  bool _loading = true;
  bool _submitting = false;
  bool _loadingHistory = false;
  String? _error;
  bool get _isPharmacy => _profile.key == 'pharmacie';

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

  int get _subtotal => _items.fold(
    0,
    (sum, item) => sum + item.product.unitPrice.toInt() * item.qty,
  );
  int get _discount => (_subtotal * 0.05).round();
  int get _total => _subtotal - _discount;
  String get _query => _searchController.text.trim().toLowerCase();

  List<CommerceProductModel> get _filteredProducts {
    if (_query.isEmpty) return _products;
    return _products.where((p) {
      return p.name.toLowerCase().contains(_query) ||
          p.sku.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final user = _authLocal.getUser();
    _profile = BusinessCategoryProfiles.fromKey(user?.businessCategory);
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerController.dispose();
    super.dispose();
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

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final source = await _source();
    if (source == null) {
      setState(() {
        _error = 'Session expirée.';
        _loading = false;
      });
      return;
    }
    try {
      final products = await source.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.isActive).toList();
        _loading = false;
      });
      await _loadCustomers();
      await _loadSalesHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickSalesDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _salesFilterDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _salesFilterDate = picked);
    await _loadSalesHistory();
  }

  Future<void> _loadSalesHistory() async {
    final source = await _source();
    if (source == null) return;
    setState(() => _loadingHistory = true);
    try {
      final dateStr = _salesFilterDate.toIso8601String().substring(0, 10);
      final sales = await source.getSalesList(date: dateStr);
      if (!mounted) return;
      setState(() {
        _salesHistory = sales;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  void _addProduct(CommerceProductModel product) {
    final index = _items.indexWhere((it) => it.product.id == product.id);
    if (index >= 0) {
      setState(() => _items[index].qty += 1);
    } else {
      setState(() => _items.add(_CartItem(product: product, qty: 1)));
    }
  }

  Future<void> _loadCustomers() async {
    final source = await _source();
    if (source == null) return;
    try {
      final customers = await source.getCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
      });
    } catch (_) {
      // Ne bloque pas la vente si la récupération client échoue.
    }
  }

  Future<void> _openCreateCustomerSheet() async {
    final rootMessenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String segment = 'regular';
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
                      'Creer un ${_profile.customerNounSingular}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone (optionnel)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optionnel)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: segment,
                      decoration: const InputDecoration(labelText: 'Segment'),
                      items: const [
                        DropdownMenuItem(
                          value: 'regular',
                          child: Text('Régulier'),
                        ),
                        DropdownMenuItem(value: 'VIP', child: Text('VIP')),
                        DropdownMenuItem(
                          value: 'À relancer',
                          child: Text('À relancer'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) =>
                                setModalState(() => segment = v ?? 'regular'),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                rootMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Le nom du ${_profile.customerNounSingular} est requis.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final source = await _source();
                              if (source == null) return;
                              setModalState(() => saving = true);
                              try {
                                final created = await source.createCustomer(
                                  fullName: name,
                                  phone: phoneCtrl.text.trim(),
                                  email: emailCtrl.text.trim(),
                                  segment: segment,
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                if (!mounted) return;
                                await _loadCustomers();
                                setState(() {
                                  _selectedCustomerId = created.id;
                                  _customerController.text = created.fullName;
                                });
                                rootMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${_profile.customerNounSingular[0].toUpperCase()}${_profile.customerNounSingular.substring(1)} cree et selectionne.',
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
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Creer le ${_profile.customerNounSingular}'),
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

  Future<void> _submitSale() async {
    if (_items.isEmpty) return;
    setState(() => _submitting = true);
    final source = await _source();
    if (source == null) {
      setState(() => _submitting = false);
      return;
    }
    try {
      final saleCustomerName = _customerController.text.trim();
      final receipt = await source.createQuickSale(
        items: _items
            .map((e) => CartItemInput(productId: e.product.id, quantity: e.qty))
            .toList(),
        paymentMethod: _paymentMethod,
        discountRate: 5,
        customerName: saleCustomerName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vente enregistree avec succes.')));
      setState(() {
        _items.clear();
        _searchController.clear();
        _selectedCustomerId = null;
        _customerController.clear();
      });
      await _loadProducts();
      await _loadSalesHistory();
      if (!mounted) return;
      await _openReceiptDialog(receipt, customerName: saleCustomerName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openReceiptDialog(
    QuickSaleReceiptModel receipt, {
    required String customerName,
  }) async {
    final date =
        DateTime.tryParse(receipt.createdAt)?.toLocal() ?? DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    final user = _authLocal.getUser();
    final companyName = (user?.companyName ?? '').trim().isNotEmpty
        ? (user?.companyName ?? '').trim()
        : (user?.displayName ?? user?.username ?? 'TEKISA');
    final reference = _receiptReference(receipt, date);
    final legalLines = _companyLegalLines(user);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Recu'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    companyName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (legalLines.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...legalLines.map(
                      (line) => Text(
                        line,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    'Recu #${receipt.id}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Reference: $reference',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(formatter.format(date)),
                  const SizedBox(height: 8),
                  const Divider(),
                  ...receipt.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${it.productName} x${it.quantity}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${it.lineTotal.toStringAsFixed(0)} CDF'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  _ReceiptLine(
                    label: 'Sous-total',
                    value: '${receipt.subtotal.toStringAsFixed(0)} CDF',
                  ),
                  _ReceiptLine(
                    label: 'Remise',
                    value: '-${receipt.discountAmount.toStringAsFixed(0)} CDF',
                  ),
                  _ReceiptLine(
                    label: 'Total',
                    value: '${receipt.total.toStringAsFixed(0)} CDF',
                    strong: true,
                  ),
                  const SizedBox(height: 6),
                  Text('Paiement: ${_paymentLabel(receipt.paymentMethod)}'),
                  Text(
                    'Client: ${customerName.isEmpty ? (_isPharmacy ? 'Patient libre' : 'Client libre') : customerName}',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await _printPosReceipt(receipt, customerName: customerName);
              },
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimer le recu'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _printPosReceipt(
    QuickSaleReceiptModel receipt, {
    required String customerName,
  }) async {
    try {
      await Printing.layoutPdf(
        name: 'ticket-pos-${receipt.id}',
        onLayout: (format) => _buildPosPdf(receipt, customerName: customerName),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impression impossible: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<Uint8List> _buildPosPdf(
    QuickSaleReceiptModel receipt, {
    required String customerName,
  }) async {
    final user = _authLocal.getUser();
    final doc = pw.Document();
    final created =
        DateTime.tryParse(receipt.createdAt)?.toLocal() ?? DateTime.now();
    final format = DateFormat('dd/MM/yyyy HH:mm');
    final companyName = (user?.companyName ?? '').trim().isNotEmpty
        ? (user?.companyName ?? '').trim()
        : (user?.displayName ?? user?.username ?? 'TEKISA');
    final reference = _receiptReference(receipt, created);
    final displayCustomer = customerName.trim().isEmpty
        ? (_isPharmacy ? 'Patient libre' : 'Client libre')
        : customerName.trim();
    final legalLines = _companyLegalLines(user);
    final qrPayload =
        'REF:$reference;RECU:${receipt.id};DATE:${format.format(created)};TOTAL:${receipt.total.toStringAsFixed(0)};PAY:${_paymentLabel(receipt.paymentMethod)}';

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          220 * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  companyName.toUpperCase(),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (legalLines.isNotEmpty)
                ...legalLines.map(
                  (line) => pw.Center(
                    child: pw.Text(
                      line,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ),
              pw.Center(
                child: pw.Text('RECU', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Recu #${receipt.id}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Reference: $reference',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                format.format(created),
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Client: $displayCustomer',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'Paiement: ${_paymentLabel(receipt.paymentMethod)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Divider(),
              ...receipt.items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item.productName} x${item.quantity}',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        item.lineTotal.toStringAsFixed(0),
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              _pdfTotalRow('Sous-total', receipt.subtotal),
              _pdfTotalRow('Remise', -receipt.discountAmount),
              _pdfTotalRow('TOTAL', receipt.total, strong: true),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrPayload,
                  width: 70,
                  height: 70,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Merci pour votre achat',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  'Recu simplifie - usage comptable interne',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfTotalRow(String label, double value, {bool strong = false}) {
    final textStyle = pw.TextStyle(
      fontSize: strong ? 10 : 9,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: textStyle),
        pw.Text('${value.toStringAsFixed(0)} CDF', style: textStyle),
      ],
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'mobile_money':
        return 'Mobile Money';
      case 'card':
        return 'Carte';
      default:
        return 'Cash';
    }
  }

  String _receiptReference(QuickSaleReceiptModel receipt, DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return 'REC-$y$m$d-${receipt.id.toString().padLeft(6, '0')}';
  }

  List<String> _companyLegalLines(UserModel? user) {
    if (user == null) return const [];
    final lines = <String>[];

    final legal = <String>[];
    final rccm = (user.rccm ?? '').trim();
    final idnat = (user.idnat ?? '').trim();
    final nif = (user.nif ?? '').trim();
    if (rccm.isNotEmpty) legal.add('RCCM: $rccm');
    if (idnat.isNotEmpty) legal.add('ID.NAT: $idnat');
    if (nif.isNotEmpty) legal.add('NIF: $nif');
    if (legal.isNotEmpty) {
      lines.add(legal.join(' | '));
    }
    return lines;
  }

  String _saleStatusLabel(String status) {
    switch (status) {
      case 'cancelled':
      case 'canceled':
        return 'Annulee';
      case 'queued_offline':
        return 'En attente sync';
      default:
        return 'Validee';
    }
  }

  Color _saleStatusColor(String status) {
    switch (status) {
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFB91C1C);
      case 'queued_offline':
        return const Color(0xFF92400E);
      default:
        return const Color(0xFF065F46);
    }
  }

  String _saleCustomerName({
    required QuickSaleHistoryItemModel sale,
    QuickSaleReceiptModel? receipt,
  }) {
    final name = (receipt?.customerName ?? sale.customerName).trim();
    if (name.isNotEmpty) return name;
    return _isPharmacy ? 'Patient libre' : 'Client libre';
  }

  Future<String?> _askCancellationReason() async {
    final reasonCtrl = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Annuler la vente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Motif d\'annulation',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton(
              onPressed: () {
                final value = reasonCtrl.text.trim();
                if (value.isEmpty) {
                  setModalState(() => errorText = 'Le motif est obligatoire.');
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
    return reason;
  }

  Future<void> _cancelSaleWithReason({
    required QuickSaleHistoryItemModel sale,
    required String reason,
  }) async {
    final source = await _source();
    if (source == null) return;
    try {
      await source.cancelSale(
        saleId: sale.id,
        reason: reason,
        saleDate: sale.date,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vente annulee avec succes.')),
      );
      await _loadSalesHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openSaleDetails(QuickSaleHistoryItemModel sale) async {
    final source = await _source();
    if (source == null) return;
    try {
      final receipt = await source.getSaleReceipt(
        saleId: sale.id,
        summary: sale,
      );
      if (!mounted) return;
      final date =
          DateTime.tryParse(receipt.createdAt)?.toLocal() ?? DateTime.now();
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Details vente #${sale.id}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _saleStatusLabel(receipt.status),
                        style: TextStyle(
                          color: _saleStatusColor(receipt.status),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(formatter.format(date)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Client: ${_saleCustomerName(sale: sale, receipt: receipt)}',
                  ),
                  Text('Paiement: ${_paymentLabel(receipt.paymentMethod)}'),
                  if ((receipt.cancelReason ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Motif annulation: ${receipt.cancelReason}',
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(),
                  if (receipt.items.isEmpty)
                    const Text(
                      'Ligne articles indisponible pour cette vente en mode hors ligne.',
                    )
                  else
                    ...receipt.items.map(
                      (it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${it.productName} x${it.quantity}'),
                            ),
                            Text('${it.lineTotal.toStringAsFixed(0)} CDF'),
                          ],
                        ),
                      ),
                    ),
                  const Divider(),
                  _ReceiptLine(
                    label: 'Sous-total',
                    value: '${receipt.subtotal.toStringAsFixed(0)} CDF',
                  ),
                  _ReceiptLine(
                    label: 'Remise',
                    value: '-${receipt.discountAmount.toStringAsFixed(0)} CDF',
                  ),
                  _ReceiptLine(
                    label: 'Total',
                    value: '${receipt.total.toStringAsFixed(0)} CDF',
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _openReceiptDialog(
                  receipt,
                  customerName: _saleCustomerName(sale: sale, receipt: receipt),
                );
              },
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Regenerer facture'),
            ),
            if (receipt.status != 'cancelled' && receipt.status != 'canceled')
              OutlinedButton.icon(
                onPressed: () async {
                  final reason = await _askCancellationReason();
                  if (reason == null || reason.trim().isEmpty) return;
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  await _cancelSaleWithReason(sale: sale, reason: reason);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler vente'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile.quickSaleTitle),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AiSaleScreen()));
            },
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'Vendre avec IA',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReceiptVerificationScreen(),
                ),
              );
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Verifier un recu',
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
      body: ListView(
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
                  backgroundColor: _profile.accentColor.withValues(alpha: 0.16),
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
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _profile.searchItemHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: _filteredProducts.isEmpty
                    ? null
                    : () => _addProduct(_filteredProducts.first),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_filteredProducts.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _filteredProducts.take(6).map((p) {
                return ActionChip(
                  label: Text('${p.name} (${p.stockQuantity})'),
                  onPressed: p.stockQuantity > 0 ? () => _addProduct(p) : null,
                );
              }).toList(),
            ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFD4FF)),
            ),
            child: Text(
              'Panier en cours',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0B4FDC),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            Text(
              'Aucun article. Ajoutez des ${_profile.itemLabelPlural} depuis la recherche.',
            ),
          ..._items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return _CartLine(
              item: item,
              onMinus: () {
                if (item.qty <= 1) return;
                setState(() => item.qty -= 1);
              },
              onPlus: () => setState(() => item.qty += 1),
              onDelete: () => setState(() => _items.removeAt(i)),
            );
          }),
          const SizedBox(height: 12),
          _TotalCard(
            subtotal: _subtotal,
            discount: _discount,
            total: _total,
            profile: _profile,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Client / Patient',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  hint: Text('Choisir un ${_profile.customerNounSingular}'),
                  items: _customers
                      .map(
                        (c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCustomerId = value;
                      CommerceCustomerModel? selected;
                      for (final c in _customers) {
                        if (c.id == value) {
                          selected = c;
                          break;
                        }
                      }
                      _customerController.text = selected?.fullName ?? '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openCreateCustomerSheet,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text('Nouveau ${_profile.customerNounSingular}'),
              ),
            ],
          ),
          if (_selectedCustomerId == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customerController,
              decoration: InputDecoration(
                labelText:
                    'Ou saisir un ${_profile.customerNounSingular} (optionnel)',
                hintText: 'Nom',
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text('Paiement', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MethodChip(
                label: 'Cash',
                icon: Icons.payments_outlined,
                selected: _paymentMethod == 'cash',
                selectedBg: _profile.softColor,
                selectedBorder: _profile.accentColor,
                onTap: () => setState(() => _paymentMethod = 'cash'),
              ),
              _MethodChip(
                label: 'Mobile Money',
                icon: Icons.phone_android_rounded,
                selected: _paymentMethod == 'mobile_money',
                selectedBg: _profile.softColor,
                selectedBorder: _profile.accentColor,
                onTap: () => setState(() => _paymentMethod = 'mobile_money'),
              ),
              _MethodChip(
                label: 'Carte',
                icon: Icons.credit_card_rounded,
                selected: _paymentMethod == 'card',
                selectedBg: _profile.softColor,
                selectedBorder: _profile.accentColor,
                onTap: () => setState(() => _paymentMethod = 'card'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _items.isEmpty || _submitting ? null : _submitSale,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_rounded),
            label: Text(_submitting ? 'Validation...' : 'Valider et encaisser'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Liste des ventes',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickSalesDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  _salesFilterDate.toIso8601String().substring(0, 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingHistory)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_salesHistory.isEmpty)
            const Text('Aucune vente sur cette date.')
          else
            ..._salesHistory.map(
              (s) => Container(
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
                  onTap: () => _openSaleDetails(s),
                  title: Text(
                    'Vente #${s.id} • ${s.time}',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    '${s.customerName.isNotEmpty ? s.customerName : (_isPharmacy ? 'Patient libre' : 'Client libre')} • '
                    '${s.itemsCount} article(s) • ${s.paymentMethod} • ${_saleStatusLabel(s.status)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${s.total.toStringAsFixed(0)} CDF',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Sous-total ${s.subtotal.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartItem {
  _CartItem({required this.product, required this.qty});

  final CommerceProductModel product;
  int qty;
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.onMinus,
    required this.onPlus,
    required this.onDelete,
  });

  final _CartItem item;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(color: theme.dividerColor)
            : Border.all(color: Colors.transparent),
      ),
      child: ListTile(
        title: Text(item.product.name, style: theme.textTheme.titleSmall),
        subtitle: Text('${item.product.unitPrice.toStringAsFixed(0)} CDF'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('${item.qty}', style: theme.textTheme.titleSmall),
            IconButton(
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.profile,
  });

  final int subtotal;
  final int discount;
  final int total;
  final BusinessCategoryProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: profile.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _TotalRow(label: 'Sous-total', value: '$subtotal CDF'),
          const SizedBox(height: 6),
          _TotalRow(label: 'Remise auto (5%)', value: '-$discount CDF'),
          Divider(color: Theme.of(context).dividerColor, height: 18),
          _TotalRow(label: 'Total', value: '$total CDF', strong: true),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final color = strong ? Colors.white : Colors.white70;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedBg,
    required this.selectedBorder,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedBg;
  final Color selectedBorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? theme.colorScheme.surface : selectedBg)
              : (isDark ? theme.colorScheme.surface : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: isDark
              ? Border.all(
                  color: selected ? Colors.white70 : theme.dividerColor,
                )
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isDark ? Colors.white : null),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isDark ? Colors.white : null)),
          ],
        ),
      ),
    );
  }
}
