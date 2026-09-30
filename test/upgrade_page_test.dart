import 'dart:convert';

import 'package:backPAC/features/premium/premium_service.dart';
import 'package:backPAC/features/premium/upgrade_page.dart';
import 'package:backPAC/features/profile/data/profile_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// A store with three plans on sale, that records what was bought.
class _Store extends PremiumService {
  _Store({this.metadata = const <String, Object>{}, this.trial}) : super.forTesting();

  final Map<String, Object> metadata;
  final String? trial;
  PlanOffer? bought;

  @override
  bool get available => true;

  @override
  bool get canSell => true;

  static PlanOffer offer(PlanTerm term, PackageType type, double amount, {String? trial, int? save}) =>
      PlanOffer(
        term: term,
        amount: amount,
        trial: trial,
        savePercent: save,
        price: PremiumService.displayPrice(amount, 'INR', fallback: '₹$amount'),
        package: Package(
          term.packageId,
          type,
          StoreProduct(term.name, '', term.label, amount, '₹$amount', 'INR'),
          const PresentedOfferingContext('default', null, null),
        ),
      );

  @override
  Future<Paywall> paywall() async => Paywall(
        metadata: metadata,
        offers: <PlanOffer>[
          offer(PlanTerm.monthly, PackageType.monthly, 199),
          offer(PlanTerm.threeMonths, PackageType.threeMonth, 499, trial: trial, save: 16),
          offer(PlanTerm.yearly, PackageType.annual, 1499, save: 37),
        ],
      );

  @override
  Future<PurchaseOutcome> buy(PlanOffer offer) async {
    bought = offer;
    return PurchaseOutcome.purchased;
  }
}

ProfileClient _client(List<http.Request> seen) => ProfileClient(
      baseUrl: 'http://api.test',
      accessToken: () => 't',
      client: MockClient((http.Request r) async {
        seen.add(r);
        if (r.url.path == '/api/v1/billing/redeem' &&
            (jsonDecode(r.body) as Map<String, dynamic>)['code'] != 'SHIPATON2026') {
          return http.Response(
            jsonEncode(<String, String>{'error': "That code isn't valid. Check it and try again."}),
            400,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'billingEnabled': true, 'premium': true}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );

Future<void> _open(WidgetTester tester, PremiumService store, List<http.Request> seen) async {
  tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: UpgradePage(premium: store, client: _client(seen)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('pricing helpers', () {
    test('whole prices read as the design writes them', () {
      expect(PremiumService.displayPrice(199, 'INR', fallback: 'x'), 'INR 199');
      expect(PremiumService.displayPrice(1499, 'INR', fallback: 'x'), 'INR 1,499');
      // A fractional price keeps the store's own formatting.
      expect(PremiumService.displayPrice(9.99, 'USD', fallback: r'$9.99'), r'$9.99');
    });

    test('savings are per month against the monthly plan', () {
      expect(PremiumService.saving(199, 1499, PlanTerm.yearly), 37);
      expect(PremiumService.saving(199, 499, PlanTerm.threeMonths), 16);
      expect(PremiumService.saving(199, 199, PlanTerm.monthly), isNull);
      // Under 5% is not worth a label.
      expect(PremiumService.saving(100, 290, PlanTerm.threeMonths), isNull);
    });
  });

  testWidgets('the paywall has every section of the design', (WidgetTester tester) async {
    await _open(tester, _Store(), <http.Request>[]);

    expect(find.text('UPGRADE PLAN'), findsOneWidget);
    expect(find.text('Upgrade to Premium'), findsOneWidget);
    for (final String plan in <String>['Monthly', '3 Months', 'Yearly']) {
      expect(find.text(plan), findsOneWidget, reason: plan);
    }
    expect(find.text('Most Popular'), findsOneWidget);
    expect(find.text('INR 199'), findsOneWidget);
    expect(find.text('/3 months'), findsOneWidget);
    expect(find.text('INR 1,499'), findsOneWidget);
    expect(find.text('Save 37%'), findsOneWidget);
    expect(find.text('What You Get'), findsOneWidget);
    for (final String perk in <String>[
      'Unlimited Plans', 'Ad-free, Always', 'Insider Tips',
      'Priority Support', 'Flexible Cancellation', 'VIP Badge',
    ]) {
      expect(find.text(perk), findsOneWidget, reason: perk);
    }
    for (final String method in <String>['Credit / Debit Card', 'UPI', 'Net Banking']) {
      expect(find.text(method), findsWidgets, reason: method);
    }
    expect(find.text('Total Amount'), findsOneWidget);
    expect(find.text('Proceed to Pay  ›'), findsOneWidget);
    // What both stores require.
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('three months is preselected and bought on Proceed', (WidgetTester tester) async {
    final _Store store = _Store();
    final List<http.Request> seen = <http.Request>[];
    await _open(tester, store, seen);

    await tester.tap(find.text('Proceed to Pay  ›'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(store.bought?.term, PlanTerm.threeMonths);
    // The backend is told at once, not when the webhook arrives.
    expect(seen.map((http.Request r) => r.url.path), contains('/api/v1/billing/sync'));
    expect(find.text('Welcome to Premium 👑'), findsOneWidget);
  });

  testWidgets('tapping a card changes what Proceed buys', (WidgetTester tester) async {
    final _Store store = _Store();
    await _open(tester, store, <http.Request>[]);
    await tester.tap(find.text('Yearly'));
    await tester.pump();
    // The total follows the card.
    expect(find.text('INR 1,499 /year'), findsOneWidget);
    await tester.tap(find.text('Proceed to Pay  ›'));
    await tester.pump();
    expect(store.bought?.term, PlanTerm.yearly);
  });

  testWidgets('a free trial changes the call to action', (WidgetTester tester) async {
    await _open(tester, _Store(trial: '7-day free trial'), <http.Request>[]);
    expect(find.text('Start free trial  ›'), findsOneWidget);
    expect(find.text('7-day free trial, then'), findsOneWidget);
  });

  testWidgets('the RevenueCat dashboard can rewrite the pitch', (WidgetTester tester) async {
    await _open(
      tester,
      _Store(metadata: <String, Object>{
        'title': 'GO PREMIUM',
        'default_package': r'$rc_annual',
        'perks': <Object>[
          <String, Object>{'icon': 'tips', 'title': 'Secret spots', 'subtitle': 'Only for members'},
        ],
      }),
      <http.Request>[],
    );
    expect(find.text('GO PREMIUM'), findsOneWidget);
    expect(find.text('Secret spots'), findsOneWidget);
    expect(find.text('Insider Tips'), findsNothing);
    // The dashboard's default plan is the one in the total.
    expect(find.text('INR 1,499 /year'), findsOneWidget);
  });

  testWidgets('a promo code unlocks Premium; a wrong one says so', (WidgetTester tester) async {
    final List<http.Request> seen = <http.Request>[];
    await _open(tester, _Store(), seen);

    await tester.tap(find.text('Have a promo code?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'WRONG');
    await tester.pump(); // the button enables on the next frame
    await tester.tap(find.text('Redeem'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining("isn't valid"), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'SHIPATON2026');
    await tester.pump();
    await tester.tap(find.text('Redeem'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Welcome to Premium 👑'), findsOneWidget);
    final http.Request redeem =
        seen.firstWhere((http.Request r) => r.url.path == '/api/v1/billing/redeem');
    expect(redeem.method, 'POST');
  });
}
