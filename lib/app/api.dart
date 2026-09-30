/// One way to call the backend's signed-in routes.
///
/// History, the profile and Premium all talk to the same API with the same
/// rules — a fresh Supabase token on every request, one retry on a timeout,
/// and failures turned into a sentence a person can read — so those rules
/// live here once rather than drifting apart in three clients.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/auth/data/auth_service.dart';
import 'app_config.dart';

/// Thrown when the backend refuses or cannot be reached. Carries a message
/// written for a person, because screens show it as-is.
class ApiException implements Exception {
  const ApiException(this.message, {this.signedOut = false, this.statusCode});

  final String message;

  /// True when the session expired. The UI treats this differently: there is
  /// nothing to retry, you have to sign in again.
  final bool signedOut;

  /// The HTTP status, when there was a response at all.
  final int? statusCode;

  /// 402: the free plan's allowance is used up. The caller offers Premium.
  bool get needsUpgrade => statusCode == 402;

  @override
  String toString() => message;
}

class Api {
  Api({
    String? baseUrl,
    http.Client? client,
    String? Function()? accessToken,
  })  : _base = baseUrl ?? AppConfig.backendUrl,
        _http = client ?? http.Client(),
        _token = accessToken ?? (() => AuthService().accessToken);

  final String _base;
  final http.Client _http;

  /// Read on every request: the token expires about hourly and the Supabase
  /// SDK refreshes it in the background, so a copy would go stale.
  final String? Function() _token;

  /// Generous on purpose. A cold backend opens its first database connection
  /// across regions, and a healthy server waking up must not read as down.
  static const Duration _timeout = Duration(seconds: 30);

  Map<String, String> _headers() {
    final String? token = _token();
    if (token == null) {
      throw const ApiException('Sign in first.', signedOut: true);
    }
    return <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_base$path').replace(queryParameters: query);

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _json(() => _http.get(_uri(path, query), headers: _headers()));

  Future<Object?> post(String path, {Object? body}) => _json(() => _http.post(
        _uri(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ));

  Future<Object?> patch(String path, {required Object body}) =>
      _json(() => _http.patch(
            _uri(path),
            headers: _headers(),
            body: jsonEncode(body),
          ));

  Future<Object?> delete(String path) =>
      _json(() => _http.delete(_uri(path), headers: _headers()));

  Future<Object?> _json(Future<http.Response> Function() run) async {
    final http.Response resp = await _send(run);
    if (resp.body.isEmpty) return null; // 204
    try {
      return jsonDecode(resp.body);
    } on FormatException {
      throw const ApiException('The server sent something unreadable.');
    }
  }

  /// Run a request and turn every failure into something worth reading.
  ///
  /// **Retries once on a timeout.** A server that has just started pays for a
  /// database handshake before it can answer anything, and the second request
  /// costs none of that. Only timeouts are retried: a 401 or a 500 will say
  /// the same thing twice.
  Future<http.Response> _send(Future<http.Response> Function() run) async {
    http.Response? resp;
    Object? lastFailure;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        resp = await run().timeout(_timeout);
        break;
      } on ApiException {
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
      throw ApiException(
        lastFailure is TimeoutException
            // "Check your connection" is unhelpful advice when the connection
            // is fine and the server is slow.
            ? 'The server is taking too long to answer. Try again.'
            : 'Could not reach the server. Check your connection.',
      );
    }
    final int code = resp.statusCode;
    if (code == 401) {
      throw const ApiException(
        'Your session expired. Sign in again.',
        signedOut: true,
        statusCode: 401,
      );
    }
    if (code >= 400) {
      throw ApiException(
        _serverMessage(resp) ??
            (code == 404
                ? 'That is no longer there.'
                : 'Something went wrong ($code).'),
        statusCode: code,
      );
    }
    return resp;
  }

  /// The backend's own explanation, when it gave one worth showing.
  ///
  /// Its errors are written for people ("You already have a group called
  /// Mountains.") — `{"error": …}` from the app, `{"detail": "…"}` from auth
  /// and limits. Validation detail (a list) is for developers and is not shown.
  static String? _serverMessage(http.Response resp) {
    if (resp.statusCode >= 500) return null;
    try {
      final Object? body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) {
        final Object? text = body['error'] ?? body['detail'];
        if (text is String && text.isNotEmpty) return text;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  void dispose() => _http.close();
}
