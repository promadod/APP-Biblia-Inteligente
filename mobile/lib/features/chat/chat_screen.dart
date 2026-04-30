import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/animated_button.dart';
import '../../core/widgets/glass_container.dart';
import '../../providers.dart';

/// Alinhado com [POST /api/ask] quando `intent=biblical_biography`.
const _kBiblicalBiographyIntent = 'biblical_biography';

class _Bubble {
  _Bubble({
    required this.role,
    required this.text,
    this.isBiography = false,
    this.bioLifeSummary,
    this.bioChronology,
    this.bioConclusion,
    this.refStrings,
    this.verseMaps,
    this.chronology,
    this.lifeSummary,
    this.sources,
  });

  final String role;
  final String text;

  /// Resposta estruturada da feature Perguntas (personagens / acontecimentos).
  final bool isBiography;
  final String? bioLifeSummary;
  final String? bioChronology;
  final String? bioConclusion;
  final List<String>? refStrings;
  final List<dynamic>? verseMaps;

  /// Formato legado (sem [intent]).
  final String? chronology;
  final String? lifeSummary;
  final List<dynamic>? sources;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Bubble>[];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _canImportToStudies() => _msgs.any((m) => m.role == 'assistant');

  String _titleForChatStudy() {
    for (final m in _msgs) {
      if (m.role == 'user') {
        final t = m.text.trim();
        if (t.isEmpty) continue;
        if (t.length <= 44) return 'Perguntas: $t';
        return 'Perguntas: ${t.substring(0, 41)}…';
      }
    }
    return 'Perguntas (importado)';
  }

  String _assistantPlainText(_Bubble m) {
    final b = StringBuffer();
    if (m.isBiography) {
      if (m.bioLifeSummary != null && m.bioLifeSummary!.trim().isNotEmpty) {
        b.writeln('Genealogia e contexto');
        b.writeln(m.bioLifeSummary!.trim());
        b.writeln();
      }
      if (m.bioChronology != null && m.bioChronology!.trim().isNotEmpty) {
        b.writeln('Cronologia');
        b.writeln(m.bioChronology!.trim());
        b.writeln();
      }
      if (m.bioConclusion != null && m.bioConclusion!.trim().isNotEmpty) {
        b.writeln('Legado e conclusão');
        b.writeln(m.bioConclusion!.trim());
        b.writeln();
      }
      if (m.refStrings != null && m.refStrings!.isNotEmpty) {
        b.writeln('Referências bíblicas');
        for (final s in m.refStrings!) {
          b.writeln('• $s');
        }
        b.writeln();
      }
      if (m.verseMaps != null && m.verseMaps!.isNotEmpty) {
        b.writeln('Trechos na Bíblia');
        for (final raw in m.verseMaps!) {
          final map = raw as Map;
          final refStr = '${map['book']} ${map['chapter']}:${map['verse']}';
          final verseText = '${map['text'] ?? ''}'.trim();
          b.writeln(refStr);
          if (verseText.isNotEmpty) b.writeln(verseText);
          b.writeln();
        }
      }
    } else {
      if (m.chronology != null && m.chronology!.trim().isNotEmpty) {
        b.writeln('Cronologia');
        b.writeln(m.chronology!.trim());
        b.writeln();
      }
      if (m.lifeSummary != null && m.lifeSummary!.trim().isNotEmpty) {
        b.writeln('Traço de vida');
        b.writeln(m.lifeSummary!.trim());
        b.writeln();
      }
      final noLegacySections = (m.chronology == null || m.chronology!.trim().isEmpty) &&
          (m.lifeSummary == null || m.lifeSummary!.trim().isEmpty);
      final answer = m.text.trim();
      if (answer.isNotEmpty) {
        if (noLegacySections) {
          b.writeln(answer);
          b.writeln();
        } else {
          b.writeln('Resposta');
          b.writeln(answer);
          b.writeln();
        }
      }
      if (m.sources != null && m.sources!.isNotEmpty) {
        b.writeln('Versículos');
        for (final raw in m.sources!) {
          final map = raw as Map;
          final refStr = '${map['book']} ${map['chapter']}:${map['verse']}';
          final verseText = '${map['text'] ?? ''}'.trim();
          b.writeln(refStr);
          if (verseText.isNotEmpty) b.writeln(verseText);
          b.writeln();
        }
      }
    }
    return b.toString().trim();
  }

  String _buildChatStudyBody() {
    final buf = StringBuffer();
    for (final m in _msgs) {
      if (m.role == 'user') {
        buf.writeln('[Pergunta]');
        buf.writeln(m.text.trim());
        buf.writeln();
      } else {
        buf.writeln('[Resposta]');
        buf.writeln(_assistantPlainText(m));
        buf.writeln();
      }
    }
    return buf.toString().trim();
  }

