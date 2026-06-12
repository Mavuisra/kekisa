/// Source de données authentification (API REST)
library;

import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/network/dio_client.dart';
import '../models/auth_tokens_model.dart';
import '../models/user_model.dart';

/// Appels API : login, register, refresh
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final DioClient _client;

  /// POST {base}/users/auth/login/ (Django: username + password → access, refresh, user)
  Future<({AuthTokensModel tokens, UserModel? user})> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.login,
        data: {'username': username, 'password': password},
        queueIfOffline: false,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final tokens = AuthTokensModel.fromJson(
        data['tokens'] as Map<String, dynamic>? ??
            Map<String, dynamic>.from(data),
      );
      final userJson = data['user'];
      final user = userJson != null
          ? UserModel.fromJson(Map<String, dynamic>.from(userJson as Map))
          : null;
      return (tokens: tokens, user: user);
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur réseau');
    }
  }

  /// POST {base}/users/auth/register/ (Django: username, password, phone, full_name → access, refresh, user)
  Future<({AuthTokensModel tokens, UserModel? user})> register({
    required String username,
    required String password,
    required String phone,
    required String businessCategory,
    required String companyName,
    String companyTradeName = '',
    String legalForm = '',
    String rccm = '',
    String idnat = '',
    String nif = '',
    String companyEmail = '',
    String companyPhone = '',
    String companyCountry = 'RDC',
    String companyProvince = '',
    String companyCity = '',
    String companyCommune = '',
    String companyQuarter = '',
    String companyAvenue = '',
    String companyNumber = '',
    String role = 'admin',
    String? fullName,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.register,
        data: {
          'username': username,
          'password': password,
          'phone': phone,
          'business_category': businessCategory,
          'company_name': companyName,
          'company_trade_name': companyTradeName,
          'legal_form': legalForm,
          'rccm': rccm,
          'idnat': idnat,
          'nif': nif,
          'company_email': companyEmail,
          'company_phone': companyPhone,
          'company_country': companyCountry,
          'company_province': companyProvince,
          'company_city': companyCity,
          'company_commune': companyCommune,
          'company_quarter': companyQuarter,
          'company_avenue': companyAvenue,
          'company_number': companyNumber,
          'role': role,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        },
        queueIfOffline: false,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      final tokens = AuthTokensModel.fromJson(
        data['tokens'] as Map<String, dynamic>? ??
            Map<String, dynamic>.from(data),
      );
      final userJson = data['user'];
      final user = userJson != null
          ? UserModel.fromJson(Map<String, dynamic>.from(userJson as Map))
          : null;
      return (tokens: tokens, user: user);
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur réseau');
    }
  }

  Future<void> requestPasswordReset({String? phone, String? email}) async {
    final data = <String, dynamic>{};
    if (phone != null && phone.trim().isNotEmpty) {
      data['phone'] = phone.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      data['email'] = email.trim();
    }
    try {
      await _client.post<Map<String, dynamic>>(
        ApiEndpoints.passwordResetRequest,
        data: data,
        queueIfOffline: false,
      );
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }

  Future<void> confirmPasswordReset({
    String? phone,
    String? email,
    required String code,
    required String newPassword,
  }) async {
    final data = <String, dynamic>{
      'code': code,
      'new_password': newPassword,
    };
    if (phone != null && phone.trim().isNotEmpty) {
      data['phone'] = phone.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      data['email'] = email.trim();
    }
    try {
      await _client.post<Map<String, dynamic>>(
        ApiEndpoints.passwordResetConfirm,
        data: data,
        queueIfOffline: false,
      );
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiEndpoints.changePassword,
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
        queueIfOffline: false,
      );
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }

  Future<void> registerPushDevice({
    required String token,
    required String platform,
  }) async {
    try {
      await _client.post<Map<String, dynamic>>(
        ApiEndpoints.pushDevices,
        data: {'token': token, 'platform': platform},
        queueIfOffline: false,
      );
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : UnknownException(e.message ?? 'Erreur reseau');
    }
  }

  /// POST {base}/token/refresh/ (Django SimpleJWT: body { "refresh": "..." } → { "access": "..." })
  Future<AuthTokensModel> refresh(String refreshToken) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
        queueIfOffline: false,
      );
      final data = response.data;
      if (data == null) throw UnknownException('Réponse vide');
      return AuthTokensModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw e.error is AppException
          ? e.error as AppException
          : AuthException(message: e.message ?? 'Erreur d\'authentification');
    }
  }
}
