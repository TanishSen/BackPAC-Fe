/// Talks to BackPAC-BE. Its one job right now: start a voice session.
///
/// The app never holds any secret. It asks the backend to start a session; the
/// backend mints a LiveKit room + a room-scoped token and returns them here.
/// The app joins the room with that token (see [VoiceSession]).
library;

import 'dart:convert';

import '../auth/data/auth_service.dart';

import 'package:http/http.dart' as http;

/// What the backend hands back from POST /api/v1/sessions.
/// One turn of a conversation that already happened, replayed on resume.
class PastMessage {
  const PastMessage({required this.role, required this.content});

  /// 'user' or 'agent'.
  final String role;
  final String content;

  bool get isUser => role == 'user';

  factory PastMessage.fromJson(Map<String, dynamic> json) => PastMessage(
        role: json['role'] as String,
        content: json['content'] as String,
      );
}

class SessionInfo {
  const SessionInfo({
    required this.sessionId,
    required this.agentId,
    required this.livekitUrl,
    required this.token,
    required this.roomName,
    this.isResuming = false,
    this.previousMessages = const <PastMessage>[],
  });

  final String sessionId;
  final String agentId;
  final String livekitUrl;
  final String token;
  final String roomName;

  /// True when this call carries on an earlier conversation rather than
  /// starting one.
  final bool isResuming;

  /// What was said last time, oldest first. Empty for a new conversation.
  final List<PastMessage> previousMessages;

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final lk = json['livekit'] as Map<String, dynamic>;
    return SessionInfo(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String,
      livekitUrl: lk['url'] as String,
      token: lk['token'] as String,
      roomName: lk['roomName'] as String,
      isResuming: json['isResuming'] as bool? ?? false,
      previousMessages: ((json['previousMessages'] as List<dynamic>?) ??
              const <dynamic>[])
          .map((dynamic e) => PastMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Calls the BackPAC backend on behalf of the signed-in user.
///
/// Every request carries the Supabase access token, because every route it
/// touches is scoped to one person's data. See BackPAC-BE/app/shared/auth.py.
class BackendClient {
  BackendClient({required this.baseUrl, http.Client? client})
      : _http = client ?? http.Client();

  /// e.g. http://10.0.2.2:8000 on the Android emulator, or your deployed URL.
  final String baseUrl;
  final http.Client _http;

  /// Start a session for [agentId]. Returns the room the app should join.
  /// Throws if the backend or the agent is unreachable.
  /// Start a session for [agentId], or carry on an earlier one.
  ///
  /// Pass [resumeSessionId] to continue a conversation from the history list.
  /// The backend puts the agent back into the same room — which is also the
  /// same LangGraph thread — so it picks up knowing what was already said,
  /// and returns that transcript to paint into the thread.
  Future<SessionInfo> startSession({
    required String agentId,
    String? participantName,
    String? resumeSessionId,
  }) async {
    final token = AuthService().accessToken;
    if (token == null) {
      // Caught rather than sent: the backend would answer 401 anyway, and a
      // round trip to be told what we already know is a second of someone
      // staring at a spinner.
      throw Exception('startSession failed: not signed in');
    }
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/sessions'),
      headers: {
        'Content-Type': 'application/json',
        // Read fresh on every call. The token expires about hourly and the
        // Supabase SDK refreshes it in the background, so a copy held since
        // sign-in would start failing an hour into a session.
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'agentId': agentId,
        'participantName': ?participantName,
        'resumeSessionId': ?resumeSessionId,
      }),
    );
    if (resp.statusCode == 401) {
      throw Exception('startSession failed: your session expired — sign in again');
    }
    if (resp.statusCode != 200) {
      throw Exception('startSession failed (${resp.statusCode}): ${resp.body}');
    }
    return SessionInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void dispose() => _http.close();
}
