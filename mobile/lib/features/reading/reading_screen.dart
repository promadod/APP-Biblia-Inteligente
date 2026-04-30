import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_content.dart';
import '../../core/widgets/neon_card.dart';
import '../../providers.dart';

enum _ReadingStep { books, chapters, verses }

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});

  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  _ReadingStep _step = _ReadingStep.books;
  Future<List<dynamic>>? _booksFuture;
  Future<List<dynamic>>? _chaptersFuture;
  Future<List<dynamic>>? _versesFuture;

  Map<String, dynamic>? _book;
  Map<String, dynamic>? _chapter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadBooks();
    });
  }

  void _reloadBooks() {
    setState(() {
      _step = _ReadingStep.books;
      _book = null;
      _chapter = null;
      _chaptersFuture = null;
      _versesFuture = null;
      _booksFuture = ref.read(apiServiceProvider).books(version: 'BKJ_PT');
    });
  }

  void _openBook(Map<String, dynamic> b) {
    final id = b['id'] as int;
    setState(() {
      _book = b;
      _chapter = null;
      _step = _ReadingStep.chapters;
      _chaptersFuture = ref.read(apiServiceProvider).chapters(id);
      _versesFuture = null;
    });
  }

  void _openChapter(Map<String, dynamic> ch) {
    final id = ch['id'] as int;
    setState(() {
      _chapter = ch;
      _step = _ReadingStep.verses;
      _versesFuture = ref.read(apiServiceProvider).verses(id);
    });
  }

  void _popStep() {
    if (_step == _ReadingStep.verses) {
      setState(() {
        _step = _ReadingStep.chapters;
        _chapter = null;
        _versesFuture = null;
      });
      return;
    }
    if (_step == _ReadingStep.chapters) {
      setState(() {
        _step = _ReadingStep.books;
        _book = null;
        _chaptersFuture = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Leitura';
    if (_book != null) title = '${_book!['name']}';
    if (_chapter != null) title = '${_book!['name']} ${_chapter!['number']}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _step != _ReadingStep.books
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: _popStep,
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Recarregar livros',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reloadBooks,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        child: switch (_step) {
          _ReadingStep.books => FutureBuilder<List<dynamic>>(
              key: const ValueKey('books'),
              future: _booksFuture,
              builder: (context, snap) {
                return AsyncContent<List<dynamic>>(
                  snapshot: snap,
                  onRetry: _reloadBooks,
                  builder: (_, list) => _BookList(list: list, onTap: _openBook),
                );
              },
            ),
          _ReadingStep.chapters => FutureBuilder<List<dynamic>>(
              key: ValueKey('ch-${_book!['id']}'),
              future: _chaptersFuture,
              builder: (context, snap) {
                return AsyncContent<List<dynamic>>(
                  snapshot: snap,
                  onRetry: () {
                    if (_book != null) _openBook(_book!);
                  },
                  builder: (_, list) => _ChapterGrid(chapters: list, onTap: _openChapter),
                );
              },
            ),
          _ReadingStep.verses => FutureBuilder<List<dynamic>>(
              key: ValueKey('v-${_chapter!['id']}'),
              future: _versesFuture,
              builder: (context, snap) {
                return AsyncContent<List<dynamic>>(
                  snapshot: snap,
                  onRetry: () {
                    if (_chapter != null) _openChapter(_chapter!);
                  },
                  builder: (_, list) => _VerseList(verses: list),
                );
              },
            ),
        },
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  const _BookList({required this.list, required this.onTap});

  final List<dynamic> list;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (ctx, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final m = list[i] as Map<String, dynamic>;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(m),
          child: NeonCard(
            accentColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${m['name']}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.onBackgroundMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({required this.chapters, required this.onTap});

  final List<dynamic> chapters;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: chapters.length,
      itemBuilder: (ctx, i) {
        final ch = chapters[i] as Map<String, dynamic>;
        final n = '${ch['number']}';
        return Material(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(ch),
            child: Center(
              child: Text(
                n,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerseList extends StatelessWidget {
  const _VerseList({required this.verses});

  final List<dynamic> verses;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: verses.length,
      separatorBuilder: (ctx, index) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final v = verses[i] as Map<String, dynamic>;
        return NeonCard(
          accentColor: AppColors.accent.withValues(alpha: 0.6),
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45, color: AppColors.onBackground),
              children: [
                TextSpan(
                  text: '${v['number']} ',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: '${v['text']}'),
              ],
            ),
          ),
        );
      },
    );
  }
}
