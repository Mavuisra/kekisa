library;

import '../../../core/config/env_config.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/offline/sync_orchestrator.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/auth_remote_datasource.dart';
import '../../../data/datasources/local_auth_datasource.dart';
import '../../../data/models/user_model.dart';

/// Connexion au backend Django : login username/password, stockage JWT, logout.
class DjangoAuthService {
  DjangoAuthService()
    : _local = AuthLocalDataSource(),
      _localAuth = LocalAuthDataSource();

  final AuthLocalDataSource _local;
  final LocalAuthDataSource _localAuth;

  UserModel _withRole(UserModel user, String role) {
    return UserModel(
      id: user.id,
      role: role,
      email: user.email,
      username: user.username,
      phone: user.phone,
      businessCategory: user.businessCategory,
      companyName: user.companyName,
      companyTradeName: user.companyTradeName,
      legalForm: user.legalForm,
      rccm: user.rccm,
      idnat: user.idnat,
      nif: user.nif,
      companyEmail: user.companyEmail,
      companyPhone: user.companyPhone,
      companyCountry: user.companyCountry,
      companyProvince: user.companyProvince,
      companyCity: user.companyCity,
      companyCommune: user.companyCommune,
      companyQuarter: user.companyQuarter,
      companyAvenue: user.companyAvenue,
      companyNumber: user.companyNumber,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      niveau: user.niveau,
      totalScore: user.totalScore,
    );
  }

  Future<void> _triggerBackgroundSync() async {
    try {
      await SyncOrchestrator.instance.flushQueue();
    } catch (_) {
      // La synchro ne doit jamais bloquer le login/register local.
    }
  }

  /// Connexion Django POST {baseUrl}/users/auth/login/
  Future<void> login({
    required String username,
    required String password,
  }) async {
    await _localAuth.ensureSeeded();
    try {
      final client = DioClient(
        baseUrl: EnvConfig.apiBaseUrl,
        accessToken: null,
      );
      final remote = AuthRemoteDataSource(client);
      final result = await remote.login(username: username, password: password);

      await _local.setAccessToken(result.tokens.accessToken);
      await _local.setRefreshToken(result.tokens.refreshToken);
      if (result.user != null) {
        final remoteUser = result.user!;
        await _local.setUser(remoteUser);
        // Persiste aussi les credentials en local pour autoriser le login offline.
        final offlineLogin =
            (remoteUser.phone ?? remoteUser.username ?? username).trim();
        if (offlineLogin.isNotEmpty) {
          await _localAuth.createOrUpdateUser(
            username: offlineLogin,
            password: password,
            role: remoteUser.role,
            businessCategory: remoteUser.businessCategory ?? 'boutique',
            companyName: remoteUser.companyName ?? '',
            displayName:
                (remoteUser.displayName ?? remoteUser.username ?? offlineLogin)
                    .trim(),
            phone: (remoteUser.phone ?? '').trim(),
            userId: remoteUser.id,
            userSnapshot: remoteUser,
          );
        }
      }
      // A l'ouverture de session, on force une tentative de sync offline -> API.
      await _triggerBackgroundSync();
      return;
    } catch (e) {
      final allowOfflineFallback =
          e is NetworkException ||
          e is ServerException ||
          e is UnknownException;
      if (!allowOfflineFallback) {
        rethrow;
      }
      final localUser = await _localAuth.authenticate(
        username: username,
        password: password,
      );
      if (localUser == null) {
        throw AuthException(
          message:
              'Connexion impossible hors ligne. Vérifiez vos identifiants ou réessayez avec le réseau.',
        );
      }
      final effectiveLocalUser = localUser;
      await _local.setAccessToken('local_offline_token');
      await _local.setRefreshToken('local_offline_refresh');
      await _local.setUser(effectiveLocalUser);
      await _triggerBackgroundSync();
    }
  }

  /// Création de compte Django POST {baseUrl}/users/auth/register/
  Future<void> register({
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
    await _localAuth.ensureSeeded();
    try {
      final client = DioClient(
        baseUrl: EnvConfig.apiBaseUrl,
        accessToken: null,
      );
      final remote = AuthRemoteDataSource(client);
      final result = await remote.register(
        username: username,
        password: password,
        phone: phone,
        businessCategory: businessCategory,
        companyName: companyName,
        companyTradeName: companyTradeName,
        legalForm: legalForm,
        rccm: rccm,
        idnat: idnat,
        nif: nif,
        companyEmail: companyEmail,
        companyPhone: companyPhone,
        companyCountry: companyCountry,
        companyProvince: companyProvince,
        companyCity: companyCity,
        companyCommune: companyCommune,
        companyQuarter: companyQuarter,
        companyAvenue: companyAvenue,
        companyNumber: companyNumber,
        role: role,
        fullName: fullName,
      );

      await _local.setAccessToken(result.tokens.accessToken);
      await _local.setRefreshToken(result.tokens.refreshToken);
      if (result.user != null) {
        final remoteUser = _withRole(result.user!, role);
        await _local.setUser(remoteUser);
        final offlineLogin =
            (remoteUser.phone ?? remoteUser.username ?? username).trim();
        if (offlineLogin.isNotEmpty) {
          await _localAuth.createOrUpdateUser(
            username: offlineLogin,
            password: password,
            role: remoteUser.role,
            businessCategory: remoteUser.businessCategory ?? businessCategory,
            companyName: remoteUser.companyName ?? companyName,
            displayName:
                (remoteUser.displayName ?? remoteUser.username ?? offlineLogin)
                    .trim(),
            phone: (remoteUser.phone ?? phone).trim(),
            userId: remoteUser.id,
            userSnapshot: remoteUser,
          );
        }
      }
      // Si des écritures étaient en attente en local, on synchronise dès l'auth.
      await _triggerBackgroundSync();
      return;
    } catch (e) {
      final allowOfflineFallback =
          e is NetworkException ||
          e is ServerException ||
          e is UnknownException;
      if (!allowOfflineFallback) {
        rethrow;
      }
      final localUser = await _localAuth.createOrUpdateUser(
        username: username,
        password: password,
        role: role,
        businessCategory: businessCategory,
        companyName: companyName,
        displayName: fullName ?? username,
        phone: phone,
      );
      await _local.setAccessToken('local_offline_token');
      await _local.setRefreshToken('local_offline_refresh');
      await _local.setUser(localUser);
      await _triggerBackgroundSync();
    }
  }

  Future<void> createLocalStaffUser({
    required String phone,
    required String password,
    required String role,
    required String businessCategory,
    required String companyName,
    String displayName = '',
  }) async {
    final loginPhone = phone.trim();
    await _localAuth.createOrUpdateUser(
      username: loginPhone,
      password: password,
      role: role,
      businessCategory: businessCategory,
      companyName: companyName,
      displayName: displayName.trim().isEmpty ? loginPhone : displayName.trim(),
      phone: loginPhone,
    );
  }

  Future<String?> getStoredAccessToken() => _local.getAccessToken();

  Future<bool> isLoggedIn() async {
    final token = await _local.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() => _local.clearAll();
}

/// Instance partagée pour login, logout et vérification de session.
final djangoAuthService = DjangoAuthService();
