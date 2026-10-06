import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("verified stats artifact covers every auction row without duplicate identities", () => {
  const rows = JSON.parse(fs.readFileSync("data/player-stats/player-stats.json", "utf8")) as Array<Record<string, unknown>>;
  assert.equal(rows.length, 620);
  assert.equal(new Set(rows.map((row) => row.source_record_key)).size, 620);
  const mapped = rows.map((row) => row.cricsheet_player_id).filter(Boolean) as string[];
  assert.equal(new Set(mapped).size, mapped.length);
  for (const row of rows) {
    assert.ok(["IPL", "T20", "NO_VERIFIED_DATA"].includes(String(row.coverage_level)));
    if (row.coverage_level !== "NO_VERIFIED_DATA") {
      assert.ok(row.stats_source);
      assert.ok(row.stats_as_of);
      assert.ok(row.stats_updated_at);
    }
    for (const value of Object.values(row)) {
      if (typeof value === "number") assert.ok(Number.isFinite(value));
    }
  }
  const verified = rows.filter((row) => row.coverage_level === "IPL" || row.coverage_level === "T20");
  const missing = rows.filter((row) => row.coverage_level === "NO_VERIFIED_DATA");
  assert.equal(verified.length, 485);
  assert.equal(missing.length, 135);
  assert.ok(missing.every((row) => row.stats_source === null && row.stats_as_of === null && row.stats_updated_at === null));
});

test("one database readiness helper gates workspace and tournament start", () => {
  const migration = fs.readFileSync("supabase/migrations/20261006145007_unified_stats_readiness.sql", "utf8");
  assert.match(migration, /create or replace function public\.get_player_stats_readiness\(\)/);
  assert.equal((migration.match(/public\.get_player_stats_readiness\(\)/g) ?? []).length >= 3, true);
  assert.match(migration, /coverage_level in \('IPL','T20'\)/);
  assert.match(migration, /'stats_ready', total_profiles >= 620 and verified_profiles = total_profiles/);
  const teamBuilder = fs.readFileSync("components/team-builder.tsx", "utf8");
  const tournament = fs.readFileSync("components/tournament-dashboard.tsx", "utf8");
  assert.match(teamBuilder, /disabled=\{busy \|\| !workspace\.stats_ready\}/);
  assert.match(tournament, /disabled=\{busy \|\| !snapshot\.stats_ready\}/);
  assert.match(tournament, /verified player performance data is complete/i);
  assert.match(tournament, /message\.includes\("PLAYER_STATS_NOT_READY"\)[\s\S]*?Tournament start is locked/i);
  assert.doesNotMatch(tournament, /<p className="error-banner">\s*PLAYER_STATS_NOT_READY/);
});

test("readiness contract rejects the original 360/620 production state and accepts complete coverage", () => {
  const verifiedRows = (coverage: "IPL" | "T20", count: number) => Array.from({ length: count }, () => ({
    coverage_level: coverage, stats_source: "Cricsheet", stats_as_of: "2026-09-17", stats_updated_at: "2026-10-06T00:00:00Z",
  }));
  const noDataRows = Array.from({ length: 260 }, () => ({
    coverage_level: "NO_VERIFIED_DATA", stats_source: null, stats_as_of: null, stats_updated_at: null,
  }));
  const readiness = (rows: Array<{ coverage_level: string; stats_source: string | null; stats_as_of: string | null; stats_updated_at: string | null }>) => {
    const total = rows.length;
    const verified = rows.filter((row) => ["IPL", "T20"].includes(row.coverage_level) && row.stats_source !== null && row.stats_as_of !== null && row.stats_updated_at !== null).length;
    return { total, verified, missing: total - verified, ready: total >= 620 && verified === total };
  };
  const original = readiness([...verifiedRows("IPL", 312), ...verifiedRows("T20", 48), ...noDataRows]);
  assert.deepEqual(original, { total: 620, verified: 360, missing: 260, ready: false });
  const complete = readiness([...verifiedRows("IPL", 312), ...verifiedRows("T20", 308)]);
  assert.deepEqual(complete, { total: 620, verified: 620, missing: 0, ready: true });
});

test("missing profile report has actionable categories and no invented metrics", () => {
  const profiles = JSON.parse(fs.readFileSync("data/player-stats/missing-profiles.json", "utf8")) as Array<Record<string, unknown>>;
  assert.equal(profiles.length, 135);
  assert.ok(profiles.every((profile) => typeof profile.player_id === "string" && /^[0-9a-f-]{36}$/i.test(String(profile.player_id))));
  assert.ok(profiles.every((profile) => ["NAME_ALIAS_MISSING", "NO_IDENTITY_MATCH", "NO_MATCHES_IN_DOWNLOADED_DATA", "OTHER"].includes(String(profile.missing_reason))));
  assert.ok(profiles.every((profile) => typeof profile.full_name === "string" && typeof profile.public_role === "string" && typeof profile.mapping_method === "string"));
});
