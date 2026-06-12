library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/env_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/offline/tenant_context.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/commerce_remote_datasource.dart';
import '../../../core/utils/file_export_helper.dart';
import '../../../data/models/commerce_models.dart';

class SalesJournalScreen extends StatefulWidget {
  const SalesJournalScreen({super.key});

  @override
  State<SalesJournalScreen> createState() => _SalesJournalScreenState();
}

class _SalesJournalScreenState extends State<SalesJournalScreen> {
  final _authLocal = AuthLocalDataSource();
  final _customerFilterCtrl = TextEditingController();
  final _productFilterCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _loadingReceipts = false;
  bool _showArchived = false;
  String? _error;

  List<QuickSaleHistoryItemModel> _sales = const [];
  final Map<int, QuickSaleReceiptModel> _receiptBySale = {};
  final Set<int> _archivedSaleIds = <int>{};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _customerFilterCtrl.dispose();
    _productFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadArchivedIds();
    await _loadSales();
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

  String _selectedDateApi() => _selectedDate.toIso8601String().substring(0, 10);

  String _archiveKey() {
    final tenantId = TenantContext.current()?.tenantId ?? 'default';
    return 'tekisa_sales_archived_${tenantId}_${_selectedDateApi()}';
  }

  Future<void> _loadArchivedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_archiveKey()) ?? const <String>[];
    final parsed = stored.map((e) => int.tryParse(e)).whereType<int>().toSet();
    if (!mounted) return;
    setState(() {
      _archivedSaleIds
        ..clear()
        ..addAll(parsed);
    });
  }

  Future<void> _saveArchivedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _archiveKey(),
      _archivedSaleIds.map((e) => '$e').toList(),
    );
  }

  Future<void> _loadSales() async {
    setState(() {
      _loading = true;
      _error = null;
      _receiptBySale.clear();
    });
    final source = await _source();
    if (source == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Session expirée. Reconnectez-vous.';
      });
      return;
    }
    try {
      final data = await source.getSalesList(date: _selectedDateApi());
      if (!mounted) return;
      setState(() {
        _sales = data;
        _loading = false;
      });
      await _loadReceiptsForProductFilterIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadArchivedIds();
    await _loadSales();
  }

  Future<void> _loadReceiptsForProductFilterIfNeeded() async {
    final query = _productFilterCtrl.text.trim().toLowerCase();
    if (query.isEmpty || _sales.isEmpty) return;
    final source = await _source();
    if (source == null) return;
    setState(() => _loadingReceipts = true);
    for (final sale in _sales) {
      if (_receiptBySale.containsKey(sale.id)) continue;
      try {
        final receipt = await source.getSaleReceipt(
          saleId: sale.id,
          summary: sale,
        );
        _receiptBySale[sale.id] = receipt;
      } catch (_) {
        // On ignore les erreurs ponctuelles de détail.
      }
    }
    if (!mounted) return;
    setState(() => _loadingReceipts = false);
  }

  bool _matchesProductFilter(QuickSaleHistoryItemModel sale) {
    final query = _productFilterCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final receipt = _receiptBySale[sale.id];
    if (receipt == null) return false;
    return receipt.items.any(
      (it) =>
          it.productName.toLowerCase().contains(query) ||
          '${it.productId}'.contains(query),
    );
  }

  List<QuickSaleHistoryItemModel> get _filteredSales {
    final customerQuery = _customerFilterCtrl.text.trim().toLowerCase();
    return _sales.where((sale) {
      final archived = _archivedSaleIds.contains(sale.id);
      if (!_showArchived && archived) return false;
      final customerOk =
          customerQuery.isEmpty ||
          sale.customerName.toLowerCase().contains(customerQuery);
      final productOk = _matchesProductFilter(sale);
      return customerOk && productOk;
    }).toList();
  }

  Future<void> _toggleArchive(QuickSaleHistoryItemModel sale) async {
    setState(() {
      if (_archivedSaleIds.contains(sale.id)) {
        _archivedSaleIds.remove(sale.id);
      } else {
        _archivedSaleIds.add(sale.id);
      }
    });
    await _saveArchivedIds();
  }

  String _currency(double value) => '${value.toStringAsFixed(0)} CDF';

  Future<Uint8List> _buildSalesPdf(List<QuickSaleHistoryItemModel> rows) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final date = DateFormat('dd/MM/yyyy HH:mm').format(now);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return [
            pw.Text(
              'TEKISA - Journal des ventes',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Date filtree: ${_selectedDateApi()}'),
            pw.Text('Genere le: $date'),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'ID',
                'Heure',
                'Client',
                'Produits',
                'Paiement',
                'Statut',
                'Total',
              ],
              data: rows
                  .map(
                    (s) => [
                      '${s.id}',
                      s.time,
                      s.customerName.isEmpty ? 'Client libre' : s.customerName,
                      '${s.itemsCount}',
                      s.paymentMethod,
                      s.status,
                      _currency(s.total),
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Total ventes: ${rows.length} | Montant cumule: ${_currency(rows.fold<double>(0, (sum, e) => sum + e.total))}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  Future<void> _exportExcel() async {
    final source = await _source();
    if (source == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connexion requise pour exporter.')),
      );
      return;
    }
    try {
      final bytes = await source.downloadSalesExport(date: _selectedDateApi());
      await FileExportHelper.shareBytes(
        bytes: bytes,
        filename: 'tekisa-ventes-${_selectedDateApi()}.xlsx',
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

  Future<void> _printFiltered() async {
    final rows = _filteredSales;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucune vente a imprimer.')));
      return;
    }
    await Printing.layoutPdf(
      name: 'tekisa-journal-ventes-${_selectedDateApi()}',
      onLayout: (_) => _buildSalesPdf(rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rows = _filteredSales;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal des ventes'),
        actions: [
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            tooltip: 'Choisir date',
          ),
          IconButton(
            onPressed: _exportExcel,
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'Exporter Excel',
          ),
          IconButton(
            onPressed: _printFiltered,
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer',
          ),
          IconButton(
            onPressed: _loadSales,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: isDark
                  ? Border.all(color: theme.dividerColor)
                  : Border.all(color: Colors.transparent),
            ),
            child: Text(
              'Date en cours: ${_selectedDateApi()}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: isDark ? Colors.white : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customerFilterCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Filtrer par client',
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _productFilterCtrl,
            onChanged: (_) async {
              setState(() {});
              await _loadReceiptsForProductFilterIfNeeded();
            },
            decoration: const InputDecoration(
              labelText: 'Filtrer par produit',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher les ventes archivees'),
            value: _showArchived,
            onChanged: (v) => setState(() => _showArchived = v),
          ),
          if (_loadingReceipts) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 10),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 10),
          ],
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (rows.isEmpty)
            const Text('Aucune vente trouvee pour ces filtres.')
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  isDark ? theme.colorScheme.surface : const Color(0xFFF1F5F9),
                ),
                dataRowColor: WidgetStatePropertyAll(theme.colorScheme.surface),
                headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                  color: isDark ? Colors.white : null,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white : null,
                ),
                columns: const [
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Heure')),
                  DataColumn(label: Text('Client')),
                  DataColumn(label: Text('Produits')),
                  DataColumn(label: Text('Paiement')),
                  DataColumn(label: Text('Statut')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: rows
                    .map(
                      (sale) => DataRow(
                        cells: [
                          DataCell(Text('${sale.id}')),
                          DataCell(Text(sale.time)),
                          DataCell(
                            Text(
                              sale.customerName.isEmpty
                                  ? 'Client libre'
                                  : sale.customerName,
                            ),
                          ),
                          DataCell(Text('${sale.itemsCount}')),
                          DataCell(Text(sale.paymentMethod)),
                          DataCell(Text(sale.status)),
                          DataCell(Text(_currency(sale.total))),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.archive_outlined),
                                  tooltip: _archivedSaleIds.contains(sale.id)
                                      ? 'Desarchiver'
                                      : 'Archiver',
                                  onPressed: () => _toggleArchive(sale),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.print_outlined),
                                  tooltip: 'Imprimer journal filtre',
                                  onPressed: _printFiltered,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Total: ${rows.length} vente(s) | ${_currency(rows.fold<double>(0, (sum, e) => sum + e.total))}',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ],
      ),
    );
  }
}
