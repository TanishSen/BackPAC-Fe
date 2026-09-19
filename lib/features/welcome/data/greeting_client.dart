/// Fetches the lines the orb says on the welcome screen.
///
/// These are short audio files plus a loudness track, not a voice call — no
/// room, no session, no microphone permission before the user has tapped
/// anything. See `BackPAC-Agent/src/bot/voice/greeting.py`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// A line the orb can say: the words, where to get the audio, and how loud it
/// is over time.
class SpokenLine {
  const SpokenLine({
    required this.text,
    required this.audioUrl,
    required this.levels,
    required this.frameMs,
  });

  final String text;

  /// Where the WAV lives. A URL rather than inline bytes so the browser and the
  /// OS cache it: inlining base64 audio made the welcome set a 2.5 MB response
  /// that had to be re-downloaded on every launch.
  final String audioUrl;

  /// One loudness value (0..1) per [frameMs]. Stepping through this in time
  /// with playback is what makes the orb move to the actual words rather than
  /// to a generic wobble.
  final List<double> levels;
  final int frameMs;

  Duration get duration => Duration(milliseconds: levels.length * frameMs);

  static SpokenLine fromJson(Map<String, dynamic> json, String baseUrl) {
    final String text = json['text'] as String;
    return SpokenLine(
      text: text,
      audioUrl: '$baseUrl/api/v1/voice/line.wav'
          '?text=${Uri.encodeQueryComponent(text)}',
      levels: <double>[
        for (final dynamic v in json['levels'] as List<dynamic>)
          (v as num).toDouble(),
      ],
      frameMs: json['frameMs'] as int,
    );
  }
}

/// Everything the orb might say while you are on the welcome screen.
class WelcomeLines {
  const WelcomeLines({
    required this.greeting,
    required this.poke,
    required this.idle,
  });

  /// What it opens with.
  final List<SpokenLine> greeting;

  /// What it says when you prod it.
  final List<SpokenLine> poke;

  /// What it says when you leave it alone.
  final List<SpokenLine> idle;

  static WelcomeLines fromJson(Map<String, dynamic> json, String baseUrl) {
    List<SpokenLine> group(String key) => <SpokenLine>[
          for (final dynamic line in json[key] as List<dynamic>)
            SpokenLine.fromJson(line as Map<String, dynamic>, baseUrl),
        ];
    return WelcomeLines(
      greeting: group('greeting'),
      poke: group('poke'),
      idle: group('idle'),
    );
  }
}

class GreetingClient {
  GreetingClient({required this.baseUrl, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  /// The opening line, or null if it could not be fetched.
  ///
  /// Null rather than throwing: a spoken hello is a nice touch, not a
  /// requirement. If the backend is down the welcome screen greets silently and
  /// the app works exactly as it did before.
  Future<SpokenLine?> fetchGreeting({String? text}) async {
    final Map<String, dynamic>? json = await _get(
      '/api/v1/voice/greeting',
      text == null ? null : <String, String>{'text': text},
      const Duration(seconds: 12),
    );
    return json == null ? null : SpokenLine.fromJson(json, baseUrl);
  }

  /// Every line for this screen, in one request.
  ///
  /// Generous timeout: a cold agent synthesises the whole set before answering
  /// (about five seconds, all lines in parallel). The app asks for this in the
  /// background, so that wait is never on screen.
  Future<WelcomeLines?> fetchWelcomeLines() async {
    final Map<String, dynamic>? json = await _get(
      '/api/v1/voice/welcome-lines',
      null,
      const Duration(seconds: 90),
    );
    return json == null ? null : WelcomeLines.fromJson(json, baseUrl);
  }

  Future<Map<String, dynamic>?> _get(
    String path,
    Map<String, String>? query,
    Duration timeout,
  ) async {
    try {
      final Uri uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final http.Response resp = await _http.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();
}
