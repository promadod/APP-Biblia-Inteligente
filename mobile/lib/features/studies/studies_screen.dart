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

String lessonAtLabel(dynamic raw) {
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  final l = dt.toLocal();
  return '${_twoDigits(l.day)}/${_twoDigits(l.month)}/${l.year} · ${_twoDigits(l.hour)}:${_twoDigits(l.minute)}';
}

class StudiesScreen extends ConsumerStatefulWidget {
  const StudiesScreen({super.key});

  @override
  ConsumerState<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends ConsumerState<StudiesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadPersonal() => ref.invalidate(studiesListProvider);

  void _reloadCollective() => ref.invalidate(collectiveStudiesOverviewProvider);

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
      _reloadPersonal();
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
      _reloadPersonal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  Future<void> _collectiveEditor({Map<String, dynamic>? existing}) async {
    List<dynamic> groups = [];
    try {
      groups = await ref.read(learningGroupsProvider.future);
    } catch (_) {}
    if (!mounted) return;

    final titleCtrl = TextEditingController(text: existing == null ? '' : '${existing['title']}');
    final bodyCtrl = TextEditingController(text: existing == null ? '' : '${existing['content']}');
    var allowExternal = existing == null ? false : (existing['allow_external_requests'] == true);
    DateTime lessonAt = existing == null
        ? DateTime.now()
        : DateTime.tryParse('${existing['lesson_at']}') ?? DateTime.now();
    int? audienceId = existing == null ? null : (existing['audience_group'] as num?)?.toInt();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(existing == null ? 'Nova aula coletiva' : 'Editar aula coletiva'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyCtrl,
                    decoration: const InputDecoration(labelText: 'Conteúdo'),
                    minLines: 4,
                    maxLines: 10,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data da aula'),
                    subtitle: Text(lessonAtLabel(lessonAt.toUtc().toIso8601String())),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: lessonAt,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d == null) return;
                      if (!ctx.mounted) return;
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(lessonAt),
                      );
                      if (t == null) return;
                      setLocal(() {
                        lessonAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Grupo audiência'),
                    initialValue: audienceId,
                    items: [
                      for (final g in groups)
                        if (g is Map<String, dynamic> && g['id'] != null)
                          DropdownMenuItem<int>(
                            value: (g['id'] as num).toInt(),
                            child: Text('${g['name'] ?? g['slug']}'),
                          ),
                    ],
                    onChanged: (v) => setLocal(() => audienceId = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aceitar pedidos de outros grupos'),
                    value: allowExternal,
                    onChanged: (v) => setLocal(() => allowExternal = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.background),
                onPressed: () {
                  if (audienceId == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Escolha o grupo.')));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    if (audienceId == null) return;

    try {
      final api = ref.read(apiServiceProvider);
      final payload = <String, dynamic>{
        'title': titleCtrl.text,
        'content': bodyCtrl.text,
        'lesson_at': lessonAt.toUtc().toIso8601String(),
        'audience_group': audienceId,
        'allow_external_requests': allowExternal,
      };
      if (existing == null) {
        await api.createCollectiveStudy(payload);
      } else {
        await api.updateCollectiveStudy(existing['id'] as int, payload);
      }
      _reloadCollective();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula guardada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  Future<void> _confirmDeleteCollective(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminar aula coletiva?'),
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
      await ref.read(apiServiceProvider).deleteCollectiveStudy(item['id'] as int);
      _reloadCollective();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  Future<void> _openCollectiveDetail(Map<String, dynamic> m) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('${m['title']}'),
        content: SingleChildScrollView(
          child: SelectableText(
            '${m['content']}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _requestAccess(Map<String, dynamic> item) async {
    try {
      await ref.read(apiServiceProvider).requestCollectiveStudyAccess(item['id'] as int);
      _reloadCollective();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido enviado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiException.userMessage(e))));
      }
    }
  }

  Widget _buildAppBarAction() {
    final session = ref.watch(sessionFutureProvider);
    final isProfessor = session.asData?.value?.isProfessor ?? false;
    final idx = _tabController.index;
    if (idx == 0) {
      return Padding(
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
      );
    }
    if (isProfessor) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AnimatedButton(
          onPressed: () => _collectiveEditor(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined),
              SizedBox(width: 6),
              Text('Nova aula'),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPersonalTab() {
    final studiesAsync = ref.watch(studiesListProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(studiesListProvider);
        await ref.read(studiesListProvider.future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
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
                        onPressed: _reloadPersonal,
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

  Widget _buildCollectiveTab() {
    final session = ref.watch(sessionFutureProvider);
    final token = session.asData?.value?.apiToken;

    if (token == null || token.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Faça logout e login novamente para sincronizar o token e ver estudos coletivos.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onBackgroundMuted),
          ),
        ),
      );
    }

    final overview = ref.watch(collectiveStudiesOverviewProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(collectiveStudiesOverviewProvider);
        ref.invalidate(learningGroupsProvider);
        await ref.read(collectiveStudiesOverviewProvider.future);
      },
      child: overview.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              ApiException.userMessage(e),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onBackgroundMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _reloadCollective,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
              ),
            ),
          ],
        ),
        data: (map) {
          final readable = (map['readable'] as List<dynamic>?) ?? [];
          final requestable = (map['requestable'] as List<dynamic>?) ?? [];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Aulas disponíveis para si',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              if (readable.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'Nenhuma aula nesta lista.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onBackgroundMuted),
                  ),
                )
              else
                ...readable.map((raw) {
                  final m = raw as Map<String, dynamic>;
                  final canEdit = m['can_edit'] == true;
                  final lesson = lessonAtLabel(m['lesson_at']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NeonCard(
                      accentColor: AppColors.secondary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => _openCollectiveDetail(m),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['title']}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                ),
                                if (lesson.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.schedule, size: 15, color: AppColors.onBackgroundMuted),
                                      const SizedBox(width: 6),
                                      Text(lesson, style: Theme.of(context).textTheme.labelMedium),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Professor: ${m['teacher_name'] ?? '—'} · ${m['audience_group_name'] ?? ''}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onBackgroundMuted),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${m['content']}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
                                ),
                              ],
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _collectiveEditor(existing: m),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Editar'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _confirmDeleteCollective(m),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),
              Text(
                'Outras turmas (pedir acesso)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              if (requestable.isEmpty)
                Text(
                  'Nenhuma aula aberta a pedidos externos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onBackgroundMuted),
                )
              else
                ...requestable.map((raw) {
                  final m = raw as Map<String, dynamic>;
                  final lesson = lessonAtLabel(m['lesson_at']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NeonCard(
                      accentColor: AppColors.accent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m['title']}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                          ),
                          if (lesson.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(lesson, style: Theme.of(context).textTheme.labelMedium),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${m['teacher_name'] ?? ''} · ${m['audience_group_name'] ?? ''}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onBackgroundMuted),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _requestAccess(m),
                            icon: const Icon(Icons.how_to_reg_outlined),
                            label: const Text('Pedir acesso'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.background,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Estudos'),
        backgroundColor: AppColors.background,
        actions: [_buildAppBarAction()],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onBackgroundMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Meus estudos'),
            Tab(text: 'Estudo compartilhado'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonalTab(),
          _buildCollectiveTab(),
        ],
      ),
    );
  }
}
