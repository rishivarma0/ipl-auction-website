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

Apply migrations in filename order, then `supabase/seed/001_franchises.sql`. The schema keeps official auction metadata, secret room queue data, auction state, squad ownership, XI selection, ratings, and tournament simulation data separate. Privileged post-auction RPCs are revoked from `anon` and `authenticated`; the Next.js server validates room session, membership, ownership, and host role before invoking the Supabase Edge Function gateway.

Do not commit real credentials. Copy `.env.example` to `.env.local` and fill in Supabase values locally.

Required Vercel variables are only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Privileged post-auction operations run through the deployed Supabase Edge Function `post-auction-gateway`, which uses Supabase-hosted server secrets internally; no privileged key is required in Vercel.

The statistics engine stores only verified, source-attributed metrics (`stats_source`, `stats_as_of`) and leaves unavailable metrics null. It uses recent form, IPL history, broader T20 history, and role/context weighting when data is present; it never fabricates missing statistics. Hidden scores are not returned by workspace or tournament snapshot routes.

Playing XI rules: exactly 11 owned players, at most four overseas, at least one capability-backed wicketkeeper, and enough real bowling capability to cover 20 overs with a four-over maximum per bowler. Batting order is persisted exactly as selected. Tournament fixtures are balanced double round-robin leagues with an adapted two/three-team path and IPL-style top-four playoffs for four or more teams. Results, scorecards, toss, conditions, seeds, standings, NRR, playoffs, and champion are persisted and idempotent.

## Official auction data

Phase 2 includes the 574-row structured IPL 2025 auction dataset plus 46 declared MARQUEE additions. The reproducible game pool in `data/ipl-2025-auction/game_players.json` contains 620 players and starts with M0 before the official sets. The source row list and aggregate IPL reference are documented in that directory. Re-run `python3 scripts/parse-ipl-2025-auction.py` after supplying the source PDF locally; the parser fails on count, serial, set, overseas, or reserve-price mismatches rather than guessing.

Run the Phase 2 checks with:

```bash
npm test
```

The development-only verification view is available at `/data-verification`. It intentionally exposes no player ratings or future auction order.
# Verified player-statistics pipeline

`npm run stats:update` reproducibly reads gitignored Cricsheet IPL, men's T20
international, and domestic/franchise T20 archives (SMAT, BBL, PSL, CPL, SA20,
ILT, MLC, LPL, T20 Blast, BPL, CSA T20 Challenge, Major Clubs T20, and Super
Smash), plus Cricsheet people/name registers. It emits audited artifacts in
`data/player-stats/`. Identity matching prefers exact/active registry matches;
ambiguous identities are deliberately left unmapped. Metrics retain provenance,
use only appearances in the source, and leave unavailable values null. Recent
form uses up to 15 appearances in the trailing 365-day source window with
exponential recency weighting. Hidden strength scores use a role-specific
combination of recent form, IPL, and broader T20 metrics; rows without verified
appearances return no score.

The current Cricsheet data cutoff is 2026-09-17. The 620-player audit reports
485 verified profiles (328 with IPL history and 157 with broader T20 history)
and 135 without verified coverage. Reasons and per-player mapping status are
recorded in `data/player-stats/missing-profiles.json`; no missing profile is
filled with invented statistics. The shared production readiness helper feeds
both Team Builder and the server-side tournament guard, so tournament start
stays disabled until all seeded profiles have verified coverage. Regenerate
the artifacts with `npm run stats:update`, then use
`scripts/generate-player-stats-sql.py <start> <end>` in manageable batches to
upsert them into the project. `data/player-stats/validation-report.json` records
source archive counts, coverage, and mapping outcomes.
