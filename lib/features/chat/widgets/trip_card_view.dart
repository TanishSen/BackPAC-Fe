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
          // "~" when the price is a cached estimate rather than a live quote.
          // Small mark, real promise: it is the difference between what we
          // can stand behind and what someone finds at the payment page.
          data['priceIsApproximate'] == true
              ? _approx(_money(data['priceInr']))
              : _money(data['priceInr']),
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

  /// "06:00 → 10:35 · 4h 35m · non-stop · IRCTC"
  ///
  /// Every part is optional, because real providers answer with different
  /// amounts of detail. The flight fare calendar gives a departure time and
  /// no arrival, so a card that insisted on the pair showed no time at all,
  /// and one that trusted `durationMinutes` printed a confident "0m".
  static String _transitSubtitle(Map<String, dynamic> d) {
    final String depart = _clock(d['depart']);
    final String arrive = _clock(d['arrive']);
    final Object? mins = d['durationMinutes'];
    final Object? stops = d['stops'];

    final List<String> parts = <String>[
      if (depart.isNotEmpty && arrive.isNotEmpty)
        '$depart → $arrive'
      else if (depart.isNotEmpty)
        depart,
      // Zero is "unknown", not "instant".
      if (mins is int && mins > 0) _duration(mins),
      if (stops is int) _stops(stops),
      if (d['provider'] is String) d['provider'] as String,
    ];
    return parts.join(' · ');
  }

  /// "non-stop", "1 stop", "2 stops" — the difference between a good morning
  /// and a bad one, and worth more room than the price saves.
  static String _stops(int stops) =>
      stops <= 0 ? 'non-stop' : (stops == 1 ? '1 stop' : '$stops stops');

  /// "Old City · 4.6★"
  static String _staySubtitle(Map<String, dynamic> d) {
    final List<String> parts = <String>[
      if (d['area'] is String) d['area'] as String,
      if (d['rating'] != null) '${d['rating']}★',
    ];
    return parts.join(' · ');
  }

  /// The clock time at the airport or station, from an ISO timestamp.
  ///
  /// Read straight out of the string rather than through `DateTime`, and that
  /// is the whole point. `DateTime.tryParse` turns "19:00+05:30" into a UTC
  /// instant, and `.hour` on it is 13 — so a SpiceJet flight leaving Delhi at
  /// seven in the evening was rendering as 13:30. The mock data never showed
  /// it because those timestamps carried no offset; the first real provider
  /// made every departure five and a half hours wrong.
  ///
  /// Travel times are always quoted in local time at the place they happen,
  /// which is exactly what the offset in the string already encodes. There is
  /// nothing to convert, so nothing converts.
  static String _clock(Object? iso) {
    if (iso is! String || iso.isEmpty) return '';
    final RegExpMatch? m =
        RegExp(r'T(\d{2}):(\d{2})').firstMatch(iso);
    if (m != null) return '${m.group(1)}:${m.group(2)}';

    // No "T": not an ISO timestamp we recognise. Fall back rather than drop
    // the time entirely — a naive local string is still readable.
    final DateTime? t = DateTime.tryParse(iso);
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  static String _approx(String money) => money.isEmpty ? '' : '~$money';

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
