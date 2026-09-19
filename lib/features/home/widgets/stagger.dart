import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// Fades and lifts its child once, [index] beats after the screen appears.
///
/// Used on the home sections so the page assembles itself top-down instead of
/// snapping in all at once.
class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.enter,
  );

  Timer? _start;

  @override
  void initState() {
    super.initState();
    _start = Timer(AppDurations.stagger * widget.index, _c.forward);
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation curve =
        CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}
