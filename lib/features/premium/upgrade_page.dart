import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/api.dart';
import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../app/widgets/round_icon_button.dart';
import '../profile/data/profile_client.dart';
import 'premium_service.dart';

/// Upgrade to Premium: pick a plan, pay through the store.
///
/// Prices are the store's, in the buyer's own currency, straight from
/// RevenueCat — nothing here hard-codes a number. Payment is the store's too,
/// which is why there is no card or UPI form: Apple and Google take it with
/// whatever the person has set up with them.
///
/// Pops `true` once Premium is active.
class UpgradePage extends StatefulWidget {
  const UpgradePage({
    super.key,
    required this.premium,
    required this.client,
    this.plan = PlanInfo.unknown,
  });

  final PremiumService premium;
  final ProfileClient client;

  /// For the free allowance, which is what Premium lifts.
  final PlanInfo plan;

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

/// What Premium actually gives you. **Only list what the product delivers.**
///
/// The design also showed exclusive deals, ad-free browsing, early booking
/// access, priority support, flexible cancellation and premium guides. None of
/// those exist yet, and a store listing or paywall promising them is both an
/// App Review rejection and a refund queue. Add each one here the day it ships.
List<(IconData, String, String)> _perks(PlanInfo plan) => <(IconData, String, String)>[
      (
        Icons.all_inclusive_rounded,
        'Unlimited trip plans',
        plan.freeMonthlyLimit == null
            ? 'Plan as many trips as you like, every month.'
            : 'Free includes ${plan.freeMonthlyLimit} new plans a month. Premium has no limit.',
      ),
    ];

class _UpgradePageState extends State<UpgradePage> {
  static const Color _wash = Color(0xFFEDE7FB);

