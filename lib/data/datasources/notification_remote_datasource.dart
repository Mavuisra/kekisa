import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/network/dio_client.dart';
import '../models/in_app_notification_model.dart';

class NotificationRemoteDataSource {
  NotificationRemoteDataSource(this._client);

  final DioClient _client;

  Future<List<InAppNotificationModel>> fetchNotifications({int limit = 25}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.inAppNotifications,
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data == null) return [];
      final results = data['results'];
      if (results is List) {
        return results
            .map(
              (e) => InAppNotificationModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
      if (data is List) {
        return (data as List)
            .map(
              (e) => InAppNotificationModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }

  Future<int> fetchUnreadCount() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.inAppNotificationsUnreadCount,
      );
      return (response.data?['count'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }
}
