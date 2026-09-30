/// Buying Premium, through RevenueCat.
///
/// RevenueCat drives the App Store and Google Play purchase sheets and turns
/// their receipts into one answer: whether this person has Premium. The store
/// takes the payment — card, UPI, net banking, whatever the person has set up
/// with Apple or Google — which is also what both stores require for a
/// digital subscription. The app never sees a card number.
///
/// **Unavailable is a normal state.** With no RevenueCat key compiled in, or
/// on the web, [available] is false and every upgrade prompt stays hidden.
///
/// **Which key.** A store build uses the platform's public key (`goog_…` /
/// `appl_…`). A debug or profile build may use RevenueCat's Test Store key
/// (`test_…`), which serves the real offerings with a simulated purchase
/// sheet — the way to demo and test without a store account. A release build
/// never uses a Test Store key: RevenueCat crashes such a build on purpose,
/// so it is refused here first.
///
/// The RevenueCat customer is the Supabase user: [configure] logs in with the
/// account id and follows sign-in and sign-out, so a purchase belongs to the
/// account — and the backend, which keys everything by that id, can verify it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;

import '../../app/app_config.dart';
import '../auth/data/auth_service.dart';

/// How long a plan runs. The upgrade screen's three cards.
enum PlanTerm { monthly, threeMonths, yearly }

extension PlanTermInfo on PlanTerm {
  String get label => switch (this) {
        PlanTerm.monthly => 'Monthly',
        PlanTerm.threeMonths => '3 Months',
        PlanTerm.yearly => 'Yearly',
      };

  String get pitch => switch (this) {
        PlanTerm.monthly => 'Perfect for short trips and quick getaways',
        PlanTerm.threeMonths => 'Great value for travellers.',
        PlanTerm.yearly => 'The best choice for travel lovers.',
      };

  /// "/month", said after a price.
  String get per => switch (this) {
        PlanTerm.monthly => '/month',
        PlanTerm.threeMonths => '/3 months',
        PlanTerm.yearly => '/year',
      };

  int get months => switch (this) {
        PlanTerm.monthly => 1,
        PlanTerm.threeMonths => 3,
        PlanTerm.yearly => 12,
      };

  /// RevenueCat's standard package identifier for this term.
  String get packageId => switch (this) {
        PlanTerm.monthly => r'$rc_monthly',
        PlanTerm.threeMonths => r'$rc_three_month',
        PlanTerm.yearly => r'$rc_annual',
      };
}

/// One plan on sale, priced by the store in the buyer's own currency.
class PlanOffer {
  const PlanOffer({
    required this.term,
    required this.price,
    required this.package,
    this.amount,
    this.trial,
    this.savePercent,
  });

  final PlanTerm term;

  /// Formatted as the design sets it — "INR 499" — from the store's own
  /// price and currency. Never hard-coded: prices differ by country and
  /// change without an app release.
  final String price;

  /// The raw price, for comparing plans.
  final double? amount;

  /// "7-day free trial", when this person is eligible for one.
  final String? trial;

  /// How much cheaper per month than the monthly plan, when it is.
  final int? savePercent;

  final Package package;
}

/// What the paywall shows: the plans, and the copy the RevenueCat dashboard
/// sets for them (Offering → Metadata), so the pitch can change without an
/// app release.
class Paywall {
  const Paywall({
    this.offers = const <PlanOffer>[],
    this.metadata = const <String, Object>{},
  });

  final List<PlanOffer> offers;
  final Map<String, Object> metadata;

  static const Paywall empty = Paywall();

  String? text(String key) {
    final Object? v = metadata[key];
    return v is String && v.trim().isNotEmpty ? v : null;
  }
}

enum PurchaseOutcome {
  purchased,
  cancelled,
  pending,

  /// The store took the payment but RevenueCat does not (yet) show Premium —
  /// a slow sync, or an entitlement not attached to the product. The person
  /// has paid, so this must never be reported as "not charged".
  unconfirmed,
  failed,
}

class PremiumService {
  PremiumService._();

  /// For tests, which subclass this to stand in for the store.
  @visibleForTesting
  PremiumService.forTesting();

  static final PremiumService instance = PremiumService._();

  bool _configured = false;
  StreamSubscription<AuthState>? _auth;

