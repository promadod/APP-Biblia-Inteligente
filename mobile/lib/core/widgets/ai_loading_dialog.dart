import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Diálogo estilo assistente IA: ícone a girar e mensagens alternadas durante espera da API.
class AiLoadingDialog extends StatefulWidget {
  const AiLoadingDialog({super.key});

  @override
  State<AiLoadingDialog> createState() => _AiLoadingDialogState();
}

class _AiLoadingDialogState extends State<AiLoadingDialog> with SingleTickerProviderStateMixin {
  static const _phrases = [
    'Carregando conteúdo…',
    'Seu conteúdo está sendo processado…',
    'Consultando as Escrituras…',
    'Trazendo informações da Bíblia…',
    'Analisando fontes e referências…',
    'Preparando a resposta para você…',
    'Quase lá…',
  ];

  late AnimationController _rotation;
  Timer? _phraseTimer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _phraseTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _phrases.length);
    });
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _rotation,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Icon(Icons.auto_awesome, size: 36, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                _phrases[_i],
                key: ValueKey<int>(_i),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.onBackground,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Isso pode levar alguns segundos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onBackgroundMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
