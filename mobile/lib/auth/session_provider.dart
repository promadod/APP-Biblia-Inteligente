import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/auth/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// Estado de sessão após ler SharedPreferences.
final sessionFutureProvider = FutureProvider<UserProfile?>((ref) async {
  return ref.watch(authRepositoryProvider).currentUser();
});