  /// Premium, as RevenueCat says on this device — updated the moment a
  /// purchase, renewal or expiry reaches it. The backend's copy can lag by a
  /// webhook; this does not, so screens show the truth straight after buying.
  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);

  static bool _isTestKey(String k) => k.startsWith('test_');

  /// The key for this build, or '' for none.
  static String get _key {
    if (kIsWeb) return '';
    if (!kReleaseMode && AppConfig.revenueCatTestKey.isNotEmpty) {
      return AppConfig.revenueCatTestKey;
    }
    final String key = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => AppConfig.revenueCatAppleKey,
      TargetPlatform.android => AppConfig.revenueCatGoogleKey,
      _ => '',
    };
    if (kReleaseMode && _isTestKey(key)) {
      // RevenueCat would show an alert and crash on purpose. No Premium in
      // this build is a much better outcome than no app.
      debugPrint('[backPAC] a Test Store key in a release build — Premium off');
      return '';
    }
    return key;
  }

  /// Whether RevenueCat is set up on this build — enough to restore a
  /// purchase or open subscription management.
  bool get available => _configured;

  /// Whether this build may show an upgrade prompt: RevenueCat is set up and
  /// the terms and privacy links exist, which the App Store requires on any
  /// screen that sells a subscription.
  bool get canSell =>
      available &&
      AppConfig.termsUrl.isNotEmpty &&
      AppConfig.privacyUrl.isNotEmpty;

  /// Set up once, at launch. Never throws: a store problem must not stop the
  /// app from opening.
  Future<void> configure() async {
    final String key = _key;
    if (key.isEmpty || _configured) return;
    try {
      final User? user = AuthService().currentUser;
      final PurchasesConfiguration config = PurchasesConfiguration(key)
        ..appUserID = user?.id;
      await Purchases.configure(config);
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      unawaited(_refresh());
      unawaited(_describe(user));
    } catch (e) {
      debugPrint('[backPAC] RevenueCat unavailable: $e');
      return;
    }
    _auth = AuthService().changes.listen((AuthState s) async {
      final User? user = s.session?.user;
      try {
        if (user != null) {
          final LogInResult result = await Purchases.logIn(user.id);
          _onCustomerInfo(result.customerInfo);
          await _describe(user);
        } else if (!await Purchases.isAnonymous) {
          _onCustomerInfo(await Purchases.logOut());
        }
      } catch (e) {
        debugPrint('[backPAC] RevenueCat user switch failed: $e');
      }
    });
  }

  /// Name the customer in the RevenueCat dashboard, so a support request or
  /// a refund can be matched to a person rather than a UUID.
  Future<void> _describe(User? user) async {
    if (user == null) return;
    try {
      if (user.email case final String email) await Purchases.setEmail(email);
      if (AuthService().displayName case final String name) {
        await Purchases.setDisplayName(name);
      }
    } catch (_) {
      // Attributes are a convenience for us, never a reason to fail.
    }
  }

  Future<void> _refresh() async {
    try {
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } on PlatformException {
      // Offline: keep what we had.
    }
  }

  void _onCustomerInfo(CustomerInfo info) => isPremium.value = _hasPremium(info);

  /// The plans on sale, in card order, with the dashboard's copy. Empty when
  /// the store has none — the upgrade screen says so rather than showing
  /// prices it cannot charge.
  Future<Paywall> paywall() async {
    if (!_configured) return Paywall.empty;
    final Offerings offerings = await Purchases.getOfferings();
    final Offering? current = offerings.current;
    if (current == null) return Paywall.empty;

    final List<(PlanTerm, Package)> found = <(PlanTerm, Package)>[
      for (final (PlanTerm term, Package? p) in <(PlanTerm, Package?)>[
        (PlanTerm.monthly, current.monthly),
        (PlanTerm.threeMonths, current.threeMonth),
        (PlanTerm.yearly, current.annual),
      ])
        if (p != null) (term, p),
    ];

    final Map<String, bool> eligible = await _trialEligibility(<String>[
      for (final (PlanTerm _, Package p) in found) p.storeProduct.identifier,
    ]);
    double? monthly;
    for (final (PlanTerm term, Package p) in found) {
      if (term == PlanTerm.monthly) monthly = p.storeProduct.price;
    }

    return Paywall(
      metadata: current.metadata,
      offers: <PlanOffer>[
        for (final (PlanTerm term, Package p) in found)
          PlanOffer(
            term: term,
            package: p,
            amount: p.storeProduct.price,
            price: displayPrice(
              p.storeProduct.price,
              p.storeProduct.currencyCode,
              fallback: p.storeProduct.priceString,
            ),
            trial: eligible[p.storeProduct.identifier] == false
                ? null
                : trialOf(p.storeProduct),
            savePercent: saving(monthly, p.storeProduct.price, term),
          ),
      ],
    );
  }

  /// Apple decides trial eligibility per person; ask, so a card never offers
  /// a trial the purchase sheet then refuses. Google already reflects it in
  /// the product's default offer, so everything else is "eligible".
  Future<Map<String, bool>> _trialEligibility(List<String> ids) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return const <String, bool>{};
    try {
      final Map<String, IntroEligibility> r =
          await Purchases.checkTrialOrIntroductoryPriceEligibility(ids);
      return r.map((String id, IntroEligibility e) => MapEntry<String, bool>(
            id,
            e.status != IntroEligibilityStatus.introEligibilityStatusIneligible,
          ));
    } catch (_) {
      return const <String, bool>{};
    }
  }

  /// "INR 499" when the price is whole, as the design writes it; the store's
  /// own formatting otherwise ("$9.99").
  @visibleForTesting
  static String displayPrice(double amount, String currency, {required String fallback}) {
    if (amount != amount.roundToDouble() || currency.isEmpty) return fallback;
    final String digits = amount.round().toString();
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
      grouped.write(digits[i]);
    }
    return '$currency $grouped';
  }

  /// Per-month saving against the monthly plan, as a whole percentage; null
  /// under 5% (not worth saying) and for the monthly plan itself.
  @visibleForTesting
  static int? saving(double? monthly, double price, PlanTerm term) {
    if (monthly == null || monthly <= 0 || term == PlanTerm.monthly) return null;
    final double perMonth = price / term.months;
    final int pct = ((1 - perMonth / monthly) * 100).floor();
    return pct >= 5 ? pct : null;
  }

  /// "7-day free trial" if the product starts with one.
  @visibleForTesting
  static String? trialOf(StoreProduct p) {
    final Period? google = p.defaultOption?.freePhase?.billingPeriod;
    if (google != null) return '${_period(google.value, google.unit)} free trial';
    final IntroductoryPrice? apple = p.introductoryPrice;
    if (apple != null && apple.price == 0) {
      return '${_period(apple.periodNumberOfUnits, apple.periodUnit)} free trial';
    }
    return null;
  }

  /// "3-day", "1-week" — a trial's length reads best as one hyphenated word.
  static String _period(int n, PeriodUnit unit) {
    final String u = switch (unit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      PeriodUnit.unknown => 'day',
    };
    return '$n-$u';
  }

  /// Run the store's purchase sheet for [offer].
  Future<PurchaseOutcome> buy(PlanOffer offer) async {
    try {
      final PurchaseResult result =
          await Purchases.purchase(PurchaseParams.package(offer.package));
      _onCustomerInfo(result.customerInfo);
      return _hasPremium(result.customerInfo)
          ? PurchaseOutcome.purchased
          : PurchaseOutcome.unconfirmed;
    } on PlatformException catch (e) {
      return switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
        // Ask to Buy, a slow card: the store will finish it later, and the
        // webhook will tell the backend when it does.
        PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
        _ => PurchaseOutcome.failed,
      };
    }
  }

  /// Apple requires a way to restore purchases on a new device. True if that
  /// found an active Premium.
  Future<bool> restore() async {
    if (!_configured) return false;
    try {
      final CustomerInfo info = await Purchases.restorePurchases();
      _onCustomerInfo(info);
      return _hasPremium(info);
    } on PlatformException {
      return false;
    }
  }

  /// Where the store lets someone cancel or change their plan.
  Future<String?> managementUrl() async {
    if (!_configured) return null;
    try {
      return (await Purchases.getCustomerInfo()).managementURL;
    } on PlatformException {
      return null;
    }
  }

  /// One tier, so any active entitlement is Premium — which also survives the
  /// dashboard's entitlement being named something other than ours.
  static bool _hasPremium(CustomerInfo info) =>
      info.entitlements.active.containsKey(AppConfig.premiumEntitlement) ||
      info.entitlements.active.isNotEmpty;

  @visibleForTesting
  void dispose() => _auth?.cancel();
}
