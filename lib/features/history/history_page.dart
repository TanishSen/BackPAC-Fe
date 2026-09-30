import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_theme.dart';
import '../../app/transitions.dart';
import '../../app/widgets/round_icon_button.dart';
import '../../data/trip_data.dart';
import '../chat/chat_page.dart';
import 'data/history_client.dart';

/// Every conversation, with the filters, groups and per-trip actions the home
/// screen's short list has no room for. "View all" lands here, and so do the
/// profile's tiles — each with its own slice already chosen.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.client,
    this.initialFilter = HistoryFilter.all,
    this.title = 'History',
  });

  /// Injected by tests. Defaults to the real API.
  final HistoryClient? client;

  /// Which slice to open on — Saved from "Saved Trips", and so on.
  final HistoryFilter initialFilter;
  final String title;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  static const int _pageSize = 20;
  static const Color _danger = Color(0xFFC0392B);

  late final HistoryClient _client = widget.client ?? HistoryClient();
  late HistoryFilter _filter = widget.initialFilter;
  final ScrollController _scroll = ScrollController();

  List<SessionSummary> _rows = <SessionSummary>[];
  List<TripGroup> _groups = <TripGroup>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// Bumped on every fresh load, so an answer for a filter the user has since
  /// changed is dropped instead of painted over the one they are looking at.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    unawaited(_reload());
    unawaited(_reloadGroups());
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  // --- loading ----------------------------------------------------------------

  Future<void> _reload() async {
    final int gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SessionPage page =
          await _client.list(limit: _pageSize, filter: _filter);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = page.sessions;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on HistoryException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _maybeLoadMore() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.extentAfter > 480) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final int gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final SessionPage page = await _client.list(
        limit: _pageSize,
        offset: _rows.length,
        filter: _filter,
      );
      if (!mounted || gen != _generation) return;
      final Set<String> have = _rows.map((SessionSummary s) => s.id).toSet();
      setState(() {
        // Deduplicated: a conversation that moved up the list while we were
        // scrolling can otherwise appear on two pages.
        _rows = <SessionSummary>[
          ..._rows,
          ...page.sessions.where((SessionSummary s) => !have.contains(s.id)),
        ];
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on HistoryException catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(e.message);
    }
  }

  Future<void> _reloadGroups() async {
    try {
      final List<TripGroup> groups = await _client.groups();
      if (mounted) setState(() => _groups = groups);
    } on HistoryException {
      // The chips are an extra; the list itself reports real failures.
    }
  }

  void _setFilter(HistoryFilter next) {
    if (next == _filter) return;
    setState(() => _filter = next);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_reload());
  }

  // --- acting on one conversation ---------------------------------------------

  /// Show an edit at once; undo it if the server says no.
  Future<void> _edit(
    SessionSummary before,
    SessionSummary after,
    Future<void> Function() save,
  ) async {
    _replace(after);
    try {
      await save();
      unawaited(_reloadGroups()); // counts may have moved
    } on HistoryException catch (e) {
      if (!mounted) return;
      _replace(before, reinsert: true);
      _toast(e.message);
    }
  }

  /// Swap a row for its edited self — or take it out if the edit moved it
  /// out of the current slice.
  void _replace(SessionSummary s, {bool reinsert = false}) {
    setState(() {
      final int i = _rows.indexWhere((SessionSummary r) => r.id == s.id);
      if (!_filter.matches(s)) {
        if (i >= 0) _rows = List<SessionSummary>.of(_rows)..removeAt(i);
        return;
      }
      if (i >= 0) {
        _rows = List<SessionSummary>.of(_rows)..[i] = s;
      } else if (reinsert) {
        _rows = <SessionSummary>[..._rows, s]
          ..sort((SessionSummary a, SessionSummary b) =>
              b.createdAt.compareTo(a.createdAt));
      }
    });
  }

  Future<void> _open(SessionSummary s) async {
    await Navigator.of(context).push(
      SlideUpRoute<void>(
        page: ChatPage(
          title: s.title ?? 'Trip',
          resumeSessionId: s.id,
          initiallySaved: s.saved,
        ),
      ),
    );
    if (mounted) unawaited(_reload());
  }

  Future<void> _rename(SessionSummary s) async {
    final String? name = await _askForText(
      title: 'Rename',
      initial: s.title ?? '',
      hint: 'Trip name',
      maxLength: 200,
      action: 'Save',
    );
    if (name == null || name == s.title) return;
    await _edit(s, s.copyWith(title: name), () => _client.rename(s.id, name));
  }

  Future<void> _toggleFavourite(SessionSummary s) => _edit(
        s,
        s.copyWith(favourite: !s.favourite),
        () => _client.setFavourite(s.id, !s.favourite),
      );

  Future<void> _toggleCompleted(SessionSummary s) {
    final TripStatus next = s.status == TripStatus.completed
        ? TripStatus.planning
        : TripStatus.completed;
    return _edit(s, s.copyWith(status: next), () => _client.setStatus(s.id, next));
  }

  Future<void> _share(SessionSummary s, Rect? origin) async {
    try {
      final List<PastTurn> turns = await _client.transcript(s.id);
      await SharePlus.instance.share(ShareParams(
        subject: s.title ?? 'My trip plan',
        text: shareText(s.title ?? 'My trip plan', turns),
        sharePositionOrigin: origin,
      ));
    } on HistoryException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _chooseGroup(SessionSummary s) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => _GroupPicker(
        groups: _groups,
        current: s.groupId,
      ),
    );
    if (picked == null) return;

    String? target = picked == _GroupPicker.none ? null : picked;
    if (picked == _GroupPicker.create) {
      final TripGroup? made = await _createGroup();
      if (made == null) return;
      target = made.id;
    }
    if (target == s.groupId) return;
    await _edit(
      s,
      s.copyWith(groupId: () => target),
      () => _client.setGroup(s.id, target),
    );
  }

  Future<void> _delete(SessionSummary s) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this conversation?', style: AppText.section),
        content: const Text(
          'Everything said in it, and the results it found, will be gone. '
          'This cannot be undone.',
          style: AppText.body,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep it', style: AppText.label.copyWith(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: AppText.label.copyWith(color: _danger)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final List<SessionSummary> before = _rows;
    setState(() => _rows = _rows.where((SessionSummary r) => r.id != s.id).toList());
    try {
      await _client.delete(s.id);
      unawaited(_reloadGroups());
    } on HistoryException catch (e) {
      if (!mounted) return;
      setState(() => _rows = before);
      _toast(e.message);
    }
  }

  // --- groups -----------------------------------------------------------------

  Future<TripGroup?> _createGroup() async {
    final String? name = await _askForText(
      title: 'New group',
      hint: 'Mountains, Honeymoon, Weekend…',
      maxLength: 40,
      action: 'Create',
    );
    if (name == null) return null;
    try {
      final TripGroup g = await _client.createGroup(name);
      if (mounted) setState(() => _groups = <TripGroup>[..._groups, g]);
      return g;
    } on HistoryException catch (e) {
      _toast(e.message);
      return null;
    }
  }

  Future<void> _manageGroup(TripGroup g) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.ink),
              title: const Text('Rename group'),
              onTap: () => Navigator.of(sheet).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: _danger),
              title: const Text('Delete group', style: TextStyle(color: _danger)),
              subtitle: const Text('Its conversations stay in your history.'),
              onTap: () => Navigator.of(sheet).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'rename') {
      final String? name = await _askForText(
        title: 'Rename group',
        initial: g.name,
        maxLength: 40,
        action: 'Save',
      );
      if (name == null || name == g.name) return;
      try {
        await _client.renameGroup(g.id, name);
        unawaited(_reloadGroups());
      } on HistoryException catch (e) {
        _toast(e.message);
      }
    } else if (choice == 'delete') {
      try {
        await _client.deleteGroup(g.id);
        if (!mounted) return;
        setState(() {
          _groups = _groups.where((TripGroup x) => x.id != g.id).toList();
          _rows = <SessionSummary>[
            for (final SessionSummary r in _rows)
              r.groupId == g.id ? r.copyWith(groupId: () => null) : r,
          ];
        });
        if (_filter.groupId == g.id) _setFilter(HistoryFilter.all);
      } on HistoryException catch (e) {
        _toast(e.message);
      }
    }
  }

  Future<void> _openFilters() async {
    final HistoryFilter? next = await showModalBottomSheet<HistoryFilter>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext sheet) => _FilterSheet(filter: _filter),
    );
    if (next != null) _setFilter(next);
  }

  // --- small helpers ------------------------------------------------------------

  Future<String?> _askForText({
    required String title,
    required int maxLength,
    required String action,
    String initial = '',
    String? hint,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _TextPrompt(
        title: title,
        initial: initial,
        hint: hint,
        maxLength: maxLength,
        action: action,
      ),
    );
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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: MediaQuery(
        data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
        child: DecoratedBox(
          // Light at the top, lavender at the foot — the design's wash.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[AppColors.canvas, AppColors.brandWash, Color(0xFFD6CDF0)],
              stops: <double>[0, 0.55, 1],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 8, AppSpacing.pageH, 0),
                  child: Row(
                    children: <Widget>[
                      RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.pageH - 8, top: 4),
                    child: TextButton(
                      onPressed: () => unawaited(_createGroup()),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Create group +',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                _filterRow(),
                const SizedBox(height: 6),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterRow() {
    final int extra = (_filter.mode != null ? 1 : 0) + (_filter.status != null ? 1 : 0);
    bool only({bool saved = false, bool favourite = false, String? group}) =>
        _filter.saved == saved &&
        _filter.favourite == favourite &&
        _filter.groupId == group;
    HistoryFilter keep({bool saved = false, bool favourite = false, String? group}) =>
        HistoryFilter(
          saved: saved,
          favourite: favourite,
          groupId: group,
          status: _filter.status,
          mode: _filter.mode,
        );

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH - 6),
        children: <Widget>[
          // Tight rather than a TextButton: its minimum width pushed the
          // Favourites chip off a 390pt screen.
          InkWell(
            onTap: _openFilters,
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    extra == 0 ? 'Filters' : 'Filters · $extra',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.ink),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _Chip(label: 'All', selected: only(), onTap: () => _setFilter(keep())),
          _Chip(
            label: 'Saved',
            selected: only(saved: true),
            onTap: () => _setFilter(keep(saved: true)),
          ),
          _Chip(
            label: 'Favourites',
            selected: only(favourite: true),
            onTap: () => _setFilter(keep(favourite: true)),
          ),
          for (final TripGroup g in _groups)
            _Chip(
              label: g.name,
              selected: only(group: g.id),
              onTap: () => _setFilter(keep(group: g.id)),
              onLongPress: () => _manageGroup(g),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && _rows.isEmpty) {
      return _Notice(
        icon: Icons.cloud_off_rounded,
        text: _error!,
        action: 'Try again',
        onAction: _reload,
      );
    }
    if (_loading && _rows.isEmpty) return const _Skeleton();

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () async {
        await Future.wait(<Future<void>>[_reload(), _reloadGroups()]);
      },
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[_Notice(icon: Icons.luggage_outlined, text: _emptyText())],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageH,
                6,
                AppSpacing.pageH,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: _rows.length + (_hasMore ? 1 : 0),
              itemBuilder: (BuildContext _, int i) {
                if (i >= _rows.length) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand),
                      ),
                    ),
                  );
                }
                final SessionSummary s = _rows[i];
                return _ConversationTile(
                  key: ValueKey<String>(s.id),
                  entry: s,
                  groupName: _groupName(s.groupId),
                  onTap: () => _open(s),
                  onAction: (_TileAction a, Rect? origin) {
                    switch (a) {
                      case _TileAction.rename:
                        unawaited(_rename(s));
                      case _TileAction.favourite:
                        unawaited(_toggleFavourite(s));
                      case _TileAction.share:
                        unawaited(_share(s, origin));
                      case _TileAction.group:
                        unawaited(_chooseGroup(s));
                      case _TileAction.completed:
                        unawaited(_toggleCompleted(s));
                      case _TileAction.delete:
                        unawaited(_delete(s));
                    }
                  },
                );
              },
            ),
    );
  }

  String? _groupName(String? id) {
    if (id == null) return null;
    for (final TripGroup g in _groups) {
      if (g.id == id) return g.name;
    }
    return null;
  }

  String _emptyText() {
    if (_filter.isAll) {
      return 'Your conversations will show up here once you have had one.';
    }
    if (_filter.favourite) return 'Tap ⋮ on a conversation and choose Favourite to keep it here.';
    if (_filter.saved) return 'Tap the bookmark in a conversation to keep it here.';
    if (_filter.groupId != null) return 'Nothing in this group yet. Use ⋮ → Add to group.';
    if (_filter.status == TripStatus.completed) {
      return 'Trips you mark as completed will show up here.';
    }
    return 'Nothing matches these filters.';
  }
}

