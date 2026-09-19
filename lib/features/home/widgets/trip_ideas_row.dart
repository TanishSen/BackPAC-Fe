import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../data/trip_data.dart';

/// Ready-made trips. Tapping one opens the conversation already pointed at it.
class TripIdeasRow extends StatelessWidget {
  const TripIdeasRow({super.key, required this.ideas, required this.onPick});

  final List<TripIdea> ideas;
  final ValueChanged<TripIdea> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageH),
        itemCount: ideas.length,
        clipBehavior: Clip.none,
        separatorBuilder: (BuildContext context, int i) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int i) =>
            _IdeaCard(idea: ideas[i], onTap: () => onPick(ideas[i])),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea, required this.onTap});

  final TripIdea idea;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${idea.place}, ${idea.subtitle}',
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 208,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Cover: a gradient with the place name over it. Real imagery
                // drops straight in here.
                Container(
                  height: 96,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: idea.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          idea.tag,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        idea.place,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Expanded, so a longer title or a larger text size eats into
                // the card's own space instead of overflowing it.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            idea.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cardTitle,
                          ),
                        ),
                        Text(idea.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption),
                      ],
                    ),
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
