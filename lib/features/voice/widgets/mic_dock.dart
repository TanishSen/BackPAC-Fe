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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: auraHeight,
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
            child: VoiceAura(state: state, level: level, height: auraHeight),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
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
    final String text = switch (state) {
      VoiceState.idle => idleHint,
      VoiceState.listening => partial.isEmpty ? 'Listening…' : partial,
      VoiceState.thinking => 'Thinking…',
      VoiceState.speaking => 'Tap to interrupt',
    };
    final bool isTranscript =
        state == VoiceState.listening && partial.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Container(
            key: ValueKey<String>(text),
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isTranscript
                  ? AppColors.surface
                  : AppColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              boxShadow: isTranscript
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x142A2140),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isTranscript ? 15.5 : 14,
                height: 1.35,
                fontWeight: isTranscript ? FontWeight.w500 : FontWeight.w500,
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
