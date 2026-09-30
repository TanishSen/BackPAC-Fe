/// Where the app points, and which conversation engine it uses.
///
/// Everything here can be overridden at build time without touching code:
///
///   flutter run --dart-define=BACKEND_URL=https://api.example.com
///   flutter run --dart-define=LIVE_VOICE=false      # offline scripted demo
///
/// Nothing secret belongs in this file. The app never holds a LiveKit, Claude
/// or ElevenLabs key — it asks the backend to start a session and the backend
/// hands back a token scoped to that one room. See BackPAC-BE/.env.
library;

// `defaultTargetPlatform` rather than `dart:io`'s Platform: importing dart:io
// at all breaks the web build, even behind a `kIsWeb` runtime check, because
// the failure is at compile time.
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class AppConfig {
  const AppConfig._();

  static const String _backendOverride = String.fromEnvironment('BACKEND_URL');

  /// The BackPAC backend.
  ///
  /// The default is a local dev server, and it differs per platform for one
  /// annoying reason: an Android emulator is its own virtual machine, so
  /// `localhost` there means the emulator, not your Mac. `10.0.2.2` is the
  /// alias that reaches the host. On a real phone neither works — pass your
  /// machine's LAN address with --dart-define=BACKEND_URL.
  static String get backendUrl {
    // A trailing slash would make every path `//api/v1/…`, which 404s.
    if (_backendOverride.isNotEmpty) {
      return _backendOverride.replaceFirst(RegExp(r'/+$'), '');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  /// Which agent the backend should start. One today; the field exists so a
  /// second (say a bookings agent) needs no plumbing.
  static const String agentId = String.fromEnvironment(
    'AGENT_ID',
    defaultValue: 'trip-planner',
  );

  // --- Supabase (sign-in) ------------------------------------------------
  //
  // Both of these are public by design. The URL is a hostname, and the
  // publishable key identifies the project without granting anything: what it
  // can reach is decided by row-level security in the database, and our tables
  // have RLS on with no policies, so it can reach none of them. The key exists
  // to let this app call /auth/v1 — sign up, sign in, refresh — and nothing
  // else.
  //
  // The secret and service_role keys are a different matter entirely: they
  // bypass RLS. Neither belongs in an app, ever, however well hidden — anyone
  // can read the strings out of a shipped binary.

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ockqlabjqqpmkdaheetb.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_nls1xSVzzpkJCGEzOE-aHA_gpThjVwP',
  );

  // --- Premium (RevenueCat) ----------------------------------------------
  //
  // Public SDK keys — one per store, from RevenueCat → Project settings → API
  // keys. They identify the app to RevenueCat and are safe to ship; the
  // *secret* key lives only on the backend. Empty (the default) means no
  // purchasing on this build: every upgrade prompt stays hidden, rather than
  // leading to a screen that cannot sell anything.

  static const String revenueCatAppleKey =
      String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const String revenueCatGoogleKey =
      String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  /// RevenueCat's Test Store (a `test_…` key): real offerings and a simulated
  /// purchase sheet, no store account needed. **Debug and profile builds
  /// only** — RevenueCat deliberately crashes a release build that carries
  /// one, so PremiumService ignores it in release. For a demo, keep it in the
  /// git-ignored dart_defines.local.json:
  ///
  ///   flutter run --dart-define-from-file=dart_defines.local.json
  static const String revenueCatTestKey =
      String.fromEnvironment('REVENUECAT_TEST_KEY');

  /// The entitlement configured in RevenueCat. Must match the backend's
  /// PREMIUM_ENTITLEMENT_ID.
  static const String premiumEntitlement =
      String.fromEnvironment('PREMIUM_ENTITLEMENT', defaultValue: 'premium');

  /// Shown on the upgrade screen and in settings. The App Store requires both
  /// on any screen that sells a subscription. By default they are the pages
  /// the backend serves itself (`/legal/terms`, `/legal/privacy`), so a build
  /// pointed at a real API has working links with nothing else to host.
  static String get termsUrl => _termsOverride.isNotEmpty
      ? _termsOverride
      : '$backendUrl/legal/terms';
  static String get privacyUrl => _privacyOverride.isNotEmpty
      ? _privacyOverride
      : '$backendUrl/legal/privacy';
  static const String _termsOverride = String.fromEnvironment('TERMS_URL');
  static const String _privacyOverride = String.fromEnvironment('PRIVACY_URL');

  /// Where "Contact support" writes to. Premium members' mail is marked
  /// priority — the "Priority Support" perk.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'contact@tanishsen.com',
  );

  /// True: tapping the mic opens a real voice call (backend + agent must be
  /// running). False: the built-in scripted demo, which needs no network and
  /// is what the app falls back to if a call cannot be started.
  static const bool liveVoice = bool.fromEnvironment(
    'LIVE_VOICE',
    defaultValue: true,
  );
}
