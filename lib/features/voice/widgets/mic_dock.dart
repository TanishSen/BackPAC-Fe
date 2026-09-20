import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../voice_controller.dart';
import 'mic_button.dart';
import 'voice_aura.dart';

/// The bottom of every voice screen: the bloom, what is being heard, and the
/// mic itself.
///
/// It is deliberately the only control down there. Typing is still possible —
/// the chat exposes a keyboard — but the default way to talk to backPAC is
/// to talk to it.
class MicDock extends StatelessWidget {
  const MicDock({
    super.key,
    required this.state,
    required this.level,
    required this.onTap,
    this.partial = '',
    this.auraHeight = 300,
    this.showTranscript = true,
    this.scrim = true,
    this.idleHint = 'Tap and tell me where to',
    this.caption,
  });

  final VoiceState state;
  final ValueListenable<double> level;
  final VoidCallback onTap;

  /// Words heard so far, shown while listening.
  final String partial;
  final double auraHeight;

  /// The home screen keeps the caption short; the chat shows live words.
  final bool showTranscript;

  /// Fades the page out underneath the bloom, so a list scrolling behind the
  /// dock disappears into the colour instead of colliding with the mic.
  final bool scrim;
  final String idleHint;

  /// Overrides the caption entirely. For states the dock cannot infer from
  /// [VoiceState] — "Connecting…", say, where the dock would otherwise read
  /// "Thinking…" and claim the assistant is working on something.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    // The dock deliberately runs to the very bottom of the screen so its bloom
    // is not cut off by a white strip — the chat wraps it in SafeArea(bottom:
    // false) for that reason. The button then has to keep clear of the system
    // gesture bar itself, or on a gesture-navigation phone it ends up sitting
    // in the swipe-up area.
    final double systemInset = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: auraHeight + systemInset,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          if (scrim) ...<Widget>[
            // A short fade at the very bottom — enough to stop a list running
            // into the mic, not a white wash over the whole lower third.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: auraHeight * 0.46,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AppColors.canvas.withValues(alpha: 0),
                        AppColors.canvas.withValues(alpha: 0.55),
                        AppColors.canvas.withValues(alpha: 0.92),
                      ],
                      stops: const <double>[0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // And a soft pool right behind the button, so whatever is under the
            // mic itself is quietened without touching the rest of the page.
            Positioned(
              bottom: -30,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        AppColors.canvas.withValues(alpha: 0.62),
                        AppColors.canvas.withValues(alpha: 0.38),
                        AppColors.canvas.withValues(alpha: 0),
                      ],
                      stops: const <double>[0.0, 0.42, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
          Positioned.fill(
            child: VoiceAura(
              state: state,
              level: level,
              height: auraHeight + systemInset,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            // The button is the bottom-most thing in the dock and sits low,
            // with the caption stacked above it — the arrangement in the
            // wireframe. MicButton draws itself inside a box 2.15x its own
            // width, so a negative offset here still leaves the visible circle
            // well inside the dock; it is trimming that invisible padding.
            bottom: systemInset - 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (showTranscript) IgnorePointer(child: _caption(context)),
                MicButton(state: state, level: level, onTap: onTap),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(BuildContext context) {
    final String text = caption ??
        switch (state) {
      VoiceState.idle => idleHint,
      VoiceState.listening => partial.isEmpty ? 'Listening…' : partial,
      VoiceState.thinking => 'Thinking…',
      VoiceState.speaking => 'Tap to interrupt',
    };
    final bool isTranscript =
        state == VoiceState.listening && partial.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        // Fade *through*, not across. The default cross-fade leaves both
        // captions at half opacity on top of each other, and two centred
        // strings of different lengths superimposed read as neither —
        // "Starting a session…" over "Thinking…" came out as "StartThinking…".
        // The old one is gone by the midpoint, the new one starts there.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchOutCurve: const Interval(0, 0.5, curve: Curves.easeOut),
          switchInCurve: const Interval(0.5, 1, curve: Curves.easeIn),
          // Bare text. It used to sit in a white pill, which reads as a
          // control you could press rather than a label for the one below it;
          // the dock already has its own bloom of colour to lift the words off
          // the page, so the card was doing nothing but adding an edge.
          child: ConstrainedBox(
            key: ValueKey<String>(text),
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // A live transcript is the user's own words, so it gets the
                // darker, slightly larger treatment; everything else is a
                // quiet status line.
                fontSize: isTranscript ? 16 : 15,
                height: 1.35,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: isTranscript ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
