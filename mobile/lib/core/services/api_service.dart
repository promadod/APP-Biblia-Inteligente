import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_exception.dart';

String? _parseErrorDetailFromBody(String body) {
  if (body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final detail = decoded['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    if (detail is List) {
      final parts = <String>[];
      for (final e in detail) {
        if (e is String) {
          parts.add(e);
        } else if (e is Map) {
          final msg = e['message'] ?? e.toString();
          parts.add(msg.toString());
        }
      }
      final joined = parts.where((s) => s.isNotEmpty).join(' ');
      if (joined.isNotEmpty) return joined;
    }
  } catch (_) {}
  return null;
}

String _httpErrorMessage(http.Response r) {
  final fromBody = _parseErrorDetailFromBody(r.body);
  if (fromBody != null) return fromBody;
  return 'Servidor respondeu ${r.statusCode}';
}

/// Cliente REST para o backend Django (`/api/`).
class ApiService {
  ApiService({http.Client? httpClient, String? baseUrl})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl != null ? normalizeApiBaseUrl(baseUrl) : resolveApiBaseUrl();

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return Uri.parse('$base/$p').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {Duration? timeout}) async {
    try {
      final r = await _client.get(uri).timeout(timeout ?? const Duration(seconds: 45));
      return _decodeMap(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Map<String, dynamic> _decodeMap(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(
        _httpErrorMessage(r),
        statusCode: r.statusCode,
      );
    }
    final raw = r.body.isEmpty ? '{}' : r.body;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw ApiException('Resposta inválida do servidor');
  }

  List<dynamic> _decodeList(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(
        _httpErrorMessage(r),
        statusCode: r.statusCode,
      );
    }
    final raw = r.body.isEmpty ? '[]' : r.body;
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
    throw ApiException('Resposta inválida (esperada lista)');
  }

  Future<Map<String, dynamic>> search(String q) async {
    final uri = _uri('api/search', {'q': q});
    return _getJson(uri);
  }

  Future<Map<String, dynamic>> dailyVerse({String? version}) async {
    final q = version != null ? {'version': version} : null;
    return _getJson(_uri('api/verse/daily', q));
  }

  Future<Map<String, dynamic>> randomVerse({int? bookId}) async {
    final q = bookId != null ? {'book_id': '$bookId'} : null;
    return _getJson(_uri('api/verse/random', q));
  }

  Future<List<dynamic>> books({String? version}) async {
    final uri = _uri('api/books/', version != null ? {'version': version} : null);
    try {
      final r = await _client.get(uri).timeout(const Duration(seconds: 45));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw ApiException(_httpErrorMessage(r), statusCode: r.statusCode);
      }
      final decoded = jsonDecode(r.body.isEmpty ? '[]' : r.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['results'] is List) {
        return decoded['results'] as List<dynamic>;
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Future<List<dynamic>> chapters(int bookId) async {
    final uri = _uri('api/books/$bookId/chapters/');
    try {
      final r = await _client.get(uri).timeout(const Duration(seconds: 45));
      return _decodeList(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Future<List<dynamic>> verses(int chapterId) async {
    final uri = _uri('api/chapters/$chapterId/verses');
    try {
      final r = await _client.get(uri).timeout(const Duration(seconds: 45));
      return _decodeList(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Future<List<dynamic>> studies() async {
    final uri = _uri('api/studies/');
    try {
      final r = await _client.get(uri).timeout(const Duration(seconds: 45));
      final map = _decodeMap(r);
      final results = map['results'];
      if (results is List) return results;
      return [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Future<Map<String, dynamic>> createStudy(
    String title,
    String content, {
    String source = 'manual',
  }) async {
    final uri = _uri('api/studies/');
    try {
      final r = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'content': content,
              'source': source,
            }),
          )
          .timeout(const Duration(seconds: 45));
      return _decodeMap(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  Future<void> deleteStudy(int id) async {
    final uri = _uri('api/studies/$id/');
    final r = await _client.delete(uri).timeout(const Duration(seconds: 45));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(_httpErrorMessage(r), statusCode: r.statusCode);
    }
  }

  Future<Map<String, dynamic>> updateStudy(int id, String title, String content) async {
    final uri = _uri('api/studies/$id/');
    try {
      final r = await _client
          .patch(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'title': title, 'content': content}),
          )
          .timeout(const Duration(seconds: 45));
      return _decodeMap(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  /// [intent] `biblical_biography` — resposta JSON da feature Perguntas (lifeSummary, chronology, text, sources[]).
  Future<Map<String, dynamic>> ask(
    String question, {
    String? version,
    String? intent,
  }) async {
    final uri = _uri('api/ask');
    final body = <String, dynamic>{'question': question};
    if (version case final v?) {
      body['version'] = v;
    }
    if (intent != null && intent.isNotEmpty) {
      body['intent'] = intent;
    }
    try {
      final r = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      return _decodeMap(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiException.userMessage(e), cause: e);
    }
  }

  void close() => _client.close();
}