/// What someone sees when they share a conversation: the plan, readably.
///
/// Plain text on purpose — it goes into WhatsApp as often as email — and
/// capped, because a forty-turn transcript is not something anyone forwards.
String shareText(String title, List<PastTurn> turns) {
  const int maxChars = 3000;
  final StringBuffer out = StringBuffer('$title\n\n');
  for (final PastTurn t in turns) {
    final String line = '${t.isAgent ? 'backPAC' : 'Me'}: ${t.content.trim()}\n';
    if (out.length + line.length > maxChars) {
      out.write('…\n');
      break;
    }
    out.write(line);
  }
  out.write('\nPlanned with backPAC');
  return out.toString();
}

enum _TileAction { rename, favourite, share, group, completed, delete }

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onAction,
    this.groupName,
  });

  final SessionSummary entry;
  final String? groupName;
  final VoidCallback onTap;
  final void Function(_TileAction action, Rect? origin) onAction;

  @override
  Widget build(BuildContext context) {
    final String title = entry.title ?? 'Untitled conversation';
    final String preview = entry.preview ?? 'Nothing said yet';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandSoft, width: 2),
                  ),
                  child: Text(
                    tripEmoji(title, preview, entry.mode),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.cardTitle,
                            ),
                          ),
                          if (entry.favourite) ...<Widget>[
                            const SizedBox(width: 6),
                            const Icon(Icons.favorite_rounded, size: 13, color: Color(0xFFE5537A)),
                          ],
                          if (entry.saved) ...<Widget>[
                            const SizedBox(width: 4),
                            const Icon(Icons.bookmark_rounded, size: 13, color: AppColors.brand),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(fontSize: 12, height: 1.35),
                      ),
                      if (groupName != null || entry.status == TripStatus.completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            children: <Widget>[
                              if (entry.status == TripStatus.completed)
                                const _Tag(label: 'Completed', icon: Icons.verified_rounded),
                              if (groupName != null)
                                _Tag(label: groupName!, icon: Icons.folder_rounded),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Builder(
                  builder: (BuildContext anchor) => IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
                    onPressed: () => _menu(anchor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The design's lavender menu of white pills, opened beside the ⋮.
  Future<void> _menu(BuildContext anchor) async {
    final RenderBox box = anchor.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final Rect origin = topLeft & box.size;

    final _TileAction? picked = await showMenu<_TileAction>(
      context: anchor,
      position: RelativeRect.fromRect(origin, Offset.zero & overlay.size),
      color: AppColors.brandLine,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: <PopupMenuEntry<_TileAction>>[
        _pill(_TileAction.rename, 'Rename'),
        _pill(_TileAction.favourite, entry.favourite ? 'Unfavourite' : 'Favourite'),
        _pill(_TileAction.share, 'Share'),
        _pill(_TileAction.group, entry.groupId == null ? 'Add to group' : 'Move group'),
        _pill(
          _TileAction.completed,
          entry.status == TripStatus.completed ? 'Mark as planning' : 'Mark as completed',
        ),
        _pill(_TileAction.delete, 'Delete', danger: true),
      ],
    );
    if (picked != null) onAction(picked, origin);
  }

  static PopupMenuItem<_TileAction> _pill(
    _TileAction value,
    String label, {
    bool danger = false,
  }) {
    return PopupMenuItem<_TileAction>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Container(
        width: 150,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: danger ? const Color(0xFFC0392B) : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.brandWash,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 11, color: AppColors.brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.brand : const Color(0xFFC9BDF3),
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 24),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 34, color: AppColors.brandSoft),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: AppText.body),
          if (action != null && onAction != null) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: AppColors.brand),
              child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tile-shaped placeholders while the first page loads — the list has a known
/// shape, so drawing it greyed out beats a spinner.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 6, AppSpacing.pageH, 0),
      children: <Widget>[
        for (int i = 0; i < 6; i++)
          Opacity(
            opacity: 1 - i * 0.13,
            child: Container(
              height: 76,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: AppColors.canvas, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(height: 11, width: 150, color: AppColors.canvas),
                        const SizedBox(height: 8),
                        Container(height: 9, color: AppColors.canvas),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Add to group": the user's groups, "no group", and "new group".
class _GroupPicker extends StatelessWidget {
  const _GroupPicker({required this.groups, required this.current});

  static const String none = '__none__';
  static const String create = '__create__';

  final List<TripGroup> groups;
  final String? current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Add to group', style: AppText.section),
            ),
            for (final TripGroup g in groups)
              ListTile(
                leading: Icon(
                  g.id == current ? Icons.check_circle_rounded : Icons.folder_outlined,
                  color: g.id == current ? AppColors.brand : AppColors.inkSoft,
                ),
                title: Text(g.name),
                trailing: Text('${g.count}', style: AppText.caption),
                onTap: () => Navigator.of(context).pop(g.id),
              ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined, color: AppColors.inkSoft),
                title: const Text('Remove from group'),
                onTap: () => Navigator.of(context).pop(none),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined, color: AppColors.brand),
              title: const Text('New group…', style: TextStyle(color: AppColors.brand)),
              onTap: () => Navigator.of(context).pop(create),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// "Filters ⌄": how they travelled, and where the trip stands.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.filter});

  final HistoryFilter filter;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TravelMode? _mode = widget.filter.mode;
  late TripStatus? _status = widget.filter.status;

  // Bus is left out: no search produces a bus trip yet, so it would always
  // come back empty.
  static const List<TravelMode> _modes = <TravelMode>[
    TravelMode.trains,
    TravelMode.flights,
    TravelMode.hotels,
  ];

  static String _statusLabel(TripStatus s) => switch (s) {
        TripStatus.planning => 'Planning',
        TripStatus.completed => 'Completed',
        TripStatus.archived => 'Archived',
      };

  @override
  Widget build(BuildContext context) {
    Widget choice(String label, bool on, VoidCallback tap) => ChoiceChip(
          label: Text(label),
          selected: on,
          onSelected: (_) => tap(),
          selectedColor: AppColors.brand,
          backgroundColor: AppColors.brandWash,
          side: BorderSide.none,
          showCheckmark: false,
          labelStyle: AppText.label.copyWith(
            color: on ? Colors.white : AppColors.brand,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Travel mode', style: AppText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                choice('Any', _mode == null, () => setState(() => _mode = null)),
                for (final TravelMode m in _modes)
                  choice(m.label, _mode == m, () => setState(() => _mode = m)),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Trip status', style: AppText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                choice('Any', _status == null, () => setState(() => _status = null)),
                for (final TripStatus s in TripStatus.values)
                  choice(_statusLabel(s), _status == s, () => setState(() => _status = s)),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    widget.filter.refine(),
                  ),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
                  onPressed: () => Navigator.of(context).pop(
                    widget.filter.refine(mode: _mode, status: _status),
                  ),
                  child: const Text('Show results'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-field dialog: rename a trip, name a group.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.maxLength,
    required this.action,
    this.hint,
  });

  final String title;
  final String initial;
  final String? hint;
  final int maxLength;
  final String action;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _text.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title, style: AppText.section),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppText.label.copyWith(color: AppColors.muted)),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (BuildContext _, TextEditingValue v, Widget? _) => TextButton(
            onPressed: v.text.trim().isEmpty ? null : _submit,
            child: Text(widget.action),
          ),
        ),
      ],
    );
  }
}