  Future<void> _importChatToStudy(BuildContext context) async {
    if (!_canImportToStudies()) return;
    try {
      await ref.read(apiServiceProvider).createStudy(
            _titleForChatStudy(),
            _buildChatStudyBody(),
            source: 'chat',
          );
      ref.invalidate(studiesListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversa guardada em Estudos'),
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

  Future<void> _send() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add(_Bubble(role: 'user', text: q));
      _busy = true;
    });
    _controller.clear();
    _scrollEnd();

    try {
      final data = await ref.read(apiServiceProvider).ask(
            q,
            version: 'BKJ_PT',
            intent: _kBiblicalBiographyIntent,
          );

      if ('${data['intent'] ?? ''}' == _kBiblicalBiographyIntent) {
        final refs = <String>[];
        final rawRefs = data['sources'];
        if (rawRefs is List) {
          for (final e in rawRefs) {
            final s = e.toString().trim();
            if (s.isNotEmpty) refs.add(s);
          }
        }
        setState(() {
          _msgs.add(
            _Bubble(
              role: 'assistant',
              text: '',
              isBiography: true,
              bioLifeSummary: data['lifeSummary'] as String?,
              bioChronology: data['chronology'] as String?,
              bioConclusion: data['text'] as String?,
              refStrings: refs.isNotEmpty ? refs : null,
              verseMaps: data['verses'] as List<dynamic>?,
            ),
          );
        });
      } else {
        final answer = '${data['answer'] ?? ''}';
        final sources = data['sources'] as List<dynamic>?;
        final chronology = data['chronology'] as String?;
        final lifeSummary = data['life_summary'] as String?;
        setState(() {
          _msgs.add(
            _Bubble(
              role: 'assistant',
              text: answer,
              chronology: chronology,
              lifeSummary: lifeSummary,
              sources: sources,
            ),
          );
        });
      }
    } catch (e) {
      setState(() {
        _msgs.add(_Bubble(role: 'assistant', text: ApiException.userMessage(e)));
      });
    } finally {
      setState(() => _busy = false);
      _scrollEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                const SliverAppBar.large(
                  floating: true,
                  title: Text('Pesquisa em toda Bíblia'),
                  backgroundColor: AppColors.background,
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      childCount: _msgs.length + (_busy ? 1 : 0),
                      (ctx, i) {
                        if (_busy && i == _msgs.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                            ),
                          );
                        }
                        final m = _msgs[i];
                        final isUser = m.role == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
                              child: GlassContainer(
                                borderRadius: isUser ? 18 : 20,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isUser)
                                      Text(
                                        m.text,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                                      )
                                    else if (m.isBiography) ...[
                                      _bioMarkdown(
                                        context,
                                        title: 'Genealogia e contexto',
                                        body: m.bioLifeSummary,
                                      ),
                                      _bioMarkdown(
                                        context,
                                        title: 'Cronologia',
                                        body: m.bioChronology,
                                      ),
                                      _bioMarkdown(
                                        context,
                                        title: 'Legado e conclusão',
                                        body: m.bioConclusion,
                                      ),
                                      if (m.refStrings != null && m.refStrings!.isNotEmpty) ...[
                                        Text(
                                          'Referências bíblicas',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...m.refStrings!.map(
                                          (s) => Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: Text(
                                              '• $s',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: AppColors.onBackgroundMuted,
                                                    height: 1.35,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      if (m.verseMaps != null && m.verseMaps!.isNotEmpty) ...[
                                        Text(
                                          'Trechos na Bíblia (ordem canónica)',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...m.verseMaps!.map((s) {
                                          final map = s as Map;
                                          final refStr =
                                              '${map['book']} ${map['chapter']}:${map['verse']}';
                                          final verseText = '${map['text'] ?? ''}'.trim();
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  refStr,
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: AppColors.secondary,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                ),
                                                if (verseText.isNotEmpty)
                                                  Text(
                                                    verseText,
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: AppColors.onBackgroundMuted,
                                                          height: 1.35,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ] else ...[
                                      if (m.chronology != null && m.chronology!.trim().isNotEmpty) ...[
                                        Text(
                                          'Cronologia',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          m.chronology!,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                      if (m.lifeSummary != null && m.lifeSummary!.trim().isNotEmpty) ...[
                                        Text(
                                          'Traço de vida',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          m.lifeSummary!,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                      if ((m.chronology == null || m.chronology!.trim().isEmpty) &&
                                          (m.lifeSummary == null || m.lifeSummary!.trim().isEmpty) &&
                                          m.text.trim().isNotEmpty)
                                        Text(
                                          m.text,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                                        ),
                                      if (m.sources != null && m.sources!.isNotEmpty) ...[
                                        Text(
                                          'Versículos (ordem bíblica)',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.accent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...m.sources!.map((s) {
                                          final map = s as Map;
                                          final refStr =
                                              '${map['book']} ${map['chapter']}:${map['verse']}';
                                          final verseText = '${map['text'] ?? ''}'.trim();
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  refStr,
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: AppColors.secondary,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                ),
                                                if (verseText.isNotEmpty)
                                                  Text(
                                                    verseText,
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: AppColors.onBackgroundMuted,
                                                          height: 1.35,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ],
                                ),
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
          ),
          if (_canImportToStudies())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AnimatedButton(
                onPressed: _busy ? null : () => _importChatToStudy(context),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_add_outlined, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Importar conversa para Estudos',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Ex.: Quem foi Jeremias?',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                    ),
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _biographyMarkdownStyle(BuildContext context) {
    final base = Theme.of(context).textTheme;
    return MarkdownStyleSheet(
      p: base.bodyMedium?.copyWith(height: 1.45, color: AppColors.onBackground),
      h1: base.titleLarge?.copyWith(color: AppColors.accent),
      h2: base.titleMedium?.copyWith(color: AppColors.accent),
      h3: base.titleSmall?.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w600,
      ),
      h4: base.bodyLarge?.copyWith(
        color: AppColors.secondary,
        fontWeight: FontWeight.w600,
      ),
      listBullet: base.bodyMedium?.copyWith(color: AppColors.onBackground),
      strong: base.bodyMedium?.copyWith(
        color: AppColors.onBackground,
        fontWeight: FontWeight.w600,
      ),
      blockquote: base.bodySmall?.copyWith(
        color: AppColors.onBackgroundMuted,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _bioMarkdown(BuildContext context, {required String title, required String? body}) {
    final t = (body ?? '').trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          MarkdownBody(
            data: t,
            selectable: true,
            styleSheet: _biographyMarkdownStyle(context),
          ),
        ],
      ),
    );
  }
}
