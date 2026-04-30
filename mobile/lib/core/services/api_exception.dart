/// Erro de rede ou API com mensagem para o utilizador.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => message;

  static String userMessage(Object e) {
    if (e is ApiException) return e.message;
    final s = e.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network')) {
      return 'Sem ligação ao servidor. Verifique o URL da API e se o Django está a correr.';
    }
    if (s.contains('timeout')) {
      return 'Pedido expirou. Tente novamente.';
    }
    return 'Algo correu mal. Tente novamente.';
  }
}
