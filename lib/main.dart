/// CisnetKids - Application parents : suivi scolaire, notes, présences, paiements, messages.
library;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/app.dart';
import 'core/constants/app_constants.dart';
import 'core/i18n/locale_controller.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/offline/local_sqlite.dart';
import 'core/offline/sync_orchestrator.dart';
import 'core/theme/theme_controller.dart';
import 'data/datasources/auth_local_datasource.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>(StorageKeys.userBox);
  await LocalSqlite.instance.init();
  await LocaleController.instance.init();
  await ThemeController.instance.init();
  await SyncOrchestrator.instance.start();
  final authLocal = AuthLocalDataSource();
  await PushNotificationService.instance.init(
    accessToken: authLocal.getAccessToken,
  );
  runApp(const CisnetKidsApp());
}
