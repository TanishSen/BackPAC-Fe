@Tags(<String>['screenshot'])
library;

// Renders the profile, full history and upgrade screens to PNGs, with the real
// fonts, for checking them against the designs without a device:
//
//   SHOT_OUT=/tmp/shots flutter test test/capture_profile_history.dart
//
// Emoji do not render in the test engine (no colour-emoji font), so avatars
// and trip pictures show as blanks here; everything else is as on a phone.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:backPAC/app/app_theme.dart';
import 'package:backPAC/features/history/data/history_client.dart';
import 'package:backPAC/features/history/history_page.dart';
import 'package:backPAC/features/premium/premium_service.dart';
import 'package:backPAC/features/premium/upgrade_page.dart';
import 'package:backPAC/features/profile/data/profile_client.dart';
import 'package:backPAC/features/profile/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class _Sells extends PremiumService {
  _Sells() : super.forTesting();
  @override
  bool get available => true;
  @override
  bool get canSell => true;

  /// Real offers need the store; the screen only needs their shape. Prices are
  /// what the store would format for India.
  @override
  Future<Paywall> paywall() async => Paywall(offers: <PlanOffer>[
        _offer(PlanTerm.monthly, PackageType.monthly, 199),
        _offer(PlanTerm.threeMonths, PackageType.threeMonth, 499, save: 16),
        _offer(PlanTerm.yearly, PackageType.annual, 1499, save: 37),
      ]);

  static PlanOffer _offer(PlanTerm term, PackageType type, double amount, {int? save}) =>
      PlanOffer(
        term: term,
        amount: amount,
        savePercent: save,
        price: PremiumService.displayPrice(amount, 'INR', fallback: '₹$amount'),
        package: Package(
          term.packageId,
          type,
          StoreProduct(term.name, '', term.label, amount, '₹$amount', 'INR'),
          const PresentedOfferingContext('default', null, null),
        ),
      );
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

Map<String, dynamic> _row(String id, String title) => <String, dynamic>{
      'id': id,
      'title': title,
      'preview': 'Give me suggestions on some amazing resorts in Goa and check if we can get some reservations there',
      'mode': 'stay',
      'saved': id == '1',
      'favourite': id == '2',
      'groupId': id == '3' ? 'g1' : null,
      'status': id == '4' ? 'completed' : 'active',
      'messageCount': 4,
      'createdAt': '2026-09-2${id}T10:00:00Z',
      'updatedAt': '2026-09-2${id}T10:05:00Z',
    };

final http.Client _backend = MockClient((http.Request r) async {
  switch (r.url.path) {
    case '/api/v1/me':
      return _json(<String, dynamic>{
        'profile': <String, dynamic>{
          'displayName': 'Jasmine',
          'homeCity': 'Kolkata, India',
          'bio': 'Collecting moments, not things. ✨',
          'avatar': '🐱',
        },
        'stats': <String, dynamic>{
          'trips': 8, 'places': 14, 'saved': 3, 'favourites': 5,
          'completed': 2, 'inProgress': 6, 'bucketList': 4,
        },
        'plan': <String, dynamic>{
          'billingEnabled': true, 'premium': false, 'freeMonthlyLimit': 5,
          'usedThisMonth': 2, 'remainingThisMonth': 3,
        },
      });
    case '/api/v1/sessions':
      return _json(<String, dynamic>{
        'sessions': <Object>[
          _row('1', 'Resorts In Goa'),
          _row('2', 'Hiking'),
          _row('3', 'Paragliding in Manali'),
          _row('4', 'Desert camp in Jaisalmer'),
          _row('5', 'Trains to Varanasi'),
          _row('6', 'Resorts In Goa'),
        ],
        'hasMore': false,
      });
    case '/api/v1/groups':
      return _json(<Object>[
        <String, dynamic>{'id': 'g1', 'name': 'Mountains', 'count': 1, 'createdAt': '2026-09-01T00:00:00Z'},
        <String, dynamic>{'id': 'g2', 'name': 'Desert', 'count': 0, 'createdAt': '2026-09-02T00:00:00Z'},
      ]);
  }
  return http.Response('{}', 404);
});

Future<void> _fonts() async {
  final FontLoader poppins = FontLoader('Poppins');
  for (final String w in <String>['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(rootBundle.load('assets/fonts/Poppins-$w.ttf'));
  }
  await poppins.load();
  final String flutter = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/development/flutter';
  final File icons = File('$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final FontLoader material = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())));
    await material.load();
  }
}

Future<void> _shoot(WidgetTester tester, Widget page, String name, {double height = 844}) async {
  final String dir = Platform.environment['SHOT_OUT'] ?? 'shots';
  Directory(dir).createSync(recursive: true);
  final Size logical = Size(390, height);
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: page),
  ));
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
  await tester.runAsync(() async {
    final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await b.toImage(pixelRatio: 2);
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_fonts);

  testWidgets('capture history', (WidgetTester tester) async {
    await _shoot(
      tester,
      HistoryPage(client: HistoryClient(baseUrl: 'http://t', client: _backend, accessToken: () => 't')),
      'history',
    );
  });

  testWidgets('capture profile', (WidgetTester tester) async {
    await _shoot(
      tester,
      ProfilePage(
        client: ProfileClient(baseUrl: 'http://t', client: _backend, accessToken: () => 't'),
        historyClient: HistoryClient(baseUrl: 'http://t', client: _backend, accessToken: () => 't'),
        premium: _Sells(),
      ),
      'profile',
      height: 1320,
    );
  });

  testWidgets('capture upgrade', (WidgetTester tester) async {
    await _shoot(
      tester,
      UpgradePage(
        premium: _Sells(),
        client: ProfileClient(baseUrl: 'http://t', client: _backend, accessToken: () => 't'),
        plan: const PlanInfo(billingEnabled: true, freeMonthlyLimit: 5, remainingThisMonth: 3),
      ),
      'upgrade',
      height: 1100,
    );
  });
}
