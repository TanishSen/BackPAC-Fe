import 'dart:async';
import 'dart:math' as math;

/// What a speech recogniser tells us as it listens.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// Words so far, still being revised.
class PartialTranscript extends SpeechEvent {
  const PartialTranscript(this.text);
  final String text;
}

/// The recogniser has settled on this.
class FinalTranscript extends SpeechEvent {
  const FinalTranscript(this.text);
  final String text;
}

/// Loudness right now, 0..1. Drives every voice animation on screen.
class SpeechAmplitude extends SpeechEvent {
  const SpeechAmplitude(this.level);
  final double level;
}

/// The seam for speech-to-text.
///
/// The app ships [SimulatedSpeechService] so the whole voice flow runs with no
/// permissions and no packages. Wiring a real recogniser (speech_to_text, or a
/// platform channel) means implementing this and nothing else — no widget
/// knows where the words come from.
abstract class SpeechService {
  Stream<SpeechEvent> get events;

  /// True once the platform has granted the microphone.
  Future<bool> start();

  /// Stop listening. Returns the final transcript, or null if nothing was said.
  Future<String?> stop();

  void dispose();
}

/// Types out a plausible request word by word, with a loudness trace to match.
class SimulatedSpeechService implements SpeechService {
  SimulatedSpeechService({math.Random? random, List<String>? phrases})
      : _rng = random ?? math.Random(),
        _phrases = phrases ?? _defaultPhrases;

  static const List<String> _defaultPhrases = <String>[
    'I want to plan a weekend trip to Goa',
    'Find me a train to Jaipur next Friday',
    'Somewhere quiet in the mountains for three nights',
    'Two flights to Kochi in the first week of March',
    'A cheap hotel near the beach, walking distance',
  ];

  final math.Random _rng;
  final List<String> _phrases;
  final StreamController<SpeechEvent> _out =
      StreamController<SpeechEvent>.broadcast();

  Timer? _amplitude;
  Timer? _words;
  List<String> _pending = <String>[];
  String _said = '';
  double _t = 0;

  @override
  Stream<SpeechEvent> get events => _out.stream;

  @override
  Future<bool> start() async {
    _said = '';
    _pending = _phrases[_rng.nextInt(_phrases.length)].split(' ');

    // Loudness first: the rings should react the moment the mic opens, before
    // any words have been recognised.
    _amplitude = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _t += 0.06;
      // Speech-shaped: syllables riding on a slower breath, never silent, never
      // pinned at the top.
      final double syllable = 0.5 + 0.5 * math.sin(_t * 11.0);
      final double breath = 0.5 + 0.5 * math.sin(_t * 1.7 + 1.1);
      final double jitter = _rng.nextDouble() * 0.18;
      final double level =
          (0.18 + 0.55 * syllable * (0.45 + 0.55 * breath) + jitter)
              .clamp(0.0, 1.0);
      _out.add(SpeechAmplitude(level));
    });

    _words = Timer.periodic(const Duration(milliseconds: 260), (Timer t) {
      if (_pending.isEmpty) {
        t.cancel();
        return;
      }
      _said = _said.isEmpty ? _pending.first : '$_said ${_pending.first}';
      _pending.removeAt(0);
      _out.add(PartialTranscript(_said));
    });
    return true;
  }

  @override
  Future<String?> stop() async {
    _amplitude?.cancel();
    _words?.cancel();
    _amplitude = null;
    _words = null;
    _out.add(const SpeechAmplitude(0));
    if (_said.trim().isEmpty) return null;
    final String text = _said.trim();
    _out.add(FinalTranscript(text));
    return text;
  }

  @override
  void dispose() {
    _amplitude?.cancel();
    _words?.cancel();
    _out.close();
  }
}
