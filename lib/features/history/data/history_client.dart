/// Reading and managing past conversations.
///
/// Sits beside [BackendClient] rather than inside it: that one exists to start
/// a call and is used mid-conversation, this one is the history screen's, and
/// keeping them apart means the home screen does not drag LiveKit's world in
/// behind it.
///
/// Every request carries the Supabase access token, read fresh each time. The
/// backend scopes every row to whoever that token says you are, so there is no
/// user id to pass and no way to ask for anybody else's.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../app/app_config.dart';
import '../../../data/trip_data.dart';
import '../../auth/data/auth_service.dart';

/// Thrown when the backend refuses or cannot be reached. Carries a message
/// written for a person, because the history screen shows it as-is.
class HistoryException implements Exception {
  const HistoryException(this.message, {this.signedOut = false});

  final String message;

  /// True when the session expired. The UI treats this differently: there is
  /// nothing to retry, you have to sign in again.
  final bool signedOut;

  @override
  String toString() => message;
}

/// One past conversation, as the list shows it.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.mode,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.saved,
  });

  final String id;

  /// Null until the conversation has been named — see the backend, which names
  /// it after the first thing the user said.
  final String? title;
  final String? preview;

  /// Null when the conversation never got as far as a result. The tile falls
  /// back to a neutral icon rather than inventing a mode.
  final TravelMode? mode;

  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status;

  /// Bookmarked from the chat screen. Drives the "Saved" filter.
  final bool saved;

  bool get isArchived => status == 'archived';

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String,
      title: json['title'] as String?,
      preview: json['preview'] as String?,
      mode: _modeFrom(json['mode'] as String?),
      messageCount: json['messageCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      status: json['status'] as String? ?? 'active',
      saved: json['saved'] as bool? ?? false,
    );
  }

  /// The backend's vocabulary is the agent's — train, flight, stay. The app's
  /// is the traveller's. This is the one place they meet.
  ///
  /// `bus` has no backend equivalent yet: the agent has no bus search, so no
  /// conversation can produce one. The chip is in the UI ready for when it
  /// does, and until then it simply matches nothing.
  static TravelMode? _modeFrom(String? raw) => switch (raw) {
        'train' => TravelMode.trains,
        'flight' => TravelMode.flights,
        'stay' => TravelMode.hotels,
        'bus' => TravelMode.bus,
        _ => null,
      };
}

/// A page of history, and whether there is more behind it.
class SessionPage {
  const SessionPage({required this.sessions, required this.hasMore});

  final List<SessionSummary> sessions;
  final bool hasMore;
}

class HistoryClient {
  HistoryClient({String? baseUrl, http.Client? client, AuthService? auth})
      : _base = baseUrl ?? AppConfig.backendUrl,
        _http = client ?? http.Client(),
        _auth = auth ?? AuthService();

  final String _base;
  final http.Client _http;
  final AuthService _auth;

  /// Generous on purpose. The old 15s was under what a cold backend needs to
  /// open its first database connection across regions, so a healthy server
  /// waking up was reported to the user as unreachable.
  static const Duration _timeout = Duration(seconds: 30);

  Map<String, String> _headers() {
    final String? token = _auth.accessToken;
    if (token == null) {
      throw const HistoryException('Sign in to see your history.',
          signedOut: true);
    }
    return <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// This user's conversations, newest first.
  Future<SessionPage> list({int limit = 20, int offset = 0}) async {
    final Uri uri = Uri.parse('$_base/api/v1/sessions').replace(
      queryParameters: <String, String>{
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final http.Response resp = await _send(() => _http.get(uri, headers: _headers()));
    final Map<String, dynamic> body =
        jsonDecode(resp.body) as Map<String, dynamic>;
    return SessionPage(
      sessions: (body['sessions'] as List<dynamic>)
          .map((dynamic e) =>
              SessionSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  /// Erase a conversation — transcript, cards and all. Not reversible.
  Future<void> delete(String id) async {
    await _send(() =>
        _http.delete(Uri.parse('$_base/api/v1/sessions/$id'), headers: _headers()));
  }

  /// Put a conversation away without deleting it.
  Future<void> archive(String id) => _patch(id, <String, dynamic>{'status': 'archived'});

  /// Bring an archived conversation back.
  Future<void> unarchive(String id) => _patch(id, <String, dynamic>{'status': 'active'});

  /// Bookmark a conversation, or un-bookmark it.
  ///
  /// Separate from archiving: a conversation can be both saved and archived,
  /// because "I want to find this again" and "I am done with this" are
  /// different things to want.
  Future<void> setSaved(String id, bool saved) =>
      _patch(id, <String, dynamic>{'saved': saved});

  /// Give a conversation a name of your own.
  Future<void> rename(String id, String title) =>
      _patch(id, <String, dynamic>{'title': title});

  Future<void> _patch(String id, Map<String, dynamic> body) async {
    await _send(() => _http.patch(
          Uri.parse('$_base/api/v1/sessions/$id'),
          headers: _headers(),
          body: jsonEncode(body),
        ));
  }

  /// Run a request and turn every failure into something worth reading.
  ///
  /// One place for this so every method answers a dead backend, an expired
  /// session and a 500 the same way, instead of each growing its own slightly
  /// different phrasing.
  ///
  /// **Retries once on a timeout.** A server that has just started pays for a
  /// database handshake to another region before it can answer anything, and
  /// the second request costs none of that. Reporting the first one as a
  /// failure meant a backend that was merely waking up looked broken — which
  /// is exactly what it did. Only timeouts are retried: a 401 or a 500 will
  /// say the same thing twice.
  Future<http.Response> _send(Future<http.Response> Function() run) async {
    http.Response? resp;
    Object? lastFailure;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        resp = await run().timeout(_timeout);
        break;
      } on HistoryException {
        rethrow; // not signed in — trying again will not help
      } on TimeoutException catch (e) {
        lastFailure = e;
        continue;
      } catch (e) {
        lastFailure = e;
        break; // a genuine connection failure; one attempt is enough
      }
    }

    if (resp == null) {
      throw HistoryException(
        lastFailure is TimeoutException
            // Said differently on purpose: "check your connection" is unhelpful
            // advice when the connection is fine and the server is slow.
            ? 'The server is taking too long to answer. Try again.'
            : 'Could not reach the server. Check your connection.',
      );
    }
    if (resp.statusCode == 401) {
      throw const HistoryException(
        'Your session expired. Sign in again.',
        signedOut: true,
      );
    }
    if (resp.statusCode == 404) {
      throw const HistoryException('That conversation is no longer there.');
    }
    if (resp.statusCode >= 400) {
      throw HistoryException('Something went wrong (${resp.statusCode}).');
    }
    return resp;
  }

  void dispose() => _http.close();
}
