import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/api.dart';
import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../orb/rezolve_orb.dart';
import '../profile/data/profile_client.dart';
import 'premium_service.dart';
import 'redeem_code.dart';

/// UPGRADE PLAN — the paywall, as designed.
///
/// Plans, prices and trials come live from RevenueCat (the current offering),
/// priced by the store in the buyer's currency. The words come from the
/// offering's metadata when the RevenueCat dashboard sets them, so the pitch
/// can be tested and changed without an app release; otherwise from the
/// defaults below.
///
/// Payment is the store's: Google Play and the App Store take cards, UPI and
/// net banking in India, which is what the payment panel lists. There is no
/// card form here because a digital subscription must go through the store.
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

  /// For the free allowance, which is one of the things Premium lifts.
  final PlanInfo plan;

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

/// The page's colours, from the design.
class _Pal {
  const _Pal._();
  static const Color wash = Color(0xFFE9E0F8);
  static const Color accent = Color(0xFFB4A2DD);
  static const Color popular = Color(0xFF7B2FF7);
  static const Color pay = Color(0xFFE6DCF7);
}

/// A perk tile in "What You Get".
class _Perk {
  const _Perk(this.icon, this.title, this.subtitle);

  final Widget icon;
  final String title;
  final String subtitle;
}

Widget _icon(String name) => switch (name) {
  'unlimited' ||
  'deals' => const Icon(Icons.back_hand_rounded, size: 40, color: _Pal.accent),
  'adfree' => const _Disc(Icons.close_rounded),
  'tips' ||
  'early' => const Icon(Icons.bolt_rounded, size: 44, color: _Pal.accent),
  'support' => const Icon(
    Icons.support_agent_rounded,
    size: 42,
    color: _Pal.accent,
  ),
  'cancel' => const _Disc(Icons.check_rounded),
  'vip' => const _Vip(),
  _ => const Icon(Icons.auto_awesome_rounded, size: 40, color: _Pal.accent),
};

/// What Premium includes. **Every default here is real**, and each names the
/// code that delivers it:
///
/// - Unlimited plans — the backend's free monthly allowance does not apply.
/// - Ad-free — Premium will never show ads.
/// - Insider tips — the agent's Premium planner (PREMIUM_CONSTRAINTS).
/// - Priority support — support mail from Premium members is flagged priority.
/// - Flexible cancellation — cancel any time in the store; nothing to ring.
/// - VIP badge — the crown on the profile.
///
/// The dashboard can replace the list (metadata key `perks`: a list of
/// `{icon, title, subtitle}`, icons: unlimited, adfree, tips, support,
/// cancel, vip). Whoever edits it there owns keeping it true.
List<_Perk> _perks(Paywall paywall, PlanInfo plan) {
  final Object? remote = paywall.metadata['perks'];
  if (remote is List && remote.isNotEmpty) {
    final List<_Perk> out = <_Perk>[
      for (final Object? p in remote)
        if (p is Map && p['title'] is String)
          _Perk(
            _icon('${p['icon'] ?? ''}'),
            p['title'] as String,
            p['subtitle'] is String ? p['subtitle'] as String : '',
          ),
    ];
    if (out.isNotEmpty) return out;
  }
  final int? limit = plan.freeMonthlyLimit;
  return <_Perk>[
    _Perk(
      _icon('unlimited'),
      'Unlimited Plans',
      limit == null
          ? 'Plan as many trips as you like'
          : 'No $limit-a-month limit',
    ),
    _Perk(_icon('adfree'), 'Ad-free, Always', 'Premium never shows ads'),
    _Perk(_icon('tips'), 'Insider Tips', 'Local know-how in every plan'),
    _Perk(_icon('support'), 'Priority Support', 'Get faster assistance'),
    _Perk(_icon('cancel'), 'Flexible Cancellation', 'Cancel anytime, in a tap'),
    _Perk(_icon('vip'), 'VIP Badge', 'A crown on your profile'),
  ];
}

