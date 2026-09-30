# Going live

> Paths below assume the three repositories checked out side by side —
> `BackPAC-BE/`, `BackPAC-Agent/`, `BackPAC-FE/` — with the compose files from
> the backend's parent folder.

The order matters: backend and agent first, prove them from a laptop, then
build the app against the live URL. Allow about an hour, most of it waiting on
builds.

## 1. Secrets (10 min)

Fill `BackPAC-BE/.env` and `BackPAC-Agent/.env` on the server (or the hosting
platform's environment settings). Each `.env.example` explains every key.

| Must be set | Where | Note |
|---|---|---|
| `ENVIRONMENT=production` | BE | hides internal addresses from `/readyz` |
| `DATABASE_URL` | BE | Supabase session pooler, `postgresql+asyncpg://…` |
| `SUPABASE_PROJECT_REF` | BE | without it every signed-in route 503s |
| `SUPABASE_SERVICE_ROLE_KEY` | BE | so "Delete account" closes the sign-in (store requirement) |
| `LIVEKIT_URL` / `_API_KEY` / `_API_SECRET` | BE **and** agent | identical in both |
| `SERVICE_TOKEN` (BE) = `BACKEND_SERVICE_TOKEN` (agent) | both | identical; the agent refuses to boot without it |
| `ANTHROPIC_API_KEY`, `ELEVENLABS_*`, `AZURE_SPEECH_*` | agent | checked at boot |
| `LANGGRAPH_DATABASE_URL` | agent | plain `postgresql://…`; without it resume forgets the trip |
| `TRAVELPAYOUTS_TOKEN` / `_MARKER` | BE | live flight prices; without it, labelled samples |
| `FREE_MONTHLY_TRIP_PLANS` | BE | leave `0` until Premium is set up (below) |

`BACKEND_URL` and `AGENT_BASE_URL` are set by the compose files. On a
platform with separate services, point each at the other's **private** address.

## 2. Deploy (15 min)

**One VM with Docker** (simplest): point a DNS A record, e.g.
`api.example.com`, at the VM, open ports 80 and 443, then:

```bash
API_DOMAIN=api.example.com docker compose -f compose.prod.yaml up -d --build
```

Caddy fetches the HTTPS certificate on first request. The API migrates the
database on boot (`entrypoint.sh`); a failed migration stops it loudly.

**Render / Railway / Fly**: two services from `BackPAC-BE` and `BackPAC-Agent`,
each with its Dockerfile. Only the API gets a public URL. Both honour `$PORT`.
Run one agent instance per ~20 concurrent calls (`MAX_SESSIONS`).

Both are single-process by design: rate limits, the flight cache and running
calls live in memory. Scale the agent by adding containers; keep the API at one
until the limiter moves to Redis.

## 3. Prove it before touching the app (5 min)

```bash
curl https://api.example.com/readyz
```

Every flag must be `true`: `livekit_configured`, `auth_configured`,
`service_token_configured`, `database_ready` (and `flights_live` if you set the
token). Then check the agent is reachable and trusts the API:

```bash
curl https://api.example.com/api/v1/voice/welcome-lines   # 200 with 19 lines (first call ~5s)
curl -o /dev/null -w '%{http_code}\n' \
  'https://api.example.com/api/v1/voice/line.wav?text=anything'   # 404, not 502
```

A 502 on either means the API cannot reach the agent or the tokens differ.
Check `docker compose -f compose.prod.yaml logs agent`.

## 4. Build the app (20–30 min)

```bash
cd BackPAC-FE
BACKEND_URL=https://api.example.com ./build_release.sh apk         # sideload / internal
BACKEND_URL=https://api.example.com ./build_release.sh appbundle   # Play Store
BACKEND_URL=https://api.example.com ./build_release.sh ipa         # TestFlight / App Store
```

The script refuses a missing or `http://` URL, and an Android build without a
release key (it prints the one-time `keytool` command). **Keep that keystore
and its passwords forever**: every future update must be signed with it.

Do not ship `build/app/outputs/flutter-apk/app-release.apk` from before this
change. It has a dead ngrok URL compiled in.

## 5. On a real phone (10 min)

Sign up → tap the mic → say "trains from Delhi to Jaipur on Friday" → hear the
answer and see a card → hang up → the conversation is in history with a title →
open it and resume → delete it → account button → Sign out.

Worth doing once with the phone's **speaker**, not headphones: that is where
echo and barge-in behave differently.

## Demo with RevenueCat's Test Store (no store account needed)

The fastest way to see the whole Premium loop — and what the Next Gen video
shows. Debug builds only; a release build refuses a `test_` key.

1. `BackPAC-FE/dart_defines.local.json` (git-ignored):
   `{"REVENUECAT_TEST_KEY": "test_…"}`
2. `BackPAC-BE/.env`: `REVENUECAT_PUBLIC_KEY=test_…` (the same key — it lets
   the API verify Test Store purchases), `FREE_MONTHLY_TRIP_PLANS=3`, and
   `PROMO_CODES=SHIPATON2026:30:500`. Then `alembic upgrade head`.
3. `flutter run --dart-define=BACKEND_URL=… --dart-define-from-file=dart_defines.local.json`
4. Profile → Unlock Premium → pick a plan → Proceed to Pay → RevenueCat's test
   sheet → *Successful purchase*. The crown appears, the limit lifts, and the
   next call gets insider tips.

Paywall copy can be changed without a release: RevenueCat → Offerings →
`default` → Metadata, e.g.
`{"title": "UPGRADE PLAN", "badge": "Most Popular", "default_package": "$rc_three_month",
"perks": [{"icon": "tips", "title": "Insider Tips", "subtitle": "Local know-how in every plan"}]}`
(icons: unlimited, adfree, tips, support, cancel, vip).

## Premium (optional — the app ships fine without it)

Off by default everywhere: with no RevenueCat keys in the build and
`FREE_MONTHLY_TRIP_PLANS=0` on the API, nobody sees a limit or an upgrade
prompt. Turn it on in this order, or free users hit a wall with no way over it:

1. **Store products.** Create three auto-renewing subscriptions in App Store
   Connect and Google Play Console — 1 month, 3 months, 1 year — at the prices
   you want (₹199 / ₹499 / ₹1,499 in the design). The store sets the displayed
   price per country; the app never hard-codes it.
2. **RevenueCat.** Add both apps, import the products, create an entitlement
   `premium` attached to all three, and a *current* offering with packages
   `$rc_monthly`, `$rc_three_month`, `$rc_annual`.
3. **Webhook.** RevenueCat → Integrations → Webhooks →
   `https://<api>/api/v1/billing/revenuecat`, with an Authorization value you
   choose. Put the same value in `REVENUECAT_WEBHOOK_AUTH` on the API, and a v1
   secret key in `REVENUECAT_SECRET_KEY`.
4. **Legal pages.** The API serves both — `https://<api>/legal/privacy` and
   `/legal/terms` — and the app links there by default. Review the wording;
   it describes what the code does, but it is not legal advice.
5. **Build** with the public SDK keys:
   ```bash
   BACKEND_URL=https://api.example.com \
   REVENUECAT_APPLE_KEY=appl_… REVENUECAT_GOOGLE_KEY=goog_… \
   TERMS_URL=https://…/terms PRIVACY_URL=https://…/privacy \
   ./build_release.sh appbundle
   ```
6. **Last**, set `FREE_MONTHLY_TRIP_PLANS` (e.g. 5) on the API and restart it.
   Check `GET /api/v1/billing/plan` shows `billingEnabled: true`.

Test a purchase with a sandbox / licence-tester account before release. What
Premium unlocks is exactly one thing today — no monthly limit — and the upgrade
screen says only that. The design's other perks (deals, ad-free, early access,
priority support, flexible cancellation, guides) are listed in
`upgrade_page.dart`'s `_perks` as not built; add each one there when it ships.

## Before the store submission (not blocking a sideload/TestFlight launch)

- **Supabase Auth email**: the built-in SMTP sends about two emails an hour, so
  with "Confirm email" on, sign-ups stall after the first couple. Add custom
  SMTP (Auth → SMTP) or turn confirmation off. Set Auth → URL Configuration →
  Site URL to something real; password-reset links go there.
- **iOS signing**: automatic, team `98AV65P6WF`. Never built for release yet;
  expect a round of provisioning in Xcode.
- **Placeholder** still visible: "Plan something new → View all" says "…is
  next on the list".

## Rollback

`docker compose -f compose.prod.yaml up -d --build` from the previous commit.
Migrations only ever add; the previous API runs against the newer schema.

## Known limits

- Trains and stays are **sample data** (`BackPAC-BE/app/domains/trips/service.py`).
  Flights are live when Travelpayouts is configured.
- `make call` in the agent predates sign-in and gets a 401 from
  `POST /sessions`; use a real device, or `make brain` for the brain alone.
