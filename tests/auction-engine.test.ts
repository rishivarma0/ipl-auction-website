import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { remainingMilliseconds, resumeTimerEndsAt } from "@/lib/auction-timer";

const migration = readFileSync(new URL("../supabase/migrations/0005_realtime_auction_engine.sql", import.meta.url), "utf8");
const foundation = readFileSync(new URL("../supabase/migrations/0001_foundation.sql", import.meta.url), "utf8");
const privileged = readFileSync(new URL("../supabase/migrations/0008_saved_simulation_playoffs.sql", import.meta.url), "utf8");
const server = readFileSync(new URL("../lib/supabase-server.ts", import.meta.url), "utf8");

test("database engine locks auction state and bids transactionally", () => {
  assert.match(migration, /auction_state where room_id=p_room_id for update/);
  assert.match(migration, /insert into bids\(/);
  assert.match(migration, /timer_ends_at=now\(\)\+make_interval/);
  assert.match(foundation, /unique\(room_id, player_id\)/);
  assert.match(migration, /SQUAD_LIMIT_REACHED/);
  assert.match(migration, /OVERSEAS_LIMIT_REACHED/);
});

test("snapshot RPC does not expose hidden queue ordering", () => {
  const snapshotBody = migration.slice(migration.indexOf("create or replace function public.get_auction_snapshot"));
  assert.doesNotMatch(snapshotBody, /random_position_in_set/);
  assert.doesNotMatch(snapshotBody, /overall_queue_position/);
  assert.match(snapshotBody, /order by lower\(p.full_name\)/);
});

test("timer helpers preserve exact paused duration and never go negative", () => {
  const now = Date.parse("2026-10-06T08:00:00.000Z");
  assert.equal(remainingMilliseconds("2026-10-06T08:00:03.250Z", now), 3250);
  assert.equal(remainingMilliseconds("2026-10-06T07:59:59.000Z", now), 0);
  assert.equal(resumeTimerEndsAt(7617, now), "2026-10-06T08:00:07.617Z");
});

test("host state machine rejects terminal restart paths", () => {
  assert.match(migration, /if v_room\.status<>'WAITING' then raise exception using message='AUCTION_ALREADY_STARTED'/);
  assert.match(migration, /if v_state\.status<>'PAUSED' then raise exception using message='INVALID_STATE_TRANSITION'/);
  assert.match(migration, /if v_room\.status not in \('RUNNING','PAUSED'\) then raise exception using message='INVALID_STATE_TRANSITION'/);
});

test("post-auction mutations are server-only and authorization is explicit", () => {
  assert.match(privileged, /revoke execute on function public\.simulate_one_match.*public\.simulate_tournament/);
  assert.match(readFileSync(new URL("../supabase/migrations/0007_auto_order_and_playoffs.sql", import.meta.url), "utf8"), /grant execute on function public\.post_auction_command.*service_role/);
  assert.match(server, /SUPABASE_SECRET_KEY/);
  assert.match(server, /authorizeRoomSession/);
  assert.doesNotMatch(server, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(server, /console\.(log|error).*secret/i);
});
