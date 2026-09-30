# backPAC

**A voice travel planner with a face.** You talk to COOKIE — an orb drawn and
animated entirely in code — and it plans the trip with you: trains, flights and
places to stay, found live, said out loud, and kept as a conversation you can
pick up again later.

Built for the RevenueCat Shipaton 2026. Flutter app, FastAPI backend, and a
Pipecat voice agent on Claude.

| Repository | What |
|---|---|
| [**BackPAC-Fe**](https://github.com/TanishSen/BackPAC-Fe) (this one) | The Flutter app: voice calls, history, profile, the Premium paywall |
| [BackPAC-Backend](https://github.com/TanishSen/BackPAC-Backend) | FastAPI: sessions, history, profile, trip search, RevenueCat entitlements |
| [BackPAC-Agent](https://github.com/TanishSen/BackPAC-Agent) | The voice agent: LiveKit + Azure STT + Claude (LangGraph) + ElevenLabs |

[`docs/INTEGRATION.md`](docs/INTEGRATION.md) is how the three talk to each
other; [`docs/DEPLOY.md`](docs/DEPLOY.md) is how to run all of it.

## How it works

```
 app ──POST /sessions──► backend ──mints a LiveKit room, checks the plan──►
                         backend ──POST /start {isPremium}──► agent joins the room
 app ◄──── live voice over LiveKit ────► agent  (Azure STT → Claude → ElevenLabs)
                                          agent ──search tools──► backend
 app ◄── transcript + result cards over the data channel ── agent
```

## Premium, with RevenueCat

- **Paywall** — `lib/features/premium/upgrade_page.dart`, built to our Figma.
  Plans, prices and free trials come live from the RevenueCat *current
  offering*; the headline, perks, badge and default plan can be changed from
  the dashboard through **offering metadata**, without an app release.
- **Purchases** — `lib/features/premium/premium_service.dart`. Store billing
  through RevenueCat; the customer is the signed-in Supabase user, so a
  purchase follows the account. A customer-info listener flips the app to
  Premium the moment RevenueCat confirms it. Restore, subscription management,
  trial eligibility and "Save X%" are all handled.
- **Server-side truth** — the backend keeps its own copy of the entitlement
  (webhook + REST refresh) and enforces the free plan there: 3 new trip plans
  a month, then a contextual paywall right inside the conversation that hit
  the limit. Resuming a past plan is always free.
- **Premium perks are real features**: unlimited plans, insider tips from the
  agent's Premium planner, priority support, flexible cancellation, a VIP
  crown on the profile.
- **Promo codes** — Settings → *Redeem promo code* (or *Have a promo code?* on
  the paywall). Judges: **`SHIPATON2026`** unlocks 30 days of Premium.
- **Test Store** — debug builds can run against RevenueCat's Test Store for a
  full purchase flow with no store account; release builds refuse a Test Store
  key rather than ship RevenueCat's deliberate crash.

## Run it

```bash
flutter pub get
# Point it at your backend, with the RevenueCat Test Store key in a
# git-ignored dart_defines.local.json:  {"REVENUECAT_TEST_KEY": "test_…"}
flutter run --dart-define=BACKEND_URL=http://<your-machine>:8000 \
            --dart-define-from-file=dart_defines.local.json
```

Release builds: `BACKEND_URL=https://… ./build_release.sh apk|appbundle|ipa`
(refuses http URLs, debug signing and Test Store keys).

## Layout

```
lib/
  app/            theme, config, the shared API client, shared widgets
  orb/            COOKIE: procedural drawing and choreography
  features/
    welcome/      the opening screen; the orb speaks and reacts to pokes
    auth/         Supabase sign-in
    home/         greeting, plan card, travel modes, trip ideas, recent history
    chat/         the conversation screen
    conversation/ live (LiveKit) and scripted-demo conversations
    realtime/     the LiveKit session and the backend's session call
    history/      full history: filters, groups, favourites, share
    profile/      profile, travel journey, bucket list, Play with COOKIE
    premium/      RevenueCat: the paywall, purchases, promo codes
test/             widget and unit tests (flutter test)
```

## Tests

```bash
flutter analyze
flutter test
SHOT_OUT=/tmp/shots flutter test test/capture_profile_history.dart   # renders screens to PNG
```

## Licence

MIT — see [LICENSE](LICENSE).
