import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/trip_data.dart';

/// Past conversations, filtered by how the trip was travelled.
class HistorySection extends StatefulWidget {
  const HistorySection({
    super.key,
    required this.entries,
    required this.onOpen,
    required this.onViewAll,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onDelete,
  });

  final List<TripHistoryEntry> entries;
  final ValueChanged<TripHistoryEntry> onOpen;
  final VoidCallback onViewAll;

  /// True while the first load is in flight. Shows placeholder tiles rather
  /// than a spinner: the list has a known shape, so drawing that shape greyed
  /// out tells you what is coming and stops the page jumping when it lands.
  final bool loading;

  /// Set when the load failed. Shown in place of the list, with a retry.
  final String? error;
  final VoidCallback? onRetry;

  /// Remove a conversation. Null hides the swipe action.
  final ValueChanged<TripHistoryEntry>? onDelete;

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  /// null = All
  TravelMode? _filter;

  /// Whether the list is narrowed to bookmarked conversations.
  ///
  /// A separate flag rather than another value of [_filter], because saving is
  /// a different axis from how you travelled: "saved flights" is a sensible
  /// thing to want, and one enum could not express it.
  bool _savedOnly = false;

  @override
  Widget build(BuildContext context) {
    // A null mode matches no chip but always shows under All, which is the
    // honest place for a conversation that never settled on a kind.
    final List<TripHistoryEntry> shown = widget.entries
        .where((TripHistoryEntry e) => _filter == null || e.mode == _filter)
        .where((TripHistoryEntry e) => !_savedOnly || e.saved)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text('History',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.section),
              ),
              TextButton(
                onPressed: widget.onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View all',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
            children: <Widget>[
              _FilterChip(
                label: 'All',
                selected: _filter == null && !_savedOnly,
                onTap: () => setState(() {
                  _filter = null;
                  _savedOnly = false;
                }),
              ),
              const SizedBox(width: 8),
              // First after All, and marked with the same bookmark as the
              // button that fills it, so the two read as the same idea.
              _FilterChip(
                label: 'Saved',
                icon: Icons.bookmark_rounded,
                selected: _savedOnly,
                onTap: () => setState(() => _savedOnly = !_savedOnly),
              ),
              for (final TravelMode m in TravelMode.values) ...<Widget>[
                const SizedBox(width: 8),
                _FilterChip(
                  label: m.label,
                  selected: _filter == m,
                  onTap: () => setState(() => _filter = m),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _body(shown),
        ),
      ],
    );
  }

  /// Whichever of the four things is true right now.
  Widget _body(List<TripHistoryEntry> shown) {
    if (widget.error != null) return _Message.error(widget.error!, widget.onRetry);

    // Placeholders only on a genuinely empty first load. Once there are rows,
    // a refresh leaves them on screen — replacing a list you were reading with
    // grey boxes is a worse answer than letting it be a second out of date.
    if (widget.loading && widget.entries.isEmpty) return const _Skeleton();

    if (shown.isEmpty) {
      return _Message.empty(
        // Several different nothings, and conflating them is how an app tells
        // a brand-new user their history is broken.
        switch ((widget.entries.isEmpty, _savedOnly, _filter)) {
          (true, _, _) =>
            'Your conversations will show up here once you have had one.',
          (_, true, final TravelMode m?) =>
            'You have not saved any ${m.label.toLowerCase()} conversations.',
          (_, true, null) =>
            'Tap the bookmark in a conversation to keep it here.',
          (_, false, final TravelMode m?) =>
            'No ${m.label.toLowerCase()} conversations yet.',
          _ => 'Nothing here yet.',
        },
      );
    }

    return Column(
      children: <Widget>[
        for (final TripHistoryEntry e in shown)
          _HistoryTile(
            key: ValueKey<String>(e.id ?? '${e.title}${e.when}'),
            entry: e,
            onTap: () => widget.onOpen(e),
            onDelete: e.id == null || widget.onDelete == null
                ? null
                : () => widget.onDelete!(e),
          ),
      ],
    );
  }
}

/// A line of explanation where the list would be.
class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry, this.bad = false});

  factory _Message.empty(String text) => _Message(text);
  factory _Message.error(String text, VoidCallback? onRetry) =>
      _Message(text, onRetry: onRetry, bad: true);

  final String text;
  final VoidCallback? onRetry;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 16, AppSpacing.pageH, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (bad) ...<Widget>[
            const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text, style: AppText.body)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

/// Three tile-shaped placeholders while the first page loads.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 6, AppSpacing.pageH, 0),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  _bar(40, 40, radius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _bar(double.infinity, 11),
                        const SizedBox(height: 8),
                        _bar(180, 10),
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

  /// Fades down the list, so it reads as "more below" rather than three
  /// identical grey slabs.
  static Widget _bar(double w, double h, {double radius = 6}) => Opacity(
        opacity: 0.55,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Optional glyph before the label. Only "Saved" uses one — it is the odd
  /// chip out, so it should look like it.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: icon == null ? 18 : 15,
                vertical: 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: 15,
                      color: selected ? Colors.white : AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: selected ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onDelete,
  });

  final TripHistoryEntry entry;
  final VoidCallback onTap;

  /// Null when this entry cannot be deleted — the sample rows, which are not
  /// real conversations.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final Widget tile = _tile(context);
    if (onDelete == null) return tile;

    return Dismissible(
      key: ValueKey<String>('dismiss-${entry.id}'),
      direction: DismissDirection.endToStart,
      // Deleting a conversation erases its transcript for good, so it asks
      // first. An undo snackbar is the friendlier pattern for reversible
      // things; this is not one.
      confirmDismiss: (DismissDirection _) => _confirm(context),
      onDismissed: (DismissDirection _) => onDelete!(),
      background: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 6, AppSpacing.pageH, 0),
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFC0392B), size: 22),
        ),
      ),
      child: tile,
    );
  }

  Future<bool> _confirm(BuildContext context) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        title: Text('Delete this conversation?', style: AppText.section),
        content: Text(
          'Everything said in it, and the results it found, will be gone. '
          'This cannot be undone.',
          style: AppText.body,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep it',
                style: AppText.label.copyWith(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppText.label.copyWith(color: const Color(0xFFC0392B))),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  Widget _tile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pageH, 6, AppSpacing.pageH, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                // A conversation that never reached a result has no mode, so
                // it gets the neutral chat glyph rather than a made-up one.
                Builder(builder: (BuildContext _) {
                  final TravelMode? m = entry.mode;
                  final Color tint = m?.tint ?? AppColors.brand;
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      m?.icon ?? Icons.chat_bubble_outline_rounded,
                      size: 19,
                      color: tint,
                    ),
                  );
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.cardTitle),
                          ),
                          const SizedBox(width: 8),
                          // A small mark rather than a whole badge: it only
                          // needs to answer "is this one of mine?" at a glance
                          // while scanning, and the Saved chip is there for
                          // when someone wants only those.
                          if (entry.saved) ...<Widget>[
                            const Icon(Icons.bookmark_rounded,
                                size: 13, color: AppColors.brand),
                            const SizedBox(width: 6),
                          ],
                          Text(entry.when, style: AppText.caption),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
