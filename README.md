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

## Data boundary

No player data is invented or seeded in Phase 1. The official IPL 2025 shortlist, official sets, and reserve prices are intentionally reserved for the next import phase.
