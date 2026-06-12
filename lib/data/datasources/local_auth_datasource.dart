library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/offline/local_sqlite.dart';
import '../../core/security/password_hash.dart';
import '../models/user_model.dart';

class LocalAuthDataSource {
  LocalAuthDataSource({LocalSqlite? sqlite})
    : _sqlite = sqlite ?? LocalSqlite.instance;

  final LocalSqlite _sqlite;
  final Uuid _uuid = const Uuid();

  Future<void> ensureSeeded() async {
    // Ne plus créer de compte demo avec mot de passe en clair.
    await _sqlite.database;
  }

  Future<UserModel?> authenticate({
    required String username,
    required String password,
  }) async {
    final db = await _sqlite.database;
    final rows = await db.query(
      'local_auth_users',
      where: 'LOWER(username) = LOWER(?) AND active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final stored = rows.first['password'] as String? ?? '';
    if (!PasswordHash.verify(password, stored)) {
      return null;
    }
    return _rowToUser(rows.first);
  }

  Future<UserModel> createOrUpdateUser({
    required String username,
    required String password,
    required String role,
    required String businessCategory,
    String companyName = '',
    String displayName = '',
    String phone = '',
    String? userId,
    UserModel? userSnapshot,
  }) async {
    final db = await _sqlite.database;
    final hashed = PasswordHash.hash(password);
    final existing = await db.query(
      'local_auth_users',
      where: 'LOWER(username) = LOWER(?)',
      whereArgs: [username.trim()],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String;
      await db.update(
        'local_auth_users',
        {
          'password': hashed,
          'role': role,
          'business_category': businessCategory,
          'company_name': companyName,
          'display_name': displayName,
          'phone': phone,
          'profile_json': jsonEncode(
            userSnapshot?.toJson() ?? const <String, dynamic>{},
          ),
          'active': 1,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final updated = await db.query(
        'local_auth_users',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return _rowToUser(updated.first);
    }

    final id = userId == null || userId.trim().isEmpty ? _uuid.v4() : userId;
    await db.insert('local_auth_users', {
      'id': id,
      'username': username.trim(),
      'password': hashed,
      'role': role,
      'business_category': businessCategory,
      'company_name': companyName,
      'display_name': displayName,
      'phone': phone,
      'profile_json': jsonEncode(
        userSnapshot?.toJson() ?? const <String, dynamic>{},
      ),
      'active': 1,
      'created_at': now,
    });
    final inserted = await db.query(
      'local_auth_users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return _rowToUser(inserted.first);
  }

  Future<void> updateUserSnapshot(UserModel user) async {
    final db = await _sqlite.database;
    final normalizedId = user.id.trim();
    final normalizedUsername = (user.username ?? '').trim();
    final normalizedPhone = (user.phone ?? '').trim();
    final where = <String>[];
    final args = <Object?>[];
    if (normalizedId.isNotEmpty) {
      where.add('id = ?');
      args.add(normalizedId);
    }
    if (normalizedUsername.isNotEmpty) {
      where.add('LOWER(username) = LOWER(?)');
      args.add(normalizedUsername);
    }
    if (normalizedPhone.isNotEmpty) {
      where.add('phone = ?');
      args.add(normalizedPhone);
    }
    if (where.isEmpty) return;
    await db.update(
      'local_auth_users',
      {
        if (user.role.trim().isNotEmpty) 'role': user.role.trim(),
        if ((user.businessCategory ?? '').trim().isNotEmpty)
          'business_category': user.businessCategory!.trim(),
        if ((user.companyName ?? '').trim().isNotEmpty)
          'company_name': user.companyName!.trim(),
        if ((user.displayName ?? '').trim().isNotEmpty)
          'display_name': user.displayName!.trim(),
        if (normalizedPhone.isNotEmpty) 'phone': normalizedPhone,
        'profile_json': jsonEncode(user.toJson()),
        'active': 1,
      },
      where: where.join(' OR '),
      whereArgs: args,
    );
  }

  UserModel _rowToUser(Map<String, Object?> row) {
    final profileRaw = row['profile_json'] as String?;
    UserModel? snapshot;
    if (profileRaw != null && profileRaw.trim().isNotEmpty) {
      try {
        snapshot = UserModel.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(profileRaw) as Map<dynamic, dynamic>,
          ),
        );
      } catch (_) {
        snapshot = null;
      }
    }
    return UserModel(
      id: row['id'] as String? ?? '',
      role: row['role'] as String? ?? snapshot?.role ?? 'seller',
      email: snapshot?.email,
      username: row['username'] as String? ?? snapshot?.username,
      phone: row['phone'] as String? ?? snapshot?.phone,
      businessCategory:
          row['business_category'] as String? ??
          snapshot?.businessCategory ??
          'boutique',
      companyName: row['company_name'] as String? ?? snapshot?.companyName,
      companyTradeName: snapshot?.companyTradeName,
      legalForm: snapshot?.legalForm,
      rccm: snapshot?.rccm,
      idnat: snapshot?.idnat,
      nif: snapshot?.nif,
      companyEmail: snapshot?.companyEmail,
      companyPhone: snapshot?.companyPhone,
      companyCountry: snapshot?.companyCountry,
      companyProvince: snapshot?.companyProvince,
      companyCity: snapshot?.companyCity,
      companyCommune: snapshot?.companyCommune,
      companyQuarter: snapshot?.companyQuarter,
      companyAvenue: snapshot?.companyAvenue,
      companyNumber: snapshot?.companyNumber,
      displayName: row['display_name'] as String? ?? snapshot?.displayName,
      avatarUrl: snapshot?.avatarUrl,
      niveau: snapshot?.niveau,
      totalScore: snapshot?.totalScore,
    );
  }

  Future<List<UserModel>> listUsers({
    String? businessCategory,
    String? companyName,
  }) async {
    final db = await _sqlite.database;
    final where = <String>['active = 1'];
    final whereArgs = <Object?>[];
    if (businessCategory != null && businessCategory.trim().isNotEmpty) {
      where.add('LOWER(business_category) = LOWER(?)');
      whereArgs.add(businessCategory.trim());
    }
    if (companyName != null && companyName.trim().isNotEmpty) {
      where.add('LOWER(company_name) = LOWER(?)');
      whereArgs.add(companyName.trim());
    }
    final rows = await db.query(
      'local_auth_users',
      where: where.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToUser).toList();
  }
}
