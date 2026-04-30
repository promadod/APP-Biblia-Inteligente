import 'package:flutter/material.dart';

import '../services/api_exception.dart';
import '../theme/app_colors.dart';

/// Estados assíncronos com loading, erro amigável e retry.
class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.snapshot,
    required this.builder,
    this.onRetry,
    this.loading,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return loading ??
          const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          );
    }
    if (snapshot.hasError) {
      final msg = ApiException.userMessage(snapshot.error!);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.error.withValues(alpha: 0.9)),
              const SizedBox(height: 16),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.onBackgroundMuted),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (!snapshot.hasData) {
      return const SizedBox.shrink();
    }
    final data = snapshot.data as T;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      child: builder(context, data),
    );
  }
}
