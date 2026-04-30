import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_exception.dart';
import '../../core/study_import_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/animated_button.dart';
import '../../core/widgets/async_content.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/neon_card.dart';
import '../../providers.dart' show apiServiceProvider, studiesListProvider;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<Map<String, dynamic>>? _searchFuture;
  String _lastQuery = '';

  void _scheduleSearch(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _searchFuture = null;
        _lastQuery = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _lastQuery = q;
        _searchFuture = ref.read(apiServiceProvider).search(q);
      });
    });
  }

  bool _hasImportablePayload(Map<String, dynamic> data) {
    final verses = (data['verses'] as List?) ?? [];
    final narrative = data['narrative'] as String?;
    final narOk = narrative != null && narrative.trim().isNotEmpty;
    return verses.isNotEmpty || narOk;
  }

  Future<void> _importSearchToStudy(BuildContext context, Map<String, dynamic> data) async {
    if (_lastQuery.isEmpty || !_hasImportablePayload(data)) return;
    try {
      await ref.read(apiServiceProvider).createStudy(
            titleForSearchStudy(_lastQuery),
            formatSearchStudyContent(_lastQuery, data),
            source: 'search',
          );
      ref.invalidate(studiesListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resultado guardado em Estudos'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.userMessage(e))),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            floating: true,
            title: const Text('Busca'),
            backgroundColor: AppColors.background,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    onChanged: _scheduleSearch,
                    decoration: const InputDecoration(
                      hintText: 'Palavras ou tema…',
                      prefixIcon: Icon(Icons.search, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_searchFuture != null)
                    FutureBuilder<Map<String, dynamic>>(
                      future: _searchFuture,
                      builder: (context, snap) {
                        return AsyncContent<Map<String, dynamic>>(
                          snapshot: snap,
                          onRetry: () => setState(() {
                            _searchFuture = ref.read(apiServiceProvider).search(_lastQuery);
                          }),
                          builder: (ctx, data) {
                            final verses = (data['verses'] as List?) ?? [];
                            final narrative = data['narrative'] as String?;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (narrative != null && narrative.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: GlassContainer(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Narrativa',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  color: AppColors.secondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            narrative,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Text(
                                  'Versículos (${verses.length})',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.primary),
                                ),
                                const SizedBox(height: 12),
                                ...verses.map((v) {
                                  final m = v as Map<String, dynamic>;
                                  final title =
                                      '${m['book'] ?? ''} ${m['chapter_number'] ?? ''}:${m['number'] ?? ''}';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: NeonCard(
                                      accentColor: AppColors.secondary.withValues(alpha: 0.8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title.trim(),
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  color: AppColors.accent,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${m['text']}',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                if (_hasImportablePayload(data))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: AnimatedButton(
                                      onPressed: () => _importSearchToStudy(context, data),
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.bookmark_add_outlined, size: 22),
                                          SizedBox(width: 10),
                                          Text(
                                            'Importar resultado para Estudos',
                                            style: TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        'Escreva para pesquisar na Bíblia importada.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onBackgroundMuted),
                      ),
                    ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
