/// Buying Premium, through RevenueCat.
///
/// RevenueCat drives the App Store and Google Play purchase sheets and turns
/// their receipts into one answer: whether this person has the `premium`
/// entitlement. The store takes the payment — card, UPI, whatever the person
/// has set up with Apple or Google — which is also what both stores require
/// for a digital subscription. The app never sees a card number.
///
/// **Unavailable is a normal state.** With no RevenueCat key compiled in, or
/// on the web, [available] is false and every upgrade prompt stays hidden.
/// That is how a build ships before the store products exist.
///
/// The RevenueCat user is the Supabase user: [configure] logs in with the
/// account id and follows sign-in and sign-out, so a purchase belongs to the
/// account — and the backend, which keys everything by that id, can check it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

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
        PlanTerm.monthly => 'Perfect for short trips and quick getaways.',
        PlanTerm.threeMonths => 'Great value for travellers.',
        PlanTerm.yearly => 'The best choice for travel lovers.',
      };

  /// "/month", said after a price.
  String get per => switch (this) {
        PlanTerm.monthly => '/month',
        PlanTerm.threeMonths => '/3 months',
        PlanTerm.yearly => '/year',
      };
}

/// One plan on sale, priced by the store in the buyer's own currency.
class PlanOffer {
  const PlanOffer({required this.term, required this.price, required this.package});

  final PlanTerm term;

  /// "₹199.00" — formatted by the store. Never hard-coded: prices differ by
  /// country and change without an app release.
  final String price;
  final Package package;
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

  static String get _key {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => AppConfig.revenueCatAppleKey,
      TargetPlatform.android => AppConfig.revenueCatGoogleKey,
      _ => '',
    };
  }

  /// Whether RevenueCat is set up on this build — enough to restore a
  /// purchase or open subscription management.
  bool get available => _configured;

  /// Whether this build may show an upgrade prompt: RevenueCat is set up *and*
  /// the terms and privacy links exist, which the App Store requires on any
  /// screen that sells a subscription.
  bool get canSell =>
      _configured &&
      AppConfig.termsUrl.isNotEmpty &&
      AppConfig.privacyUrl.isNotEmpty;

  /// Set up once, at launch. Never throws: a store problem must not stop the
  /// app from opening.
  Future<void> configure() async {
    final String key = _key;
    if (key.isEmpty || _configured) return;
    try {
      final PurchasesConfiguration config = PurchasesConfiguration(key)
        ..appUserID = AuthService().currentUser?.id;
      await Purchases.configure(config);
      _configured = true;
    } catch (e) {
      debugPrint('[backPAC] RevenueCat unavailable: $e');
      return;
    }
    _auth = AuthService().changes.listen((AuthState s) async {
      final String? id = s.session?.user.id;
      try {
        if (id != null) {
          await Purchases.logIn(id);
        } else if (!await Purchases.isAnonymous) {
          await Purchases.logOut();
        }
      } catch (e) {
        debugPrint('[backPAC] RevenueCat user switch failed: $e');
      }
    });
  }

  /// The plans on sale, in card order. Empty when the store has none — the
  /// upgrade screen says so rather than showing prices it cannot charge.
  Future<List<PlanOffer>> offers() async {
    if (!_configured) return const <PlanOffer>[];
    final Offerings offerings = await Purchases.getOfferings();
    final Offering? current = offerings.current;
    if (current == null) return const <PlanOffer>[];
    return <PlanOffer>[
      for (final (PlanTerm term, Package? p) in <(PlanTerm, Package?)>[
        (PlanTerm.monthly, current.monthly),
        (PlanTerm.threeMonths, current.threeMonth),
        (PlanTerm.yearly, current.annual),
      ])
        if (p != null)
          PlanOffer(term: term, price: p.storeProduct.priceString, package: p),
    ];
  }

  /// Run the store's purchase sheet for [offer].
  Future<PurchaseOutcome> buy(PlanOffer offer) async {
    try {
      final PurchaseResult result =
          await Purchases.purchase(PurchaseParams.package(offer.package));
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
      return _hasPremium(await Purchases.restorePurchases());
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

  static bool _hasPremium(CustomerInfo info) =>
      info.entitlements.active.containsKey(AppConfig.premiumEntitlement);

  @visibleForTesting
  void dispose() => _auth?.cancel();
}
