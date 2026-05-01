import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/session_provider.dart';

export 'auth/session_provider.dart' show apiServiceProvider, authRepositoryProvider, sessionFutureProvider;

/// Lista de estudos pessoais; use [ref.invalidate] após criar, importar, editar ou apagar.
final studiesListProvider = FutureProvider<List<dynamic>>((ref) {
  return ref.read(apiServiceProvider).studies();
});

/// `{ readable: [...], requestable: [...] }` para estudos coletivos.
final collectiveStudiesOverviewProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.read(apiServiceProvider).collectiveStudiesOverview();
});

/// Grupos pedagógicos (`GET /api/learning-groups/`).
final learningGroupsProvider = FutureProvider<List<dynamic>>((ref) {
  return ref.read(apiServiceProvider).learningGroups();
});
