library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/commerce_remote_datasource.dart';
import '../../../data/models/commerce_models.dart';

const _businessDomains = <MapEntry<String, String>>[
  MapEntry('restaurant', 'Restaurant'),
  MapEntry('pharmacy', 'Pharmacy'),
  MapEntry('boutique', 'Boutique'),
  MapEntry('supermarket', 'Supermarket'),
  MapEntry('hardware', 'Quincaillerie'),
  MapEntry('cosmetics', 'Cosmetiques'),
  MapEntry('electronics', 'Electronique'),
  MapEntry('other', 'Autre'),
];

class SupplierNetworkScreen extends StatelessWidget {
  const SupplierNetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: _SupplierTopBar(),
        body: TabBarView(
          children: [
            _MarketplaceTab(),
            _FindTab(),
            _ChatsTab(),
            _OrdersTab(),
            _ProfileTab(),
          ],
        ),
      ),
    );
  }
}

class _SupplierTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _SupplierTopBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Fournisseurs'),
      bottom: const TabBar(
        tabs: [
          Tab(
            icon: Icon(Icons.store_mall_directory_outlined),
            text: 'Marketplace',
          ),
          Tab(icon: Icon(Icons.search_rounded), text: 'Trouver'),
          Tab(icon: Icon(Icons.forum_outlined), text: 'Chats'),
          Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Commandes'),
          Tab(icon: Icon(Icons.storefront_outlined), text: 'Profil'),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 48);
}

class _MarketplaceTab extends StatefulWidget {
  const _MarketplaceTab();

