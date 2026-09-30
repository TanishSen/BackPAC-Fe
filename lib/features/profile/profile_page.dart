import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/api.dart';
import '../../app/app_config.dart';
import '../../app/app_theme.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../orb/rezolve_orb.dart';
import '../auth/auth_page.dart';
import '../auth/data/auth_service.dart';
import '../history/data/history_client.dart';
import '../history/history_page.dart';
import '../home/home_page.dart';
import '../premium/premium_service.dart';
import '../premium/redeem_code.dart';
import '../premium/upgrade_page.dart';
import '../welcome/welcome_page.dart';
import 'bucket_list_page.dart';
import 'data/profile_client.dart';
import 'edit_profile_sheet.dart';
import 'orb_play_page.dart';

/// Who you are, where you have been, and what you are planning — plus the
/// account itself: plan, sign out, delete.
///
/// Every number and list on it is real: the backend counts them from the
/// conversations themselves (`GET /me`), and each tile opens the slice of
/// history it names.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.client, this.historyClient, this.premium});

  /// Injected by tests. Default to the real API.
  final ProfileClient? client;
  final HistoryClient? historyClient;
  final PremiumService? premium;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color _danger = Color(0xFFD64545);

  late final ProfileClient _client = widget.client ?? ProfileClient();
  late final PremiumService _premium = widget.premium ?? PremiumService.instance;

  Me? _me;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _premium.isPremium.addListener(_onPremium);
  }

  void _onPremium() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _premium.isPremium.removeListener(_onPremium);
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  /// Premium by either account: the backend's copy, or RevenueCat on this
  /// device — which knows the instant a purchase lands.
  bool get _isPremium => (_me?.plan.premium ?? false) || _premium.isPremium.value;

  /// "Contact support" — flagged priority for Premium members, which is the
  /// Priority Support perk: their mail is answered first.
  Future<void> _contactSupport() async {
    final String subject = _isPremium ? '[Priority] backPAC Premium support' : 'backPAC support';
    final Uri mail = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (!await launchUrl(mail)) {
      _toast('Write to us at ${AppConfig.supportEmail}');
    }
  }

  Future<void> _load() async {
    try {
      final Me me = await _client.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String get _name {
    final String? mine = _me?.profile.displayName;
    if (mine != null && mine.isNotEmpty) return mine;
    return AuthService().displayName ?? 'Traveller';
  }

  String get _firstName => _name.split(' ').first;

  // --- navigation -------------------------------------------------------------

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) unawaited(_load()); // counts may have changed
  }

  void _history(String title, HistoryFilter filter) => _push(HistoryPage(
        title: title,
        initialFilter: filter,
        client: widget.historyClient,
      ));

  Future<void> _editProfile() async {
    final Me? updated = await showModalBottomSheet<Me>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => EditProfileSheet(
        client: _client,
        profile: _me?.profile ?? const Profile(),
        fallbackName: AuthService().displayName,
      ),
    );
    if (updated != null && mounted) setState(() => _me = updated);
  }

  Future<void> _upgrade() async {
    final bool? bought = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => UpgradePage(
          premium: _premium,
          client: _client,
          plan: _me?.plan ?? PlanInfo.unknown,
        ),
      ),
    );
    if (bought == true && mounted) unawaited(_load());
  }

  // --- account -------------------------------------------------------------------

  Future<void> _signOut({bool switchAccount = false}) async {
    await AuthService().signOut();
    if (!mounted) return;
    final NavigatorState nav = Navigator.of(context);
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => switchAccount
            ? AuthPage(
                onSignedIn: () => nav.pushAndRemoveUntil(
                  MaterialPageRoute<void>(builder: (_) => const HomePage()),
                  (Route<dynamic> _) => false,
                ),
              )
            : const WelcomePage(),
      ),
      (Route<dynamic> _) => false,
    );
  }

  Future<void> _openSettings() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (AuthService().currentUser?.email case final String email)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(email, style: AppText.caption),
              ),
            _SheetItem(Icons.edit_outlined, 'Edit profile', () => Navigator.of(sheet).pop('edit')),
            if (_premium.available) ...<Widget>[
              _SheetItem(Icons.restore_rounded, 'Restore purchases',
                  () => Navigator.of(sheet).pop('restore')),
              if (_isPremium)
                _SheetItem(Icons.credit_card_rounded, 'Manage subscription',
                    () => Navigator.of(sheet).pop('manage')),
            ],
            if (AppConfig.privacyUrl.isNotEmpty)
              _SheetItem(Icons.privacy_tip_outlined, 'Privacy policy',
                  () => Navigator.of(sheet).pop('privacy')),
            if (AppConfig.termsUrl.isNotEmpty)
              _SheetItem(Icons.description_outlined, 'Terms of use',
                  () => Navigator.of(sheet).pop('terms')),
            if (!_isPremium)
              _SheetItem(Icons.redeem_rounded, 'Redeem promo code',
                  () => Navigator.of(sheet).pop('redeem')),
            _SheetItem(
              Icons.support_agent_rounded,
              _isPremium ? 'Priority support' : 'Contact support',
              () => Navigator.of(sheet).pop('support'),
            ),
            _SheetItem(Icons.delete_forever_rounded, 'Delete account',
                () => Navigator.of(sheet).pop('delete'),
                color: _danger),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await _editProfile();
      case 'restore':
        await _restore();
      case 'manage':
        await _manage();
      case 'privacy':
        await _open(AppConfig.privacyUrl);
      case 'terms':
        await _open(AppConfig.termsUrl);
      case 'redeem':
        final PlanInfo? plan = await redeemPromoCode(
          context,
          client: _client,
          premium: _premium,
        );
        if (plan != null) {
          await _load();
          _toast('Premium unlocked 👑 Enjoy!');
        }
      case 'support':
        await _contactSupport();
      case 'delete':
        await _deleteAccount();
    }
  }

  Future<void> _restore() async {
    final bool found = await _premium.restore();
    if (found) {
      try {
        final PlanInfo plan = await _client.syncPlan();
        if (mounted && _me != null) {
          setState(() => _me = Me(profile: _me!.profile, stats: _me!.stats, plan: plan));
        }
      } on ApiException {
        // The webhook will catch the backend up.
      }
    }
    _toast(found ? 'Premium restored.' : 'No purchases to restore on this account.');
  }

  Future<void> _manage() async {
    final String? url = await _premium.managementUrl();
    if (url == null) {
      _toast('Manage your subscription in your App Store or Google Play settings.');
      return;
    }
    await _open(url);
  }

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open that link.');
    }
  }

  Future<void> _deleteAccount() async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete your account?', style: AppText.section),
        content: Text(
          'This permanently erases your profile, conversations, groups and '
          'bucket list, and closes your account. It cannot be undone.'
          '${_isPremium ? '\n\nThis does not cancel your Premium subscription — cancel it in your App Store or Google Play settings first.' : ''}',
          style: AppText.body,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final HistoryClient history = widget.historyClient ?? HistoryClient();
    try {
      final bool closed = await history.deleteAccount();
      await _signOut();
      messenger.showSnackBar(SnackBar(
        content: Text(closed
            ? 'Your account has been deleted.'
            : 'Your data has been erased. Contact support to close the sign-in account.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (widget.historyClient == null) history.dispose();
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: AppColors.ink,
      ));
  }

  // --- building -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final Me me = _me ?? const Me();
    final PlanInfo plan = me.plan;
    final bool premium = _isPremium;
    // Premium's perks stand on their own, so it is offered wherever it can be
    // sold — not only once the backend's free allowance is switched on.
    final bool canUpgrade = !premium && _premium.canSell;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: MediaQuery(
        data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
        child: Stack(
          children: <Widget>[
            const _Backdrop(),
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.pageH,
                    8,
                    AppSpacing.pageH,
                    28 + media.padding.bottom,
                  ),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        RoundIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 12),
                        Text('backPAC.', style: AppText.wordmark.copyWith(fontSize: 20)),
                        const Spacer(),
                        RoundIconButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Settings',
                          onTap: _openSettings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Greeting(name: _firstName),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      name: _name,
                      profile: me.profile,
                      stats: me.stats,
                      loading: _me == null && _error == null,
                      premium: premium,
                      onEdit: _editProfile,
                      onViewAll: () => _history('History', HistoryFilter.all),
                    ),
                    if (_error != null && _me == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: AppText.body)),
                            TextButton(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    _TileGrid(
                      tiles: <_Tile>[
                        _Tile(
                          icon: Icons.bookmark_rounded,
                          tint: AppColors.brand,
                          title: 'Saved Trips',
                          subtitle: 'Your dream trips',
                          onTap: () => _history('Saved trips', const HistoryFilter(saved: true)),
                        ),
                        _Tile(
                          icon: Icons.verified_rounded,
                          tint: const Color(0xFF4F7BF0),
                          title: 'Completed Trips',
                          subtitle: "Trips you've taken",
                          onTap: () => _history(
                            'Completed trips',
                            const HistoryFilter(status: TripStatus.completed),
                          ),
                        ),
                        _Tile(
                          icon: Icons.format_list_bulleted_rounded,
                          tint: const Color(0xFFEE8A4E),
                          title: 'Bucket List',
                          subtitle: 'Places to explore',
                          onTap: () => _push(BucketListPage(client: widget.client)),
                        ),
                        _Tile(
                          icon: Icons.pending_actions_rounded,
                          tint: const Color(0xFFB266D9),
                          title: 'In Progress',
                          subtitle: "Trips you're planning",
                          onTap: () => _history(
                            'In progress',
                            const HistoryFilter(status: TripStatus.planning),
                          ),
                        ),
                        _Tile(
                          icon: Icons.favorite_rounded,
                          tint: const Color(0xFFE5537A),
                          title: 'Favourites',
                          subtitle: 'Your favourite places',
                          onTap: () => _history('Favourites', const HistoryFilter(favourite: true)),
                        ),
                        _Tile(
                          icon: Icons.sentiment_very_satisfied_rounded,
                          tint: const Color(0xFFE6A23C),
                          title: 'Play with COOKIE',
                          subtitle: 'Fun travel games',
                          onTap: () => _push(const OrbPlayPage()),
                        ),
                      ],
                    ),
                    if (premium) ...<Widget>[
                      const SizedBox(height: 18),
                      _PremiumActive(plan: plan, onManage: _premium.available ? _manage : null),
                    ] else if (canUpgrade) ...<Widget>[
                      const SizedBox(height: 18),
                      _UnlockPremium(plan: plan, onUpgrade: _upgrade),
                    ],
                    const SizedBox(height: 18),
                    _AccountRow(
                      onSwitch: () => _signOut(switchAccount: true),
                      onLogOut: _signOut,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lavender wash behind the top of the page, with the faint travel marks
/// from the design — drawn from icons, so there is nothing to ship.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 340,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFE6E0FA), AppColors.canvas],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 70,
                right: 70,
                child: Transform.rotate(
                  angle: -0.5,
                  child: Icon(Icons.flight_rounded, size: 34, color: AppColors.surface.withValues(alpha: 0.9)),
                ),
              ),
              Positioned(
                top: 150,
                right: 8,
                child: Icon(Icons.beach_access_rounded, size: 96, color: AppColors.brandSoft.withValues(alpha: 0.16)),
              ),
              Positioned(
                top: 190,
                right: 110,
                child: Icon(Icons.park_rounded, size: 60, color: AppColors.brandSoft.withValues(alpha: 0.12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The orb, saying hello from beside the card.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(
            width: 96,
            height: 104,
            child: OverflowBox(
              maxWidth: 130,
              maxHeight: 130,
              child: RezolveOrb(size: 110, headroom: 0.1, playfulness: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x14262046), blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Hi $name! 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ready for your next adventure?',
                    style: AppText.body.copyWith(fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.profile,
    required this.stats,
    required this.loading,
    required this.onEdit,
    required this.onViewAll,
    this.premium = false,
  });

  final String name;
  final Profile profile;
  final JourneyStats stats;
  final bool loading;
  final bool premium;
  final VoidCallback onEdit;
  final VoidCallback onViewAll;

  static const double _avatar = 104;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(top: _avatar * 0.42),
          padding: const EdgeInsets.fromLTRB(20, _avatar * 0.62, 20, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x0F2A2140), blurRadius: 22, offset: Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Only the name shares its line with the button; the city gets
              // the full width beneath, so neither is cut short.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      backgroundColor: AppColors.canvas,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: AppText.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: profile.homeCity == null ? onEdit : null,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.location_on_outlined, size: 15, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        profile.homeCity ?? 'Add your home city',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(
                          color: profile.homeCity == null ? AppColors.brand : AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                profile.bio ?? 'Add a line about yourself ✨',
                style: AppText.body.copyWith(
                  fontSize: 13.5,
                  height: 1.45,
                  color: profile.bio == null ? AppColors.muted.withValues(alpha: 0.8) : AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 16),
              _Journey(stats: stats, loading: loading, onViewAll: onViewAll),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(child: _Avatar(emoji: profile.avatar, size: _avatar, onEdit: onEdit, premium: premium)),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.emoji,
    required this.size,
    required this.onEdit,
    this.premium = false,
  });

  /// The VIP badge perk: a crown on the avatar.
  final bool premium;
  final String? emoji;
  final double size;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change your avatar',
      child: GestureDetector(
        onTap: onEdit,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: <Color>[AppColors.brand, AppColors.brandSoft]),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: Color(0x336A68DF), blurRadius: 18, offset: Offset(0, 8)),
                  ],
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF4DF),
                    shape: BoxShape.circle,
                  ),
                  child: emoji == null
                      ? Icon(Icons.person_rounded, size: size * 0.5, color: AppColors.brandSoft)
                      : Text(emoji!, style: TextStyle(fontSize: size * 0.48)),
                ),
              ),
              if (premium)
                const Positioned(
                  top: -18,
                  left: 0,
                  right: 0,
                  child: Center(child: Text('👑', style: TextStyle(fontSize: 30))),
                ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2.5),
                  ),
                  child: const Icon(Icons.edit_rounded, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Your Travel Journey": four counts, each from the backend.
class _Journey extends StatelessWidget {
  const _Journey({required this.stats, required this.loading, required this.onViewAll});

  final JourneyStats stats;
  final bool loading;
  final VoidCallback onViewAll;

  /// "08" rather than "8": the design sets the counts in two digits, which
  /// also keeps the four columns from shifting as a number grows.
  static String _pad(int n) => n < 10 ? '0$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final List<(IconData, Color, int, String)> items = <(IconData, Color, int, String)>[
      (Icons.flight_rounded, AppColors.brand, stats.trips, 'Trips'),
      (Icons.location_on_rounded, const Color(0xFFE5537A), stats.places, 'Places'),
      (Icons.bookmark_rounded, const Color(0xFF4F7BF0), stats.saved, 'Saved'),
      (Icons.favorite_rounded, const Color(0xFFEE8A4E), stats.favourites, 'Favourites'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F5FC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('Your Travel Journey', style: AppText.cardTitle),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('View All', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: items[i].$2.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(items[i].$1, size: 18, color: items[i].$2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loading ? '–' : _pad(items[i].$3),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(items[i].$4, style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  const _Tile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _TileView(tile: tiles[i])),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < tiles.length ? _TileView(tile: tiles[i + 1]) : const SizedBox(),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: tile.onTap,
        borderRadius: BorderRadius.circular(20),
        // A tile is ~170pt wide on a phone, so every point of padding is a
        // letter of title: tight insets, and the title may take two lines
        // rather than lose "Completed Trips" to an ellipsis.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tile.tint.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tile.icon, size: 20, color: tile.tint),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tile.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle.copyWith(fontSize: 13, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tile.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 10.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnlockPremium extends StatelessWidget {
  const _UnlockPremium({required this.plan, required this.onUpgrade});

  final PlanInfo plan;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final int? limit = plan.freeMonthlyLimit;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFEDE8FD), Color(0xFFFBE8F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RichText(
                  text: TextSpan(
                    style: AppText.section.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                    children: const <InlineSpan>[
                      TextSpan(text: 'Unlock '),
                      TextSpan(text: 'Premium', style: TextStyle(color: AppColors.brand)),
                      TextSpan(text: ' 👑'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  limit == null
                      ? 'Plan as many trips as you like.'
                      : 'Plan as many trips as you like. Free includes $limit a month'
                          '${plan.remainingThisMonth != null ? ' — ${plan.remainingThisMonth} left' : ''}.',
                  style: AppText.body.copyWith(fontSize: 13, height: 1.4, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onUpgrade,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('Upgrade Now', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Icon(Icons.luggage_rounded, size: 84, color: AppColors.brand.withValues(alpha: 0.75)),
              const Positioned(
                top: -4,
                right: -4,
                child: Icon(Icons.auto_awesome, size: 20, color: Color(0xFFE6A23C)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumActive extends StatelessWidget {
  const _PremiumActive({required this.plan, this.onManage});

  final PlanInfo plan;
  final VoidCallback? onManage;

  static String _date(DateTime d) {
    const List<String> m = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? until = plan.premiumUntil;
    final String line = until == null
        ? 'Unlimited trip plans, for life.'
        : plan.willRenew
            ? 'Renews on ${_date(until)}.'
            : 'Ends on ${_date(until)} — it will not renew.';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandLine),
      ),
      child: Row(
        children: <Widget>[
          const Text('👑', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("You're Premium", style: AppText.cardTitle),
                Text(line, style: AppText.caption.copyWith(fontSize: 12)),
              ],
            ),
          ),
          if (onManage != null)
            TextButton(
              onPressed: onManage,
              style: TextButton.styleFrom(foregroundColor: AppColors.brand),
              child: const Text('Manage', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.onSwitch, required this.onLogOut});

  final VoidCallback onSwitch;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      // Each half may shrink, so large accessibility text wraps into the row
      // instead of pushing Log Out off the edge.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: TextButton.icon(
              onPressed: onSwitch,
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
              label: const Text('Switch Account', overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                textStyle: AppText.label.copyWith(fontSize: 14),
              ),
            ),
          ),
          Flexible(
            child: TextButton.icon(
              onPressed: onLogOut,
              icon: const Icon(Icons.logout_rounded, size: 19),
              label: const Text('Log Out', overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE5537A),
                textStyle: AppText.label.copyWith(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem(this.icon, this.label, this.onTap, {this.color = AppColors.ink});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}
