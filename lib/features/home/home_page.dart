import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../data/trip_data.dart';
import '../../app/transitions.dart';
import '../chat/chat_page.dart';
import '../auth/data/auth_service.dart';
import '../../app/api.dart';
import '../history/data/history_client.dart';
import '../history/history_page.dart';
import '../premium/premium_service.dart';
import '../premium/upgrade_page.dart';
import '../profile/data/profile_client.dart';
import '../profile/profile_page.dart';
import '../voice/voice_controller.dart';
import '../voice/widgets/mic_button.dart';
import 'widgets/history_section.dart';
import 'widgets/home_header.dart';
import 'widgets/pro_card.dart';
import 'widgets/stagger.dart';
import 'widgets/travel_modes.dart';
import 'widgets/trip_ideas_row.dart';

/// Where "Let's Start" lands: everything the user can point the assistant at.
///
/// Every route out of this screen ends in the same place — a conversation —
/// so the page is a set of ways to open one, not a set of separate features.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.name, this.loadHistory});

  /// Overrides who the screen greets. Normally null, and the name comes from
  /// whoever is signed in — the mockup's "Jasmin" was greeting every real user
  /// by a stranger's name. Tests pass one so they do not need a session.
  final String? name;

  /// Where past conversations come from. Defaults to the real API.
  ///
  /// Injectable so widget tests can hand over fixtures instead of standing up
  /// a backend and a signed-in user — and so a demo with nothing running can
  /// show the sample rows rather than an error.
  final HistoryLoader? loadHistory;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Fetches a page of history. See [HomePage.loadHistory].
typedef HistoryLoader = Future<List<TripHistoryEntry>> Function();

class _HomePageState extends State<HomePage> {
  late final HistoryClient? _history =
      widget.loadHistory == null ? HistoryClient() : null;
  final ProfileClient _profile = ProfileClient();

  /// Premium, and what is left of the free allowance. Unknown until loaded —
  /// and unknown means no badge and no upgrade button, never a guess.
  PlanInfo _plan = PlanInfo.unknown;

  /// Who to greet. The signed-in person, or a neutral fallback.
  ///
  /// Read on every build rather than cached: signing in happens on another
  /// screen, and a value captured in initState would greet the previous user —
  /// or nobody — until the app restarted.
  String get _greetingName =>
      widget.name ?? AuthService().displayName ?? 'there';

  List<TripHistoryEntry> _entries = <TripHistoryEntry>[];
  bool _loadingHistory = true;
  String? _historyError;

