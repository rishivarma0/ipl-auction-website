# IPL Auction Website

Secure realtime IPL Mega Auction and tournament simulator. The verified 620-player pool and 80 official auction sets remain intact; post-auction mutations run through server-only Supabase authorization.

## Routes

- `/` homepage
- `/create` create-room setup
- `/join` join-room setup
- `/lobby` waiting lobby
- `/auction` secure realtime auction room with server-authoritative bids and host controls
- `/xi` qualified-team Playing XI, batting-order, validation, and lock experience
- `/tournament` Team OVR, standings, persisted scorecards, playoffs, final, and champion view

## Local development

```bash
npm install
npm run dev
```

## Supabase

Apply migrations in filename order, then `supabase/seed/001_franchises.sql`. The schema keeps official auction metadata, secret room queue data, auction state, squad ownership, XI selection, ratings, and tournament simulation data separate. Privileged post-auction RPCs are revoked from `anon` and `authenticated`; Next.js routes validate the room session, membership, ownership, and host role before using the server-only Supabase secret.

Do not commit real credentials. Copy `.env.example` to `.env.local` and fill in Supabase values locally.

Required variables are `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and server-only `SUPABASE_SECRET_KEY` (or legacy `SUPABASE_SERVICE_ROLE_KEY`). Never prefix a privileged key with `NEXT_PUBLIC_`. Configure the server secret in Vercel Project Settings → Environment Variables for Production/Preview.

The statistics engine stores only verified, source-attributed metrics (`stats_source`, `stats_as_of`) and leaves unavailable metrics null. It uses recent form, IPL history, broader T20 history, and role/context weighting when data is present; it never fabricates missing statistics. Hidden scores are not returned by workspace or tournament snapshot routes.

Playing XI rules: exactly 11 owned players, at most four overseas, at least one capability-backed wicketkeeper, and enough real bowling capability to cover 20 overs with a four-over maximum per bowler. Batting order is persisted exactly as selected. Tournament fixtures are balanced double round-robin leagues with an adapted two/three-team path and IPL-style top-four playoffs for four or more teams. Results, scorecards, toss, conditions, seeds, standings, NRR, playoffs, and champion are persisted and idempotent.

## Official auction data

Phase 2 includes the 574-row structured IPL 2025 auction dataset plus 46 declared MARQUEE additions. The reproducible game pool in `data/ipl-2025-auction/game_players.json` contains 620 players and starts with M0 before the official sets. The source row list and aggregate IPL reference are documented in that directory. Re-run `python3 scripts/parse-ipl-2025-auction.py` after supplying the source PDF locally; the parser fails on count, serial, set, overseas, or reserve-price mismatches rather than guessing.

Run the Phase 2 checks with:

```bash
npm test
```

The development-only verification view is available at `/data-verification`. It intentionally exposes no player ratings or future auction order.
