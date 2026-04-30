import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/session_provider.dart';
import '../../core/auth/user_profile.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_content.dart';
import '../../core/widgets/neon_card.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

String _verseKey(Map<String, dynamic> v) {
  final id = v['id'];
  if (id != null) return 'id_$id';
  return '${v['book']}_${v['chapter_number']}_${v['number']}';
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<Map<String, dynamic>>> _versesFuture;

  @override
  void initState() {
    super.initState();
    _versesFuture = _fetchThreeVerses();
  }

  Future<List<Map<String, dynamic>>> _fetchThreeVerses() async {
    final api = ref.read(apiServiceProvider);
    final out = <Map<String, dynamic>>[];
    final keys = <String>{};
    var attempts = 0;
    while (out.length < 3 && attempts < 60) {
      attempts++;
      final r = await api.randomVerse();
      final k = _verseKey(r);
      if (!keys.contains(k)) {
        keys.add(k);
        out.add(r);
      }
    }
    return out;
  }

  Future<void> _refresh() async {
    setState(() {
      _versesFuture = _fetchThreeVerses();
    });
    await _versesFuture;
  }

  String _welcomeTitle(AsyncValue<UserProfile?> session) {
    return session.when(
      data: (user) {
        if (user == null) return 'Bem-vindo';
        final name = user.fullName.trim();
        if (name.isNotEmpty) return 'Bem-vindo, $name';
        return 'Bem-vindo, ${user.username}';
      },
      loading: () => 'Bem-vindo',
      error: (error, stackTrace) => 'Bem-vindo',
    );
  }

  Widget _verseCard(BuildContext context, Map<String, dynamic> data) {
    final refStr =
        '${data['book'] ?? ''} ${data['chapter_number'] ?? ''}:${data['number'] ?? ''}'.trim();
    return NeonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            refStr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            '${data['text'] ?? ''}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: AppColors.onBackground,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionFutureProvider);

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              floating: true,
              title: Text(_welcomeTitle(session)),
              actions: [
                IconButton(
                  tooltip: 'Sair',
                  icon: const Icon(Icons.logout_rounded),
                  onPressed: () async {
                    await ref.read(authRepositoryProvider).logout();
                    ref.invalidate(sessionFutureProvider);
                  },
                ),
              ],
              backgroundColor: AppColors.background,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Versículos do dia',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _versesFuture,
                      builder: (context, snap) {
                        return AsyncContent<List<Map<String, dynamic>>>(
                          snapshot: snap,
                          onRetry: _refresh,
                          builder: (ctx, list) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < list.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 16),
                                  _verseCard(context, list[i]),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
