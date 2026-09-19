# BackPAC

# backPAC

Conversational trip planner. Tell it where you want to go — by typing or by
talking — and it plans the trip with you. The assistant has a face: an orb
drawn and animated entirely in code, not played back from a video or a sprite
sheet.

Three screens so far: the welcome page, the home screen, and the conversation.

## Run it

```bash
flutter pub get
flutter run            # attached device or simulator
flutter run -d chrome  # web
```

## Layout

```
lib/
  main.dart                       app entry: orientation, system UI, runApp
  app/
    app.dart                      MaterialApp
    app_theme.dart                every colour, text style, spacing and duration
  data/
    trip_data.dart                travel modes, trip ideas, history — all the seed content
  features/
    voice/                        the mic, the bloom, and the speech-to-text seam
    welcome/                      the opening screen with the talking orb
    home/
      home_page.dart              greeting, pro card, modes, trip ideas, history
      widgets/                    each section, plus the bottom bar with the mic
    chat/
      chat_page.dart              the conversation
      chat_controller.dart        messages, typing, recording — the only state the UI reads
      data/agent_service.dart     the seam: who answers. Ships a ScriptedAgent
      model/chat_message.dart     message + voice note
      widgets/                    bubbles, voice note player, composer, waveforms
  orb/                            the animated assistant (see orb/README.md)
```

Every route out of the home screen ends in the same place — a conversation. A
travel mode, a trip idea, a history entry, the message field and the mic all
open `ChatPage` with a different opening line.

## Voice

The bottom of both screens is one control: the mic, floating on a bloom of
colour that reacts to whoever is talking.

| State | What you see |
|---|---|
| Idle | A calm bloom, one quiet ring, the mic glyph, and a slow wave leaving the button every few seconds so it never looks dead. |
| Listening | The glyph becomes a small waveform inside the circle, quick and uneven, sized by live loudness — and the words appear above the mic as they are recognised. |
| Thinking | The same waveform, low and even, barely moving. |
| Speaking | The waveform again, but slower and more regular — a different rhythm, so you always know who has the floor. Tap to interrupt. |

The button is filled with the orb's own colour field — `OrbPainter` with
`showFace: false`, clipped to a circle — so the mic and the assistant can never
drift out of step on colour. A standing highlight and a band of light that
sweeps across every four seconds give it its gloss.

Two things move: the waveform inside the circle, and waves rolling outwards from
its rim — three thin rings at most, fading on a curve so each one spends its
last stretch almost invisible. They quicken and widen with the voice. A ring of
bars around the rim was tried first and read as clutter, so the waves carry the
energy on their own.

Tapping the mic on the home screen slides the conversation up over the page
(`SlideUpRoute`) and opens the mic once it has landed, so the first thing you
see is the mic arriving rather than a screen already listening.

### Speech-to-text

`SpeechService` (lib/features/voice/speech_service.dart) is the seam. The app
ships `SimulatedSpeechService`, which types out a plausible request word by word
with a loudness trace to match, so the whole flow runs with no permissions and
no packages. A real recogniser implements three methods:

```dart
class RealSpeech implements SpeechService {
  Stream<SpeechEvent> get events;   // PartialTranscript | FinalTranscript | SpeechAmplitude
  Future<bool> start();
  Future<String?> stop();
  void dispose();
}

ChatPage(speech: RealSpeech())
```

Feed it `SpeechAmplitude` events and every animation on the screen follows — the
bloom, the rings and the bars all read the same 0..1 level. Nothing else
changes.

`VoiceController` owns the session and keeps that level in its own
`ValueNotifier`, deliberately separate from the state the page rebuilds on: it
changes about sixteen times a second and must only repaint the painters that
care.

Speech is an input method, not a kind of message: the transcript goes into the
thread as ordinary text and reaches the agent as text. There is no recording to
play back, and nothing downstream can tell whether a message was spoken or
typed.

## Wiring it to a real backend

`AgentService` is the only thing standing between the chat and a server:

```dart
class MyAgent implements AgentService {
  @override
  Duration get thinkingTime => const Duration(milliseconds: 250);

  @override
  Future<AgentReply> respondTo(String prompt, List<ChatMessage> history) async {
    // call your API, return the text and any suggested replies
  }
}

ChatPage(agent: MyAgent())
```

Nothing in the widgets knows the difference. The same goes for voice: the
composer already produces a clip with a duration and bar levels, so a real
recorder replaces `ChatController.stopListening` and nothing else.

## Tests

```bash
flutter test           # widget + layout tests
flutter analyze        # clean
```

Two files in `test/` are tools rather than tests, so they are deliberately not
named `*_test.dart` and do not run with the suite:

```bash
flutter test test/capture_welcome.dart      # renders the welcome page to shots/welcome.png
flutter test test/generate_app_icons.dart   # regenerates every launcher icon from the orb
flutter test test/capture_antics.dart       # one still per antic and mouth shape
flutter test test/capture_playtime.dart     # 20 s of the orb amusing itself, frame by frame
```

## Design notes

- The palette lives in `app_theme.dart`; the orb's own colours in
  `orb/orb_palette.dart`.
- Type is Poppins, per the branding sheet, bundled in `assets/fonts` in four
  weights (400/500/600/700). It is an SIL Open Font License face and the licence
  text sits beside the files; nothing is fetched at runtime. The family name
  appears exactly once, in `AppText._family`.
- The little icon tiles are `StickerIcon`: a rounded square with a lighter one
  tipped behind its top-right corner, which is what gives them their depth.
- System text scaling is honoured but capped at 1.25 on the welcome screen; past
  that the headline would collide with the orb. The page scrolls rather than
  overflowing on short screens.
- Launcher icons are generated from the orb (see the tool above), so the icon
  and the in-app assistant can never drift apart.

## Before shipping

- Bundle identifier is `com.rezolve.backPAC` (set at scaffold time) — change
  it in `android/app/build.gradle.kts` and Xcode if that is not the final one.
- Signing configs for both platforms are still the debug defaults.
