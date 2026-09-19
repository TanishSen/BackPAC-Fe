import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../orb/rezolve_orb.dart';

/// The banner with the orb, the remaining requests, and the upgrade nudge.
class ProCard extends StatefulWidget {
  const ProCard({
    super.key,
    required this.credits,
    required this.onUpgrade,
    required this.onOrbTap,
  });

  final int credits;
  final VoidCallback onUpgrade;
  final VoidCallback onOrbTap;

  @override
  State<ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<ProCard> {
  /// Short, light-hearted lines for the headline — a fresh shuffle each
  /// session, cycling on a slow timer rather than a static pitch.
  static const List<String> _taglines = <String>[
    "Let's plan your day, the fun-first way",
    "Adventure's calling — answer it",
    "Wanderlust? We've got you covered",
    'Say where, and off we go',
    'One tap, one plan, one great trip',
    'Trip goals? Say less, on it',
    'Ready, set, wander!',
    'Your next escape is one tap away',
    "Let's turn 'maybe' into 'let's go'",
    'Big trip energy, incoming',
    'Your travel bestie is typing…',
    'Passport ready? Let both loose',
    'Beach, hike, or skyline — you pick',
    'Somewhere new is a tap away',
    "Itchy feet? Let's plan the treat",
    'From daydream to itinerary',
    'Plans so good, they rhyme',
    "Tap in, zone out, trip's sorted",
  ];

  late final List<String> _order;
  late int _index;
  Timer? _rotate;

  @override
  void initState() {
    super.initState();
    _order = List<String>.of(_taglines)..shuffle();
    _index = math.Random().nextInt(_order.length);
    _rotate = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _order.length);
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F2A2140),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          // The orb sits half outside the card's left edge, as in the design.
          SizedBox(
            width: 132,
            height: 152,
            child: OverflowBox(
              maxWidth: 200,
              maxHeight: 200,
              child: Transform.translate(
                offset: const Offset(-18, 6),
                child: RezolveOrb(
                  size: 168,
                  headroom: 0.1,
                  playfulness: 0.45,
                  onTap: widget.onOrbTap,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.brandWash,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.auto_awesome,
                            size: 13, color: AppColors.brand),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${widget.credits} requests left',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (Widget child, Animation<double> a) =>
                        FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _order[_index],
                      key: ValueKey<String>(_order[_index]),
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Outlined(label: 'Update now', onTap: widget.onUpgrade),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Outlined extends StatelessWidget {
  const _Outlined({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.brandLine),
        borderRadius: BorderRadius.circular(22),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.brand,
            ),
          ),
        ),
      ),
    );
  }
}
