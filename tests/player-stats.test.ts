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
});
