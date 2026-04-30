import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AnimatedButton extends StatefulWidget {
  const AnimatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  });

  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> with SingleTickerProviderStateMixin {
  double _scale = 1;

  void _setDown(bool down) {
    setState(() => _scale = down ? 0.96 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: widget.onPressed == null
                  ? [AppColors.surfaceVariant, AppColors.surfaceVariant]
                  : [AppColors.primary, AppColors.secondary],
            ),
            boxShadow: widget.onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Padding(
            padding: widget.padding,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: widget.onPressed == null ? AppColors.onBackgroundMuted : AppColors.background,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: widget.onPressed == null ? AppColors.onBackgroundMuted : AppColors.background,
                  size: 20,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
