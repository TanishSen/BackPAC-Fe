import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sign-in, before the first frame. Supabase restores a saved session from
  // disk here, which is what makes someone who signed in last week land on the
  // home screen rather than the login form. Awaited on purpose: deciding which
  // screen to show needs the answer, and a frame of the wrong screen followed
  // by a jump is worse than a few milliseconds of nothing.
  //
  // Both values are public — see AppConfig. The keys that are not public are
  // not in this app and never will be.
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
    );
  } catch (e) {
    // A failure here means no sign-in, not no app. The welcome screen and the
    // orb work regardless, and the login form will say what is wrong when
    // someone tries to use it.
    debugPrint('[backPAC] Supabase init failed: $e');
  }

  // Let the app's sounds coexist instead of evicting each other.
  //
  // By default every AudioPlayer asks Android for AUDIOFOCUS_GAIN — "I am now
  // the only thing playing". With two players (the orb's plink and the orb's
  // voice) the second request takes focus from the first, and audioplayers
  // responds to losing focus by stopping that player. On a phone the result
  // was the plink playing and the voice never being heard at all.
  //
  // These are short UI sounds, not media playback: they should request no
  // exclusive focus, which is what mixWithOthers means here
  // (AndroidAudioFocus.none on Android, mixWithOthers on iOS). It also keeps
  // them from interrupting the LiveKit call audio.
  unawaited(AudioPlayer.global.setAudioContext(
    AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
  ));

  // The page is designed portrait, and its light canvas wants dark status-bar
  // icons on both platforms.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFF4F4F6),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const backPACApp());
}
