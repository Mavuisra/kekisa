library;

import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/network/dio_client.dart';
import '../../core/offline/sqlite_cache_service.dart';
import '../../core/offline/tenant_context.dart';
import '../models/commerce_models.dart';

class CommerceRemoteDataSource {
  CommerceRemoteDataSource(this._client);

  final DioClient _client;
  final SqliteCacheService _cache = SqliteCacheService();
  static const _productsCacheKey = 'commerce/products';
  static const _stockOverviewCacheKey = 'commerce/stock/overview';
  static const _customersSummaryCacheKey = 'commerce/customers/summary';
  static const _customersListCacheKey = 'commerce/customers/list';
  static const _salesSummaryCacheKey = 'commerce/sales/summary';
  static const _saleReceiptCacheBase = 'commerce/sales/receipt';
  static const _insightsCacheKey = 'commerce/insights';
  static const _supplierProfileCacheKey = 'commerce/suppliers/my-profile';
  static const _supplierProductsCacheKey = 'commerce/suppliers/my-products';

  List<dynamic> _extractList(dynamic data) {
    if (data == null) return const [];
    if (data is List<dynamic>) return data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final results = map['results'];
      if (results is List<dynamic>) return results;
    }
    throw UnknownException('Format de réponse inattendu: liste attendue.');
  }

  TenantContext _tenant() {
    final tenant = TenantContext.current();
    if (tenant == null) {
      throw UnknownException('Aucun tenant actif.');
    }
    return tenant;
  }

  String _cacheKey(String base, [Map<String, dynamic>? query]) {
    if (query == null || query.isEmpty) {
      return base;
    }
    final entries = query.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final encoded = entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$base?$encoded';
  }

  String _saleReceiptCacheKey(int saleId) => '$_saleReceiptCacheBase/$saleId';

  Future<List<Map<String, dynamic>>?> _readCachedList(String key) async {
    final tenant = _tenant();
    final cached = await _cache.read(
      tenantId: tenant.tenantId,
      resourceKey: key,
    );
    if (cached is! List) {
      return null;
    }
    return cached
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>?> _readCachedMap(String key) async {
    final tenant = _tenant();
    final cached = await _cache.read(
      tenantId: tenant.tenantId,
      resourceKey: key,
    );
    if (cached is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(cached);
  }

  Future<void> _saveCache(String key, Object payload) async {
    final tenant = _tenant();
    await _cache.save(
      tenantId: tenant.tenantId,
      resourceKey: key,
      payload: payload,
    );
  }

  int _offlineId() {
    final seed = DateTime.now().millisecondsSinceEpoch;
    return -max(seed % 1000000000, 1);
  }

  Future<List<CommerceProductModel>> getProducts() async {
    const key = _productsCacheKey;
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceProducts,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(CommerceProductModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(CommerceProductModel.fromJson).toList();
      }
      await _saveCache(key, const <Map<String, dynamic>>[]);
      return const <CommerceProductModel>[];
    }
  }

  Future<void> createProduct({
    required String name,
    required String sku,
    required double unitPrice,
    double? costPrice,
    required int stockQuantity,
    required int reorderThreshold,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'sku': sku,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'stock_quantity': stockQuantity,
      'reorder_threshold': reorderThreshold,
      'is_active': true,
    }..removeWhere((_, value) => value == null);

    try {
      await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceProducts,
        data: payload,
      );
      await _invalidateProductCache();
    } on QueuedForSyncException {
      await _appendOfflineProduct(
        name: name,
        sku: sku,
        unitPrice: unitPrice,
        costPrice: costPrice ?? 0,
        stockQuantity: stockQuantity,
        reorderThreshold: reorderThreshold,
      );
    }
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required String sku,
    required double unitPrice,
    double? costPrice,
    required int stockQuantity,
    required int reorderThreshold,
    bool isActive = true,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'sku': sku,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'stock_quantity': stockQuantity,
      'reorder_threshold': reorderThreshold,
      'is_active': isActive,
    }..removeWhere((_, value) => value == null);
    final path = '${ApiEndpoints.commerceProducts}$productId/';
    try {
      await _client.put<Map<String, dynamic>>(path, data: payload);
      await _applyOfflineProductUpdate(
        productId: productId,
        name: name,
        sku: sku,
        unitPrice: unitPrice,
        costPrice: costPrice ?? 0,
        stockQuantity: stockQuantity,
        reorderThreshold: reorderThreshold,
        isActive: isActive,
      );
    } on QueuedForSyncException {
      await _applyOfflineProductUpdate(
        productId: productId,
        name: name,
        sku: sku,
        unitPrice: unitPrice,
        costPrice: costPrice ?? 0,
        stockQuantity: stockQuantity,
        reorderThreshold: reorderThreshold,
        isActive: isActive,
      );
    }
  }

  Future<void> deleteProduct({required int productId}) async {
    final path = '${ApiEndpoints.commerceProducts}$productId/';
    try {
      await _client.delete<void>(path);
      await _applyOfflineProductDelete(productId: productId);
    } on QueuedForSyncException {
      await _applyOfflineProductDelete(productId: productId);
    }
  }

  Future<void> _invalidateProductCache() async {
    const key = _productsCacheKey;
    final cached = await _readCachedList(key);
    if (cached == null) {
      return;
    }
    await _saveCache(key, cached);
  }

  Future<void> _appendOfflineProduct({
    required String name,
    required String sku,
    required double unitPrice,
    required double costPrice,
    required int stockQuantity,
    required int reorderThreshold,
  }) async {
    const productsKey = _productsCacheKey;
    const overviewKey = _stockOverviewCacheKey;

    final products =
        (await _readCachedList(productsKey) ?? <Map<String, dynamic>>[])
            .toList();
    final id = _offlineId();
    products.insert(0, {
      'id': id,
      'name': name,
      'sku': sku,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'stock_quantity': stockQuantity,
      'reorder_threshold': reorderThreshold,
      'is_active': true,
    });
    await _saveCache(productsKey, products);

    final overview =
        (await _readCachedList(overviewKey) ?? <Map<String, dynamic>>[])
            .toList();
    overview.insert(0, {
      'id': id,
      'name': name,
      'sku': sku,
      'stock_quantity': stockQuantity,
      'reorder_threshold': reorderThreshold,
      'is_critical': stockQuantity <= reorderThreshold,
      'velocity': 'stable',
      'last_stock_add_at': DateTime.now().toUtc().toIso8601String(),
      'last_stock_add_by': 'offline',
      'last_stock_add_qty': stockQuantity,
    });
    await _saveCache(overviewKey, overview);
  }

  Future<void> _applyOfflineProductUpdate({
    required int productId,
    required String name,
    required String sku,
    required double unitPrice,
    required double costPrice,
    required int stockQuantity,
    required int reorderThreshold,
    required bool isActive,
  }) async {
    const productsKey = _productsCacheKey;
    const overviewKey = _stockOverviewCacheKey;
    final products = await _readCachedList(productsKey);
    if (products != null) {
      final updatedProducts = products.map((row) {
        final copy = Map<String, dynamic>.from(row);
        final id = (copy['id'] as num?)?.toInt() ?? 0;
        if (id == productId) {
          copy['name'] = name;
          copy['sku'] = sku;
          copy['unit_price'] = unitPrice;
          copy['cost_price'] = costPrice;
          copy['stock_quantity'] = stockQuantity;
          copy['reorder_threshold'] = reorderThreshold;
          copy['is_active'] = isActive;
        }
        return copy;
      }).toList();
      await _saveCache(productsKey, updatedProducts);
    }

    final overview = await _readCachedList(overviewKey);
    if (overview != null) {
      final updatedOverview = overview.map((row) {
        final copy = Map<String, dynamic>.from(row);
        final id = (copy['id'] as num?)?.toInt() ?? 0;
        if (id == productId) {
          copy['name'] = name;
          copy['sku'] = sku;
          copy['stock_quantity'] = stockQuantity;
          copy['reorder_threshold'] = reorderThreshold;
          copy['is_critical'] = stockQuantity <= reorderThreshold;
          copy['velocity'] = stockQuantity <= reorderThreshold
              ? 'critical'
              : 'stable';
        }
        return copy;
      }).toList();
      await _saveCache(overviewKey, updatedOverview);
    }
  }

  Future<void> _applyOfflineProductDelete({required int productId}) async {
    const productsKey = _productsCacheKey;
    const overviewKey = _stockOverviewCacheKey;
    final products = await _readCachedList(productsKey);
    if (products != null) {
      final next = products.where((row) {
        final id = (row['id'] as num?)?.toInt() ?? 0;
        return id != productId;
      }).toList();
      await _saveCache(productsKey, next);
    }
    final overview = await _readCachedList(overviewKey);
    if (overview != null) {
      final next = overview.where((row) {
        final id = (row['id'] as num?)?.toInt() ?? 0;
        return id != productId;
      }).toList();
      await _saveCache(overviewKey, next);
    }
  }

  Future<Map<String, dynamic>> addStock({
    required int productId,
    required int quantity,
    String reason = '',
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceStockAdd,
        data: {
          'product_id': productId,
          'quantity': quantity,
          if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        },
      );
      return response.data ?? const <String, dynamic>{};
    } on QueuedForSyncException {
      await _applyOfflineStockAdd(
        productId: productId,
        quantity: quantity,
        reason: reason,
      );
      return {
        'queued': true,
        'message': 'Ajout de stock en attente de synchronisation',
      };
    }
  }

  Future<List<StockMovementTraceModel>> getStockMovements({
    int? productId,
    String? date,
    String? addedBy,
  }) async {
    final query = <String, dynamic>{};
    if (productId != null) {
      query['product_id'] = productId;
    }
    if (date?.isNotEmpty ?? false) {
      query['date'] = date;
    }
    final trimmedUser = addedBy?.trim();
    if (trimmedUser?.isNotEmpty ?? false) {
      query['added_by'] = trimmedUser;
    }
    final key = _cacheKey('commerce/stock/movements', query);
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceStockMovements,
        queryParameters: query.isEmpty ? null : query,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(StockMovementTraceModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(StockMovementTraceModel.fromJson).toList();
      }
      return const <StockMovementTraceModel>[];
    }
  }

  Future<List<StockOverviewItemModel>> getStockOverview() async {
    const key = _stockOverviewCacheKey;
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceStockOverview,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(StockOverviewItemModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(StockOverviewItemModel.fromJson).toList();
      }
      final products = await getProducts();
      final generated = _stockRowsFromProductModels(products);
      await _saveCache(key, generated);
      return generated.map(StockOverviewItemModel.fromJson).toList();
    }
  }

  Future<List<CustomerSummaryModel>> getCustomersSummary() async {
    const key = _customersSummaryCacheKey;
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceCustomersSummary,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(CustomerSummaryModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(CustomerSummaryModel.fromJson).toList();
      }
      await _saveCache(key, const <Map<String, dynamic>>[]);
      return const <CustomerSummaryModel>[];
    }
  }

  Future<List<CommerceCustomerModel>> getCustomers() async {
    const key = _customersListCacheKey;
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceCustomers,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(CommerceCustomerModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(CommerceCustomerModel.fromJson).toList();
      }
      await _saveCache(key, const <Map<String, dynamic>>[]);
      return const <CommerceCustomerModel>[];
    }
  }

  Future<SupplierProfileModel?> getMySupplierProfile() async {
    const key = _supplierProfileCacheKey;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.commerceSupplierMyProfile,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final profilePayload = data.containsKey('profile')
          ? data['profile']
          : data;
      if (profilePayload == null ||
          (profilePayload is Map && profilePayload.isEmpty)) {
        await _saveCache(key, <String, dynamic>{'profile': null});
        return null;
      }
      final map = Map<String, dynamic>.from(profilePayload as Map);
      await _saveCache(key, map);
      return SupplierProfileModel.fromJson(map);
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached == null || cached.isEmpty) return null;
      final profilePayload = cached['profile'];
      if (profilePayload == null && cached.containsKey('profile')) {
        return null;
      }
      return SupplierProfileModel.fromJson(cached);
    }
  }

  Future<SupplierProfileModel> saveMySupplierProfile({
    required String businessName,
    required String description,
    required String phone,
    required bool isActive,
    required String businessDomain,
    required String commune,
    required String quarter,
    required String avenue,
    required String profileImageUrl,
    required String coverImageUrl,
    required String supportWhatsapp,
    double? latitude,
    double? longitude,
  }) async {
    final payload = <String, dynamic>{
      'business_name': businessName,
      'description': description,
      'phone': phone,
      'is_active': isActive,
      'business_domain': businessDomain,
      'commune': commune,
      'quarter': quarter,
      'avenue': avenue,
      'profile_image_url': profileImageUrl,
      'cover_image_url': coverImageUrl,
      'support_whatsapp': supportWhatsapp,
      'latitude': latitude,
      'longitude': longitude,
    }..removeWhere((_, value) => value == null);
    try {
      final response = await _client.put<Map<String, dynamic>>(
        ApiEndpoints.commerceSupplierMyProfile,
        data: payload,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final map = Map<String, dynamic>.from(data);
      await _saveCache(_supplierProfileCacheKey, map);
      return SupplierProfileModel.fromJson(map);
    } on QueuedForSyncException {
      final cached = await _readCachedMap(_supplierProfileCacheKey);
      final tempId = (cached?['id'] as num?)?.toInt() ?? _offlineId();
      final tempUserId = (cached?['user_id'] as num?)?.toInt() ?? 0;
      final map = <String, dynamic>{
        'id': tempId,
        'user_id': tempUserId,
        'business_name': businessName,
        'description': description,
        'phone': phone,
        'is_active': isActive,
        'business_domain': businessDomain,
        'latitude': latitude,
        'longitude': longitude,
        'commune': commune,
        'quarter': quarter,
        'avenue': avenue,
        'profile_image_url': profileImageUrl,
        'cover_image_url': coverImageUrl,
        'support_whatsapp': supportWhatsapp,
        'products': cached?['products'] ?? const <Map<String, dynamic>>[],
      };
      await _saveCache(_supplierProfileCacheKey, map);
      return SupplierProfileModel.fromJson(map);
    }
  }

  Future<List<SupplierProductModel>> getMySupplierProducts() async {
    const key = _supplierProductsCacheKey;
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSupplierMyProducts,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(SupplierProductModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(SupplierProductModel.fromJson).toList();
      }
      return const <SupplierProductModel>[];
    }
  }

  Future<SupplierProductModel> createSupplierProduct({
    required int sourceProductId,
    double? price,
    required bool isAvailable,
    String imageUrl = '',
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceSupplierMyProducts,
        data: {
          'source_product_id': sourceProductId,
          'price': price,
          'is_available': isAvailable,
          'image_url': imageUrl,
        },
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final map = Map<String, dynamic>.from(data);
      final cached =
          (await _readCachedList(_supplierProductsCacheKey) ??
                  <Map<String, dynamic>>[])
              .toList();
      cached.insert(0, map);
      await _saveCache(_supplierProductsCacheKey, cached);
      return SupplierProductModel.fromJson(map);
    } on QueuedForSyncException {
      final map = <String, dynamic>{
        'id': _offlineId(),
        'source_product_id': sourceProductId,
        'name': 'Produit #$sourceProductId',
        'price': price ?? 0,
        'is_available': isAvailable,
        'image_url': imageUrl,
        'stock_quantity': 0,
      };
      final cached =
          (await _readCachedList(_supplierProductsCacheKey) ??
                  <Map<String, dynamic>>[])
              .toList();
      cached.insert(0, map);
      await _saveCache(_supplierProductsCacheKey, cached);
      return SupplierProductModel.fromJson(map);
    }
  }

  Future<List<SupplierProfileModel>> getNearbySuppliers({
    double? latitude,
    double? longitude,
    String? productName,
    String? commune,
    String? businessDomain,
  }) async {
    final query = <String, dynamic>{};
    if (latitude != null && longitude != null) {
      query['lat'] = latitude;
      query['lng'] = longitude;
    }
    if (productName?.trim().isNotEmpty ?? false) {
      query['product_name'] = productName!.trim();
    }
    if (commune?.trim().isNotEmpty ?? false) {
      query['commune'] = commune!.trim();
    }
    if (businessDomain?.trim().isNotEmpty ?? false) {
      query['business_domain'] = businessDomain!.trim();
    }
    final key = _cacheKey('commerce/suppliers/nearby', query);
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSupplierNearby,
        queryParameters: query.isEmpty ? null : query,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(SupplierProfileModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(SupplierProfileModel.fromJson).toList();
      }
      return const <SupplierProfileModel>[];
    }
  }

  Future<List<SupplierProfileModel>> getSupplierMarketplace({
    String? query,
    String? commune,
    String? businessDomain,
  }) async {
    final params = <String, dynamic>{};
    if (query?.trim().isNotEmpty ?? false) params['q'] = query!.trim();
    if (commune?.trim().isNotEmpty ?? false) params['commune'] = commune!.trim();
    if (businessDomain?.trim().isNotEmpty ?? false) {
      params['business_domain'] = businessDomain!.trim();
    }
    final key = _cacheKey('commerce/suppliers/marketplace', params);
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSupplierMarketplace,
        queryParameters: params.isEmpty ? null : params,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(SupplierProfileModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(SupplierProfileModel.fromJson).toList();
      }
      return const <SupplierProfileModel>[];
    }
  }

  Future<List<Map<String, dynamic>>> getKinshasaLocations() async {
    const key = 'commerce/suppliers/kinshasa-locations';
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSupplierKinshasaLocations,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows;
    } catch (_) {
      return (await _readCachedList(key) ?? <Map<String, dynamic>>[]);
    }
  }

  Future<SupplierConversationModel> createSupplierConversation({
    required int supplierId,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierConversations,
      data: {'supplier_id': supplierId},
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return SupplierConversationModel.fromJson(data);
  }

  Future<List<SupplierConversationModel>> getSupplierConversations() async {
    final response = await _client.get<dynamic>(
      ApiEndpoints.commerceSupplierConversations,
    );
    final rows = _extractList(response.data);
    return rows
        .map(
          (e) => SupplierConversationModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<List<SupplierMessageModel>> getSupplierMessages({
    required int conversationId,
  }) async {
    final response = await _client.get<dynamic>(
      ApiEndpoints.commerceSupplierConversationMessages(conversationId),
    );
    final rows = _extractList(response.data);
    return rows
        .map(
          (e) => SupplierMessageModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  Future<SupplierMessageModel> sendSupplierMessage({
    required int conversationId,
    required String messageType,
    String content = '',
    String voiceUrl = '',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierConversationMessages(conversationId),
      data: {
        'message_type': messageType,
        'content': content,
        'voice_url': voiceUrl,
      },
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return SupplierMessageModel.fromJson(data);
  }

  Future<String> uploadSupplierImage({required String filePath}) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierUploadImage,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
      queueIfOffline: false,
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    final url = (data['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      throw UnknownException('URL image manquante.');
    }
    return url;
  }

  Future<String> uploadSupplierAudio({required String filePath}) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierUploadAudio,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
      queueIfOffline: false,
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    final url = (data['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      throw UnknownException('URL audio manquante.');
    }
    return url;
  }

  Future<String> uploadSupplierFile({required String filePath}) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierUploadFile,
      data: form,
      options: Options(contentType: 'multipart/form-data'),
      queueIfOffline: false,
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    final url = (data['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      throw UnknownException('URL fichier manquante.');
    }
    return url;
  }

  Future<Map<String, dynamic>> createSupplierQuickOrder({
    required int supplierProductId,
    int quantity = 1,
    String notes = '',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierQuickOrder,
      data: {
        'supplier_product_id': supplierProductId,
        'quantity': quantity,
        'notes': notes,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<SupplierOrderModel> createSupplierOrder({
    required int supplierId,
    required List<SupplierOrderItemInput> items,
    String notes = '',
    String deliveryCommune = '',
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierOrders,
      data: {
        'supplier_id': supplierId,
        'items': items.map((e) => e.toJson()).toList(),
        'notes': notes,
        'delivery_commune': deliveryCommune,
      },
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return SupplierOrderModel.fromJson(data);
  }

  Future<List<SupplierOrderModel>> getSupplierOrders({
    String scope = 'all',
  }) async {
    final key = _cacheKey('commerce/suppliers/orders', {'scope': scope});
    // Evite les 401 inutiles quand la session locale offline
    // n'a pas de token JWT valide pour le backend.
    if (!_client.hasRemoteAuthToken) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(SupplierOrderModel.fromJson).toList();
      }
      return const <SupplierOrderModel>[];
    }
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSupplierOrders,
        queryParameters: {'scope': scope},
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(SupplierOrderModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(SupplierOrderModel.fromJson).toList();
      }
      return const <SupplierOrderModel>[];
    }
  }

  Future<SupplierOrderModel> updateSupplierOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierOrderStatus(orderId),
      data: {'status': status},
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return SupplierOrderModel.fromJson(data);
  }

  Future<Map<String, dynamic>> startSupplierCall({
    required int supplierId,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierCallStart,
      data: {'supplier_id': supplierId},
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> endSupplierCall({required int sessionId}) async {
    await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSupplierCallEnd,
      data: {'session_id': sessionId},
    );
  }

  Future<CommerceCustomerModel> createCustomer({
    required String fullName,
    String phone = '',
    String email = '',
    String segment = 'regular',
    String notes = '',
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceCustomers,
        data: {
          'full_name': fullName,
          'phone': phone,
          'email': email,
          'segment': segment,
          'notes': notes,
        },
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      return CommerceCustomerModel.fromJson(data);
    } on QueuedForSyncException {
      final temp = CommerceCustomerModel(
        id: _offlineId(),
        fullName: fullName,
        phone: phone,
        email: email,
        segment: segment,
        notes: notes,
      );
      await _appendOfflineCustomer(temp);
      return temp;
    }
  }

  Future<CommerceInsightsModel> getInsights() async {
    const key = _insightsCacheKey;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.commerceInsights,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      await _saveCache(key, data);
      return CommerceInsightsModel.fromJson(data);
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached != null) {
        return CommerceInsightsModel.fromJson(cached);
      }
      final now = DateTime.now();
      final fallback = {
        'weekly_revenue': List.generate(7, (index) {
          final d = now.subtract(Duration(days: 6 - index));
          final day =
              '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          return {'date': day, 'revenue': 0};
        }),
        'top_products': const <Map<String, dynamic>>[],
        'decisions': const <Map<String, dynamic>>[
          {
            'title': 'Mode hors ligne actif',
            'subtitle':
                'Vos données sont conservées en local. Elles seront synchronisées automatiquement dès le retour d\'Internet.',
          },
        ],
      };
      await _saveCache(key, fallback);
      return CommerceInsightsModel.fromJson(fallback);
    }
  }

  Future<Map<String, dynamic>> getAccountingReports({int days = 30}) async {
    final key = _cacheKey('commerce/accounting/reports', {'days': days});
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.commerceAccountingReports,
        queryParameters: {'days': days},
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      await _saveCache(key, data);
      return data;
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached != null) {
        return cached;
      }
      final fallback = <String, dynamic>{
        'kpis': {
          'gross_sales': 0,
          'discounts': 0,
          'net_sales': 0,
          'cogs': 0,
          'net_result': 0,
        },
        'income_statement': {
          'net_sales': 0,
          'cost_of_goods_sold': 0,
          'gross_profit': 0,
          'operating_expenses': 0,
          'net_result': 0,
        },
        'balance_sheet': {
          'assets': {'cash': 0, 'inventory': 0, 'receivables': 0},
          'liabilities': {'payables': 0},
          'equity': {'retained_earnings': 0},
        },
        'cashflow': {
          'operating_inflows': 0,
          'operating_outflows': 0,
          'net_operating_cashflow': 0,
          'investing_cashflow': 0,
          'financing_cashflow': 0,
          'net_cashflow': 0,
        },
        'trial_balance': const <Map<String, dynamic>>[],
        'journal': const <Map<String, dynamic>>[],
      };
      await _saveCache(key, fallback);
      return fallback;
    }
  }

  Future<SalesSummaryModel> getSalesSummary() async {
    const key = _salesSummaryCacheKey;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.commerceSalesSummary,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      await _saveCache(key, data);
      return SalesSummaryModel.fromJson(data);
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached != null) {
        return SalesSummaryModel.fromJson(cached);
      }
      const fallback = {
        'today_revenue': 0,
        'transactions': 0,
        'average_ticket': 0,
      };
      await _saveCache(key, fallback);
      return SalesSummaryModel.fromJson(fallback);
    }
  }

  Future<AiSaleDraftModel> getAiSaleDraft({required String prompt}) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.commerceSalesAiDraft,
      data: {'prompt': prompt},
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return AiSaleDraftModel.fromJson(data);
  }

  Future<List<QuickSaleHistoryItemModel>> getSalesList({String? date}) async {
    final query = date != null && date.isNotEmpty
        ? {'date': date}
        : const <String, dynamic>{};
    final key = _cacheKey('commerce/sales/list', query);
    try {
      final response = await _client.get<dynamic>(
        ApiEndpoints.commerceSalesList,
        queryParameters: query.isEmpty ? null : query,
      );
      final rows = _extractList(
        response.data,
      ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _saveCache(key, rows);
      return rows.map(QuickSaleHistoryItemModel.fromJson).toList();
    } catch (_) {
      final cached = await _readCachedList(key);
      if (cached != null) {
        return cached.map(QuickSaleHistoryItemModel.fromJson).toList();
      }
      rethrow;
    }
  }

  Future<QuickSaleReceiptModel> getSaleReceipt({
    required int saleId,
    QuickSaleHistoryItemModel? summary,
  }) async {
    final key = _saleReceiptCacheKey(saleId);
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.commerceSaleDetail(saleId),
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      await _saveCache(key, data);
      return QuickSaleReceiptModel.fromJson(data);
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached != null) {
        return QuickSaleReceiptModel.fromJson(cached);
      }
      if (summary != null) {
        return QuickSaleReceiptModel(
          id: summary.id,
          subtotal: summary.subtotal,
          discountAmount: summary.discountAmount,
          total: summary.total,
          paymentMethod: summary.paymentMethod,
          status: summary.status,
          createdAt: '${summary.date}T${summary.time}:00',
          items: const [],
          customerName: summary.customerName,
          cancelReason: summary.cancelReason,
          canceledAt: summary.canceledAt,
        );
      }
      throw UnknownException('Détails de vente indisponibles hors ligne.');
    }
  }

  Future<QuickSaleReceiptModel> cancelSale({
    required int saleId,
    required String reason,
    String? saleDate,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw UnknownException('Motif d\'annulation obligatoire.');
    }
    final key = _saleReceiptCacheKey(saleId);
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceSaleCancel(saleId),
        data: {'reason': cleanReason},
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final payload = data['receipt'] is Map
          ? Map<String, dynamic>.from(data['receipt'] as Map)
          : Map<String, dynamic>.from(data);
      payload.putIfAbsent('status', () => 'cancelled');
      payload.putIfAbsent('cancel_reason', () => cleanReason);
      payload.putIfAbsent(
        'canceled_at',
        () => DateTime.now().toUtc().toIso8601String(),
      );
      await _saveCache(key, payload);
      await _updateCachedSaleStatus(
        saleId: saleId,
        saleDate: saleDate,
        status: payload['status'] as String? ?? 'cancelled',
        cancelReason: payload['cancel_reason'] as String? ?? cleanReason,
        canceledAt: payload['canceled_at'] as String?,
      );
      return QuickSaleReceiptModel.fromJson(payload);
    } catch (_) {
      final cached = await _readCachedMap(key);
      if (cached == null) {
        throw UnknownException(
          'Impossible d\'annuler hors ligne sans détails de vente en cache.',
        );
      }
      cached['status'] = 'cancelled';
      cached['cancel_reason'] = cleanReason;
      cached['canceled_at'] = DateTime.now().toUtc().toIso8601String();
      await _saveCache(key, cached);
      await _updateCachedSaleStatus(
        saleId: saleId,
        saleDate: saleDate,
        status: 'cancelled',
        cancelReason: cleanReason,
        canceledAt: cached['canceled_at'] as String?,
      );
      return QuickSaleReceiptModel.fromJson(cached);
    }
  }

  Future<ReceiptVerificationModel> verifyReceipt({
    String? reference,
    String? payload,
  }) async {
    final query = <String, dynamic>{
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
      if (payload != null && payload.trim().isNotEmpty)
        'payload': payload.trim(),
    };
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.commerceReceiptVerify,
      queryParameters: query.isEmpty ? null : query,
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return ReceiptVerificationModel.fromJson(data);
  }

  Future<QuickSaleReceiptModel> createQuickSale({
    required List<CartItemInput> items,
    required String paymentMethod,
    double discountRate = 0,
    String customerName = '',
  }) async {
    final payload = {
      'items': items.map((e) => e.toJson()).toList(),
      'discount_rate': discountRate,
      'payment_method': paymentMethod,
      if (customerName.trim().isNotEmpty) 'customer_name': customerName.trim(),
    };
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.commerceQuickSale,
        data: payload,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final receiptData = Map<String, dynamic>.from(data);
      if ((receiptData['customer_name'] as String? ?? '').trim().isEmpty &&
          customerName.trim().isNotEmpty) {
        receiptData['customer_name'] = customerName.trim();
      }
      final idValue = receiptData['id'];
      final saleId = idValue is num
          ? idValue.toInt()
          : int.tryParse('$idValue') ?? 0;
      if (saleId > 0) {
        await _saveCache(_saleReceiptCacheKey(saleId), receiptData);
      }
      return QuickSaleReceiptModel.fromJson(receiptData);
    } on QueuedForSyncException {
      final receipt = await _buildOfflineReceipt(
        items: items,
        paymentMethod: paymentMethod,
        customerName: customerName,
      );
      await _appendOfflineSale(receipt, customerName: customerName);
      await _applyOfflineSaleStock(items);
      return receipt;
    }
  }

  Future<AdminPlatformOverviewModel> getAdminPlatformOverview() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.commerceAdminOverview,
    );
    final data = response.data;
    if (data == null) throw UnknownException('Réponse vide');
    return AdminPlatformOverviewModel.fromJson(data);
  }

  Future<List<SellerActivityModel>> getAdminSellersActivity() async {
    final response = await _client.get<dynamic>(
      ApiEndpoints.commerceAdminSellersActivity,
    );
    final rows = _extractList(response.data);
    return rows
        .map(
          (e) =>
              SellerActivityModel.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> _applyOfflineStockAdd({
    required int productId,
    required int quantity,
    required String reason,
  }) async {
    const overviewKey = _stockOverviewCacheKey;
    final overview = await _readCachedList(overviewKey);
    if (overview != null) {
      final updated = overview.map((row) {
        final copy = Map<String, dynamic>.from(row);
        if (copy['id'] == productId) {
          final stock = (copy['stock_quantity'] as num?)?.toInt() ?? 0;
          copy['stock_quantity'] = stock + quantity;
          final threshold = (copy['reorder_threshold'] as num?)?.toInt() ?? 0;
          copy['is_critical'] = (stock + quantity) <= threshold;
          copy['last_stock_add_qty'] = quantity;
          copy['last_stock_add_at'] = DateTime.now().toUtc().toIso8601String();
          copy['last_stock_add_by'] = 'offline';
        }
        return copy;
      }).toList();
      await _saveCache(overviewKey, updated);
    }
  }

  Future<void> _appendOfflineCustomer(CommerceCustomerModel customer) async {
    const listKey = _customersListCacheKey;
    const summaryKey = _customersSummaryCacheKey;
    final list = (await _readCachedList(listKey) ?? <Map<String, dynamic>>[])
        .toList();
    list.insert(0, {
      'id': customer.id,
      'full_name': customer.fullName,
      'phone': customer.phone,
      'email': customer.email,
      'segment': customer.segment,
      'notes': customer.notes,
    });
    await _saveCache(listKey, list);

    final summary =
        (await _readCachedList(summaryKey) ?? <Map<String, dynamic>>[])
            .toList();
    summary.insert(0, {
      'id': customer.id,
      'full_name': customer.fullName,
      'phone': customer.phone,
      'segment': customer.segment,
      'sales_count': 0,
      'total_spent': 0,
      'last_purchase_at': null,
    });
    await _saveCache(summaryKey, summary);
  }

  Future<QuickSaleReceiptModel> _buildOfflineReceipt({
    required List<CartItemInput> items,
    required String paymentMethod,
    required String customerName,
  }) async {
    final products = await getProducts();
    final productById = {for (final p in products) p.id: p};

    var subtotal = 0.0;
    final receiptItems = <QuickSaleReceiptItemModel>[];
    var idx = 0;
    for (final item in items) {
      idx += 1;
      final product = productById[item.productId];
      final unitPrice = product?.unitPrice ?? 0.0;
      final lineTotal = unitPrice * item.quantity;
      subtotal += lineTotal;
      receiptItems.add(
        QuickSaleReceiptItemModel(
          id: _offlineId() - idx,
          productId: item.productId,
          productName: product?.name ?? 'Article #${item.productId}',
          quantity: item.quantity,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        ),
      );
    }

    return QuickSaleReceiptModel(
      id: _offlineId(),
      subtotal: subtotal,
      discountAmount: 0,
      total: subtotal,
      paymentMethod: paymentMethod,
      status: 'queued_offline',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      items: receiptItems,
      customerName: customerName,
    );
  }

  Future<void> _appendOfflineSale(
    QuickSaleReceiptModel receipt, {
    required String customerName,
  }) async {
    final dateKey = _cacheKey('commerce/sales/list', {
      'date': DateTime.now().toIso8601String().substring(0, 10),
    });
    final sales = (await _readCachedList(dateKey) ?? <Map<String, dynamic>>[])
        .toList();
    sales.insert(0, {
      'id': receipt.id,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'time': DateTime.now().toIso8601String().substring(11, 16),
      'customer_name': customerName,
      'payment_method': receipt.paymentMethod,
      'items_count': receipt.items.fold<int>(0, (sum, e) => sum + e.quantity),
      'subtotal': receipt.subtotal,
      'discount_amount': receipt.discountAmount,
      'total': receipt.total,
      'status': receipt.status,
      if (receipt.cancelReason != null) 'cancel_reason': receipt.cancelReason,
      if (receipt.canceledAt != null) 'canceled_at': receipt.canceledAt,
    });
    await _saveCache(dateKey, sales);
    await _saveCache(_saleReceiptCacheKey(receipt.id), {
      'id': receipt.id,
      'subtotal': receipt.subtotal,
      'discount_amount': receipt.discountAmount,
      'total': receipt.total,
      'payment_method': receipt.paymentMethod,
      'status': receipt.status,
      'created_at': receipt.createdAt,
      'customer_name': customerName,
      'items': receipt.items
          .map(
            (it) => {
              'id': it.id,
              'product': it.productId,
              'product_name': it.productName,
              'quantity': it.quantity,
              'unit_price': it.unitPrice,
              'line_total': it.lineTotal,
            },
          )
          .toList(),
      if (receipt.cancelReason != null) 'cancel_reason': receipt.cancelReason,
      if (receipt.canceledAt != null) 'canceled_at': receipt.canceledAt,
    });
  }

  Future<void> _updateCachedSaleStatus({
    required int saleId,
    String? saleDate,
    required String status,
    required String cancelReason,
    String? canceledAt,
  }) async {
    if (saleDate == null || saleDate.trim().isEmpty) return;
    final listKey = _cacheKey('commerce/sales/list', {'date': saleDate});
    final rows = await _readCachedList(listKey);
    if (rows == null) return;
    final updated = rows.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final idValue = copy['id'];
      final currentId = idValue is num
          ? idValue.toInt()
          : int.tryParse('$idValue') ?? 0;
      if (currentId == saleId) {
        copy['status'] = status;
        copy['cancel_reason'] = cancelReason;
        copy['canceled_at'] =
            canceledAt ?? DateTime.now().toUtc().toIso8601String();
      }
      return copy;
    }).toList();
    await _saveCache(listKey, updated);
  }

  Future<void> _applyOfflineSaleStock(List<CartItemInput> items) async {
    const overviewKey = _stockOverviewCacheKey;
    final overview = await _readCachedList(overviewKey);
    if (overview == null) {
      return;
    }
    final quantityByProduct = <int, int>{};
    for (final item in items) {
      quantityByProduct.update(
        item.productId,
        (v) => v + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    final updated = overview.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final id = (copy['id'] as num?)?.toInt();
      final sold = id == null ? 0 : (quantityByProduct[id] ?? 0);
      if (sold > 0) {
        final current = (copy['stock_quantity'] as num?)?.toInt() ?? 0;
        final next = max(0, current - sold);
        final threshold = (copy['reorder_threshold'] as num?)?.toInt() ?? 0;
        copy['stock_quantity'] = next;
        copy['is_critical'] = next <= threshold;
      }
      return copy;
    }).toList();
    await _saveCache(overviewKey, updated);
  }

  List<Map<String, dynamic>> _stockRowsFromProductModels(
    List<CommerceProductModel> products,
  ) {
    return products
        .map(
          (p) => {
            'id': p.id,
            'name': p.name,
            'sku': p.sku,
            'stock_quantity': p.stockQuantity,
            'reorder_threshold': p.reorderThreshold,
            'is_critical': p.stockQuantity <= p.reorderThreshold,
            'velocity': p.stockQuantity <= p.reorderThreshold
                ? 'critical'
                : 'stable',
            'last_stock_add_at': DateTime.now().toUtc().toIso8601String(),
            'last_stock_add_by': 'local_seed',
            'last_stock_add_qty': p.stockQuantity,
          },
        )
        .toList();
  }

  Future<Uint8List> downloadSalesExport({String? date}) async {
    final response = await _client.get<List<int>>(
      ApiEndpoints.commerceSalesExport,
      queryParameters: date == null ? null : {'date': date},
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw UnknownException('Export ventes vide.');
    }
    return Uint8List.fromList(data);
  }

  Future<Uint8List> downloadStockExport() async {
    final response = await _client.get<List<int>>(
      ApiEndpoints.commerceStockExport,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw UnknownException('Export stock vide.');
    }
    return Uint8List.fromList(data);
  }
}