class _UpgradePageState extends State<UpgradePage> {
  Paywall? _paywall;
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
      final Paywall paywall = await widget.premium.paywall();
      if (!mounted) return;
      // The dashboard may say which plan to preselect; the design's "Most
      // Popular" three months otherwise.
      final String wanted =
          paywall.text('default_package') ?? PlanTerm.threeMonths.packageId;
      PlanOffer? chosen;
      for (final PlanOffer o in paywall.offers) {
        if (o.package.identifier == wanted) chosen = o;
      }
      setState(() {
        _paywall = paywall;
        _chosen =
            chosen ?? (paywall.offers.isEmpty ? null : paywall.offers.first);
      });
    } catch (e) {
      debugPrint('[backPAC] offerings failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Could not load the plans. Check your connection.');
    }
  }

  String get _store => defaultTargetPlatform == TargetPlatform.iOS
      ? 'the App Store'
      : 'Google Play';

  Future<void> _buy() async {
    final PlanOffer? offer = _chosen;
    if (offer == null || _buying) return;
    setState(() => _buying = true);
    final PurchaseOutcome outcome = await widget.premium.buy(offer);
    if (!mounted) return;
    setState(() => _buying = false);

    switch (outcome) {
      case PurchaseOutcome.purchased:
        await _welcome();
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.unconfirmed:
        _toast(
          'Your purchase went through, but Premium has not switched on yet. '
          'Give it a minute, then use Restore purchases.',
        );
      case PurchaseOutcome.pending:
        _toast(
          'Your purchase is waiting for approval. Premium switches on as soon as it goes through.',
        );
      case PurchaseOutcome.failed:
        _toast(
          'The purchase did not go through, and you have not been charged. Please try again.',
        );
    }
  }

  /// Tell the backend now rather than when the webhook lands, then celebrate.
  Future<void> _welcome() async {
    try {
      await widget.client.syncPlan();
    } on ApiException {
      // The webhook will bring the backend up to date within moments.
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext sheet) => const _Welcome(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _redeem() async {
    final PlanInfo? plan = await redeemPromoCode(
      context,
      client: widget.client,
      premium: widget.premium,
    );
    if (plan != null && mounted) await _welcome();
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
    await _welcome();
  }

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open that link.');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: AppColors.ink,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final Paywall paywall = _paywall ?? Paywall.empty;
    return Scaffold(
      backgroundColor: _Pal.wash,
      body: MediaQuery(
        data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.2),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: <Widget>[
                    _Header(
                      title: paywall.text('title') ?? 'UPGRADE PLAN',
                      subtitle: paywall.text('subtitle') ?? 'Unlock more features and make your travel experience even better!',
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 20),
                    _PremiumCard(
                      title:
                          paywall.text('premium_title') ?? 'Upgrade to Premium',
                      subtitle: paywall.text('premium_subtitle') ?? 'Get exclusive perks, insider tips and a smoother travel experience.',
                    ),
                    const SizedBox(height: 30),
                    _plans(paywall),
                    const SizedBox(height: 30),
                    Text(
                      paywall.text('perks_title') ?? 'What You Get',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PerkGrid(perks: _perks(paywall, widget.plan)),
                    const SizedBox(height: 26),
                    _PaymentPanel(store: _store),
                    const SizedBox(height: 14),
                    _legal(),
                  ],
                ),
              ),
              _checkout(paywall, media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plans(Paywall paywall) {
    if (_error != null) {
      return Column(
        children: <Widget>[
          Text(_error!, style: AppText.body),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }
    if (_paywall == null) {
      return const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator(color: _Pal.popular)),
      );
    }
    if (paywall.offers.isEmpty) {
      return Text(
        "Premium isn't on sale on this device right now. Please try again later.",
        style: AppText.body,
      );
    }
    final String badge = paywall.text('badge') ?? 'Most Popular';
    final String popular =
        paywall.text('popular_package') ?? PlanTerm.threeMonths.packageId;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < paywall.offers.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _PlanCard(
                offer: paywall.offers[i],
                selected: identical(paywall.offers[i], _chosen),
                badge:
                    paywall.offers[i].package.identifier == popular &&
                        paywall.offers.length > 1
                    ? badge
                    : null,
                onTap: _buying
                    ? null
                    : () => setState(() => _chosen = paywall.offers[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What both stores require on a subscription screen: how renewal works,
  /// how to cancel, the terms and privacy policy, and a way to restore.
  Widget _legal() {
    final TextStyle link = AppText.caption.copyWith(
      color: _Pal.popular,
      fontWeight: FontWeight.w600,
    );
    final String? trial = _chosen?.trial;
    return Column(
      children: <Widget>[
        Text(
          '${trial != null ? 'After the $trial you are charged unless you cancel before it ends. ' : ''}'
          'Subscriptions renew automatically at the same price unless cancelled '
          'at least 24 hours before the end of the current period. Manage or '
          'cancel any time in your $_store account settings.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(
            fontSize: 11,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: _buying ? null : _redeem,
              child: Text('Have a promo code?', style: link),
            ),
            TextButton(
              onPressed: _buying ? null : _restore,
              child: Text('Restore purchases', style: link),
            ),
            TextButton(
              onPressed: () => _open(AppConfig.termsUrl),
              child: Text('Terms', style: link),
            ),
            TextButton(
              onPressed: () => _open(AppConfig.privacyUrl),
              child: Text('Privacy', style: link),
            ),
          ],
        ),
      ],
    );
  }

  Widget _checkout(Paywall paywall, double bottomInset) {
    final PlanOffer? offer = _chosen;
    final String cta = offer?.trial != null
        ? 'Start free trial'
        : (paywall.text('cta') ?? 'Proceed to Pay');
    return Container(
      margin: EdgeInsets.fromLTRB(16, 4, 16, 10 + bottomInset),
      padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14262046),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  offer?.trial != null
                      ? '${offer!.trial}, then'
                      : 'Total Amount',
                  style: AppText.caption.copyWith(
                    fontSize: 12.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: offer?.price ?? '—',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      if (offer != null)
                        TextSpan(
                          text: ' ${offer.term.per.replaceAll(' ', '')}',
                          style: AppText.caption.copyWith(color: AppColors.ink),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Its own width, not a share: as a Flexible it split the bar with
          // the total and cut "Proceed to Pay" short. Capped, so a very large
          // text size ellipsizes instead of overflowing.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Semantics(
              button: true,
              label: cta,
              child: Material(
                color: _Pal.pay,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: offer == null || _buying ? null : _buy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: _buying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: _Pal.popular,
                            ),
                          )
                        : Text(
                            '$cta  ›',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: offer == null
                                  ? AppColors.muted
                                  : Colors.black,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Sized by the text, not fixed: a large accessibility text size makes the
    // subtitle wrap further, and a fixed box would clip it.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // The design's corner: a boarding pass, a cyclist, a palm over a wave.
        const Positioned(right: -10, top: -4, child: _TravelArt()),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              button: true,
              label: 'Close',
              child: InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close_rounded,
                    size: 24,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 250),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  height: 1.45,
                  color: Color(0xFF2B2A2E),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }
}

class _TravelArt extends StatelessWidget {
  const _TravelArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Positioned(
            left: 14,
            top: 0,
            child: Icon(
              Icons.airplane_ticket_rounded,
              size: 34,
              color: _Pal.accent,
            ),
          ),
          const Positioned(
            left: 0,
            top: 36,
            child: Icon(
              Icons.directions_bike_rounded,
              size: 44,
              color: _Pal.accent,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: CustomPaint(
              size: const Size(76, 84),
              painter: _PalmPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A palm tree leaning over a curling wave, in the design's flat lavender.
class _PalmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final Paint fill = Paint()..color = _Pal.accent;
    final double w = s.width, h = s.height;

    // The wave: a block with a curl on its crest.
    final Path wave = Path()
      ..moveTo(w * 0.18, h)
      ..lineTo(w * 0.18, h * 0.70)
      ..quadraticBezierTo(w * 0.22, h * 0.48, w * 0.44, h * 0.46)
      ..quadraticBezierTo(w * 0.62, h * 0.46, w * 0.62, h * 0.60)
      ..quadraticBezierTo(w * 0.50, h * 0.56, w * 0.46, h * 0.66)
      ..quadraticBezierTo(w * 0.60, h * 0.76, w * 0.76, h * 0.66)
      ..lineTo(w, h * 0.62)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(wave, fill);

    // The trunk, curving up and to the left.
    final Paint trunk = Paint()
      ..color = _Pal.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.86, h * 0.64)
        ..quadraticBezierTo(w * 0.86, h * 0.30, w * 0.58, h * 0.20),
      trunk,
    );

    // Four fronds fanning from the crown.
    final Offset crown = Offset(w * 0.58, h * 0.20);
    for (final (double angle, double len) in <(double, double)>[
      (math.pi * 0.95, 0.42),
      (math.pi * 1.25, 0.38),
      (math.pi * 1.62, 0.36),
      (math.pi * 1.95, 0.40),
    ]) {
      final Offset tip =
          crown + Offset(math.cos(angle), math.sin(angle)) * w * len;
      final Offset mid = (crown + tip) / 2;
      final Offset normal =
          Offset(-math.sin(angle), math.cos(angle)) * w * 0.10;
      canvas.drawPath(
        Path()
          ..moveTo(crown.dx, crown.dy)
          ..quadraticBezierTo(
            mid.dx + normal.dx,
            mid.dy + normal.dy,
            tip.dx,
            tip.dy,
          )
          ..quadraticBezierTo(
            mid.dx - normal.dx * 0.2,
            mid.dy - normal.dy * 0.2,
            crown.dx,
            crown.dy,
          )
          ..close(),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_PalmPainter oldDelegate) => false;
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.verified_rounded, size: 60, color: _Pal.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF2B2A2E),
                  ),
                ),
              ],
            ),
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
    required this.onTap,
    this.badge,
  });

  final PlanOffer offer;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${offer.term.label}, ${offer.price} ${offer.term.per}'
          '${offer.trial != null ? ', ${offer.trial}' : ''}',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: selected ? _Pal.popular : Colors.transparent,
                width: 2,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 30, 10, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        offer.term.label,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        offer.term.pitch,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          height: 1.45,
                          color: Color(0xFF2B2A2E),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 18),
                      // Price, then period. The design sets them on one line,
                      // which on a phone-width card only fits by shrinking —
                      // and each card would shrink differently. Two lines keep
                      // the three prices the same size.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          offer.price,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      Text(
                        offer.term.per,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2B2A2E),
                        ),
                      ),
                      if (offer.trial != null ||
                          offer.savePercent != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          offer.trial ?? 'Save ${offer.savePercent}%',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E9E63),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              top: -12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _Pal.popular,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    badge!,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PerkGrid extends StatelessWidget {
  const _PerkGrid({required this.perks});

  final List<_Perk> perks;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < perks.length; i += 3) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 26),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int j = i; j < i + 3; j++) ...<Widget>[
                if (j > i) const SizedBox(width: 10),
                Expanded(
                  child: j < perks.length
                      ? _PerkView(perk: perks[j])
                      : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _PerkView extends StatelessWidget {
  const _PerkView({required this.perk});

  final _Perk perk;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 50,
          child: Align(alignment: Alignment.centerLeft, child: perk.icon),
        ),
        const SizedBox(height: 8),
        Text(
          perk.title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          perk.subtitle,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            height: 1.4,
            color: Color(0xFF2B2A2E),
          ),
        ),
      ],
    );
  }
}

