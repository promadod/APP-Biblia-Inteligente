import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Painel estilo vidro fosco com blur leve.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.borderColor = AppColors.border,
    this.blurSigma = 14,
    this.gradientStartAlpha = 0.08,
    this.gradientEndAlpha = 0.03,
    this.overlayColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color borderColor;
  /// Intensidade do desfoque do fundo (menor = imagem mais visível atrás do vidro).
  final double blurSigma;
  final double gradientStartAlpha;
  final double gradientEndAlpha;
  /// Camada opcional por cima do gradiente (ex.: preto suave) para manter contraste do texto.
  final Color? overlayColor;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: gradientStartAlpha),
                Colors.white.withValues(alpha: gradientEndAlpha),
              ],
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (overlayColor != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: r,
                      color: overlayColor,
                    ),
                  ),
                ),
              Padding(
                padding: padding,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
