import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/datasources/notification_remote_datasource.dart';
import '../config/env_config.dart';
import '../network/dio_client.dart';

/// Notifications gratuites sans Firebase : polling API + alertes locales.
class InAppNotificationService {
  InAppNotificationService._();

  static final InAppNotificationService instance = InAppNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Timer? _pollTimer;
  bool _initialized = false;
  int _lastSeenId = 0;
  bool _firstPoll = true;
  Future<String?> Function()? _accessToken;

  Future<void> init({required Future<String?> Function() accessToken}) async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _accessToken = accessToken;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (_) {},
    );

    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    await _pollOnce();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _pollOnce(),
    );
    debugPrint('[TEKISA] Notifications in-app actives (sans Firebase).');
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    final token = await _accessToken?.call();
    if (token == null || token.isEmpty || token.startsWith('local_')) {
      return;
    }
    try {
      final client = DioClient(baseUrl: EnvConfig.apiBaseUrl, accessToken: token);
      final remote = NotificationRemoteDataSource(client);
      final items = await remote.fetchNotifications(limit: 10);
      if (items.isEmpty) return;
      final maxId = items.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      if (_firstPoll) {
        _lastSeenId = maxId;
        _firstPoll = false;
        return;
      }
      for (final item in items) {
        if (item.id <= _lastSeenId || item.isRead) continue;
        await _showLocal(item.title, item.body);
      }
      if (maxId > _lastSeenId) _lastSeenId = maxId;
    } catch (e) {
      debugPrint('[TEKISA] Poll notifications: $e');
    }
  }

  Future<void> _showLocal(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tekisa_alerts',
        'Alertes Tekisa',
        channelDescription: 'Commandes, stock et messages Tekisa',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
