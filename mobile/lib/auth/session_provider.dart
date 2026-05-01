import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/user_profile.dart';
import '../core/services/api_service.dart';

/// Login/registo usam [AuthRepository] com [ApiService] interno (sem ciclo com sessão).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Estado de sessão após ler SharedPreferences.
final sessionFutureProvider = FutureProvider<UserProfile?>((ref) async {
  return ref.watch(authRepositoryProvider).currentUser();
});

/// Cliente API com `X-App-Username` / `X-App-Token` quando a sessão tem token.
final apiServiceProvider = Provider<ApiService>((ref) {
  final asyncUser = ref.watch(sessionFutureProvider);
  final user = asyncUser.asData?.value;
  final s = ApiService(
    appUsername: user?.username,
    appToken: user?.apiToken,
  );
  ref.onDispose(() => s.close());
  return s;
});
