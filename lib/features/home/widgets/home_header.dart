import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/widgets/round_icon_button.dart';

/// "Hi, Jasmin", and the way to your profile.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.name, required this.onProfile});

  final String name;

  /// Opens the profile — history, journey, plan, sign out.
  final VoidCallback onProfile;

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
        RoundIconButton(
          icon: Icons.person_outline_rounded,
          tooltip: 'Profile',
          size: 48,
          onTap: onProfile,
        ),
      ],
    );
  }
}
