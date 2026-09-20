import 'package:flutter/material.dart';

import '../features/welcome/welcome_page.dart';
import 'app_theme.dart';

/// Tells a screen when it has been covered by another, and when it is back.
///
/// The welcome screen needs this because it talks on its own. Pushing another
/// route does not dispose it — it stays alive underneath with its timers
/// running — so it has to be told to be quiet, and told again when it is back
/// on top.
///
/// Watching the pushed route's future is not good enough, and that is not a
/// theoretical point: that future completes when the route is *replaced* as
/// well as when it is popped. Signing in replaces the login screen with the
/// home screen, which completed the future, which woke the welcome screen up
/// — and it spent the rest of the session chatting to itself from underneath
/// whatever you were actually looking at.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class backPACApp extends StatelessWidget {
  const backPACApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'backPAC',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: <NavigatorObserver>[routeObserver],
      home: const WelcomePage(),
    );
  }
}
