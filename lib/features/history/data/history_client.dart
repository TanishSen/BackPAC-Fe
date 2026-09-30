/// Reading and managing past conversations, and the groups they are filed in.
///
/// Sits beside [BackendClient] rather than inside it: that one exists to start
/// a call and is used mid-conversation, this one is the history screens', and
/// keeping them apart means the home screen does not drag LiveKit's world in
/// behind it.
///
/// Every request carries the Supabase access token, read fresh each time (see
/// [Api]). The backend scopes every row to whoever that token says you are, so
/// there is no user id to pass and no way to ask for anybody else's.
library;

import 'package:http/http.dart' as http;

import '../../../app/api.dart';
import '../../../data/trip_data.dart';

/// The history screens' error. The same thing as [ApiException] — kept under
/// its old name because that is what the screens catch.
typedef HistoryException = ApiException;

/// Where a trip stands, as the user sees it.
enum TripStatus { planning, completed, archived }

extension TripStatusWire on TripStatus {
  String get wire => switch (this) {
        TripStatus.planning => 'active',
        TripStatus.completed => 'completed',
        TripStatus.archived => 'archived',
      };

  static TripStatus from(String? raw) => switch (raw) {
        'completed' => TripStatus.completed,
        'archived' => TripStatus.archived,
        _ => TripStatus.planning,
      };
}

/// One past conversation, as the list shows it.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.mode,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.saved,
    this.favourite = false,
    this.groupId,
  });

  final String id;

  /// Null until the conversation has been named — see the backend, which names
  /// it after the first thing the user said.
  final String? title;
  final String? preview;

  /// Null when the conversation never got as far as a result. The tile falls
  /// back to a neutral icon rather than inventing a mode.
  final TravelMode? mode;

  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TripStatus status;

  /// Bookmarked from the chat screen. Drives the "Saved" filter.
  final bool saved;

  /// Hearted from the history list. Drives the "Favourites" filter.
  final bool favourite;

  /// The user's group (folder) for it, or null.
  final String? groupId;

  bool get isArchived => status == TripStatus.archived;

  /// A copy with some fields changed — how the list reflects an edit before
  /// (or without) reloading. `groupId` takes a function so null can be set.
  SessionSummary copyWith({
    String? title,
    bool? saved,
    bool? favourite,
    String? Function()? groupId,
    TripStatus? status,
  }) =>
      SessionSummary(
        id: id,
        title: title ?? this.title,
        preview: preview,
        mode: mode,
        messageCount: messageCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        status: status ?? this.status,
        saved: saved ?? this.saved,
        favourite: favourite ?? this.favourite,
        groupId: groupId == null ? this.groupId : groupId(),
      );

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String,
      title: json['title'] as String?,
      preview: json['preview'] as String?,
      mode: modeFromWire(json['mode'] as String?),
      messageCount: json['messageCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      status: TripStatusWire.from(json['status'] as String?),
      saved: json['saved'] as bool? ?? false,
      favourite: json['favourite'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }

  /// The backend's vocabulary is the agent's — train, flight, stay. The app's
  /// is the traveller's. This is the one place they meet.
  ///
  /// `bus` has no backend equivalent yet: the agent has no bus search, so no
  /// conversation can produce one. The chip is in the UI ready for when it
  /// does, and until then it simply matches nothing.
  static TravelMode? modeFromWire(String? raw) => switch (raw) {
        'train' => TravelMode.trains,
        'flight' => TravelMode.flights,
        'stay' => TravelMode.hotels,
        'bus' => TravelMode.bus,
        _ => null,
      };

  static String? modeToWire(TravelMode? m) => switch (m) {
        TravelMode.trains => 'train',
        TravelMode.flights => 'flight',
        TravelMode.hotels => 'stay',
        TravelMode.bus => 'bus',
        null => null,
      };
}

/// A page of history, and whether there is more behind it.
class SessionPage {
  const SessionPage({required this.sessions, required this.hasMore});

  final List<SessionSummary> sessions;
  final bool hasMore;
}

/// Which slice of history to ask for. Every field narrows; they combine.
class HistoryFilter {
  const HistoryFilter({
    this.saved = false,
    this.favourite = false,
    this.groupId,
    this.status,
    this.mode,
  });

  final bool saved;
  final bool favourite;
  final String? groupId;
  final TripStatus? status;
  final TravelMode? mode;

  static const HistoryFilter all = HistoryFilter();

  /// Whether [s] belongs in this slice — so an edit that takes a row out of
  /// it (unfavouriting, under Favourites) takes it off the screen too.
  bool matches(SessionSummary s) =>
      (!saved || s.saved) &&
      (!favourite || s.favourite) &&
      (groupId == null || s.groupId == groupId) &&
      (status == null || s.status == status) &&
      (mode == null || s.mode == mode);

  bool get isAll =>
      !saved && !favourite && groupId == null && status == null && mode == null;

  Map<String, String> get query => <String, String>{
        if (saved) 'saved': 'true',
        if (favourite) 'favourite': 'true',
        'groupId': ?groupId,
        'status': ?status?.wire,
        // Bus has no backend mode; asking for it would be a 422.
        if (mode != null && mode != TravelMode.bus)
          'mode': SessionSummary.modeToWire(mode)!,
      };

