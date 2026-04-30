import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile.dart';

const _kUsersJson = 'auth_users_v1';
const _kSessionUser = 'auth_session_username_v1';

String _hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

class AuthRepository {
  Future<Map<String, dynamic>> _loadUsersMap(SharedPreferences p) async {
    final raw = p.getString(_kUsersJson);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) {
        return Map<String, dynamic>.from(m);
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveUsersMap(SharedPreferences p, Map<String, dynamic> map) async {
    await p.setString(_kUsersJson, jsonEncode(map));
  }

  String _normUser(String u) => u.trim().toLowerCase();

  /// Sessão actual ou null.
  Future<UserProfile?> currentUser() async {
    final p = await SharedPreferences.getInstance();
    final session = p.getString(_kSessionUser);
    if (session == null || session.isEmpty) return null;
    final users = await _loadUsersMap(p);
    final entry = users[session];
    if (entry is! Map<String, dynamic>) return null;
    final full = entry['fullName'] as String? ?? '';
    final age = (entry['age'] as num?)?.toInt() ?? 0;
    return UserProfile(username: session, fullName: full, age: age);
  }

  /// Erro em português ou null se OK.
  Future<String?> register({
    required String fullName,
    required int age,
    required String username,
    required String password,
  }) async {
    final u = _normUser(username);
    if (u.isEmpty) return 'Informe um usuário.';
    if (fullName.trim().isEmpty) return 'Informe o nome completo.';
    if (age < 1 || age > 120) return 'Informe uma idade válida.';
    if (password.length < 4) return 'A senha deve ter pelo menos 4 caracteres.';

    final p = await SharedPreferences.getInstance();
    final users = await _loadUsersMap(p);
    if (users.containsKey(u)) return 'Este usuário já está cadastrado.';

    users[u] = {
      'fullName': fullName.trim(),
      'age': age,
      'passwordHash': _hashPassword(password),
    };
    await _saveUsersMap(p, users);
    await p.setString(_kSessionUser, u);
    return null;
  }

  Future<String?> login(String username, String password) async {
    final u = _normUser(username);
    if (u.isEmpty || password.isEmpty) return 'Preencha usuário e senha.';

    final p = await SharedPreferences.getInstance();
    final users = await _loadUsersMap(p);
    final entry = users[u];
    if (entry is! Map<String, dynamic>) return 'Usuário ou senha incorretos.';
    final stored = entry['passwordHash'] as String?;
    if (stored != _hashPassword(password)) return 'Usuário ou senha incorretos.';

    await p.setString(_kSessionUser, u);
    return null;
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSessionUser);
  }
}
