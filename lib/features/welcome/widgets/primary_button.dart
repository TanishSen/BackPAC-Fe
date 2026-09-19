import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// The white pill at the bottom of the page.
///
/// Pressing it dips the surface slightly instead of scaling it, which reads as
/// a physical press rather than a bouncing toy.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: AppSpacing.buttonHeight,
          transform: Matrix4.translationValues(0, _down ? 1.5 : 0, 0),
          decoration: BoxDecoration(
            color: _down ? const Color(0xFFF7F7F9) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF2A2140).withValues(alpha: _down ? 0.05 : 0.08),
                blurRadius: _down ? 12 : 22,
                offset: Offset(0, _down ? 4 : 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(widget.label, style: AppText.button),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward, size: 20, color: AppColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}
