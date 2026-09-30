# BackPAC — how the three pieces talk to each other

Read this once before changing anything. It's the map; the per-repo guides
(`BackPAC-BE/API_GUIDE.md`, `BackPAC-Agent/AGENT_GUIDE.md`) are the detail.

## The shape

```
  ┌────────────┐   1. POST /api/v1/sessions        ┌────────────┐
  │            │ ────────────────────────────────► │            │
  │ BackPAC-FE │                                    │ BackPAC-BE │
  │  (Flutter) │   4. { livekit url + token }       │  (FastAPI) │
  │            │ ◄──────────────────────────────── │            │
  └─────┬──────┘                                    └─────┬──────┘
        │                                                 │ 2. mint room + token
        │                                                 │ 3. POST /start
        │                                                 ▼
        │  5. join the LiveKit room            ┌─────────────────┐
        └────────────── live voice ──────────►│  BackPAC-Agent  │
                                               │ (Pipecat+Claude)│
             agent text + cards over           │                 │
             the data channel  ◄───────────── │  6. tools call ─┼──► BackPAC-BE
             typed turns ───────────────────► │                 │    /trips/search/*
                                               └─────────────────┘
```

1. The app calls **BE** `POST /api/v1/sessions` with an `agentId`.
2. BE mints a **LiveKit room** and a **room-scoped token**.
3. BE calls **Agent** `POST /start` → the agent joins that room.
4. BE returns `{ livekit: { url, token, roomName } }` to the app.
5. The app joins the room with that token (`livekit_client`). Now audio flows:
   the phone's mic → the agent's STT; the agent's ElevenLabs voice → the phone.
6. While talking, the agent's tools call **BE** `/api/v1/trips/search/*` for
   train/flight/stay data. The agent pushes the **transcript** and **result
   cards** back to the app over the LiveKit **data channel**, and accepts
   **typed turns** back over the same channel.

**The phone only ever talks to BE.** It never sees the Anthropic, ElevenLabs or
LiveKit *secret* — only a short-lived token scoped to one room.

## The contracts (don't let these drift)

**Session start** — `POST /api/v1/sessions` → `SessionEnvelope`
(BE `domains/sessions/schemas.py`, FE `realtime/backend_client.dart`).

**What the orb says** — `GET /api/v1/voice/{greeting,welcome-lines,line.wav}`
(BE `domains/voice/`, Agent `src/bot/voice/greeting.py`, FE
`features/welcome/data/`). Not a call: cached audio files plus a level track for
the orb, so the welcome screen needs no room, session or mic permission. The
JSON carries text and levels; the audio is a separate cacheable file, because
inlining it as base64 made the set a 2.5 MB body no cache could reuse.

**Trip search** — `POST /api/v1/trips/search/{trains,flights,stays}`
(BE `domains/trips/schemas.py`, Agent `core/tools.py`). Same shape on both
sides; change a field in one, change it in the other.

**Service auth, both directions** — one shared secret, `SERVICE_TOKEN` in BE
and `BACKEND_SERVICE_TOKEN` in the agent, sent as `X-Service-Token`:

| caller → callee | routes |
|---|---|
| BE → Agent | every agent route except `GET /` (`/start`, `/stop`, `/sessions`, `/greeting`, `/welcome-lines`, `/voice-line.wav`) |
| Agent → BE | `/api/v1/trips/search/*`, `/api/v1/sessions/internal/*` |

Mismatched or missing, and every call fails: BE gets 401 from `/start` and
reports "Could not start the voice agent"; the agent's searches come back as
"The search service is unavailable". The agent refuses to boot without it.

**Stored cards** — the agent writes each card it shows to
`/sessions/internal/trip-results` as `{tool, query, result}`. `query` is the
search's own arguments (`destination`, dates…); the profile's "Places" count is
the distinct `query.destination` values, so keep that field name.

