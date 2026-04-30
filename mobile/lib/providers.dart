import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final s = ApiService();
  ref.onDispose(() => s.close());
  return s;
});

/// Lista de estudos; use [ref.invalidate] após criar, importar, editar ou apagar.
final studiesListProvider = FutureProvider<List<dynamic>>((ref) {
  return ref.read(apiServiceProvider).studies();
});
