import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/datasources/auth_remote_datasource.dart';
import '../config/env_config.dart';
import '../network/dio_client.dart';
import 'in_app_notification_service.dart';

/// Point d'entree notifications — in-app gratuit par defaut (sans Firebase).
///
/// FCM reste optionnel : ajouter `firebase_messaging` + `google-services.json`.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;

  Future<void> init({required Future<String?> Function() accessToken}) async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    await InAppNotificationService.instance.init(accessToken: accessToken);
    debugPrint('[TEKISA] PushNotificationService pret (in-app gratuit).');
  }

  Future<void> registerDevice({
    required String token,
    required Future<String?> Function() accessToken,
  }) async {
    final access = await accessToken();
    if (access == null || access.isEmpty || access.startsWith('local_')) {
      return;
    }
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
        ? 'android'
        : 'web';
    final client = DioClient(baseUrl: EnvConfig.apiBaseUrl, accessToken: access);
    final remote = AuthRemoteDataSource(client);
    await remote.registerPushDevice(token: token, platform: platform);
  }
}
