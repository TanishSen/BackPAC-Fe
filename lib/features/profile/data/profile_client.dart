/// The profile screen's data: who you are, your journey so far, your plan,
/// and your bucket list.
library;

import 'package:http/http.dart' as http;

import '../../../app/api.dart';

/// What someone has said about themselves. Every field optional.
class Profile {
  const Profile({this.displayName, this.homeCity, this.bio, this.avatar});

  final String? displayName;
  final String? homeCity;
  final String? bio;

  /// One of [kAvatars], or null for the default.
  final String? avatar;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        displayName: json['displayName'] as String?,
        homeCity: json['homeCity'] as String?,
        bio: json['bio'] as String?,
        avatar: json['avatar'] as String?,
      );
}

/// The avatars to choose from. Emoji rather than uploads: nothing to store,
/// nothing to moderate, and they look at home next to the orb.
const List<String> kAvatars = <String>[
  '🐱', '🐶', '🦊', '🐼', '🐨', '🐯', '🦁', '🐸', '🐵', '🐧', '🦄', '🐙',
];

/// The numbers on "Your Travel Journey", all counted by the backend from real
/// conversations — nothing here is estimated.
class JourneyStats {
  const JourneyStats({
    this.trips = 0,
    this.places = 0,
    this.saved = 0,
    this.favourites = 0,
    this.completed = 0,
    this.inProgress = 0,
    this.bucketList = 0,
  });

  final int trips;
  final int places;
  final int saved;
  final int favourites;
  final int completed;
  final int inProgress;
  final int bucketList;

  factory JourneyStats.fromJson(Map<String, dynamic> json) => JourneyStats(
        trips: json['trips'] as int? ?? 0,
        places: json['places'] as int? ?? 0,
        saved: json['saved'] as int? ?? 0,
        favourites: json['favourites'] as int? ?? 0,
        completed: json['completed'] as int? ?? 0,
        inProgress: json['inProgress'] as int? ?? 0,
        bucketList: json['bucketList'] as int? ?? 0,
      );
}

/// Premium or not, and what is left of the free allowance.
class PlanInfo {
  const PlanInfo({
    this.billingEnabled = false,
    this.premium = false,
    this.premiumUntil,
    this.willRenew = false,
    this.freeMonthlyLimit,
    this.usedThisMonth = 0,
    this.remainingThisMonth,
  });

  /// False => Premium is not on sale, and nothing in the app mentions it.
  final bool billingEnabled;
  final bool premium;
  final DateTime? premiumUntil;
  final bool willRenew;

  /// Null when unlimited.
  final int? freeMonthlyLimit;
  final int usedThisMonth;
  final int? remainingThisMonth;

  static const PlanInfo unknown = PlanInfo();

  factory PlanInfo.fromJson(Map<String, dynamic> json) => PlanInfo(
        billingEnabled: json['billingEnabled'] as bool? ?? false,
        premium: json['premium'] as bool? ?? false,
        premiumUntil: json['premiumUntil'] == null
            ? null
            : DateTime.parse(json['premiumUntil'] as String).toLocal(),
        willRenew: json['willRenew'] as bool? ?? false,
        freeMonthlyLimit: json['freeMonthlyLimit'] as int?,
        usedThisMonth: json['usedThisMonth'] as int? ?? 0,
        remainingThisMonth: json['remainingThisMonth'] as int?,
      );
}

class Me {
  const Me({
    this.profile = const Profile(),
    this.stats = const JourneyStats(),
    this.plan = PlanInfo.unknown,
  });

  final Profile profile;
  final JourneyStats stats;
  final PlanInfo plan;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
        stats: JourneyStats.fromJson(json['stats'] as Map<String, dynamic>),
        plan: PlanInfo.fromJson(json['plan'] as Map<String, dynamic>),
      );
}

/// A place someone wants to go, one day.
class BucketItem {
  const BucketItem({required this.id, required this.place, this.note});

  final int id;
  final String place;

  /// What they said about it — "for the northern lights". Null when the note
  /// would only repeat the place.
  final String? note;

  factory BucketItem.fromJson(Map<String, dynamic> json) {
    final String place = json['destination'] as String;
    final String title = json['title'] as String? ?? '';
    return BucketItem(
      id: json['id'] as int,
      place: place,
      note: title.trim().isEmpty || title.trim() == place.trim() ? null : title,
    );
  }
}

class ProfileClient {
  ProfileClient({
    String? baseUrl,
    http.Client? client,
    String? Function()? accessToken,
  }) : _api = Api(baseUrl: baseUrl, client: client, accessToken: accessToken);

  final Api _api;

  Future<Me> me() async =>
      Me.fromJson(await _api.get('/api/v1/me') as Map<String, dynamic>);

  /// Send only what changed. An empty string clears a field.
  Future<Me> update({
    String? displayName,
    String? homeCity,
    String? bio,
    String? avatar,
  }) async =>
      Me.fromJson(await _api.patch('/api/v1/me', body: <String, String>{
        'displayName': ?displayName,
        'homeCity': ?homeCity,
        'bio': ?bio,
        'avatar': ?avatar,
      }) as Map<String, dynamic>);

  Future<PlanInfo> plan() async => PlanInfo.fromJson(
      await _api.get('/api/v1/billing/plan') as Map<String, dynamic>);

  /// After a purchase or restore: have the backend ask RevenueCat now, so
  /// Premium works immediately instead of when the webhook arrives.
  Future<PlanInfo> syncPlan() async => PlanInfo.fromJson(
      await _api.post('/api/v1/billing/sync') as Map<String, dynamic>);

  // --- bucket list (the backend's saved trips) --------------------------------

  Future<List<BucketItem>> bucketList() async {
    final List<dynamic> body = await _api.get('/api/v1/trips/saved') as List<dynamic>;
    return body
        .map((dynamic e) => BucketItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BucketItem> addToBucketList(String place, {String? note}) async {
    final String clean = place.trim();
    final String? why = note?.trim();
    return BucketItem.fromJson(await _api.post('/api/v1/trips/saved', body: <String, Object>{
      'destination': clean,
      'title': (why == null || why.isEmpty) ? clean : why,
    }) as Map<String, dynamic>);
  }

  Future<void> removeFromBucketList(int id) => _api.delete('/api/v1/trips/saved/$id');

  void dispose() => _api.dispose();
}
