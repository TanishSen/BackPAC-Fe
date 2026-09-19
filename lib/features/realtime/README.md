# Realtime voice layer

The transport for a real call. It knows about LiveKit and HTTP and nothing about
the UI; `features/conversation/` turns what comes out of here into a chat, and
`features/chat/` draws it.

```
  chat_page.dart                 draws a Conversation, knows nothing else
        │
  conversation/
    conversation.dart            the interface between screen and engine
    live_conversation.dart       ── a real call  ─┐
    demo_conversation.dart       ── the offline scripted demo
        │                                        │
  realtime/                                      │
    backend_client.dart          POST /api/v1/sessions
    voice_session.dart           the LiveKit room  ◄┘
```

## The two files here

**`backend_client.dart`** — calls `BackPAC-BE POST /api/v1/sessions` and returns
the room URL and a token scoped to that one room. The app holds no secret of any
kind; this one call is how it gets permission to join.

**`voice_session.dart`** — joins that room, publishes the microphone, and
exposes what the call produces:

| member | what |
|---|---|
| `transcript` | live user/agent text fragments |
| `cards` | result cards the agent emits (train/flight/stay lists) |
| `state` | `connecting → live → ended / error` |
| `level` + `talker` | loudness 0..1 and who it belongs to — drives the orb |
| `sendUserText` | a typed turn, for the keyboard |
| `setMicEnabled` | mute without hanging up |

`level` is a `ValueNotifier`, not a stream, because it changes ~16 times a
second: the orb's painter listens to it and the page never rebuilds.

## Three things about the wire format

Get any of these wrong and it fails quietly rather than loudly.

**Agent text streams.** It arrives as many fragments with `speech_final: false`,
then one *empty* fragment with `speech_final: true` meaning "turn over". Append
the fragments into a single message. `LiveConversation` does this.

**Cards are wrapped.** Pipecat puts every server message in an RTVI envelope, so
the card is at `data`, not the top level:

```json
{"label":"rtvi-ai","type":"server-message",
 "data":{"type":"agent-card","cardType":"search_trains","payload":[…]}}
```

Checking `type == "agent-card"` on the outer object silently drops every card.

**Loudness needs polling.** LiveKit only fires an event when the *set* of active
speakers changes — far too coarse for an animation — so `audioLevel` is sampled
on a timer instead.

## Configuration

Nothing is hard-coded. See `lib/app/app_config.dart`:

```bash
flutter run                                              # live call, localhost
flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8000   # a real phone
flutter run --dart-define=LIVE_VOICE=false               # offline scripted demo
```

The default backend differs per platform: an Android emulator is its own VM, so
`localhost` there means the emulator, and `10.0.2.2` is the alias that reaches
your machine. On a real phone neither works — pass your LAN address.

## Permissions

Already declared: `RECORD_AUDIO` and friends in
`android/app/src/main/AndroidManifest.xml`, `NSMicrophoneUsageDescription` and
background audio in `ios/Runner/Info.plist`. Declaring them is only half of it —
the OS still asks the user, which happens the moment the app enables the mic, so
it happens with the call screen already open.

Plain HTTP to the dev backend is allowed for local hosts only
(`res/xml/network_security_config.xml` on Android, `NSAllowsLocalNetworking` on
iOS). Everything else stays HTTPS-only.

## Verifying without a phone

`cd BackPAC-Agent && make call` runs the same contract this file implements —
it joins a room, speaks, and checks the transcript and cards come back. If that
passes and the app still misbehaves, the bug is on this side of the wire.
