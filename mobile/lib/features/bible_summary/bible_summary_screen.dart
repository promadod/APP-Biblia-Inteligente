import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_container.dart';
import '../../core/widgets/neon_card.dart';
import 'bible_summary_provider.dart';

class BibleSummaryScreen extends ConsumerStatefulWidget {
  const BibleSummaryScreen({super.key});

  @override
  ConsumerState<BibleSummaryScreen> createState() => _BibleSummaryScreenState();
}

class _BibleSummaryScreenState extends ConsumerState<BibleSummaryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final base = Theme.of(context).textTheme;
    return MarkdownStyleSheet(
      p: base.bodyMedium?.copyWith(height: 1.48, color: AppColors.onBackground),
      h1: base.headlineSmall?.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
      h2: base.titleMedium?.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h3: base.titleSmall?.copyWith(
        color: AppColors.secondary,
        fontWeight: FontWeight.w700,
      ),
      strong: base.bodyMedium?.copyWith(
        color: AppColors.secondary,
        fontWeight: FontWeight.w700,
      ),
      em: base.bodyMedium?.copyWith(
        color: AppColors.onBackgroundMuted,
        fontStyle: FontStyle.italic,
      ),
      listBullet: base.bodyMedium?.copyWith(color: AppColors.primary),
      blockSpacing: 12,
      listIndent: 22,
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncBooks = ref.watch(bibleSummaryListProvider);
    final q = _searchCtrl.text.trim().toLowerCase();

    return asyncBooks.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
      ),
      data: (books) {
        final filtered =
            q.isEmpty ? books : books.where((b) => b.title.toLowerCase().contains(q)).toList();
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar.large(
                floating: true,
                pinned: false,
                title: Text('Resumo dos livros'),
                backgroundColor: AppColors.background,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Filtrar por nome do livro…',
                        hintStyle:
                            TextStyle(color: AppColors.onBackgroundMuted.withValues(alpha: 0.85)),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(color: AppColors.onBackground),
                    ),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Nenhum livro encontrado.',
                      style: TextStyle(color: AppColors.onBackgroundMuted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      childCount: filtered.length,
                      (context, i) {
                        final book = filtered[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: NeonCard(
                            accentColor: AppColors.secondary,
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
                                title: Text(
                                  book.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Toque para expandir o resumo',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: AppColors.onBackgroundMuted,
                                        ),
                                  ),
                                ),
                                iconColor: AppColors.accent,
                                collapsedIconColor: AppColors.accent,
                                children: [
                                  MarkdownBody(
                                    data: book.markdown,
                                    selectable: true,
                                    styleSheet: _markdownStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
