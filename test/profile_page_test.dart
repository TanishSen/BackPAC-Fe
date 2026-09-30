import 'dart:convert';

import 'package:backPAC/features/history/data/history_client.dart';
import 'package:backPAC/features/history/history_page.dart';
import 'package:backPAC/features/premium/premium_service.dart';
import 'package:backPAC/features/profile/bucket_list_page.dart';
import 'package:backPAC/features/profile/data/profile_client.dart';
import 'package:backPAC/features/profile/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The store, standing still: says whether it could sell, sells nothing.
class _FakePremium extends PremiumService {
  _FakePremium({this.sells = false}) : super.forTesting();

  final bool sells;

  @override
  bool get available => sells;

  @override
  bool get canSell => sells;
}

Map<String, dynamic> _me({
  bool billing = false,
  bool premium = false,
  Map<String, dynamic>? profile,
}) =>
    <String, dynamic>{
      'profile': profile ??
          <String, dynamic>{
            'displayName': 'Jasmine',
            'homeCity': 'Kolkata, India',
            'bio': 'Collecting moments, not things.',
            'avatar': '🐱',
          },
      'stats': <String, dynamic>{
        'trips': 8, 'places': 14, 'saved': 3, 'favourites': 126,
        'completed': 2, 'inProgress': 5, 'bucketList': 4,
      },
      'plan': <String, dynamic>{
        'billingEnabled': billing,
        'premium': premium,
        'premiumUntil': premium ? '2026-12-01T00:00:00Z' : null,
        'willRenew': premium,
        'freeMonthlyLimit': billing && !premium ? 5 : null,
        'usedThisMonth': 2,
        'remainingThisMonth': billing && !premium ? 3 : null,
      },
    };

/// JSON as the backend sends it — which matters here: without the content
/// type, package:http would encode the 🐱 as latin1 and fail.
http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

http.Client _backend(Map<String, dynamic> me) => MockClient((http.Request r) async {
      final String path = r.url.path;
      if (path == '/api/v1/me') return _json(me);
      if (path == '/api/v1/sessions') {
        return _json(<String, dynamic>{'sessions': <Object>[], 'hasMore': false});
      }
      if (path == '/api/v1/groups') return _json(<Object>[]);
      if (path == '/api/v1/trips/saved') return _json(<Object>[]);
      return _json(<String, String>{'error': 'unexpected $path'}, 404);
    });

Future<void> _open(
  WidgetTester tester,
  Map<String, dynamic> me, {
  PremiumService? premium,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final http.Client http_ = _backend(me);
  await tester.pumpWidget(MaterialApp(
    home: ProfilePage(
      client: ProfileClient(baseUrl: 'http://api.test', client: http_, accessToken: () => 't'),
      historyClient: HistoryClient(baseUrl: 'http://api.test', client: http_, accessToken: () => 't'),
      premium: premium ?? _FakePremium(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('shows who you are and your real journey numbers', (WidgetTester tester) async {
    await _open(tester, _me());

    expect(find.text('Jasmine'), findsOneWidget);
    expect(find.text('Hi Jasmine! 👋'), findsOneWidget);
    expect(find.text('Kolkata, India'), findsOneWidget);
    expect(find.text('Collecting moments, not things.'), findsOneWidget);
    expect(find.text('🐱'), findsOneWidget);
    expect(find.text('Your Travel Journey'), findsOneWidget);
    // Two digits, as the design sets them.
    expect(find.text('08'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('126'), findsOneWidget);
    for (final String tile in <String>[
      'Saved Trips', 'Completed Trips', 'Bucket List',
      'In Progress', 'Favourites', 'Play with COOKIE',
    ]) {
      // "Favourites" is also a journey stat, so at least one.
      expect(find.text(tile, skipOffstage: false), findsWidgets, reason: tile);
    }
    expect(find.text('Switch Account', skipOffstage: false), findsOneWidget);
    expect(find.text('Log Out', skipOffstage: false), findsOneWidget);
  });

  testWidgets('an empty profile invites filling it in', (WidgetTester tester) async {
    await _open(tester, _me(profile: <String, dynamic>{}));
    expect(find.text('Add your home city'), findsOneWidget);
    expect(find.text('Add a line about yourself ✨'), findsOneWidget);
  });

  testWidgets('each tile opens the slice it names', (WidgetTester tester) async {
    await _open(tester, _me());
    await tester.ensureVisible(find.text('Saved Trips'));
    await tester.tap(find.text('Saved Trips'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final HistoryPage page = tester.widget(find.byType(HistoryPage));
    expect(page.title, 'Saved trips');
    expect(page.initialFilter.saved, isTrue);
  });

  testWidgets('bucket list tile opens the bucket list', (WidgetTester tester) async {
    await _open(tester, _me());
    await tester.ensureVisible(find.text('Bucket List'));
    await tester.tap(find.text('Bucket List'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BucketListPage), findsOneWidget);
  });

  testWidgets('no Premium banner while Premium is not on sale', (WidgetTester tester) async {
    // Billing on at the backend, but this build cannot sell (no store key).
    await _open(tester, _me(billing: true));
    expect(find.text('Upgrade Now', skipOffstage: false), findsNothing);
  });

  testWidgets('Premium banner shows what is left when it is on sale', (WidgetTester tester) async {
    await _open(tester, _me(billing: true), premium: _FakePremium(sells: true));
    expect(find.text('Upgrade Now', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('3 left', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a Premium member sees their plan, not a sales pitch', (WidgetTester tester) async {
    await _open(tester, _me(billing: true, premium: true), premium: _FakePremium(sells: true));
    expect(find.text('Upgrade Now', skipOffstage: false), findsNothing);
    expect(find.text("You're Premium", skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Renews on', skipOffstage: false), findsOneWidget);
  });
}
