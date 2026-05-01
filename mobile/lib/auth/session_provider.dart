import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/user_profile.dart';
import '../providers.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(api: ref.watch(apiServiceProvider));
});

/// Estado de sessão após ler SharedPreferences.
final sessionFutureProvider = FutureProvider<UserProfile?>((ref) async {
  return ref.watch(authRepositoryProvider).currentUser();
});
