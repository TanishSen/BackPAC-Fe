/// Plays what the orb says, and publishes a live level for its mouth.
///
/// The level track and the audio start together and run on the same clock, so
/// the orb is shaped by the actual words rather than animating near them.
///
/// **The animation runs whether or not the audio does.** Browsers refuse to
/// play sound before the user has interacted with the page, and the welcome
/// screen greets before anyone has touched anything — so on web the *opening*
/// greeting is usually silent. Driving the orb from the level track regardless
/// means it still visibly says hello, and [retryAudio] lets the caller release
/// the sound on the first real tap. Every line after that is audible, because
/// by then there has been a gesture. On a phone there is no such rule.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'greeting_client.dart';

class GreetingVoice {
  GreetingVoice()
      : _player = AudioPlayer(playerId: 'orb-voice')
          ..setReleaseMode(ReleaseMode.stop);

  final AudioPlayer _player;

  /// 0..1, refreshed once per audio frame. A notifier rather than setState:
  /// it changes 20 times a second and only the orb needs to know.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  /// True while a line is being said.
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  Timer? _ticker;

  /// A line that was ready but which the browser refused to play. Released by
  /// [retryAudio] on the next gesture.
  SpokenLine? pendingAudio;

  /// Say it: start the audio, and step the level track alongside.
  ///
  /// Interrupts whatever was being said — poking the orb mid-sentence should
  /// get a reaction, not a queue.
  Future<void> say(SpokenLine line) async {
    _ticker?.cancel();
    speaking.value = true;

    try {
      await _player.stop();
      await _player.play(UrlSource(line.audioUrl));
      pendingAudio = null;
    } catch (e) {
      // Usually the browser's autoplay policy, which is expected and harmless.
      // Anything else is a real failure worth seeing — swallowing it silently
      // is how an Android audio-focus problem went unnoticed while the orb
      // mouthed along to nothing.
      debugPrint('[backPAC] could not play "${line.text}": $e');
      pendingAudio = line;
    }

    _runLevels(line);
  }

  /// Walks the level track in time with playback.
  ///
  /// The frame is computed from a clock rather than counted per tick. A
  /// counter assumes every tick arrives on time, and they do not: a browser
  /// throttles timers in a background tab to about once a second, which turns
  /// a two-second line into forty seconds of slow motion that never ends — the
  /// audio finishes, the orb keeps mouthing, and anything waiting on
  /// [speaking] waits forever. Reading the elapsed time instead means a
  /// throttled tab skips frames and still finishes on schedule.
  void _runLevels(SpokenLine line) {
    final Stopwatch clock = Stopwatch()..start();
    _ticker = Timer.periodic(Duration(milliseconds: line.frameMs), (Timer t) {
      final int frame = clock.elapsedMilliseconds ~/ line.frameMs;
      if (frame >= line.levels.length) {
        t.cancel();
        level.value = 0;
        speaking.value = false;
        return;
      }
      level.value = line.levels[frame];
    });
  }

  /// After a user gesture, play the line the browser refused earlier.
  Future<void> retryAudio() async {
    final SpokenLine? blocked = pendingAudio;
    if (blocked == null) return;
    pendingAudio = null;
    try {
      await _player.stop();
      await _player.play(UrlSource(blocked.audioUrl));
    } catch (e) {
      debugPrint('[backPAC] retry still blocked: $e');
    }
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    level.value = 0;
    speaking.value = false;
    unawaited(_player.stop());
  }

  void dispose() {
    _ticker?.cancel();
    _player.dispose();
    level.dispose();
    speaking.dispose();
  }
}
