import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hachage local SHA-256 avec sel (stockage offline, pas équivalent serveur).
class PasswordHash {
  PasswordHash._();

  static String hash(String password) {
    final salt = _randomSalt();
    return '$salt:${_digest(salt, password)}';
  }

  static bool verify(String password, String stored) {
    final parts = stored.split(':');
    if (parts.length != 2) {
      return false;
    }
    final salt = parts[0];
    final expected = parts[1];
    return _digest(salt, password) == expected;
  }

  static String _digest(String salt, String password) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  static String _randomSalt() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
