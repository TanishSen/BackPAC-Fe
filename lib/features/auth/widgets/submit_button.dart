import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// The filled brand pill that submits the form.
///
/// A sibling of [PrimaryButton], not a copy of it: that one is the white pill
/// the welcome screen ends on, and this one is the single obvious action on a
/// form. Same press behaviour — the surface dips rather than scales — so they
/// feel like the same hand made them.
///
/// It carries its own busy state. A form that can be submitted twice while the
/// first request is in flight creates two accounts, and the honest way to stop
/// that is for the button to visibly stop being a button.
class SubmitButton extends StatefulWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  State<SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<SubmitButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool live = !widget.busy;

    return Semantics(
      button: true,
      enabled: live,
      label: widget.label,
      child: GestureDetector(
        onTapDown: live ? (_) => setState(() => _down = true) : null,
        onTapCancel: live ? () => setState(() => _down = false) : null,
        onTapUp: live ? (_) => setState(() => _down = false) : null,
        onTap: live ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: AppSpacing.buttonHeight,
          transform: Matrix4.translationValues(0, _down ? 1.5 : 0, 0),
          decoration: BoxDecoration(
            color: widget.busy
                ? AppColors.brand.withValues(alpha: 0.55)
                : AppColors.brand,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.brand.withValues(alpha: _down ? 0.16 : 0.26),
                blurRadius: _down ? 12 : 22,
                offset: Offset(0, _down ? 4 : 8),
              ),
            ],
          ),
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.surface),
                    ),
                  )
                : Text(
                    widget.label,
                    style: AppText.button.copyWith(color: AppColors.surface),
                  ),
          ),
        ),
      ),
    );
  }
}
