import 'package:backPAC/data/trip_data.dart';
import 'package:backPAC/features/history/data/history_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanWhen', () {
    // A fixed "now" so these never depend on when they are run. Mid-afternoon
    // on purpose: the interesting bugs live around midnight boundaries, and a
    // reference at 00:30 would hide them.
    final DateTime now = DateTime(2026, 9, 20, 15, 0);

    test('reads as someone would say it', () {
      expect(humanWhen(now.subtract(const Duration(seconds: 20)), now: now),
          'Just now');
      expect(humanWhen(now.subtract(const Duration(minutes: 1)), now: now),
          'A minute ago');
      expect(humanWhen(now.subtract(const Duration(minutes: 40)), now: now),
          '40 minutes ago');
      expect(humanWhen(now.subtract(const Duration(hours: 1)), now: now),
          'An hour ago');
      expect(humanWhen(now.subtract(const Duration(hours: 5)), now: now),
          '5 hours ago');
    });

    test('counts calendar days, not 24-hour blocks', () {
      // 11pm last night is "Yesterday" at 3pm today — 16 hours ago, but a
      // different day, and the day is what a person means.
      expect(humanWhen(DateTime(2026, 9, 19, 23, 0), now: now), 'Yesterday');

      // And within the day you are still in, hours are the right unit: 1am
      // this morning is "14 hours ago", not "Today" — which would say less.
      expect(humanWhen(DateTime(2026, 9, 20, 1, 0), now: now), '14 hours ago');
    });

    test('gets coarser as it gets older, then gives a date', () {
      expect(humanWhen(DateTime(2026, 9, 17, 10, 0), now: now), '3 days ago');
      expect(humanWhen(DateTime(2026, 9, 12, 10, 0), now: now), 'Last week');
      expect(humanWhen(DateTime(2026, 9, 1, 10, 0), now: now), '2 weeks ago');
      // Past a month, "nine weeks ago" stops meaning anything.
      expect(humanWhen(DateTime(2026, 6, 4, 10, 0), now: now), '4 Jun');
      // Another year needs saying, or "4 Jun" is ambiguous.
      expect(humanWhen(DateTime(2024, 6, 4, 10, 0), now: now), '4 Jun 2024');
    });
  });

  group('SessionSummary.fromJson', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => <String, dynamic>{
          'id': 'abc',
          'title': 'Trains to Varanasi',
          'preview': 'Overnight, before 8am',
          'mode': 'train',
          'agentId': 'trip-planner',
          'status': 'active',
          'messageCount': 4,
          'createdAt': '2026-09-19T10:00:00Z',
          'updatedAt': '2026-09-19T10:05:00Z',
          ...extra,
        };

    test('maps the agent vocabulary to the traveller one', () {
      expect(SessionSummary.fromJson(row(<String, dynamic>{'mode': 'train'})).mode,
          TravelMode.trains);
      expect(SessionSummary.fromJson(row(<String, dynamic>{'mode': 'flight'})).mode,
          TravelMode.flights);
      // 'stay' is the backend's word for what the app calls Hotels.
      expect(SessionSummary.fromJson(row(<String, dynamic>{'mode': 'stay'})).mode,
          TravelMode.hotels);
    });

    test('a conversation with no result has no mode, rather than a wrong one',
        () {
      expect(SessionSummary.fromJson(row(<String, dynamic>{'mode': null})).mode,
          isNull);
      // And an unknown value from a newer backend must not throw.
      expect(
          SessionSummary.fromJson(row(<String, dynamic>{'mode': 'hovercraft'}))
              .mode,
          isNull);
    });

    test('survives a brand-new conversation with nothing said in it', () {
      final SessionSummary s = SessionSummary.fromJson(row(<String, dynamic>{
        'title': null,
        'preview': null,
        'mode': null,
        'messageCount': 0,
      }));
      expect(s.title, isNull);
      expect(s.preview, isNull);
      expect(s.messageCount, 0);
    });

    test('timestamps come back as local time', () {
      final SessionSummary s = SessionSummary.fromJson(row(<String, dynamic>{}));
      // The API speaks UTC; the tile says "3 hours ago" relative to the phone.
      expect(s.updatedAt.isUtc, isFalse);
      expect(s.updatedAt.toUtc(), DateTime.utc(2026, 9, 19, 10, 5));
    });
  });
}
