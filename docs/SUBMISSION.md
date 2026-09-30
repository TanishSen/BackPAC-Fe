# backPAC — Shipaton 2026 submission (Next Gen Award)

Paste-ready text for the Devpost form, and the plan for the video.

---

## Tagline

Plan a trip by talking to it. A voice travel planner with a face.

## Promo code for judges

**`SHIPATON2026`** — 30 days of Premium. In the app: **Profile → ⚙ Settings →
Redeem promo code**, or **Have a promo code?** at the bottom of the Upgrade
screen. Each account can redeem it once.

## What it does

backPAC is a travel planner you talk to. Tap the mic and tell COOKIE — an
animated orb drawn entirely in code — where you want to go. It asks what it
needs, searches trains, flights and stays live, reads you the best options, and
drops result cards into the conversation. Every conversation is kept: rename
it, favourite it, file it in a group, share it, or pick it up days later exactly
where you left off, with the agent remembering what you already decided.

- **Voice first, typing welcome.** Live two-way voice over LiveKit, with
  barge-in; a keyboard for when you can't talk.
- **History that works like a library.** Filters, groups, favourites, "mark as
  completed", share as text.
- **A profile that is actually yours.** Travel Journey counts (trips, places
  searched, saved, favourites) come from your real conversations. A bucket list
  that turns into a plan with one tap. And *Play with COOKIE*: poke it, make it
  do tricks, or spin the trip roulette.

## Premium, and how RevenueCat powers it

Free: 3 new trip plans a month. Premium: unlimited plans, insider tips in every
plan, priority support, flexible cancellation and a VIP crown — each one a real
feature, not a slide.

- **A paywall built to our Figma, fed live by RevenueCat.** Plans, localised
  prices, free trials (with Apple eligibility checks) and "Save X%" all come
  from the current offering. Headline, perks, badge and default plan are read
  from **offering metadata**, so the pitch can be changed from the dashboard
  without an app release.
- **Contextual, not naggy.** The paywall appears where the value is: when a
  free user starts their fourth plan of the month, the conversation itself
  offers *See Premium* — and after buying, it reopens the same request.
  Resuming an old plan is always free.
- **Server-side truth.** The backend keeps its own copy of the entitlement,
  refreshed by RevenueCat's webhook and REST API, and enforces the free plan
  there. Before ever turning someone away it asks RevenueCat once more, so a
  person who bought seconds ago is never blocked. Premium status travels to
  the voice agent, which switches on its Premium planner.
- **Identity done right.** The RevenueCat customer is the Supabase user:
  `logIn`/`logOut` follow sign-in, email and name are set as attributes, and
  a customer-info listener flips the whole app to Premium the instant a
  purchase lands.
- **The unglamorous parts.** Restore purchases, subscription management,
  pending purchases, "paid but not yet confirmed" handled honestly, promo codes
  (granted as RevenueCat promotional entitlements when a secret key is set),
  account deletion that also removes the RevenueCat customer, and store-billing
  only — no card forms. Release builds refuse a Test Store key rather than ship
  RevenueCat's deliberate crash.

## How we built it

- **App:** Flutter. COOKIE is a procedural `CustomPainter` with its own
  choreography engine — moods, antics, and a mouth driven by the real audio
  level of what it says.
- **Backend:** FastAPI + async SQLAlchemy on Supabase Postgres, Alembic
  migrations with row-level security on every table, Supabase JWT verification
  against the project's public signing keys, per-user rate limits.
- **Agent:** Pipecat on LiveKit, Azure speech-to-text, a LangGraph team of
  Claude specialists (trains, flights, stays) behind an orchestrator,
  ElevenLabs voice, conversation memory in Postgres so resume really resumes.
- **Tests:** 75 backend tests (including database flows against real Postgres),
  75 Flutter widget/unit tests.

## Challenges

Making voice feel like a conversation, not a walkie-talkie: barge-in, echo off
a phone speaker, streamed replies that must close cleanly when interrupted.
And making Premium honest end to end — the app, the backend and the agent all
agreeing on who is Premium, even in the seconds after a purchase.

## What's next

Real train and hotel inventory (flights are live today), more Premium perks as
they ship — remotely configurable through the same offering metadata — and
store release.

## Built with

flutter, dart, revenuecat, fastapi, python, postgresql, supabase, livekit,
pipecat, langgraph, claude, elevenlabs, azure-speech

---

## The video (under 2 minutes — Premium in the first 40 seconds)

Judges are not required to watch past two minutes, so the money shot comes
first.

| Time | Show | Say |
|---|---|---|
| 0:00–0:08 | Welcome screen; COOKIE says hello | "This is backPAC. You plan trips by talking to COOKIE." |
| 0:08–0:20 | Home → mic → "Trains from Delhi to Jaipur on Friday" → the paywall banner appears | "Free accounts get three plans a month. Hit the limit and Premium is offered right in the conversation." |
| 0:20–0:40 | See Premium → the Upgrade screen → pick 3 Months → Proceed to Pay → test sheet → Welcome to Premium | "Plans, prices and copy come live from RevenueCat. One tap, and the entitlement flips everywhere — app, backend and voice agent." |
| 0:40–1:05 | The same request reopens; the agent answers with options **and an insider tip**; a card appears | "Premium turns on insider tips from the agent's Premium planner." |
| 1:05–1:25 | History: filters, groups, ⋮ → favourite, share | "Every conversation is kept, filed and shareable." |
| 1:25–1:45 | Profile: VIP crown, Travel Journey, bucket list, Play with COOKIE roulette | "Your profile is built from real trips." |
| 1:45–1:55 | Settings → Redeem promo code | "Judges: SHIPATON2026 unlocks Premium." |

Record on a phone with a debug build using the Test Store key (see
[DEPLOY.md](DEPLOY.md)). Before recording, use an account that has already
had three conversations this month, so the limit is hit on camera.

## Next Gen checklist

- [ ] Submit with your **student / academic email** — required for this award
- [ ] Demo video on YouTube or Vimeo, public, under 2 minutes
- [ ] Code repository public, with an open-source licence (MIT, included) —
      link **github.com/TanishSen/BackPAC-Fe**; its README links the other two
- [ ] **BackPAC-Backend is private** — make it public so judges can read it
- [ ] 1024×1024 icon and a 1179×2556 screenshot (no device frame)
