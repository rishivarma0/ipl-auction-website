import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { remainingMilliseconds, resumeTimerEndsAt } from "@/lib/auction-timer";
import { groupByPublicRole, normalizePublicRole } from "@/lib/player-roles";

const migration = readFileSync(new URL("../supabase/migrations/0005_realtime_auction_engine.sql", import.meta.url), "utf8");
const foundation = readFileSync(new URL("../supabase/migrations/0001_foundation.sql", import.meta.url), "utf8");
const privileged = readFileSync(new URL("../supabase/migrations/0008_saved_simulation_playoffs.sql", import.meta.url), "utf8");
const moderation = readFileSync(new URL("../supabase/migrations/0013_host_kick_member.sql", import.meta.url), "utf8");
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
  assert.match(server, /callPostAuctionGateway/);
  assert.doesNotMatch(server, /SUPABASE_(SECRET|SERVICE_ROLE)_KEY/);
  assert.doesNotMatch(server, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(server, /console\.(log|error).*secret/i);
});

test("host moderation and timer lock stay server-authoritative", () => {
  assert.match(moderation, /assert_room_session\(p_room_id, p_session_key\)/);
  assert.match(moderation, /v_room\.host_member_id <> v_host/);
  assert.match(moderation, /v_room\.status <> 'WAITING'/);
  assert.match(readFileSync(new URL("../supabase/migrations/0012_live_timer_and_bidder_snapshot.sql", import.meta.url), "utf8"), /AUCTION_ALREADY_STARTED/);
  assert.match(readFileSync(new URL("../app/api/auction/action/route.ts", import.meta.url), "utf8"), /kick_room_member/);
});

test("host can change the bid timer during the live auction", () => {
  const liveTimer = readFileSync(new URL("../supabase/migrations/0015_allow_live_timer_changes.sql", import.meta.url), "utf8");
  assert.match(liveTimer, /v_room\.status not in \('WAITING', 'RUNNING', 'PAUSED'\)/);
  assert.match(liveTimer, /next bid\/reset/);
});

test("public roles normalize with wicketkeeper precedence and skip empty groups", () => {
  const players = [
    { specialism: "WICKETKEEPER-BATTER", wicketkeeper: true },
    { specialism: "ALL-ROUNDER/BATTER", wicketkeeper: false },
    { specialism: "PACE BOWLER", wicketkeeper: false },
    { specialism: "BATTER/OPENER", wicketkeeper: false },
  ];
  assert.deepEqual(players.map(normalizePublicRole), ["WICKET-KEEPER", "ALL-ROUNDER", "BOWLER", "BATTER"]);
  assert.deepEqual(groupByPublicRole(players).map(group => [group.role, group.players.length]), [["BATTER", 1], ["WICKET-KEEPER", 1], ["ALL-ROUNDER", 1], ["BOWLER", 1]]);
});

test("team builder exposes manual-only readiness and host start", () => {
  const builder = readFileSync(new URL("../components/team-builder.tsx", import.meta.url), "utf8");
  assert.match(builder, /START_TOURNAMENT/);
  assert.match(builder, /workspace\.all_ready && session\.isHost/);
  assert.doesNotMatch(builder, /AUTO_PICK_BEST_XI|AUTO_SET_ORDER|AUTO_PICK_XI|AUTO_PICK & LOCK/);
});
