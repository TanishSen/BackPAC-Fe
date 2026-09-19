import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// "Hi, Jasmin" and the bell.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.name, required this.onBell});

  final String name;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Hi, $name', style: AppText.title),
              const SizedBox(height: 4),
              const Text('Where are we going today?', style: AppText.body),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          label: 'Notifications, 1 unread',
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onBell,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    const Icon(Icons.notifications_none_rounded,
                        size: 23, color: AppColors.ink),
                    Positioned(
                      top: 13,
                      right: 14,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