/// A lavender disc with a white glyph — the design's ✕ and ✓ perk icons.
class _Disc extends StatelessWidget {
  const _Disc(this.glyph);

  final IconData glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: _Pal.accent,
        shape: BoxShape.circle,
      ),
      child: Icon(glyph, size: 26, color: Colors.white),
    );
  }
}

class _Vip extends StatelessWidget {
  const _Vip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _Pal.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'VIP',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// How the store takes payment, as the design lays it out. Informational:
/// the store's own sheet is where the method is picked, which is also why a
/// Test Store build shows RevenueCat's simulated sheet instead.
class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({required this.store});

  final String store;

  @override
  Widget build(BuildContext context) {
    Widget row(Widget icon, String title, String subtitle) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Align(alignment: Alignment.centerLeft, child: icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15.5,
                    color: Colors.black,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: Color(0xFF2B2A2E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    const Divider line = Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFEDEAF6),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 12, 26, 2),
            child: Row(
              children: <Widget>[
                const Icon(Icons.lock_rounded, size: 14, color: _Pal.popular),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Secure checkout with $store',
                    style: AppText.caption.copyWith(
                      color: _Pal.popular,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          row(
            Container(
              width: 50,
              height: 36,
              decoration: BoxDecoration(
                color: _Pal.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 8),
              child: Container(height: 4, color: AppColors.surface),
            ),
            'Credit / Debit Card',
            'Visa, MasterCard, RuPay',
          ),
          line,
          row(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _Pal.pay,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'UPI',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _Pal.accent,
                ),
              ),
            ),
            'UPI',
            'Google Pay, PhonePe, Paytm, etc.',
          ),
          line,
          row(
            const Icon(
              Icons.account_balance_rounded,
              size: 44,
              color: _Pal.accent,
            ),
            'Net Banking',
            'All major banks',
          ),
        ],
      ),
    );
  }
}

/// Straight after buying: COOKIE, delighted.
class _Welcome extends StatefulWidget {
  const _Welcome();

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  final RezolveOrbController _orb = RezolveOrbController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _orb.play(OrbAntic.doubleHop),
    );
  }

  @override
  void dispose() {
    _orb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RezolveOrb(
              size: 120,
              controller: _orb,
              mood: OrbMood.speaking,
              playfulness: 1,
            ),
            const SizedBox(height: 10),
            const Text('Welcome to Premium 👑', style: AppText.section),
            const SizedBox(height: 6),
            Text(
              'Unlimited plans, insider tips in every trip, and priority support. Let’s go somewhere.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _Pal.popular,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "Let's go",
                  style: AppText.label.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
