import 'package:flutter/material.dart';

import '../features/welcome/welcome_page.dart';
import 'app_theme.dart';

class backPACApp extends StatelessWidget {
  const backPACApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'backPAC',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const WelcomePage(),
    );
  }
}
