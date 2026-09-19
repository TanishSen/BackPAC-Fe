import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../model/trip_card.dart';

/// The rows behind what the assistant just said.
///
/// The voice reads out two or three options in words a person would speak; this
/// shows the same results with the detail speech is bad at — exact times, exact
/// prices, ratings. It renders whatever the agent's tool returned, so a new tool
/// shows up as a readable list rather than nothing.
class TripCardView extends StatelessWidget {
  const TripCardView({super.key, required this.card});

  final TripCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F2A2140),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            card.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          for (final Map<String, dynamic> row in card.rows)
            _Row(kind: card.kind, data: row),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.kind, required this.data});

  final TripCardKind kind;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final (String title, String subtitle, String trailing) = switch (kind) {
      TripCardKind.trains || TripCardKind.flights => (
          '${data['name'] ?? 'Option'}',
          _transitSubtitle(data),
          _money(data['priceInr']),
        ),
      TripCardKind.stays => (
          '${data['name'] ?? 'Stay'}',
          _staySubtitle(data),
          _money(data['pricePerNightInr']).isEmpty
              ? ''
              : '${_money(data['pricePerNightInr'])}/night',
        ),
      TripCardKind.other => ('${data.values.first}', '', ''),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.caption),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              trailing,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: AppColors.brand,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "06:00 → 10:35 · 4h 35m · IRCTC"
  static String _transitSubtitle(Map<String, dynamic> d) {
    final String depart = _clock(d['depart']);
    final String arrive = _clock(d['arrive']);
    final List<String> parts = <String>[
      if (depart.isNotEmpty && arrive.isNotEmpty) '$depart → $arrive',
      if (d['durationMinutes'] is int) _duration(d['durationMinutes'] as int),
      if (d['provider'] is String) d['provider'] as String,
    ];
    return parts.join(' · ');
  }

  /// "Old City · 4.6★"
  static String _staySubtitle(Map<String, dynamic> d) {
    final List<String> parts = <String>[
      if (d['area'] is String) d['area'] as String,
      if (d['rating'] != null) '${d['rating']}★',
    ];
    return parts.join(' · ');
  }

  /// The backend sends ISO timestamps; only the clock time is useful here.
  static String _clock(Object? iso) {
    if (iso is! String) return '';
    final DateTime? t = DateTime.tryParse(iso);
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  static String _duration(int minutes) =>
      minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h ${minutes % 60}m';

  /// "₹1,240" — grouped the Indian way, which is what these prices are in.
  static String _money(Object? value) {
    if (value is! num) return '';
    final String digits = value.round().toString();
    if (digits.length <= 3) return '₹$digits';
    final String head = digits.substring(0, digits.length - 3);
    final String tail = digits.substring(digits.length - 3);
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 2 == 0) grouped.write(',');
      grouped.write(head[i]);
    }
    return '₹$grouped,$tail';
  }
}
