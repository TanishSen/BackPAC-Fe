import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/trip_data.dart';
import 'sticker_icon.dart';

/// Trains, flights, bus, hotels — the four ways into a conversation.
class TravelModes extends StatelessWidget {
  const TravelModes({super.key, required this.onPick});

  final ValueChanged<TravelMode> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        itemCount: TravelMode.values.length,
        clipBehavior: Clip.none,
        separatorBuilder: (BuildContext context, int i) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int i) {
          final TravelMode mode = TravelMode.values[i];
          return _ModeCard(mode: mode, onTap: () => onPick(mode));
        },
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.onTap});

  final TravelMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: mode.label,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Container(
            width: 138,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                StickerIcon(icon: mode.icon, tint: mode.tint),
                Text(mode.label, style: AppText.cardTitle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
