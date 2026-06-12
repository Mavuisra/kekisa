import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/datasources/auth_remote_datasource.dart';
import '../config/env_config.dart';
import '../network/dio_client.dart';

/// Scaffold notifications push — enregistre le token FCM côté API quand disponible.
///
/// Pour activer FCM : ajouter `google-services.json` / `GoogleService-Info.plist`,
/// puis brancher `firebase_messaging` dans `init()`.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;

  Future<void> init({required Future<String?> Function() accessToken}) async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    // Point d'extension FCM : récupérer le token et appeler registerDevice().
    debugPrint('[TEKISA] PushNotificationService pret (FCM a configurer).');
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
