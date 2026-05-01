/// Porta do `runserver` Django (alinhar com `python manage.py runserver 8000`).
const int kApiDevPort = 8000;

/// Override absoluto: `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
const String _kDefineBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

/// Remove barras finais e sufixo `/api` se existir.
/// O [ApiService] acrescenta `api/...` em cada pedido; se a base for
/// `http://host:8000/api`, o URL final seria `.../api/api/...` (404).
String normalizeApiBaseUrl(String input) {
  var u = input.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.toLowerCase().endsWith('/api')) {
    u = u.substring(0, u.length - 4);
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
  }
  return u;
}

/// Resolve a base da API REST (origem do servidor, **sem** path `/api` — isso entra nos métodos do [ApiService]).
///
/// * `--dart-define=API_BASE_URL=...` tem prioridade.
/// * Android emulator: `http://10.0.2.2:PORT` (127.0.0.1 no host não é o PC).
/// * Outros (iOS simulator, desktop): `http://127.0.0.1:PORT`.
String resolveApiBaseUrl() {
  final trimmed = _kDefineBaseUrl.trim();
  if (trimmed.isNotEmpty) {
    return normalizeApiBaseUrl(trimmed);
  }
  
  // ==========================================
  // CONFIGURAÇÃO DE PRODUÇÃO NO PYTHONANYWHERE
  // ==========================================
  // Retorna a URL do seu servidor real (lembre-se: SEM a barra / no final e SEM o /api)
  return 'https://bibliaoneira.pythonanywhere.com';
}
