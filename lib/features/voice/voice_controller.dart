import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'speech_service.dart';

enum VoiceState {
  /// Nothing happening. The mic waits.
  idle,

  /// The user is talking; words are arriving.
  listening,

  /// The mic is closed and the assistant is working.
  thinking,

  /// The assistant is talking back.
  speaking,
}

/// Runs the voice half of the conversation.
///
/// Keeps [state], the partial transcript, and a live [level] the animations
/// read. Level is a separate [ValueNotifier] on purpose: it changes ~16 times a
/// second and must not rebuild the page, only the painters that care.
class VoiceController extends ChangeNotifier {
  VoiceController({required SpeechService service, math.Random? random})
      : _speech = service,
        _rng = random ?? math.Random() {
    _sub = _speech.events.listen(_onEvent);
  }

  final SpeechService _speech;
  final math.Random _rng;
  StreamSubscription<SpeechEvent>? _sub;

  /// 0..1, updated continuously while anyone is talking.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  String _partial = '';
  String get partial => _partial;

  bool get isBusy => _state != VoiceState.idle;

  Timer? _speaking;
  Timer? _speakLevel;



  void _onEvent(SpeechEvent e) {
    switch (e) {
      case SpeechAmplitude(:final double level):
        this.level.value = level;
      case PartialTranscript(:final String text):
        _partial = text;
        notifyListeners();
      case FinalTranscript():
        break; // start/stop own the transcript's lifecycle
    }
  }

  Future<void> startListening() async {
    if (_state != VoiceState.idle) return;
    _partial = '';
    _state = VoiceState.listening;
    notifyListeners();
    final bool ok = await _speech.start();
    if (!ok) {
      _state = VoiceState.idle;
      notifyListeners();
    }
  }

  /// Close the mic. Returns the transcript, or null if nothing was said.
  Future<String?> stopListening({bool keep = true}) async {
    if (_state != VoiceState.listening) return null;
    final String? text = await _speech.stop();
    level.value = 0;
    _partial = '';
    _state = keep && text != null ? VoiceState.thinking : VoiceState.idle;
    notifyListeners();
    return keep ? text : null;
  }

  /// The assistant starts talking. Held for as long as the words would take to
  /// say out loud, so the animation matches the length of the answer.
  void speak(String text) {
    _speaking?.cancel();
    _speakLevel?.cancel();
    _state = VoiceState.speaking;
    notifyListeners();

    final int words = text.trim().split(RegExp(r'\s+')).length;
    // ~2.6 words a second, with a floor and a ceiling so nothing drags.
    final Duration held = Duration(
      milliseconds: (words / 2.6 * 1000).round().clamp(1400, 9000),
    );

    double t = 0;
    _speakLevel = Timer.periodic(const Duration(milliseconds: 60), (_) {
      t += 0.06;
      final double syllable = 0.5 + 0.5 * math.sin(t * 8.2);
      final double phrase = 0.5 + 0.5 * math.sin(t * 1.3 + 0.7);
      level.value =
          (0.14 + 0.5 * syllable * (0.5 + 0.5 * phrase) + _rng.nextDouble() * 0.1)
              .clamp(0.0, 1.0);
    });

    _speaking = Timer(held, () {
      _speakLevel?.cancel();
      level.value = 0;
      _state = VoiceState.idle;
      notifyListeners();
    });
  }

  /// Cut the assistant off — tapping the mic while it talks does this.
  void stopSpeaking() {
    _speaking?.cancel();
    _speakLevel?.cancel();
    level.value = 0;
    if (_state == VoiceState.speaking) {
      _state = VoiceState.idle;
      notifyListeners();
    }
  }

  /// The assistant is working, before it has anything to say.
  void think() {
    if (_state == VoiceState.speaking) return;
    _state = VoiceState.thinking;
    notifyListeners();
  }

  void settle() {
    if (_state == VoiceState.thinking) {
      _state = VoiceState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _speaking?.cancel();
    _speakLevel?.cancel();
    _sub?.cancel();
    _speech.dispose();
    level.dispose();
    super.dispose();
  }
}