  /// The same slice with the Filters sheet's two refinements replaced — null
  /// clears one, which is why this is not a conventional `copyWith`.
  HistoryFilter refine({TravelMode? mode, TripStatus? status}) => HistoryFilter(
        saved: saved,
        favourite: favourite,
        groupId: groupId,
        status: status,
        mode: mode,
      );

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.saved == saved &&
      other.favourite == favourite &&
      other.groupId == groupId &&
      other.status == status &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(saved, favourite, groupId, status, mode);
}

/// A folder of conversations — "Mountains", "Honeymoon".
class TripGroup {
  const TripGroup({required this.id, required this.name, this.count = 0});

  final String id;
  final String name;
  final int count;

  factory TripGroup.fromJson(Map<String, dynamic> json) => TripGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        count: json['count'] as int? ?? 0,
      );
}

/// One turn of a conversation, for sharing it.
class PastTurn {
  const PastTurn({required this.role, required this.content});

  final String role;
  final String content;

  bool get isAgent => role == 'agent';
}

class HistoryClient {
  HistoryClient({
    String? baseUrl,
    http.Client? client,
    String? Function()? accessToken,
  }) : _api = Api(baseUrl: baseUrl, client: client, accessToken: accessToken);

  final Api _api;

  /// This user's conversations, newest first.
  Future<SessionPage> list({
    int limit = 20,
    int offset = 0,
    HistoryFilter filter = HistoryFilter.all,
  }) async {
    final Map<String, dynamic> body = await _api.get(
      '/api/v1/sessions',
      query: <String, String>{
        'limit': '$limit',
        'offset': '$offset',
        ...filter.query,
      },
    ) as Map<String, dynamic>;
    return SessionPage(
      sessions: (body['sessions'] as List<dynamic>)
          .map((dynamic e) =>
              SessionSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: body['hasMore'] as bool? ?? false,
    );
  }

  /// A conversation's turns, oldest first — what Share sends.
  Future<List<PastTurn>> transcript(String id) async {
    final Map<String, dynamic> body =
        await _api.get('/api/v1/sessions/$id') as Map<String, dynamic>;
    return <PastTurn>[
      for (final dynamic m in body['messages'] as List<dynamic>? ?? <dynamic>[])
        PastTurn(
          role: (m as Map<String, dynamic>)['role'] as String,
          content: m['content'] as String,
        ),
    ];
  }

  /// Delete the whole account: every conversation, group and saved trip, the
  /// profile, then the sign-in itself. Returns whether the sign-in account was
  /// closed too — the server says false only when it is not configured to.
  Future<bool> deleteAccount() async {
    final Object? body = await _api.delete('/api/v1/account');
    return body is Map<String, dynamic> && body['accountDeleted'] == true;
  }

  /// Erase a conversation — transcript, cards and all. Not reversible.
  Future<void> delete(String id) => _api.delete('/api/v1/sessions/$id');

  /// Put a conversation away without deleting it.
  Future<void> archive(String id) => setStatus(id, TripStatus.archived);

  /// Bring an archived conversation back.
  Future<void> unarchive(String id) => setStatus(id, TripStatus.planning);

  /// Planning, taken, or put away.
  Future<void> setStatus(String id, TripStatus status) =>
      _patch(id, <String, dynamic>{'status': status.wire});

  /// Bookmark a conversation, or un-bookmark it.
  ///
  /// Separate from archiving: a conversation can be both saved and archived,
  /// because "I want to find this again" and "I am done with this" are
  /// different things to want.
  Future<void> setSaved(String id, bool saved) =>
      _patch(id, <String, dynamic>{'saved': saved});

  Future<void> setFavourite(String id, bool favourite) =>
      _patch(id, <String, dynamic>{'favourite': favourite});

  /// File in a group, or pass null to take it out of one.
  Future<void> setGroup(String id, String? groupId) =>
      _patch(id, <String, dynamic>{'groupId': groupId});

  /// Give a conversation a name of your own.
  Future<void> rename(String id, String title) =>
      _patch(id, <String, dynamic>{'title': title});

  Future<void> _patch(String id, Map<String, dynamic> body) =>
      _api.patch('/api/v1/sessions/$id', body: body);

  // --- groups ----------------------------------------------------------------

  Future<List<TripGroup>> groups() async {
    final List<dynamic> body = await _api.get('/api/v1/groups') as List<dynamic>;
    return body
        .map((dynamic e) => TripGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TripGroup> createGroup(String name) async => TripGroup.fromJson(
        await _api.post('/api/v1/groups', body: <String, String>{'name': name})
            as Map<String, dynamic>,
      );

  Future<TripGroup> renameGroup(String id, String name) async =>
      TripGroup.fromJson(
        await _api.patch('/api/v1/groups/$id', body: <String, String>{'name': name})
            as Map<String, dynamic>,
      );

  /// Its conversations stay, ungrouped.
  Future<void> deleteGroup(String id) => _api.delete('/api/v1/groups/$id');

  void dispose() => _api.dispose();
}
