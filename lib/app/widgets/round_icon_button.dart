import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The round white button every top bar uses — back, settings, profile.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 46,
    this.background = AppColors.surface,
    this.foreground = AppColors.ink,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final Color background;
  final Color foreground;

  /// Drawn instead of [icon] when set — an avatar, say.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: child ?? Icon(icon, size: size * 0.48, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
