# IPL Auction Website

Phase 1 foundation for a realtime IPL Mega Auction experience.

## Routes

- `/` homepage
- `/create` create-room setup
- `/join` join-room setup
- `/lobby` waiting lobby
- `/auction` Phase 1 auction-room shell

## Local development

```bash
npm install
npm run dev
```

## Supabase

Apply `supabase/migrations/0001_foundation.sql`, then `supabase/seed/001_franchises.sql`. The schema keeps official auction metadata, secret room queue data, auction state, squad ownership, XI selection, ratings, and tournament simulation data separate. Critical state mutations will be added as server-authoritative RPCs in the auction-engine phase.

Do not commit real credentials. Copy `.env.example` to `.env.local` and fill in Supabase values locally.

## Official auction data

Phase 2 includes the 574-row structured IPL 2025 auction dataset in `data/ipl-2025-auction/players.json` plus deterministic `auction_sets.json`. The source row list and aggregate IPL reference are documented in that directory. Re-run `python3 scripts/parse-ipl-2025-auction.py` after supplying the source PDF locally; the parser fails on count, serial, set, overseas, or reserve-price mismatches rather than guessing.

Run the Phase 2 checks with:

```bash
npm test
```

The development-only verification view is available at `/data-verification`. It intentionally exposes no player ratings or future auction order.