  /// The home mic never listens itself — it hands the microphone to the chat,
  /// which slides up over this page. This notifier only feeds the idle visuals.
  final ValueNotifier<double> _idleLevel = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshHistory());
    unawaited(_refreshPlan());
    PremiumService.instance.isPremium.addListener(_onPremium);
  }

  void _onPremium() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PremiumService.instance.isPremium.removeListener(_onPremium);
    _idleLevel.dispose();
    _history?.dispose();
    _profile.dispose();
    super.dispose();
  }

  Future<void> _refreshPlan() async {
    try {
      final PlanInfo plan = await _profile.plan();
      if (mounted) setState(() => _plan = plan);
    } on ApiException {
      // The card simply shows no badge; history reports real failures.
    }
  }

  /// "3 plans left this month", "Premium", or nothing while Premium is not
  /// for sale.
  /// Premium by either account: the backend's copy, or RevenueCat on this
  /// device — which knows the instant a purchase lands.
  bool get _premium => _plan.premium || PremiumService.instance.isPremium.value;

  String? get _planBadge {
    if (_premium) return 'Premium';
    final int? left = _plan.remainingThisMonth;
    if (!_plan.billingEnabled || left == null) return null;
    return left == 1 ? '1 plan left this month' : '$left plans left this month';
  }

  /// Premium's perks stand on their own (insider tips, priority support), so
  /// it is offered wherever it can be sold — not only once the free
  /// allowance is switched on.
  bool get _canUpgrade => !_premium && PremiumService.instance.canSell;

  Future<void> _openUpgrade() async {
    final bool? bought = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => UpgradePage(
          premium: PremiumService.instance,
          client: _profile,
          plan: _plan,
        ),
      ),
    );
    if (bought == true) unawaited(_refreshPlan());
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
    );
    if (!mounted) return;
    unawaited(_refreshHistory());
    unawaited(_refreshPlan());
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
    );
    if (mounted) unawaited(_refreshHistory());
  }

  /// Load the history list. Safe to call again — pull-to-refresh does, and so
  /// does coming back from a conversation that may have added one.
  Future<void> _refreshHistory() async {
    if (!mounted) return;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final List<TripHistoryEntry> rows = widget.loadHistory != null
          ? await widget.loadHistory!()
          : (await _history!.list()).sessions.map(_toEntry).toList();
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loadingHistory = false;
      });
    } on HistoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = 'Could not load your history.';
      });
    }
  }

  /// The API's shape, turned into the one the tile draws.
  ///
  /// The fallbacks matter: a conversation is written to the database the
  /// moment it starts, so the list can legitimately contain one that has no
  /// title and no preview yet because nobody has said anything into it.
  static TripHistoryEntry _toEntry(SessionSummary s) => TripHistoryEntry(
        id: s.id,
        title: s.title ?? 'Untitled conversation',
        preview: s.preview ?? 'Nothing said yet',
        mode: s.mode,
        when: humanWhen(s.updatedAt),
        saved: s.saved,
      );

  Future<void> _deleteHistory(TripHistoryEntry e) async {
    final String? id = e.id;
    if (id == null || _history == null) return;

    // Off the screen first, restored if the server disagrees. The swipe has
    // already animated it away; putting it back for a round trip and then
    // removing it again is a flicker that reads as a bug.
    final List<TripHistoryEntry> before = _entries;
    setState(() => _entries =
        _entries.where((TripHistoryEntry x) => x.id != id).toList());
    try {
      await _history.delete(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _entries = before);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not delete that. It is still there.'),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  Future<void> _openChat({
    String? opener,
    String title = 'New trip',
    bool listen = false,
    String? resumeSessionId,
    bool saved = false,
  }) async {
    await Navigator.of(context).push(
      SlideUpRoute<void>(
        page: ChatPage(
          title: title,
          opener: opener,
          resumeSessionId: resumeSessionId,
          autoListen: listen,
          initiallySaved: saved,
        ),
      ),
    );
    // A conversation may have been started, added to or renamed while that
    // screen was open, so the list behind it is now out of date — and a new
    // one has used a plan.
    if (!mounted) return;
    unawaited(_refreshHistory());
    unawaited(_refreshPlan());
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$what is next on the list.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: AppColors.ink,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final TextScaler scaler = media.textScaler.clamp(maxScaleFactor: 1.3);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: MediaQuery(
        data: media.copyWith(textScaler: scaler),
        child: SafeArea(
          bottom: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH,
                      8,
                      AppSpacing.pageH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Stagger(
                        index: 0,
                        child: HomeHeader(
                          name: _greetingName,
                          onProfile: _openProfile,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH,
                      18,
                      AppSpacing.pageH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Stagger(
                        index: 1,
                        child: ProCard(
                          badge: _planBadge,
                          onUpgrade: _canUpgrade ? _openUpgrade : null,
                          onOrbTap: () => _openChat(),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: TravelModes(
                          onPick: (TravelMode m) =>
                              _openChat(opener: m.prompt, title: m.label),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.pageH,
                          22,
                          AppSpacing.pageH,
                          12,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Plan something new',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.section,
                              ),
                            ),
                            TextButton(
                              onPressed: () => _soon('The full list'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.brand,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'View all',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 4,
                      child: TripIdeasRow(
                        ideas: kTripIdeas,
                        onPick: (TripIdea idea) =>
                            _openChat(opener: idea.prompt, title: idea.place),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Stagger(
                      index: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: HistorySection(
                          entries: _entries,
                          loading: _loadingHistory,
                          error: _historyError,
                          onRetry: _refreshHistory,
                          onDelete: _deleteHistory,
                          onViewAll: _openHistory,
                          // Resume, never replay. Passing the preview as an
                          // opener made the app say the agent's own last line
                          // back to it as though the user had.
                          onOpen: (TripHistoryEntry e) => _openChat(
                            title: e.title,
                            resumeSessionId: e.id,
                            saved: e.saved,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Room for the bloom and the mic that float over the list.
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
              // The mic sits in the corner and stays out of the way: the page
              // behind it is a list, and a list should be readable.
              Positioned(
                right: -8,
                bottom: -6,
                child: MicButton(
                  state: VoiceState.idle,
                  level: _idleLevel,
                  size: 62,
                  onTap: () => _openChat(listen: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