  List<PlanOffer>? _offers;
  PlanOffer? _chosen;
  String? _error;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final List<PlanOffer> offers = await widget.premium.offers();
      if (!mounted) return;
      // The design's "Most Popular" three-month plan is the default pick.
      PlanOffer? chosen;
      for (final PlanOffer o in offers) {
        if (o.term == PlanTerm.threeMonths) chosen = o;
      }
      setState(() {
        _offers = offers;
        _chosen = chosen ?? (offers.isEmpty ? null : offers.first);
      });
    } catch (e) {
      debugPrint('[backPAC] offerings failed: $e');
      if (mounted) setState(() => _error = 'Could not load the plans. Check your connection.');
    }
  }

  Future<void> _buy() async {
    final PlanOffer? offer = _chosen;
    if (offer == null || _buying) return;
    setState(() => _buying = true);
    final PurchaseOutcome outcome = await widget.premium.buy(offer);
    if (!mounted) return;
    setState(() => _buying = false);

    switch (outcome) {
      case PurchaseOutcome.purchased:
        try {
          await widget.client.syncPlan();
        } on ApiException {
          // The webhook will bring the backend up to date within moments.
        }
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Welcome to Premium 👑', style: AppText.section),
            content: const Text('Plan as many trips as you like.', style: AppText.body),
            actions: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text("Let's go"),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.unconfirmed:
        _toast('Your purchase went through, but Premium has not switched on yet. '
            'Give it a minute, then use Restore purchases.');
      case PurchaseOutcome.pending:
        _toast('Your purchase is waiting for approval. Premium switches on as soon as it goes through.');
      case PurchaseOutcome.failed:
        _toast('The purchase did not go through, and you have not been charged. Please try again.');
    }
  }

  Future<void> _restore() async {
    setState(() => _buying = true);
    final bool found = await widget.premium.restore();
    if (!mounted) return;
    setState(() => _buying = false);
    if (!found) {
      _toast('No Premium purchase found for this account.');
      return;
    }
    try {
      await widget.client.syncPlan();
    } on ApiException {
      // The webhook catches the backend up.
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open that link.');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: AppColors.ink,
      ));
  }

  String get _store => defaultTargetPlatform == TargetPlatform.iOS ? 'App Store' : 'Google Play';

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: _wash,
      body: MediaQuery(
        data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.25)),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 8, AppSpacing.pageH, 20),
                  children: <Widget>[
                    _header(),
                    const SizedBox(height: 18),
                    _premiumCard(),
                    const SizedBox(height: 22),
                    _plans(),
                    const SizedBox(height: 26),
                    const Text('What You Get', style: AppText.section),
                    const SizedBox(height: 12),
                    for (final (IconData icon, String title, String body) in _perks(widget.plan))
                      _Perk(icon: icon, title: title, body: body),
                    const SizedBox(height: 14),
                    _payment(),
                    const SizedBox(height: 14),
                    _legal(),
                  ],
                ),
              ),
              _checkout(media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          right: -6,
          top: 0,
          child: IgnorePointer(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Icon(Icons.directions_bike_rounded, size: 40, color: AppColors.brandSoft.withValues(alpha: 0.7)),
                Column(
                  children: <Widget>[
                    Icon(Icons.airplane_ticket_rounded, size: 34, color: AppColors.brandSoft.withValues(alpha: 0.7)),
                    Icon(Icons.beach_access_rounded, size: 64, color: AppColors.brandSoft.withValues(alpha: 0.7)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 18),
            Text(
              'UPGRADE PLAN',
              style: AppText.headline.copyWith(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                'Unlock more and make your travel planning even better!',
                style: AppText.body.copyWith(color: AppColors.inkSoft, fontSize: 15),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _premiumCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.workspace_premium_rounded, size: 52, color: AppColors.brandSoft),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Upgrade to Premium', style: AppText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'No monthly limit on planning — every trip, whenever it comes to you.',
                  style: AppText.caption.copyWith(fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _plans() {
    if (_error != null) {
      return Column(
        children: <Widget>[
          Text(_error!, style: AppText.body),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }
    final List<PlanOffer>? offers = _offers;
    if (offers == null) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    if (offers.isEmpty) {
      return Text(
        "Premium isn't on sale on this device right now. Please try again later.",
        style: AppText.body,
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < offers.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _PlanCard(
                offer: offers[i],
                selected: identical(offers[i], _chosen),
                popular: offers[i].term == PlanTerm.threeMonths && offers.length > 1,
                onTap: _buying ? null : () => setState(() => _chosen = offers[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _payment() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brandWash,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              defaultTargetPlatform == TargetPlatform.iOS ? Icons.apple_rounded : Icons.shop_rounded,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Pay with your $_store account', style: AppText.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  'Cards, UPI and more — whatever you have set up with $_store. '
                  'backPAC never sees your payment details.',
                  style: AppText.caption.copyWith(fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What both stores require on a subscription screen: how renewal works, how
  /// to cancel, the terms and privacy policy, and a way to restore.
  Widget _legal() {
    final TextStyle link = AppText.caption.copyWith(
      color: AppColors.brand,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: <Widget>[
        Text(
          'Subscriptions renew automatically at the same price unless cancelled '
          'at least 24 hours before the end of the current period. Manage or '
          'cancel any time in your $_store account settings.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: _buying ? null : _restore,
              child: Text('Restore purchases', style: link),
            ),
            if (AppConfig.termsUrl.isNotEmpty)
              TextButton(onPressed: () => _open(AppConfig.termsUrl), child: Text('Terms', style: link)),
            if (AppConfig.privacyUrl.isNotEmpty)
              TextButton(onPressed: () => _open(AppConfig.privacyUrl), child: Text('Privacy', style: link)),
          ],
        ),
      ],
    );
  }

  Widget _checkout(double bottomInset) {
    final PlanOffer? offer = _chosen;
    return Container(
      margin: EdgeInsets.fromLTRB(AppSpacing.pageH, 0, AppSpacing.pageH, 12 + bottomInset),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x14262046), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Total Amount', style: AppText.caption.copyWith(fontSize: 12)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: offer?.price ?? '—',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      if (offer != null)
                        TextSpan(text: ' ${offer.term.per}', style: AppText.caption),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: offer == null || _buying ? null : _buy,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: const StadiumBorder(),
            ),
            child: _buying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Proceed to Pay  ›', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.popular,
    required this.onTap,
  });

  final PlanOffer offer;
  final bool selected;
  final bool popular;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${offer.term.label}, ${offer.price} ${offer.term.per}',
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: selected ? const Color(0xFF7B2FF7) : Colors.transparent,
                width: 2,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(offer.term.label, style: AppText.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: 8),
                    Text(
                      offer.term.pitch,
                      style: AppText.caption.copyWith(fontSize: 11.5, height: 1.35, color: AppColors.inkSoft),
                    ),
                    const Spacer(),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        offer.price,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    Text(offer.term.per, style: AppText.caption),
                  ],
                ),
              ),
            ),
          ),
          if (popular)
            Positioned(
              top: -11,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2FF7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Most Popular',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.brandSoft, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppText.cardTitle.copyWith(fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(body, style: AppText.caption.copyWith(fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
