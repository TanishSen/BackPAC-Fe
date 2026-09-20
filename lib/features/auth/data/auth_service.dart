/// Signing in, and the access token everything else needs.
///
/// One thin wrapper over Supabase Auth, so the rest of the app never imports
/// the SDK directly and the sign-in method can change without a search and
/// replace. Two jobs:
///
/// 1. **Sign in, sign up, sign out.** Each returns either nothing or a message
///    written for a person. Supabase's own errors are not: "Invalid login
///    credentials" is fine, but "AuthApiException(message: ...)" on screen is
///    not, so [_readable] translates the ones a user can actually hit.
///
/// 2. **Hand out the access token.** The backend verifies it on every request
///    that touches someone's data. Read it through [accessToken] rather than
///    caching it anywhere: it expires roughly hourly, the SDK refreshes it in
///    the background, and a copy taken at sign-in would quietly go stale and
///    start returning 401 an hour into a session.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// The Supabase client, or null when there isn't one.
  ///
  /// Null is a real state, not a defensive flourish. `Supabase.initialize` can
  /// fail — no network on a cold start, a misconfigured build — and main.dart
  /// deliberately carries on when it does, because the welcome screen and the
  /// orb do not need an account. Reaching for `Supabase.instance` before a
  /// successful initialize throws an assertion, so every method here goes
  /// through this and reports "sign-in unavailable" rather than crashing the
  /// screen someone is looking at. Widget tests never initialize it at all,
  /// which is how this was found.
  SupabaseClient? get _client {
    if (_injected != null) return _injected;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Whether sign-in is possible at all right now.
  bool get available => _client != null;

  /// Whoever is signed in, or null.
  User? get currentUser => _client?.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Fires on sign-in, sign-out and token refresh. The app listens to this
  /// rather than checking a flag, so a session expiring in the background
  /// takes you back to the login screen instead of failing on the next tap.
  ///
  /// An empty stream when there is no client: a listener that never fires is
  /// correct, because without Supabase nothing can ever sign in or out.
  Stream<AuthState> get changes =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  /// The current access token, fresh. Null when signed out.
  ///
  /// This is the Supabase JWT the backend verifies against the project's
  /// published signing keys — its `sub` claim is the user id that every
  /// session, message and trip result is filed under.
  String? get accessToken => _client?.auth.currentSession?.accessToken;

  /// Sign in with an email and password. Returns null on success, or a
  /// message to show.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) return _unavailable;
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on AuthException catch (e) {
      return _readable(e);
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// Create an account. Returns null on success, or a message to show.
  ///
  /// Whether this signs you straight in depends on one setting in the Supabase
  /// dashboard: with email confirmation on, the account exists but there is no
  /// session until the link is clicked. [needsConfirmation] answers that for
  /// the caller so the UI can say so rather than appearing to hang.
  Future<String?> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) return _unavailable;
    try {
      await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName == null || displayName.trim().isEmpty
            ? null
            : <String, dynamic>{'display_name': displayName.trim()},
      );
      return null;
    } on AuthException catch (e) {
      return _readable(e);
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// What to call this person on screen, or null if we have nothing to go on.
  ///
  /// Three sources, in descending order of how much the user meant them:
  ///
  /// 1. `display_name` — what they typed into "Your name" when signing up.
  /// 2. `full_name` / `name` — what Google or Apple hands over, for accounts
  ///    that came in that way rather than through the form.
  /// 3. The local part of their email, tidied up. A guess, but "Hi, Tanish"
  ///    from tanishsen@… is a better greeting than a blank space, and far
  ///    better than calling everyone by a name from the mockups.
  ///
  /// Null only when there is no session at all.
  String? get displayName {
    final User? u = currentUser;
    if (u == null) return null;

    final Map<String, dynamic> meta = u.userMetadata ?? <String, dynamic>{};
    for (final String key in const <String>['display_name', 'full_name', 'name']) {
      final Object? value = meta[key];
      if (value is String && value.trim().isNotEmpty) {
        // Just the first name. "Hi, Tanish Sen" reads like a form letter.
        return value.trim().split(RegExp(r'\s+')).first;
      }
    }

    final String? email = u.email;
    return email == null ? null : _fromEmail(email);
  }

  /// A first name out of an email address, or null if there isn't one in there.
  ///
  /// Handles the shapes people actually have — tanish.sen@, tanish_sen@,
  /// tanishsen.2520@ — by cutting at the first separator and dropping anything
  /// that is just digits. Gives up rather than guess when the result would be
  /// nonsense, because "Hi, Xk92" is worse than no name at all.
  @visibleForTesting
  static String? nameFromEmailForTest(String email) => _fromEmail(email);

  static String? _fromEmail(String email) {
    // Checked here rather than only at the call site, so the function is safe
    // to call with anything — a test found it happily turning 'not-an-email'
    // into 'Not'.
    if (!email.contains('@')) return null;
    final String local = email.split('@').first;
    final String first = local.split(RegExp(r'[._+\-0-9]')).first;
    if (first.length < 2) return null;
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  /// True when an account was created but no session came with it — email
  /// confirmation is on and the link has not been clicked yet.
  bool get needsConfirmation => !isSignedIn;

  Future<void> signOut() async => _client?.auth.signOut();

  static const String _unavailable =
      'Sign-in is unavailable right now. Check your connection and restart '
      'the app.';

  /// Send a password reset email.
  Future<String?> sendPasswordReset(String email) async {
    final SupabaseClient? client = _client;
    if (client == null) return _unavailable;
    try {
      await client.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return _readable(e);
    } catch (_) {
      return 'Could not reach the server. Check your connection.';
    }
  }

  /// Supabase's error text, rewritten for someone who is not a developer.
  ///
  /// Deliberately vague about *which* half of a wrong email/password pair was
  /// wrong. "No account with that email" tells anyone who asks which of your
  /// users exist, which is a free list of addresses to go and attack.
  static String _readable(AuthException e) {
    final String raw = e.message.toLowerCase();
    if (raw.contains('invalid login credentials')) {
      return 'That email and password do not match.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Check your email and confirm your address first.';
    }
    if (raw.contains('already registered') || raw.contains('already exists')) {
      return 'There is already an account with that email. Try logging in.';
    }
    if (raw.contains('password') && raw.contains('least')) {
      return 'Use a password of at least 6 characters.';
    }
    // Two different limits wear the same 429, and telling someone to "wait a
    // minute" when the real wait is an hour is worse than saying nothing.
    if (raw.contains('email rate limit') ||
        raw.contains('over_email_send_rate_limit')) {
      // Supabase's built-in sender allows only a couple of emails an hour per
      // project, shared by everyone using it. Hitting this is a server-side
      // quota, not anything this person did.
      return 'Too many sign-ups from this app in the last hour. Try again '
          'later, or log in if you already have an account.';
    }
    if (raw.contains('rate limit') || raw.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return e.message;
  }
}
