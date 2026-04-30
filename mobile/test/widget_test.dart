import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bible_intelligent_app/auth/session_provider.dart';
import 'package:bible_intelligent_app/core/auth/user_profile.dart';
import 'package:bible_intelligent_app/core/services/api_service.dart';
import 'package:bible_intelligent_app/main.dart';
import 'package:bible_intelligent_app/providers.dart';

class _FakeApiService extends ApiService {
  _FakeApiService() : super(baseUrl: 'http://127.0.0.1:9');

  @override
  Future<Map<String, dynamic>> search(String q) async => {};

  @override
  Future<Map<String, dynamic>> dailyVerse({String? version}) async => {
        'book': 'Gênesis',
        'chapter_number': 1,
        'number': 1,
        'text': 'Teste',
      };

  @override
  Future<Map<String, dynamic>> randomVerse({int? bookId}) async => dailyVerse();

  @override
  Future<List<dynamic>> books({String? version}) async => [];

  @override
  Future<List<dynamic>> chapters(int bookId) async => [];

  @override
  Future<List<dynamic>> verses(int chapterId) async => [];

  @override
  Future<List<dynamic>> studies() async => [];

  @override
  Future<Map<String, dynamic>> createStudy(String title, String content, {String source = 'manual'}) async => {};

  @override
  Future<void> deleteStudy(int id) async {}

  @override
  Future<Map<String, dynamic>> updateStudy(int id, String title, String content) async => {};

  @override
  Future<Map<String, dynamic>> ask(String question, {String? version, String? intent}) async => {
        'answer': 'fake',
        'sources': [],
        'backend': 'stub',
      };
}

void main() {
  testWidgets('App starts with dark shell and navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(_FakeApiService()),
          sessionFutureProvider.overrideWith(
            (ref) async => const UserProfile(
              username: 'test',
              fullName: 'Usuário Teste',
              age: 30,
            ),
          ),
        ],
        child: const BibleIntelligentApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Leitura'), findsOneWidget);
  });
}