  @override
  State<_MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends State<_MarketplaceTab> with _RemoteMixin {
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _selectedDomain;
  List<SupplierProfileModel> _suppliers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = await remote();
    if (api == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await api.getSupplierMarketplace(
        query: _searchController.text.trim(),
        businessDomain: _selectedDomain,
      );
      if (!mounted) return;
      setState(() => _suppliers = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openProduct(
    SupplierProfileModel supplier,
    SupplierProductModel product,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _SupplierProductDetailScreen(supplier: supplier, product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final supplier in _suppliers) {
      for (final product in supplier.products) {
        cards.add(
          InkWell(
            onTap: () => _openProduct(supplier, product),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          product.imageUrl.isEmpty
                              ? const ColoredBox(
                                  color: Color(0x22000000),
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                )
                              : Image.network(
                                  product.imageUrl,
                                  fit: BoxFit.cover,
                                ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                supplier.businessName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${product.price.toStringAsFixed(0)} CDF',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${supplier.commune}${supplier.quarter.isEmpty ? '' : ' • ${supplier.quarter}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Rechercher un produit',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: _selectedDomain == null,
                  onSelected: (_) {
                    setState(() => _selectedDomain = null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                ..._businessDomains.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _selectedDomain == entry.key,
                      onSelected: (_) {
                        setState(() => _selectedDomain = entry.key);
                        _load();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading && cards.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                'Aucun produit disponible pour le moment.',
                textAlign: TextAlign.center,
              ),
            ),
          if (cards.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (_, i) => cards[i],
            ),
        ],
      ),
    );
  }
}

class _ChatsTab extends StatefulWidget {
  const _ChatsTab();

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> with _RemoteMixin {
  bool _loading = true;
  List<SupplierConversationModel> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    final api = await remote();
    if (api == null || !mounted) return;
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      final rows = await api.getSupplierConversations();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _rows = const []);
    } finally {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(SupplierConversationModel c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _SupplierChatScreen(conversationId: c.id, title: c.supplierName),
      ),
    );
    await _load(showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                'Aucune conversation pour le moment.',
                textAlign: TextAlign.center,
              ),
            ),
          ..._rows.map(
            (c) => Card(
              child: ListTile(
                onTap: () => _open(c),
                title: Text(c.supplierName),
                subtitle: Text(
                  c.lastMessagePreview.trim().isEmpty
                      ? 'Ouvrir la discussion'
                      : c.lastMessagePreview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

mixin _RemoteMixin<T extends StatefulWidget> on State<T> {
  final _auth = AuthLocalDataSource();

  Future<CommerceRemoteDataSource?> remote() async {
    final token = await _auth.getAccessToken();
    if (token == null || token.isEmpty) return null;
    final client = DioClient(
      baseUrl: EnvConfig.apiBaseUrl,
      accessToken: token,
      getRefreshToken: () => _auth.getRefreshToken(),
      saveAccessToken: (t) => _auth.setAccessToken(t),
    );
    return CommerceRemoteDataSource(client);
  }
}

class _FindTab extends StatefulWidget {
  const _FindTab();

  @override
  State<_FindTab> createState() => _FindTabState();
}

enum _SupplierSearchUiState { idle, loading, success, empty, error }

class _SupplierMapPoint {
  const _SupplierMapPoint({
    required this.supplier,
    required this.point,
    required this.distanceKm,
    required this.isEstimated,
  });

  final SupplierProfileModel supplier;
  final LatLng point;
  final double? distanceKm;
  final bool isEstimated;
}

class _FindTabState extends State<_FindTab> with _RemoteMixin {
  final _commune = TextEditingController();
  final _product = TextEditingController();
  bool _loading = false;
  bool _locating = false;
  bool _loadingLocations = true;
  double? _lat;
  double? _lng;
  List<SupplierProfileModel> _rows = const [];
  String? _selectedDomain;
  Map<String, List<String>> _locationMap = const {};
  String? _selectedCommune;
  String? _selectedQuarter;
  final Map<int, bool> _unreadBySupplier = <int, bool>{};
  Timer? _conversationPollTimer;
  int? _currentUserId;
  _SupplierSearchUiState _uiState = _SupplierSearchUiState.idle;
  String? _searchError;
  final MapController _mapController = MapController();
  SupplierProfileModel? _selectedMapSupplier;
  List<_SupplierMapPoint> _mapPoints = const <_SupplierMapPoint>[];
  static const Map<String, LatLng> _communeCenter = <String, LatLng>{
    'GOMBE': LatLng(-4.3107, 15.3070),
    'KINTAMBO': LatLng(-4.3252, 15.2780),
    'NGALIEMA': LatLng(-4.3505, 15.2591),
    'LINGWALA': LatLng(-4.3226, 15.3027),
    'BARUMBU': LatLng(-4.3172, 15.3275),
    'BANDALUNGWA': LatLng(-4.3437, 15.2892),
    'BUMBU': LatLng(-4.3750, 15.3000),
    'KALAMU': LatLng(-4.3601, 15.3158),
    'KASA-VUBU': LatLng(-4.3405, 15.3142),
    'LIMETE': LatLng(-4.3365, 15.3469),
    'LEMBA': LatLng(-4.3953, 15.3149),
    'MASINA': LatLng(-4.3836, 15.4001),
    'KIMBANSEKE': LatLng(-4.4038, 15.4187),
    'MONT-NGAFULA': LatLng(-4.4421, 15.2669),
    'NGABA': LatLng(-4.3962, 15.3054),
    'MATETE': LatLng(-4.3875, 15.3379),
    'NDJILI': LatLng(-4.3845, 15.3843),
    'MALUKU': LatLng(-4.1400, 15.5700),
    'SELEMBAO': LatLng(-4.4042, 15.2699),
    'NGIRI-NGIRI': LatLng(-4.3506, 15.2957),
    'NSELE': LatLng(-4.3200, 15.5000),
  };

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _initConversationIndicators();
  }

  @override
  void dispose() {
    _conversationPollTimer?.cancel();
    _commune.dispose();
    _product.dispose();
    super.dispose();
  }

  Future<void> _initConversationIndicators() async {
    final rawId = _auth.getUser()?.id ?? '';
    _currentUserId = int.tryParse(rawId);
    await _refreshConversationIndicators();
    _conversationPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshConversationIndicators(),
    );
  }

  Future<void> _refreshConversationIndicators() async {
    final api = await remote();
    final myId = _currentUserId;
    if (api == null || myId == null || !mounted) return;
    try {
      final conversations = await api.getSupplierConversations();
      final next = <int, bool>{};
      for (final convo in conversations) {
        final messages = await api.getSupplierMessages(
          conversationId: convo.id,
        );
        if (messages.isEmpty) {
          next[convo.supplierId] = false;
          continue;
        }
        final last = messages.last;
        next[convo.supplierId] = last.senderId != myId;
      }
      if (!mounted) return;
      setState(() {
        _unreadBySupplier
          ..clear()
          ..addAll(next);
      });
    } catch (_) {}
  }

  bool _hasUnreadForSupplier(int supplierId) =>
      _unreadBySupplier[supplierId] == true;

  Future<void> _loadLocations() async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final rows = await api.getKinshasaLocations();
      final next = <String, List<String>>{};
      for (final row in rows) {
        final commune = _normalizeLocationKey(row['commune'] as String? ?? '');
        if (commune.isEmpty) continue;
        final raw = (row['quarters'] as List<dynamic>? ?? const []);
        final seen = <String>{};
        next[commune] = raw
            .map((e) => '$e')
            .map(_normalizeLocationKey)
            .where((e) => e.isNotEmpty && seen.add(e))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _locationMap = next;
        _selectedCommune = _matchDropdownValue(
          _selectedCommune,
          _locationMap.keys,
        );
        _selectedQuarter = _matchDropdownValue(
          _selectedQuarter,
          _locationMap[_selectedCommune] ?? const <String>[],
        );
        _loadingLocations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLocations = false);
    }
  }

  String _normalizeLocationKey(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    return v.toUpperCase();
  }

  String? _matchDropdownValue(String? value, Iterable<String> choices) {
    if (value == null) return null;
    final normalized = _normalizeLocationKey(value);
    for (final c in choices) {
      if (_normalizeLocationKey(c) == normalized) {
        return c;
      }
    }
    return null;
  }

  Future<void> _gps() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) throw Exception('Activez le GPS.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permission GPS refusee.');
      }
      // Etape 1: utiliser une position cachee pour aller vite.
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && mounted) {
        setState(() {
          _lat = cached.latitude;
          _lng = cached.longitude;
        });
      }

      // Etape 2: tenter une position fraiche plus precise.
      const settings = LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 35),
      );
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      if (!mounted) return;
      setState(() {
        _lat = fresh.latitude;
        _lng = fresh.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position GPS detectee. Recherche en cours...'),
        ),
      );
      await _search();
    } on TimeoutException {
      if (!mounted) return;
      if (_lat != null && _lng != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Position approximative utilisee. Recherche en cours...',
            ),
          ),
        );
        await _search();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS indisponible. Activez la localisation precise ou saisissez la commune.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search() async {
    final api = await remote();
    if (api == null || !mounted) return;
    final commune = _commune.text.trim();
    if ((_lat == null || _lng == null) && commune.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisez GPS ou renseignez la commune.')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _uiState = _SupplierSearchUiState.loading;
      _searchError = null;
    });
    try {
      final rows = await api.getNearbySuppliers(
        latitude: _lat,
        longitude: _lng,
        commune: commune,
        productName: _product.text.trim(),
        businessDomain: _selectedDomain,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _mapPoints = _buildMapPoints(rows);
        _selectedMapSupplier = null;
        _uiState = rows.isEmpty
            ? _SupplierSearchUiState.empty
            : _SupplierSearchUiState.success;
      });
      _fitMapToContent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _uiState = _SupplierSearchUiState.error;
        _searchError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_SupplierMapPoint> _buildMapPoints(List<SupplierProfileModel> rows) {
    final points = <_SupplierMapPoint>[];
    for (final supplier in rows) {
      LatLng? position;
      var estimated = false;
      if (supplier.latitude != null && supplier.longitude != null) {
        position = LatLng(supplier.latitude!, supplier.longitude!);
      } else {
        final fallback =
            _communeCenter[_normalizeLocationKey(supplier.commune)];
        if (fallback != null) {
          position = fallback;
          estimated = true;
        }
      }
      if (position == null) continue;
      final distance = (_lat != null && _lng != null)
          ? Geolocator.distanceBetween(
                  _lat!,
                  _lng!,
                  position.latitude,
                  position.longitude,
                ) /
                1000
          : supplier.distanceKm;
      points.add(
        _SupplierMapPoint(
          supplier: supplier,
          point: position,
          distanceKm: distance,
          isEstimated: estimated,
        ),
      );
    }
    return points;
  }

  void _fitMapToContent() {
    if (_mapPoints.isEmpty) return;
    final pts = _mapPoints.map((e) => e.point).toList();
    if (_lat != null && _lng != null) {
      pts.add(LatLng(_lat!, _lng!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || pts.isEmpty) return;
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.all(42),
          ),
        );
      } catch (_) {}
    });
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Shimmer.fromColors(
            baseColor: Colors.grey.withValues(alpha: 0.22),
            highlightColor: Colors.grey.withValues(alpha: 0.10),
            child: Container(
              height: 138,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return Column(
      children: [
        _buildSuppliersMap(),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Touchez la carte pour ouvrir en plein ecran',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ..._rows.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.businessName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _openChat(s),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded),
                              if (_hasUnreadForSupplier(s.id))
                                Positioned(
                                  top: -1,
                                  right: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          tooltip: 'Chat',
                        ),
                        IconButton(
                          onPressed: () => _call(s),
                          icon: const Icon(Icons.call_outlined),
                          tooltip: 'Appeler',
                        ),
                      ],
                    ),
                    Text(
                      '${s.commune.isEmpty ? '-' : s.commune}${s.quarter.isEmpty ? '' : ' / ${s.quarter}'}'
                      '${s.distanceKm != null ? ' • ${s.distanceKm!.toStringAsFixed(1)} km' : ''}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: s.products
                          .map(
                            (p) => InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _SupplierProductDetailScreen(
                                    supplier: s,
                                    product: p,
                                  ),
                                ),
                              ),
                              child: Container(
                                width: 150,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 70,
                                      width: double.infinity,
                                      child: p.imageUrl.isEmpty
                                          ? const Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                p.imageUrl,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text('${p.price.toStringAsFixed(0)} CDF'),
                                    Text(
                                      p.isAvailable
                                          ? 'Disponible'
                                          : 'Indisponible',
                                      style: TextStyle(
                                        color: p.isAvailable
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuppliersMap() {
    if (_mapPoints.isEmpty) {
      return _buildStateMessage(
        icon: Icons.map_outlined,
        title: 'Carte indisponible',
        subtitle:
            'Aucune coordonnee exploitable pour les fournisseurs trouves.',
      );
    }
    final center = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : _mapPoints.first.point;
    final markers = _mapPoints
        .map(
          (mp) => Marker(
            point: mp.point,
            width: 58,
            height: 58,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.72, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: _buildTekisaMarker(),
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _selectedMapSupplier = mp.supplier),
                  child: child,
                ),
              ),
            ),
          ),
        )
        .toList();
    if (_lat != null && _lng != null) {
      markers.add(
        Marker(
          point: LatLng(_lat!, _lng!),
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12,
              onTap: (_, point) => _openFullMapScreen(),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.tekisa.cisnetkids',
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              if (_lat != null && _lng != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_lat!, _lng!),
                      radius: 48,
                      useRadiusInMeter: true,
                      color: Colors.blueAccent.withValues(alpha: 0.16),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.blueAccent.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          if (_selectedMapSupplier != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: _buildMapSupplierPopup(_selectedMapSupplier!),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openFullMapScreen() async {
    if (_mapPoints.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SupplierMapFullscreenScreen(
          points: _mapPoints,
          userPoint: (_lat != null && _lng != null)
              ? LatLng(_lat!, _lng!)
              : null,
          onOpenChat: _openChat,
          onCall: _call,
        ),
      ),
    );
  }

  Widget _buildTekisaMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF035D8A), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: ClipOval(
        child: Image.asset('assets/images/tekisa_logo.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildMapSupplierPopup(SupplierProfileModel supplier) {
    _SupplierMapPoint? point;
    for (final p in _mapPoints) {
      if (p.supplier.id == supplier.id) {
        point = p;
        break;
      }
    }
    final distanceText = point?.distanceKm != null
        ? '${point!.distanceKm!.toStringAsFixed(1)} km'
        : 'Distance indisponible';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                supplier.businessName,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              distanceText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF035D8A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${supplier.commune}${supplier.quarter.isEmpty ? '' : ' • ${supplier.quarter}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (point?.isEstimated == true)
          Text(
            'Position approximative (commune)',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.orange),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openChat(supplier),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _call(supplier),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Appeler'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchStateBody() {
    switch (_uiState) {
      case _SupplierSearchUiState.loading:
        return _buildLoadingSkeleton();
      case _SupplierSearchUiState.success:
        return _buildResultsList();
      case _SupplierSearchUiState.empty:
        return _buildStateMessage(
          icon: Icons.search_off_rounded,
          title: 'Aucun fournisseur trouvé',
          subtitle:
              'Essaie un autre filtre (commune, domaine ou nom de produit).',
        );
      case _SupplierSearchUiState.error:
        return _buildStateMessage(
          icon: Icons.wifi_off_rounded,
          title: 'Erreur pendant la recherche',
          subtitle: _searchError ?? 'Impossible de charger les résultats.',
          action: FilledButton(
            onPressed: _search,
            child: const Text('Réessayer'),
          ),
        );
      case _SupplierSearchUiState.idle:
        return _buildStateMessage(
          icon: Icons.store_mall_directory_outlined,
          title: 'Lance une recherche fournisseur',
          subtitle:
              'Utilise GPS ou choisis la commune puis appuie sur Trouver.',
        );
    }
  }

  Future<void> _call(SupplierProfileModel s) async {
    final api = await remote();
    if (api == null) return;
    try {
      final meta = await api.startSupplierCall(supplierId: s.id);
      final phone = (meta['supplier_phone'] as String? ?? s.phone).trim();
      final sessionId = (meta['session_id'] as num?)?.toInt();
      if (phone.isEmpty) throw Exception('Numero introuvable.');
      bool ok = await FlutterPhoneDirectCaller.callNumber(phone) ?? false;
      if (!ok) {
        ok = await launchUrl(Uri.parse('tel:$phone'));
      }
      if (sessionId != null) {
        await api.endSupplierCall(sessionId: sessionId);
      }
      if (!ok) throw Exception('Impossible de lancer l appel.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _openChat(SupplierProfileModel s) async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final convo = await api.createSupplierConversation(supplierId: s.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _SupplierChatScreen(
            conversationId: convo.id,
            title: s.businessName,
          ),
        ),
      );
      await _refreshConversationIndicators();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loadingLocations) const LinearProgressIndicator(minHeight: 2),
        DropdownButtonFormField<String>(
          initialValue: _matchDropdownValue(
            _selectedCommune,
            _locationMap.keys,
          ),
          decoration: const InputDecoration(labelText: 'Commune (Kinshasa)'),
          items: _locationMap.keys
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedCommune = value;
              _selectedQuarter = null;
              _commune.text = value ?? '';
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _matchDropdownValue(
            _selectedQuarter,
            _locationMap[_selectedCommune] ?? const <String>[],
          ),
          decoration: const InputDecoration(labelText: 'Quartier'),
          items: (_locationMap[_selectedCommune] ?? const <String>[])
              .map((q) => DropdownMenuItem<String>(value: q, child: Text(q)))
              .toList(),
          onChanged: (value) => setState(() => _selectedQuarter = value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedDomain,
          decoration: const InputDecoration(labelText: 'Domaine'),
          items: _businessDomains
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedDomain = value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commune,
          decoration: const InputDecoration(labelText: 'Commune'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _product,
          decoration: const InputDecoration(labelText: 'Produit (optionnel)'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _gps,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(_locating ? 'GPS...' : 'GPS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Trouver'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(_uiState.name),
            child: _buildSearchStateBody(),
          ),
        ),
      ],
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> with _RemoteMixin {
  bool _loading = true;
  List<SupplierOrderModel> _orders = const [];
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = int.tryParse(_auth.getUser()?.id ?? '');
    _load();
  }

  Future<void> _load() async {
    final api = await remote();
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final rows = await api.getSupplierOrders(scope: 'all');
      if (!mounted) return;
      setState(() => _orders = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'En attente';
      case 'accepted':
        return 'Acceptee';
      case 'rejected':
        return 'Rejetee';
      case 'canceled':
        return 'Annulee';
      case 'fulfilled':
        return 'Terminee';
      default:
        return status;
    }
  }

  Future<void> _openOrderDetail(SupplierOrderModel order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SupplierOrderDetailScreen(
          order: order,
          currentUserId: _currentUserId,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          ..._orders.map(
            (o) => ListTile(
              onTap: () => _openOrderDetail(o),
              title: Text(
                '${o.supplierName} • ${o.totalAmount.toStringAsFixed(0)} CDF',
              ),
              subtitle: Text(
                '${_statusLabel(o.status)} • ${o.items.length} article(s)',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierOrderDetailScreen extends StatefulWidget {
  const _SupplierOrderDetailScreen({
    required this.order,
    required this.currentUserId,
  });

  final SupplierOrderModel order;
  final int? currentUserId;

  @override
  State<_SupplierOrderDetailScreen> createState() =>
      _SupplierOrderDetailScreenState();
}

class _SupplierOrderDetailScreenState extends State<_SupplierOrderDetailScreen>
    with _RemoteMixin {
  late SupplierOrderModel _order;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'En attente';
      case 'accepted':
        return 'Acceptee';
      case 'rejected':
        return 'Rejetee';
      case 'canceled':
        return 'Annulee';
      case 'fulfilled':
        return 'Terminee';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'rejected':
      case 'canceled':
        return Colors.redAccent;
      case 'fulfilled':
        return Colors.green;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Future<void> _setStatus(String status) async {
    final api = await remote();
    if (api == null || !mounted) return;
    setState(() => _updating = true);
    try {
      final updated = await api.updateSupplierOrderStatus(
        orderId: _order.id,
        status: status,
      );
      if (!mounted) return;
      setState(() => _order = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande marquee: ${_statusLabel(status)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _continueConversation() async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final convo = await api.createSupplierConversation(
        supplierId: _order.supplierId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _SupplierChatScreen(
            conversationId: convo.id,
            title: _order.supplierName,
          ),
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
    final canMerchantActions = widget.currentUserId == _order.merchantId;
    final canSupplierActions = !canMerchantActions;
    final chipColor = _statusColor(context, _order.status);
    return Scaffold(
      appBar: AppBar(title: Text('Commande #${_order.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _order.supplierName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        _statusLabel(_order.status),
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: chipColor,
                    ),
                    Chip(
                      label: Text(
                        '${_order.totalAmount.toStringAsFixed(0)} CDF',
                      ),
                    ),
                  ],
                ),
                if (_order.deliveryCommune.isNotEmpty)
                  Text('Livraison: ${_order.deliveryCommune}'),
                if (_order.notes.isNotEmpty) Text('Note: ${_order.notes}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Details des articles'),
          const SizedBox(height: 8),
          ..._order.items.map(
            (item) => Card(
              child: ListTile(
                title: Text(item.productName),
                subtitle: Text(
                  'Qte: ${item.quantity} • PU: ${item.unitPrice.toStringAsFixed(0)} CDF',
                ),
                trailing: Text('${item.lineTotal.toStringAsFixed(0)} CDF'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _updating ? null : _continueConversation,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Poursuivre conversation'),
              ),
              FilledButton.icon(
                onPressed: (_updating ||
                        !canSupplierActions ||
                        _order.status != 'pending')
                    ? null
                    : () => _setStatus('accepted'),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Accepter'),
              ),
              OutlinedButton.icon(
                onPressed: (_updating ||
                        !canSupplierActions ||
                        _order.status != 'pending')
                    ? null
                    : () => _setStatus('rejected'),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Rejeter'),
              ),
              OutlinedButton.icon(
                onPressed: (_updating || !canMerchantActions)
                    ? null
                    : () => _setStatus('pending'),
                icon: const Icon(Icons.hourglass_top_rounded),
                label: const Text('En attente'),
              ),
              FilledButton.icon(
                onPressed: (_updating ||
                        !canSupplierActions ||
                        _order.status != 'accepted')
                    ? null
                    : () => _setStatus('fulfilled'),
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Terminer'),
              ),
              OutlinedButton.icon(
                onPressed: (_updating || !canMerchantActions)
                    ? null
                    : () => _setStatus('canceled'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler'),
              ),
            ],
          ),
          if (canSupplierActions) ...[
            const SizedBox(height: 8),
            Text(
              'Mode fournisseur: vous pouvez marquer cette commande comme terminee.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> with _RemoteMixin {
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _commune = TextEditingController();
  final _quarter = TextEditingController();
  final _avenue = TextEditingController();
  final _description = TextEditingController();
  final _profileImageUrl = TextEditingController();
  final _coverImageUrl = TextEditingController();
  final _whatsapp = TextEditingController();
  final _productPrice = TextEditingController();
  final _productImage = TextEditingController();
  final _picker = ImagePicker();
  bool _active = false;
  String _domain = 'other';
  bool _addingProduct = false;
  List<SupplierProductModel> _products = const [];
  List<CommerceProductModel> _stockProducts = const [];
  int? _selectedStockProductId;
  bool _supplierProductAvailable = true;
  bool _loadingBootstrap = true;
  bool _uploadingProductImage = false;
  bool _uploadingProfileImage = false;
  bool _uploadingCoverImage = false;
  bool _loadingLocations = true;
  bool _locating = false;
  bool _savingGps = false;
  bool _gpsSavedInBackend = false;
  Map<String, List<String>> _locationMap = const {};
  String? _selectedCommune;
  String? _selectedQuarter;
  double? _latitude;
  double? _longitude;

  String _normalizeLocationKey(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    return v.toUpperCase();
  }

  String? _matchDropdownValue(String? value, Iterable<String> choices) {
    if (value == null) return null;
    final normalized = _normalizeLocationKey(value);
    for (final c in choices) {
      if (_normalizeLocationKey(c) == normalized) {
        return c;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _business.dispose();
    _phone.dispose();
    _commune.dispose();
    _quarter.dispose();
    _avenue.dispose();
    _description.dispose();
    _profileImageUrl.dispose();
    _coverImageUrl.dispose();
    _whatsapp.dispose();
    _productPrice.dispose();
    _productImage.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final api = await remote();
    if (api == null || !mounted) return;
    setState(() => _loadingBootstrap = true);
    try {
      final locations = await api.getKinshasaLocations();
      final profile = await api.getMySupplierProfile();
      final published = await api.getMySupplierProducts();
      final stock = await api.getProducts();
      final nextLocationMap = <String, List<String>>{};
      for (final row in locations) {
        final commune = _normalizeLocationKey(row['commune'] as String? ?? '');
        if (commune.isEmpty) continue;
        final raw = (row['quarters'] as List<dynamic>? ?? const []);
        final seen = <String>{};
        nextLocationMap[commune] = raw
            .map((e) => '$e')
            .map(_normalizeLocationKey)
            .where((e) => e.isNotEmpty && seen.add(e))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _products = published;
        _stockProducts = stock;
        _locationMap = nextLocationMap;
        _loadingLocations = false;
        if (profile != null) {
          _business.text = profile.businessName;
          _phone.text = profile.phone;
          _commune.text = profile.commune;
          _quarter.text = profile.quarter;
          _avenue.text = profile.avenue;
          _description.text = profile.description;
          _profileImageUrl.text = profile.profileImageUrl;
          _coverImageUrl.text = profile.coverImageUrl;
          _whatsapp.text = profile.supportWhatsapp;
          _domain = profile.businessDomain;
          _active = profile.isActive;
          _latitude = profile.latitude;
          _longitude = profile.longitude;
          _gpsSavedInBackend =
              profile.latitude != null && profile.longitude != null;
          _selectedCommune = _matchDropdownValue(
            profile.commune.isEmpty ? null : profile.commune,
            _locationMap.keys,
          );
          _selectedQuarter = _matchDropdownValue(
            profile.quarter.isEmpty ? null : profile.quarter,
            _locationMap[_selectedCommune] ?? const <String>[],
          );
        }
        _loadingBootstrap = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBootstrap = false;
        _loadingLocations = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final rows = await api.getMySupplierProducts();
      if (!mounted) return;
      setState(() => _products = rows);
    } catch (_) {}
  }

  Future<void> _save() async {
    final api = await remote();
    if (api == null || !mounted) return;
    await api.saveMySupplierProfile(
      businessName: _business.text.trim(),
      description: _description.text.trim(),
      phone: _phone.text.trim(),
      isActive: _active,
      businessDomain: _domain,
      commune: _commune.text.trim(),
      quarter: _quarter.text.trim(),
      avenue: _avenue.text.trim(),
      profileImageUrl: _profileImageUrl.text.trim(),
      coverImageUrl: _coverImageUrl.text.trim(),
      supportWhatsapp: _whatsapp.text.trim(),
      latitude: _latitude,
      longitude: _longitude,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil fournisseur enregistre.')),
    );
    await _bootstrap();
  }

  Future<void> _saveGpsToBackend() async {
    if (_savingGps) return;
    final api = await remote();
    if (api == null || !mounted) return;
    if (_latitude == null || _longitude == null) return;
    setState(() => _savingGps = true);
    try {
      await api.saveMySupplierProfile(
        businessName: _business.text.trim(),
        description: _description.text.trim(),
        phone: _phone.text.trim(),
        isActive: _active,
        businessDomain: _domain,
        commune: _commune.text.trim(),
        quarter: _quarter.text.trim(),
        avenue: _avenue.text.trim(),
        profileImageUrl: _profileImageUrl.text.trim(),
        coverImageUrl: _coverImageUrl.text.trim(),
        supportWhatsapp: _whatsapp.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      setState(() => _gpsSavedInBackend = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position enregistrée dans la base.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _gpsSavedInBackend = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Position capturée mais non enregistrée. Vérifiez Internet.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingGps = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Activez votre GPS pour utiliser cette fonction.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permission de localisation refusée.');
      }

      // 1) Réponse ultra rapide: utiliser immédiatement la position cache si dispo.
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _latitude = cached.latitude;
          _longitude = cached.longitude;
          _gpsSavedInBackend = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Position approximative utilisée immédiatement. Actualisation en cours...',
            ),
          ),
        );
        _applyReverseGeocode(cached.latitude, cached.longitude);
        _saveGpsToBackend();
      }

      // 2) Tentative de position fraîche, non bloquante (court timeout).
      try {
        final fresh = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (!mounted) return;
        setState(() {
          _latitude = fresh.latitude;
          _longitude = fresh.longitude;
          _gpsSavedInBackend = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Position GPS actualisée. N\'oubliez pas d\'enregistrer.',
            ),
          ),
        );
        _applyReverseGeocode(fresh.latitude, fresh.longitude);
        _saveGpsToBackend();
      } on TimeoutException {
        // On ne bloque jamais l'UX sur timeout.
      }

      if (_latitude == null || _longitude == null) {
        throw Exception(
          'GPS indisponible. Activez la localisation precise puis reessayez.',
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS lent. Position approximative utilisée si disponible.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _applyReverseGeocode(double lat, double lng) async {
    final geo = await _reverseGeocodeFromCoords(lat, lng);
    if (!mounted) return;
    setState(() {
      final communeCandidate = _matchDropdownValue(geo.$1, _locationMap.keys);
      if (communeCandidate != null) {
        _selectedCommune = communeCandidate;
        _commune.text = communeCandidate;
      }
      final quarterCandidate = _matchDropdownValue(
        geo.$2,
        _locationMap[_selectedCommune] ?? const <String>[],
      );
      if (quarterCandidate != null) {
        _selectedQuarter = quarterCandidate;
        _quarter.text = quarterCandidate;
      }
    });
  }

  Future<(String?, String?)> _reverseGeocodeFromCoords(
    double lat,
    double lng,
  ) async {
    try {
      final dio = Dio();
      final response = await dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: <String, dynamic>{
          'format': 'jsonv2',
          'lat': lat,
          'lon': lng,
          'addressdetails': 1,
        },
        options: Options(
          headers: const <String, String>{
            'User-Agent': 'tekisa-cisnetkids/1.0',
          },
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final data = response.data ?? const <String, dynamic>{};
      final address =
          (data['address'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final communeRaw =
          (address['suburb'] as String? ??
                  address['city_district'] as String? ??
                  address['county'] as String? ??
                  '')
              .trim();
      final quarterRaw =
          (address['neighbourhood'] as String? ??
                  address['quarter'] as String? ??
                  '')
              .trim();
      return (communeRaw, quarterRaw);
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> _addProduct() async {
    final api = await remote();
    if (api == null || !mounted) return;
    final sourceProductId = _selectedStockProductId;
    final price = double.tryParse(_productPrice.text.trim());
    if (sourceProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un produit du stock.')),
      );
      return;
    }
    if (_productImage.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez une image pour ce produit.')),
      );
      return;
    }
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseignez un prix valide.')),
      );
      return;
    }
    setState(() => _addingProduct = true);
    try {
      await api.createSupplierProduct(
        sourceProductId: sourceProductId,
        price: price,
        isAvailable: _supplierProductAvailable,
        imageUrl: _productImage.text.trim(),
      );
      _selectedStockProductId = null;
      _productPrice.clear();
      _productImage.clear();
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produit fournisseur ajoute.')),
      );
    } finally {
      if (mounted) setState(() => _addingProduct = false);
    }
  }

  Future<void> _pickAndUploadProductImage(ImageSource source) async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return;
      setState(() => _uploadingProductImage = true);
      final url = await api.uploadSupplierImage(filePath: picked.path);
      if (!mounted) return;
      setState(() => _productImage.text = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image chargee avec succes.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _uploadingProductImage = false);
    }
  }

  Future<void> _pickAndUploadSupplierPhoto({
    required ImageSource source,
    required bool isProfile,
  }) async {
    final api = await remote();
    if (api == null || !mounted) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (picked == null) return;
      setState(() {
        if (isProfile) {
          _uploadingProfileImage = true;
        } else {
          _uploadingCoverImage = true;
        }
      });
      final url = await api.uploadSupplierImage(filePath: picked.path);
      if (!mounted) return;
      setState(() {
        if (isProfile) {
          _profileImageUrl.text = url;
        } else {
          _coverImageUrl.text = url;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isProfile
                ? 'Photo profil chargee avec succes.'
                : 'Photo couverture chargee avec succes.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (isProfile) {
            _uploadingProfileImage = false;
          } else {
            _uploadingCoverImage = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loadingBootstrap) const LinearProgressIndicator(minHeight: 2),
        TextField(
          controller: _business,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'Nom entreprise'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'Telephone'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _domain,
          decoration: const InputDecoration(labelText: 'Domaine'),
          items: _businessDomains
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _domain = v ?? 'other'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        if (_loadingLocations) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _matchDropdownValue(
            _selectedCommune,
            _locationMap.keys,
          ),
          decoration: const InputDecoration(labelText: 'Commune (Kinshasa)'),
          items: _locationMap.keys
              .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedCommune = value;
              _selectedQuarter = null;
              _commune.text = value ?? '';
              _quarter.clear();
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _matchDropdownValue(
            _selectedQuarter,
            _locationMap[_selectedCommune] ?? const <String>[],
          ),
          decoration: const InputDecoration(labelText: 'Quartier'),
          items: (_locationMap[_selectedCommune] ?? const <String>[])
              .map((q) => DropdownMenuItem<String>(value: q, child: Text(q)))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedQuarter = value;
              _quarter.text = value ?? '';
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(
                  _locating ? 'Localisation...' : 'Utiliser ma position',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              _gpsSavedInBackend ? Icons.check_circle : Icons.sync_problem,
              size: 16,
              color: _gpsSavedInBackend ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 6),
            Text(
              _gpsSavedInBackend
                  ? 'Position GPS enregistrée (base de données)'
                  : (_savingGps
                        ? 'Enregistrement GPS en cours...'
                        : 'Position GPS non encore enregistrée'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _gpsSavedInBackend ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (_latitude != null && _longitude != null) ...[
          const SizedBox(height: 6),
          Text(
            'GPS: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _avenue,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'Avenue'),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 8),
        const Text('Photo profil'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingProfileImage
                    ? null
                    : () => _pickAndUploadSupplierPhoto(
                        source: ImageSource.gallery,
                        isProfile: true,
                      ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galerie'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingProfileImage
                    ? null
                    : () => _pickAndUploadSupplierPhoto(
                        source: ImageSource.camera,
                        isProfile: true,
                      ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (_uploadingProfileImage) const LinearProgressIndicator(minHeight: 2),
        if (_profileImageUrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 90,
              child: Image.network(_profileImageUrl.text, fit: BoxFit.cover),
            ),
          ),
        ],
        const SizedBox(height: 10),
        const Text('Photo couverture'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingCoverImage
                    ? null
                    : () => _pickAndUploadSupplierPhoto(
                        source: ImageSource.gallery,
                        isProfile: false,
                      ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galerie'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingCoverImage
                    ? null
                    : () => _pickAndUploadSupplierPhoto(
                        source: ImageSource.camera,
                        isProfile: false,
                      ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (_uploadingCoverImage) const LinearProgressIndicator(minHeight: 2),
        if (_coverImageUrl.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 90,
              child: Image.network(_coverImageUrl.text, fit: BoxFit.cover),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _whatsapp,
          decoration: const InputDecoration(labelText: 'Numero WhatsApp'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          title: const Text('Mode fournisseur actif'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
        const SizedBox(height: 12),
        const Divider(height: 20),
        const Text('Publier depuis mon stock'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _selectedStockProductId,
          decoration: const InputDecoration(labelText: 'Produit du stock'),
          items: _stockProducts
              .map(
                (p) => DropdownMenuItem<int>(
                  value: p.id,
                  child: Text('${p.name} (${p.stockQuantity})'),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedStockProductId = value;
              CommerceProductModel? selected;
              for (final p in _stockProducts) {
                if (p.id == value) {
                  selected = p;
                  break;
                }
              }
              if (selected != null) {
                _productPrice.text = selected.unitPrice.toStringAsFixed(0);
              }
            });
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _productPrice,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Prix'),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 8),
        const Text('Photo produit'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingProductImage
                    ? null
                    : () => _pickAndUploadProductImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galerie'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingProductImage
                    ? null
                    : () => _pickAndUploadProductImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (_productImage.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 90,
              child: Image.network(_productImage.text, fit: BoxFit.cover),
            ),
          ),
        ],
        if (_uploadingProductImage) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _supplierProductAvailable,
          onChanged: (v) => setState(() => _supplierProductAvailable = v),
          title: const Text('Disponible'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addingProduct ? null : _addProduct,
          icon: const Icon(Icons.add_box_outlined),
          label: Text(
            _addingProduct ? 'Publication...' : 'Publier pour fournisseur',
          ),
        ),
        const SizedBox(height: 12),
        const Text('Produits publies pour fournir'),
        const SizedBox(height: 8),
        if (_products.isEmpty)
          const Text('Aucun produit publie pour le moment.')
        else
          ..._products.map(
            (p) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 74,
                        height: 74,
                        child: p.imageUrl.isEmpty
                            ? const ColoredBox(
                                color: Color(0x22000000),
                                child: Icon(Icons.inventory_2_outlined),
                              )
                            : Image.network(p.imageUrl, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text('${p.price.toStringAsFixed(0)} CDF'),
                          Text('Stock: ${p.stockQuantity}'),
                          const SizedBox(height: 4),
                          Text(
                            p.isAvailable ? 'Disponible' : 'Indisponible',
                            style: TextStyle(
                              color: p.isAvailable ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SupplierProductDetailScreen extends StatefulWidget {
  const _SupplierProductDetailScreen({
    required this.supplier,
    required this.product,
  });

  final SupplierProfileModel supplier;
  final SupplierProductModel product;

  @override
  State<_SupplierProductDetailScreen> createState() =>
      _SupplierProductDetailScreenState();
}

class _SupplierProductDetailScreenState
    extends State<_SupplierProductDetailScreen>
    with _RemoteMixin {
  int _quantity = 1;
  bool _ordering = false;

  Future<void> _orderNow() async {
    final api = await remote();
    if (api == null || !mounted) return;
    setState(() => _ordering = true);
    try {
      final result = await api.createSupplierQuickOrder(
        supplierProductId: widget.product.id,
        quantity: _quantity,
      );
      final conversationId = (result['conversation_id'] as num?)?.toInt();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commande envoyee au fournisseur.')),
      );
      if (conversationId != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SupplierChatScreen(
              conversationId: conversationId,
              title: widget.supplier.businessName,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: Text('Detail produit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: p.imageUrl.isEmpty
                  ? const ColoredBox(
                      color: Color(0x22000000),
                      child: Icon(Icons.image_not_supported_outlined, size: 64),
                    )
                  : Image.network(p.imageUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Text(p.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('${p.price.toStringAsFixed(0)} CDF'),
          Text(p.isAvailable ? 'Disponible' : 'Indisponible'),
          const SizedBox(height: 10),
          Text('Fournisseur: ${widget.supplier.businessName}'),
          Text('Telephone: ${widget.supplier.phone}'),
          Text(
            'Adresse: ${widget.supplier.commune} ${widget.supplier.quarter} ${widget.supplier.avenue}',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Quantite'),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _quantity > 1
                    ? () => setState(() => _quantity--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_quantity'),
              IconButton(
                onPressed: () => setState(() => _quantity++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (!p.isAvailable || _ordering) ? null : _orderNow,
            icon: const Icon(Icons.shopping_bag_outlined),
            label: Text(_ordering ? 'Envoi...' : 'Commander directement'),
          ),
        ],
      ),
    );
  }
}

class _SupplierChatScreen extends StatefulWidget {
  const _SupplierChatScreen({
    required this.conversationId,
    required this.title,
  });

  final int conversationId;
  final String title;

  @override
  State<_SupplierChatScreen> createState() => _SupplierChatScreenState();
}

class _PendingAttachment {
  const _PendingAttachment({
    required this.path,
    required this.name,
    required this.type,
  });

  final String path;
  final String name;
  final String type; // image, video, document, audio
}

class _AttachmentPayload {
  const _AttachmentPayload({
    required this.type,
    required this.name,
    required this.url,
    required this.caption,
  });

  final String type;
  final String name;
  final String url;
  final String caption;
}

class _SupplierChatScreenState extends State<_SupplierChatScreen>
    with _RemoteMixin {
  final _message = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<SupplierMessageModel> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _isRecordingVoice = false;
  String? _activeVoiceUrl;
  bool _voiceIsPlaying = false;
  Duration _voicePosition = Duration.zero;
  Duration _voiceDuration = Duration.zero;
  Timer? _messagePollTimer;
  Timer? _recordTimer;
  int? _currentUserId;
  String _myDisplayName = '';
  String _myCompanyName = '';
  final List<_PendingAttachment> _pendingAttachments = <_PendingAttachment>[];
  String? _draftVoicePath;
  Duration _draftVoiceDuration = Duration.zero;
  DateTime? _recordStartAt;
  bool _cancelRecordingBySlide = false;
  double? _recordStartDx;
  bool _isRecordingLockedUi = false;

  @override
  void initState() {
    super.initState();
    final me = _auth.getUser();
    _currentUserId = int.tryParse(me?.id ?? '');
    _myDisplayName = (me?.displayName ?? me?.username ?? '').trim().isEmpty
        ? 'Moi'
        : (me?.displayName ?? me?.username ?? '').trim();
    _myCompanyName = (me?.companyName ?? me?.companyTradeName ?? '').trim();
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _audioPlayer.setVolume(1.0);
    _audioPlayer.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _voiceDuration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _voicePosition = p);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _voiceIsPlaying = false;
        _voicePosition = Duration.zero;
      });
    });
    _load();
    _messagePollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(showLoader: false),
    );
  }

  @override
  void dispose() {
    _messagePollTimer?.cancel();
    _recordTimer?.cancel();
    _message.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    final api = await remote();
    if (api == null || !mounted) return;
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      final rows = await api.getSupplierMessages(
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      final hasChanged =
          rows.length != _messages.length ||
          (rows.isNotEmpty &&
              _messages.isNotEmpty &&
              rows.last.id != _messages.last.id);
      if (hasChanged || showLoader) {
        setState(() => _messages = rows);
      }
    } finally {
      if (mounted && showLoader) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitComposer() async {
    final api = await remote();
    if (api == null || !mounted) return;
    final text = _message.text.trim();
    final hasAttachments = _pendingAttachments.isNotEmpty;
    final hasDraftVoice = (_draftVoicePath ?? '').isNotEmpty;
    if (text.isEmpty && !hasAttachments && !hasDraftVoice) return;
    setState(() => _sending = true);
    try {
      if (hasDraftVoice) {
        final path = _draftVoicePath!;
        final voiceUrl = await api.uploadSupplierAudio(filePath: path);
        await api.sendSupplierMessage(
          conversationId: widget.conversationId,
          messageType: 'voice',
          voiceUrl: voiceUrl,
        );
        _draftVoicePath = null;
        _draftVoiceDuration = Duration.zero;
      }

      if (hasAttachments) {
        final caption = text;
        var first = true;
        for (final file in List<_PendingAttachment>.from(_pendingAttachments)) {
          final url = await api.uploadSupplierFile(filePath: file.path);
          final safeName = file.name.replaceAll('|', ' ');
          final safeCaption = (first ? caption : '').replaceAll('|', ' ');
          final payload = '__ATTACH__|${file.type}|$safeName|$url|$safeCaption';
          await api.sendSupplierMessage(
            conversationId: widget.conversationId,
            messageType: 'text',
            content: payload,
          );
          first = false;
        }
        _pendingAttachments.clear();
      } else if (text.isNotEmpty) {
        await api.sendSupplierMessage(
          conversationId: widget.conversationId,
          messageType: 'text',
          content: text,
        );
      }
      _message.clear();
      await _load(showLoader: false);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startVoiceRecord() async {
    if (_isRecordingVoice) return;
    final api = await remote();
    if (api == null || !mounted) return;
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission micro refusee.')),
      );
      return;
    }
    final filePath = p.join(
      Directory.systemTemp.path,
      'tekisa_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: filePath,
    );
    if (!mounted) return;
    _recordStartAt = DateTime.now();
    _cancelRecordingBySlide = false;
    _isRecordingLockedUi = true;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_isRecordingVoice) return;
      setState(() {});
    });
    setState(() => _isRecordingVoice = true);
  }

  Future<void> _stopAndSendVoice() async {
    if (!_isRecordingVoice) return;
    final path = await _audioRecorder.stop();
    if (!mounted) return;
    _recordTimer?.cancel();
    setState(() {
      _isRecordingVoice = false;
      _isRecordingLockedUi = false;
    });
    if (path == null || path.isEmpty) return;
    if (_cancelRecordingBySlide) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      return;
    }
    final elapsed = DateTime.now().difference(_recordStartAt ?? DateTime.now());
    setState(() {
      _draftVoicePath = path;
      _draftVoiceDuration = elapsed;
    });
  }

  Future<void> _toggleVoicePlayback(String url) async {
    if (url.trim().isEmpty) return;
    if (_activeVoiceUrl == url && _voiceIsPlaying) {
      await _audioPlayer.pause();
      if (!mounted) return;
      setState(() => _voiceIsPlaying = false);
      return;
    }
    if (_activeVoiceUrl == url && !_voiceIsPlaying) {
      await _audioPlayer.resume();
      if (!mounted) return;
      setState(() => _voiceIsPlaying = true);
      return;
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
    if (!mounted) return;
    setState(() {
      _activeVoiceUrl = url;
      _voiceIsPlaying = true;
      _voicePosition = Duration.zero;
      _voiceDuration = Duration.zero;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  _AttachmentPayload? _parseAttachmentMessage(String content) {
    if (!content.startsWith('__ATTACH__|')) return null;
    final parts = content.split('|');
    if (parts.length < 5) return null;
    return _AttachmentPayload(
      type: parts[1],
      name: parts[2],
      url: parts[3],
      caption: parts.sublist(4).join('|'),
    );
  }

  Future<void> _pickAttachment(String kind) async {
    if (!mounted) return;
    FilePickerResult? result;
    switch (kind) {
      case 'image':
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
        break;
      case 'video':
        result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        break;
      case 'audio':
        result = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
        break;
      default:
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
          allowMultiple: true,
        );
        break;
    }
    if (result == null) return;
    final files = result.files.where((f) => (f.path ?? '').isNotEmpty);
    setState(() {
      for (final f in files) {
        _pendingAttachments.add(
          _PendingAttachment(
            path: f.path!,
            name: f.name,
            type: kind == 'document' ? 'document' : kind,
          ),
        );
      }
    });
  }

  Future<void> _pickFromCamera() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;
    setState(() {
      _pendingAttachments.add(
        _PendingAttachment(
          path: picked.path,
          name: p.basename(picked.path),
          type: 'image',
        ),
      );
    });
  }

  Future<void> _openAttachmentMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAttachment('document');
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Image'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAttachment('image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Vidéo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAttachment('video');
              },
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack_outlined),
              title: const Text('Audio'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAttachment('audio');
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isMine(SupplierMessageModel m) {
    final me = _currentUserId;
    if (me == null) return false;
    return m.senderId == me;
  }

  Widget _messageMeta(SupplierMessageModel m, {required bool isMine}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMine ? Icons.done_all_rounded : Icons.south_west_rounded,
          size: 14,
          color: isMine ? const Color(0xFF2E7D32) : Colors.grey,
        ),
        const SizedBox(width: 4),
        Text(m.createdAt, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _senderHeader(SupplierMessageModel m, {required bool isMine}) {
    final senderName = isMine
        ? _myDisplayName
        : (m.senderName.isEmpty ? widget.title : m.senderName);
    final senderCompany = isMine
        ? _myCompanyName
        : (m.senderCompany.isEmpty ? '' : m.senderCompany);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMine
                ? Icons.account_circle_rounded
                : Icons.person_outline_rounded,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (senderCompany.isNotEmpty) ...[
            const SizedBox(width: 6),
            const Icon(Icons.business_outlined, size: 13, color: Colors.grey),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                senderCompany,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceBubble(SupplierMessageModel m) {
    final isMine = _isMine(m);
    final isActive = _activeVoiceUrl == m.voiceUrl;
    final progress =
        (isActive &&
            _voiceDuration.inMilliseconds > 0 &&
            _voicePosition.inMilliseconds >= 0)
        ? (_voicePosition.inMilliseconds / _voiceDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final left = isActive ? _fmt(_voicePosition) : '00:00';
    final right = isActive ? _fmt(_voiceDuration) : '--:--';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isMine
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _toggleVoicePlayback(m.voiceUrl),
              icon: Icon(
                isActive && _voiceIsPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
              ),
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: isMine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _senderHeader(m, isMine: isMine),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: progress,
                      backgroundColor: Colors.black12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(left, style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      Text(right, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: isMine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _messageMeta(m, isMine: isMine),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextBubble(SupplierMessageModel m) {
    final isMine = _isMine(m);
    final attachment = _parseAttachmentMessage(m.content);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isMine
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            _senderHeader(m, isMine: isMine),
            if (attachment == null)
              Text(m.content)
            else ...[
              if (attachment.type == 'image')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 150,
                      width: 180,
                      child: Image.network(attachment.url, fit: BoxFit.cover),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        attachment.type == 'video'
                            ? Icons.videocam_outlined
                            : attachment.type == 'audio'
                            ? Icons.audiotrack_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          attachment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (attachment.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(attachment.caption),
              ],
            ],
            const SizedBox(height: 4),
            _messageMeta(m, isMine: isMine),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasComposerText = _message.text.trim().isNotEmpty;
    final showSend =
        hasComposerText ||
        _pendingAttachments.isNotEmpty ||
        (_draftVoicePath ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('Chat • ${widget.title}')),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: _messages
                  .map(
                    (m) => m.messageType == 'voice'
                        ? _buildVoiceBubble(m)
                        : _buildTextBubble(m),
                  )
                  .toList(),
            ),
          ),
          if (_isRecordingLockedUi)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                _cancelRecordingBySlide
                    ? 'Relâchez pour annuler'
                    : 'Enregistrement... glissez à gauche pour annuler',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          if (_pendingAttachments.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) {
                  final a = _pendingAttachments[i];
                  return Chip(
                    avatar: Icon(
                      a.type == 'image'
                          ? Icons.image_outlined
                          : a.type == 'video'
                          ? Icons.videocam_outlined
                          : a.type == 'audio'
                          ? Icons.audiotrack_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 16,
                    ),
                    label: Text(a.name, overflow: TextOverflow.ellipsis),
                    onDeleted: () =>
                        setState(() => _pendingAttachments.removeAt(i)),
                  );
                },
                separatorBuilder: (_, index) => const SizedBox(width: 6),
                itemCount: _pendingAttachments.length,
              ),
            ),
          if ((_draftVoicePath ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Audio prêt (${_fmt(_draftVoiceDuration)})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      final path = _draftVoicePath;
                      setState(() {
                        _draftVoicePath = null;
                        _draftVoiceDuration = Duration.zero;
                      });
                      if (path != null) {
                        try {
                          final f = File(path);
                          if (await f.exists()) await f.delete();
                        } catch (_) {}
                      }
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.emoji_emotions_outlined),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _message,
                              maxLength: 2000,
                              buildCounter:
                                  (
                                    _, {
                                    required int currentLength,
                                    required bool isFocused,
                                    required int? maxLength,
                                  }) => null,
                              textInputAction: TextInputAction.send,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submitComposer(),
                              decoration: const InputDecoration(
                                hintText: 'Tapez un message',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _openAttachmentMenu,
                            icon: const Icon(Icons.attach_file_rounded),
                          ),
                          IconButton(
                            onPressed: _pickFromCamera,
                            icon: const Icon(Icons.camera_alt_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPressStart: _sending || showSend
                      ? null
                      : (details) {
                          _recordStartDx = details.globalPosition.dx;
                          _startVoiceRecord();
                        },
                  onLongPressMoveUpdate: _sending || showSend
                      ? null
                      : (details) {
                          final start = _recordStartDx;
                          if (start == null) return;
                          final delta = details.globalPosition.dx - start;
                          if (delta < -90 && !_cancelRecordingBySlide) {
                            setState(() => _cancelRecordingBySlide = true);
                          }
                        },
                  onLongPressEnd: _sending || showSend
                      ? null
                      : (_) => _stopAndSendVoice(),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Material(
                      color: const Color(0xFF25D366),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending
                            ? null
                            : () {
                                if (showSend) {
                                  _submitComposer();
                                }
                              },
                        child: Icon(
                          showSend ? Icons.send_rounded : Icons.mic_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierMapFullscreenScreen extends StatefulWidget {
  const _SupplierMapFullscreenScreen({
    required this.points,
    required this.userPoint,
    required this.onOpenChat,
    required this.onCall,
  });

  final List<_SupplierMapPoint> points;
  final LatLng? userPoint;
  final Future<void> Function(SupplierProfileModel supplier) onOpenChat;
  final Future<void> Function(SupplierProfileModel supplier) onCall;

  @override
  State<_SupplierMapFullscreenScreen> createState() =>
      _SupplierMapFullscreenScreenState();
}

class _SupplierMapFullscreenScreenState
    extends State<_SupplierMapFullscreenScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _controller;
  late final AnimationController _pulse;
  SupplierProfileModel? _selected;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitContent());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _fitContent() {
    final pts = widget.points.map((e) => e.point).toList();
    if (widget.userPoint != null) pts.add(widget.userPoint!);
    if (pts.isEmpty) return;
    try {
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(54),
        ),
      );
    } catch (_) {}
  }

  bool _isAvailable(SupplierProfileModel supplier) =>
      supplier.products.any((p) => p.isAvailable);

  Widget _buildTekisaPin({required bool available}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = 1 + (_pulse.value * 0.22);
        return Stack(
          alignment: Alignment.center,
          children: [
            if (available)
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.18),
                  ),
                ),
              ),
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: available ? Colors.green : const Color(0xFF035D8A),
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 9,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/tekisa_logo.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.userPoint ?? widget.points.first.point;
    final markers = widget.points
        .map(
          (mp) => Marker(
            point: mp.point,
            width: 66,
            height: 66,
            child: GestureDetector(
              onTap: () => setState(() => _selected = mp.supplier),
              child: _buildTekisaPin(available: _isAvailable(mp.supplier)),
            ),
          ),
        )
        .toList();
    if (widget.userPoint != null) {
      markers.add(
        Marker(
          point: widget.userPoint!,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte fournisseurs'),
        actions: [
          IconButton(
            onPressed: _fitContent,
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'Recentrer',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
              onTap: (_, point) => setState(() => _selected = null),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.tekisa.cisnetkids',
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              if (widget.userPoint != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: widget.userPoint!,
                      radius: 58,
                      useRadiusInMeter: true,
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderColor: Colors.blueAccent.withValues(alpha: 0.40),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${widget.points.length} fournisseurs sur la carte',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (_selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: _SupplierMapBottomCard(
                  supplier: _selected!,
                  onOpenChat: widget.onOpenChat,
                  onCall: widget.onCall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierMapBottomCard extends StatelessWidget {
  const _SupplierMapBottomCard({
    required this.supplier,
    required this.onOpenChat,
    required this.onCall,
  });

  final SupplierProfileModel supplier;
  final Future<void> Function(SupplierProfileModel supplier) onOpenChat;
  final Future<void> Function(SupplierProfileModel supplier) onCall;

  @override
  Widget build(BuildContext context) {
    final availableProducts = supplier.products
        .where((p) => p.isAvailable)
        .toList();
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    supplier.businessName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: availableProducts.isNotEmpty
                        ? Colors.green.withValues(alpha: 0.14)
                        : Colors.orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    availableProducts.isNotEmpty ? 'Disponible' : 'Rupture',
                    style: TextStyle(
                      color: availableProducts.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${supplier.commune}${supplier.quarter.isEmpty ? '' : ' • ${supplier.quarter}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Produits disponibles (${availableProducts.length})',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: availableProducts.take(6).map((p) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    p.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onOpenChat(supplier),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Chat'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onCall(supplier),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Appeler'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
