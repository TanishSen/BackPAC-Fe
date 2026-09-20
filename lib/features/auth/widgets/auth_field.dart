import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// A labelled text field, in the app's own shape.
///
/// The label sits above the box rather than floating inside it. A floating
/// label is a nice trick on a form with two fields and a nuisance on a form
/// someone is filling in for the first time on a phone, because the thing that
/// tells you what to type moves and shrinks the moment you start typing.
///
/// The field grows a brand-coloured ring on focus and a red one when it has
/// something to complain about, so "where am I" and "what is wrong" are the
/// same glance.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.error,
    this.enabled = true,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  /// Shown under the field, in red. Null when there is nothing wrong.
  final String? error;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final FocusNode _focus = FocusNode();
  late bool _hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool bad = widget.error != null;
    final Color ring = bad
        ? const Color(0xFFD9534F)
        : _focus.hasFocus
            ? AppColors.brand
            : AppColors.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: AppText.label),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _focus.hasFocus ? AppColors.surface : AppColors.canvas,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: ring,
              width: _focus.hasFocus || bad ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: _hidden,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  onSubmitted: widget.onSubmitted,
                  style: AppText.message,
                  cursorColor: AppColors.brand,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppText.body,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
              if (widget.obscure)
                // The reveal is a necessity, not a nicety: a mistyped password
                // on a phone keyboard is the single most common reason a login
                // fails, and there is no way to spot one through dots.
                Semantics(
                  button: true,
                  label: _hidden ? 'Show password' : 'Hide password',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _hidden = !_hidden),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, left: 8),
                      child: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Reserve nothing when there is no error: a permanently empty line
        // under every field pushes the button down the screen for no reason.
        if (bad)
          Padding(
            padding: const EdgeInsets.only(top: 7, left: 4),
            child: Text(
              widget.error!,
              style: AppText.caption.copyWith(color: const Color(0xFFD9534F)),
            ),
          ),
      ],
    );
  }
}
