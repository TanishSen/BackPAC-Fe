/// Talks to BackPAC-BE. Its one job right now: start a voice session.
///
/// The app never holds any secret. It asks the backend to start a session; the
/// backend mints a LiveKit room + a room-scoped token and returns them here.
/// The app joins the room with that token (see [VoiceSession]).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the backend hands back from POST /api/v1/sessions.
class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.agentId,
    required this.livekitUrl,
    required this.token,
    required this.roomName,
  });

  final String sessionId;
  final String agentId;
  final String livekitUrl;
  final String token;
  final String roomName;

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final lk = json['livekit'] as Map<String, dynamic>;
    return SessionInfo(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String,
      livekitUrl: lk['url'] as String,
      token: lk['token'] as String,
      roomName: lk['roomName'] as String,
    );
  }
}

class BackendClient {
  BackendClient({required this.baseUrl, http.Client? client})
      : _http = client ?? http.Client();

  /// e.g. http://10.0.2.2:8000 on the Android emulator, or your deployed URL.
  final String baseUrl;
  final http.Client _http;

  /// Start a session for [agentId]. Returns the room the app should join.
  /// Throws if the backend or the agent is unreachable.
  Future<SessionInfo> startSession({
    required String agentId,
    String? participantName,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/sessions'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'agentId': agentId,
        'participantName': ?participantName,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('startSession failed (${resp.statusCode}): ${resp.body}');
    }
    return SessionInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void dispose() => _http.close();
}
