import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_channel.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';
import 'user_profile.dart';

const _kUsersJson = 'auth_users_v1';
const _kSessionUser = 'auth_session_username_v1';

String _hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

class AuthRepository {
  AuthRepository() : _api = ApiService();

  /// Só para login/registo (sem cabeçalhos X-App); o resto da app usa [apiServiceProvider].
  final ApiService _api;

  static String? _apiTokenFrom(dynamic data) {
    if (data == null) return null;
    final s = data.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _slugFrom(dynamic data) {
    if (data == null) return null;
    final s = data.toString().trim();
    return s.isEmpty ? null : s;
  }

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

  Future<void> _persistLocalSession({
    required String normalizedUsername,
    required String fullName,
    required int age,
    required String passwordHash,
    String? apiToken,
    String? learningGroupSlug,
  }) async {
    await _persistUserRecord(
      normalizedUsername: normalizedUsername,
      fullName: fullName,
      age: age,
      passwordHash: passwordHash,
      openSession: true,
      apiToken: apiToken,
      learningGroupSlug: learningGroupSlug,
    );
  }

  /// Grava utilizador localmente; [openSession] false = só credenciais (ex.: web após cadastro).
  Future<void> _persistUserRecord({
    required String normalizedUsername,
    required String fullName,
    required int age,
    required String passwordHash,
    required bool openSession,
    String? apiToken,
    String? learningGroupSlug,
  }) async {
    final p = await SharedPreferences.getInstance();
    final users = await _loadUsersMap(p);
    final row = <String, dynamic>{
      'fullName': fullName,
      'age': age,
      'passwordHash': passwordHash,
    };
    if (apiToken != null) row['apiToken'] = apiToken;
    if (learningGroupSlug != null) row['learningGroupSlug'] = learningGroupSlug;
    users[normalizedUsername] = row;
    await _saveUsersMap(p, users);
    if (openSession) {
      await p.setString(_kSessionUser, normalizedUsername);
    }
  }

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
    final token = _apiTokenFrom(entry['apiToken']);
    final slug = _slugFrom(entry['learningGroupSlug']);
    return UserProfile(
      username: session,
      fullName: full,
      age: age,
      apiToken: token,
      learningGroupSlug: slug,
    );
  }

  /// Erro em português ou null se OK.
  ///
  /// [openSessionAfterRegister] em `false` (ex.: web) só grava credenciais; o utilizador deve
  /// fazer login em seguida.
  Future<String?> register({
    required String fullName,
    required int age,
    required String username,
    required String password,
    bool openSessionAfterRegister = true,
  }) async {
    final u = _normUser(username);
    if (u.isEmpty) return 'Informe um usuário.';
    if (fullName.trim().isEmpty) return 'Informe o nome completo.';
    if (age < 1 || age > 120) return 'Informe uma idade válida.';
    if (password.length < 4) return 'A senha deve ter pelo menos 4 caracteres.';

    final hash = _hashPassword(password);

    try {
      final data = await _api.registerAppUser(
        username: username,
        password: password,
        fullName: fullName.trim(),
        age: age,
        channel: resolveAppChannel(),
      );
      final name = data['full_name'] as String? ?? fullName.trim();
      final ageOut = (data['age'] as num?)?.toInt() ?? age;
      await _persistUserRecord(
        normalizedUsername: u,
        fullName: name,
        age: ageOut,
        passwordHash: hash,
        openSession: openSessionAfterRegister,
        apiToken: _apiTokenFrom(data['api_token']),
        learningGroupSlug: _slugFrom(data['learning_group_slug']),
      );
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        return e.message;
      }
    }

    final p = await SharedPreferences.getInstance();
    final users = await _loadUsersMap(p);
    if (users.containsKey(u)) {
      final entry = users[u];
      if (entry is Map<String, dynamic>) {
        final stored = entry['passwordHash'] as String?;
        if (stored == hash) {
          if (openSessionAfterRegister) {
            await p.setString(_kSessionUser, u);
          }
          return null;
        }
      }
      return 'Este usuário já está cadastrado.';
    }

    await _persistUserRecord(
      normalizedUsername: u,
      fullName: fullName.trim(),
      age: age,
      passwordHash: hash,
      openSession: openSessionAfterRegister,
    );
    return null;
  }

  Future<String?> login(String username, String password) async {
    final u = _normUser(username);
    if (u.isEmpty || password.isEmpty) return 'Preencha usuário e senha.';

    final hash = _hashPassword(password);

    try {
      final data = await _api.loginAppUser(username: username, password: password);
      final name = data['full_name'] as String? ?? '';
      final ageOut = (data['age'] as num?)?.toInt() ?? 0;
      await _persistLocalSession(
        normalizedUsername: u,
        fullName: name,
        age: ageOut,
        passwordHash: hash,
        apiToken: _apiTokenFrom(data['api_token']),
        learningGroupSlug: _slugFrom(data['learning_group_slug']),
      );
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        return e.message;
      }
    }

    final p = await SharedPreferences.getInstance();
    final users = await _loadUsersMap(p);
    final entry = users[u];
    if (entry is! Map<String, dynamic>) return 'Usuário ou senha incorretos.';
    final stored = entry['passwordHash'] as String?;
    if (stored != hash) return 'Usuário ou senha incorretos.';

    await p.setString(_kSessionUser, u);
    return null;
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSessionUser);
  }
}
