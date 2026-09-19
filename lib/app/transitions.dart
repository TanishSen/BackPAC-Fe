import 'package:flutter/material.dart';

/// Slides a page up over the one below it, the way a sheet does.
///
/// Used for home → chat: tapping the mic lifts the conversation into view
/// rather than cutting to it, so the mic appears to stay put while everything
/// else moves.
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  SlideUpRoute({required this.page, this.duration = const Duration(milliseconds: 460)})
      : super(
          transitionDuration: duration,
          reverseTransitionDuration:
              Duration(milliseconds: (duration.inMilliseconds * 0.8).round()),
          opaque: false,
          barrierColor: Colors.transparent,
          pageBuilder: (BuildContext context, Animation<double> animation,
                  Animation<double> secondary) =>
              page,
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondary,
            Widget child,
          ) {
            final Animation<double> curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                // Fades in over the first third only: the movement carries it,
                // the fade just softens the edges.
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0, 0.35, curve: Curves.easeOut),
                ),
                child: child,
              ),
            );
          },
        );

  final Widget page;
  final Duration duration;
}
