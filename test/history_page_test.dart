import 'dart:convert';

import 'package:backPAC/data/trip_data.dart';
import 'package:backPAC/features/history/data/history_client.dart';
import 'package:backPAC/features/history/history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A backend in miniature: enough of `/sessions` and `/groups` to drive the
/// page, recording what it was asked.
class _FakeBackend {
  _FakeBackend({List<Map<String, dynamic>>? rows, this.hasMore = false})
      : rows = rows ?? <Map<String, dynamic>>[_row('1', 'Resorts in Goa'), _row('2', 'Paragliding in Manali')];

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> groups = <Map<String, dynamic>>[
    <String, dynamic>{'id': 'g1', 'name': 'Mountains', 'count': 1, 'createdAt': '2026-09-01T00:00:00Z'},
  ];
  bool hasMore;
  bool failList = false;
  final List<http.Request> seen = <http.Request>[];

  static Map<String, dynamic> _row(String id, String title, {bool favourite = false}) => <String, dynamic>{
        'id': id,
        'title': title,
        'preview': 'Give me suggestions on some amazing places and check reservations',
        'mode': 'stay',
        'agentId': 'trip-planner',
        'saved': false,
        'favourite': favourite,
        'groupId': null,
        'status': 'active',
        'messageCount': 4,
        'createdAt': '2026-09-2${id}T10:00:00Z',
        'updatedAt': '2026-09-2${id}T10:05:00Z',
      };

  late final HistoryClient client = HistoryClient(
    baseUrl: 'http://api.test',
    accessToken: () => 'token',
    client: MockClient((http.Request r) async {
      seen.add(r);
      final String path = r.url.path;
      if (path == '/api/v1/groups' && r.method == 'GET') {
        return http.Response(jsonEncode(groups), 200);
      }
      if (path == '/api/v1/sessions' && r.method == 'GET') {
        if (failList) return http.Response('{"error":"nope"}', 500);
        final bool fav = r.url.queryParameters['favourite'] == 'true';
        final int offset = int.parse(r.url.queryParameters['offset'] ?? '0');
        final List<Map<String, dynamic>> shown = rows
            .where((Map<String, dynamic> x) => !fav || x['favourite'] == true)
            .skip(offset)
            .toList();
        return http.Response(
          jsonEncode(<String, dynamic>{'sessions': shown, 'hasMore': offset == 0 && hasMore}),
          200,
        );
      }
      if (path.startsWith('/api/v1/sessions/') && r.method == 'PATCH') {
        final String id = path.split('/').last;
        final Map<String, dynamic> row = rows.firstWhere((Map<String, dynamic> x) => x['id'] == id);
        row.addAll(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(row), 200);
      }
      return http.Response('{"error":"unexpected ${r.method} $path"}', 404);
    }),
  );
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester, _FakeBackend b, {HistoryFilter filter = HistoryFilter.all}) async {
  usePhone(tester);
  await tester.pumpWidget(MaterialApp(home: HistoryPage(client: b.client, initialFilter: filter)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('lists conversations with a picture for each trip', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend();
    await _open(tester, b);

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Resorts in Goa'), findsOneWidget);
    expect(find.text('Paragliding in Manali'), findsOneWidget);
    // The words decide the picture: a beach for Goa, a parachute for Manali.
    expect(find.text('🏖️'), findsOneWidget);
    expect(find.text('🪂'), findsOneWidget);
    // Chips from the design, with the user's own group among them.
    // The chip row scrolls sideways; the test font is far wider than Poppins,
    // so look past the screen edge rather than assert what is on it.
    for (final String chip in <String>['All', 'Saved', 'Favourites', 'Mountains']) {
      expect(find.text(chip, skipOffstage: false), findsOneWidget, reason: chip);
    }
    expect(find.text('Create group +'), findsOneWidget);
  });

  testWidgets('a chip asks the backend for that slice', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend(rows: <Map<String, dynamic>>[
      _FakeBackend._row('1', 'Resorts in Goa', favourite: true),
      _FakeBackend._row('2', 'Paragliding in Manali'),
    ]);
    await _open(tester, b);

    await tester.ensureVisible(find.text('Favourites'));
    await tester.pump();
    await tester.tap(find.text('Favourites'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final http.Request last = b.seen.lastWhere((http.Request r) => r.url.path == '/api/v1/sessions');
    expect(last.url.queryParameters['favourite'], 'true');
    expect(find.text('Resorts in Goa'), findsOneWidget);
    expect(find.text('Paragliding in Manali'), findsNothing);
  });

  testWidgets('the ⋮ menu has the design’s actions, and Favourite saves', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend();
    await _open(tester, b);

    await tester.tap(find.byTooltip('More').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (final String item in <String>['Rename', 'Favourite', 'Share', 'Add to group', 'Mark as completed', 'Delete']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }

    await tester.tap(find.text('Favourite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final http.Request patch = b.seen.lastWhere((http.Request r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/v1/sessions/1');
    expect(jsonDecode(patch.body), <String, dynamic>{'favourite': true});
    // The heart appears on the row straight away.
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('an empty slice says what would fill it', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend(rows: <Map<String, dynamic>>[]);
    await _open(tester, b, filter: const HistoryFilter(favourite: true));
    expect(find.textContaining('choose Favourite'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend()..failList = true;
    await _open(tester, b);
    expect(find.text('Try again'), findsOneWidget);

    b.failList = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Resorts in Goa'), findsOneWidget);
  });

  testWidgets('scrolling to the end fetches the next page', (WidgetTester tester) async {
    final _FakeBackend b = _FakeBackend(
      rows: <Map<String, dynamic>>[
        for (int i = 1; i <= 9; i++) _FakeBackend._row('$i', 'Trip $i'),
      ],
      hasMore: true,
    );
    // The fake serves everything on the first page but says there is more,
    // so the second request is the proof of paging.
    await _open(tester, b);
    await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final List<http.Request> lists =
        b.seen.where((http.Request r) => r.url.path == '/api/v1/sessions').toList();
    expect(lists.length, greaterThanOrEqualTo(2));
    expect(lists.last.url.queryParameters['offset'], '9');
  });

  test('share text reads as a plan, not a log', () {
    final String text = shareText('Goa in December', const <PastTurn>[
      PastTurn(role: 'user', content: 'Three nights in north Goa'),
      PastTurn(role: 'agent', content: 'Here are two stays.'),
    ]);
    expect(text, startsWith('Goa in December'));
    expect(text, contains('Me: Three nights in north Goa'));
    expect(text, contains('backPAC: Here are two stays.'));
    expect(text, endsWith('Planned with backPAC'));
  });

  test('tripEmoji: keywords, then mode, then a speech bubble', () {
    expect(tripEmoji('Resorts in Goa', '', TravelMode.hotels), '🏖️');
    expect(tripEmoji('Trains to Delhi', '', TravelMode.trains), '🚆');
    expect(tripEmoji('Hello', '', null), '💬');
  });
}