The agent only ever speaks its own fixed welcome lines: `/voice-line.wav` and
`/greeting` 404 on any other `text`, so the public `/api/v1/voice/*` routes are
not a free text-to-speech API.

**Data channel** — agent ⇄ app
(Agent `word_interceptor.py` / `card_dispatcher.py` / `infrastructure/text_input.py`,
FE `realtime/voice_session.dart`):

| direction | topic | payload |
|---|---|---|
| agent → app | `transcription` | `{"role":"user"\|"agent","text":"…","speech_final":bool}` |
| agent → app | *(default)* | `{"label":"rtvi-ai","type":"server-message","data":{"type":"agent-card","cardType":"search_trains","payload":[…]}}` |
| app → agent | `user-text` | `{"type":"user-text","text":"…"}` |

Two things about that table are easy to get wrong and were both bugs once:

- **Cards are wrapped.** Pipecat puts every server message inside an RTVI
  envelope, so the useful object is at `data`, not at the top level. Checking
  `type == "agent-card"` on the outer object silently drops every card.
- **Agent text streams.** It arrives as many fragments with
  `speech_final: false`, then one *empty* fragment with `speech_final: true`
  meaning "turn over". Append the fragments into one message; don't add a
  message per fragment.

## Bring it up locally, in order

1. **LiveKit** — one project at livekit.io. The same
   `LIVEKIT_URL` / `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` must be in **both**
   `BackPAC-BE/.env` and `BackPAC-Agent/.env`. Different projects means the
   room the BE mints is invisible to the agent, and the call connects to nobody.

2. **BE** — needs no database to run a call:
   ```bash
   cd BackPAC-BE && .venv/bin/python -m uvicorn app.main:app --port 8000
   curl localhost:8000/readyz     # livekit_configured + database_ready
   ```
   `DATABASE_URL` defaults to SQLite, so it just works. Point it at Postgres for
   anything shared. If the database is unreachable the API still starts — only
   the saved-trip routes 503, because nothing else touches a table.

3. **Agent** — `cd BackPAC-Agent && make run`. It refuses to start with a clear
   message if a required key is missing, rather than failing mid-call.

4. **Prove it works without a phone:**
   ```bash
   cd BackPAC-Agent
   make brain      # talk to the brain in the terminal — no voice at all
   make call       # a real LiveKit call: synthesised speech in, agent voice out
   ```
   `make call` is the acceptance test. It exits non-zero unless the agent
   transcribed the speech, answered, and spoke back.

5. **FE** — `cd BackPAC-FE && flutter run`. On a real phone the default
   `localhost` is wrong; pass your machine's address:
   ```bash
   flutter run --dart-define=BACKEND_URL=http://192.168.1.20:8000
   flutter run --dart-define=LIVE_VOICE=false      # offline scripted demo
   ```

## What is verified, and how

Everything below was exercised against the live services, not just compiled:

- **BE** — boots, all 12 routes, search returns data, a saved trip round-trips
  through SQLite, `/readyz` reports what is configured.
- **Brain** — routes to the right specialist, calls the real backend, resolves
  "the 2nd of October" to a real date, remembers across turns (`make brain`).
- **Full voice loop** — synthesised speech → Azure STT → Claude → tool call →
  ElevenLabs → audio back, with the transcript and a result card on the data
  channel (`make call`, exit 0).
- **Typed turns** — `make call --type` drives the same loop through the
  keyboard path.
- **FE** — `flutter analyze` clean, 21 tests pass, debug APK builds with the
  LiveKit plugin and microphone permissions.

Not verified from a laptop, and worth doing once on a device: **a human on a
real phone**, especially barge-in (talking over the agent) and echo behaviour
with the phone's speaker rather than headphones.

## The one honest gap

**Search returns mock data.** `BackPAC-BE/app/domains/trips/service.py` returns
fixed trains, flights and stays. Everything above it is real — the agent decides
when to search, passes real dates, and speaks whatever comes back — so wiring an
actual provider is a change to that one file, behind the schema that is already
there.
