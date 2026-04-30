import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/animated_button.dart';
import '../../core/widgets/neon_card.dart';
import '../../providers.dart';

String _twoDigits(int n) => n < 10 ? '0$n' : '$n';

/// Formata `created_at` ISO do backend para exibição no cartão.
String studyCreatedLabel(Map<String, dynamic> m) {
  final raw = m['created_at'];
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return '';
  final l = dt.toLocal();
  return '${_twoDigits(l.day)}/${_twoDigits(l.month)}/${l.year} · ${_twoDigits(l.hour)}:${_twoDigits(l.minute)}';
}

class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> {
  void _reloadList() => ref.invalidate(studiesListProvider);

  Future<void> _editor({Map<String, dynamic>? existing}) async {
    final titleCtrl = TextEditingController(text: existing == null ? '' : '${existing['title']}');
    final bodyCtrl = TextEditingController(text: existing == null ? '' : '${existing['content']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(existing == null ? 'Novo estudo' : 'Editar estudo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                decoration: const InputDecoration(labelText: 'Conteúdo'),
                minLines: 5,
                maxLines: 12,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.background),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final api = ref.read(apiServiceProvider);
      if (existing == null) {
        await api.createStudy(titleCtrl.text, bodyCtrl.text);
      } else {
        await api.updateStudy(existing['id'] as int, titleCtrl.text, bodyCtrl.text);
      }
      _reloadList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar estudo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Não')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color.fromARGB(255, 8, 100, 142)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiServiceProvider).deleteStudy(item['id'] as int);
      _reloadList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final studiesAsync = ref.watch(studiesListProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            floating: true,
            title: const Text('Estudos'),
            backgroundColor: AppColors.background,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedButton(
                  onPressed: () => _editor(),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add),
                      SizedBox(width: 6),
                      Text('Novo'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: studiesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    children: [
                      Text(
                        ApiException.userMessage(e),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onBackgroundMuted),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _reloadList,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                        ),
                      ),
                    ],
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        'Sem estudos. Crie o primeiro.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onBackgroundMuted),
                      ),
                    );
                  }
                  return Column(
                    children: list.map((raw) {
                      final m = raw as Map<String, dynamic>;
                      final source = '${m['source'] ?? 'manual'}';
                      final accent = switch (source) {
                        'search' => AppColors.primary,
                        'chat' => AppColors.accent,
                        _ => AppColors.secondary,
                      };
                      final dateLabel = studyCreatedLabel(m);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NeonCard(
                          accentColor: accent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${m['title']}',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: AppColors.accent),
                                    onPressed: () => _editor(existing: m),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Color.fromRGBO(2, 255, 171, 1)),
                                    onPressed: () => _confirmDelete(m),
                                  ),
                                ],
                              ),
                              if (dateLabel.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.onBackgroundMuted),
                                    const SizedBox(width: 8),
                                    Text(
                                      dateLabel,
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            color: AppColors.onBackgroundMuted,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              Text(
                                '${m['content']}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
