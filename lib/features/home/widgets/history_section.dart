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
  });

  final List<TripHistoryEntry> entries;
  final ValueChanged<TripHistoryEntry> onOpen;
  final VoidCallback onViewAll;

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  /// null = All
  TravelMode? _filter;

  @override
  Widget build(BuildContext context) {
    final List<TripHistoryEntry> shown = _filter == null
        ? widget.entries
        : widget.entries
            .where((TripHistoryEntry e) => e.mode == _filter)
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
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
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
          child: shown.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.pageH, 18, AppSpacing.pageH, 8),
                  child: Text('Nothing here yet.', style: AppText.body),
                )
              : Column(
                  children: <Widget>[
                    for (final TripHistoryEntry e in shown)
                      _HistoryTile(entry: e, onTap: () => widget.onOpen(e)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: selected ? Colors.white : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final TripHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: entry.mode.tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(entry.mode.icon, size: 19, color: entry.mode.tint),
                ),
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
