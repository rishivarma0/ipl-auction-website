import test from "node:test";
import assert from "node:assert/strict";
import { initialXiDraft, xiDraftReducer } from "../lib/xi-draft";

function workspace(ids = ["saved-b", "saved-a"], locked = false) {
  return {
    squad: { franchise_id: "RCB", xi_locked: locked },
    xi: ids.map((player_id, index) => ({ player_id, batting_position: index + 1 })).reverse(),
    qualified_teams: [{ squad_id: "MI", xi_locked: false }],
    all_ready: false, verified_profiles: 360,
  };
}
const refresh = (state: ReturnType<typeof initialXiDraft<ReturnType<typeof workspace>>>, next = workspace(), requestId = state.requestId + 1) =>
  xiDraftReducer(state, { type: "workspace", workspace: next, requestId });

test("first successful load hydrates saved batting order without sorting the response in place", () => {
  const next = workspace(); const copy = structuredClone(next);
  const state = refresh(initialXiDraft(), next);
  assert.deepEqual(state.selected, ["saved-b", "saved-a"]);
  assert.deepEqual(next, copy);
  assert.equal(state.dirty, false);
});

test("ten seconds of polls preserve dirty selections and order while another client locks", () => {
  let state = refresh(initialXiDraft(), workspace([]));
  for (let i = 0; i < 11; i++) state = xiDraftReducer(state, { type: "toggle", playerId: `player-${i}` });
  state = xiDraftReducer(state, { type: "move", from: 4, to: 7 });
  const draft = [...state.selected];
  for (let i = 0; i < 4; i++) {
    const next = workspace([]);
    next.qualified_teams[0].xi_locked = true;
    next.verified_profiles = 361;
    state = refresh(state, next);
    assert.deepEqual(state.selected, draft);
    assert.equal(state.dirty, true);
    assert.equal(state.workspace?.qualified_teams[0].xi_locked, true);
    assert.equal(state.workspace?.verified_profiles, 361);
  }
});

test("ordinary polls preserve clean drafts too; successful save only acknowledges its own revision", () => {
  let state = refresh(initialXiDraft());
  state = xiDraftReducer(state, { type: "move", from: 0, to: 1 });
  const revision = state.revision;
  state = xiDraftReducer(state, { type: "saved", revision });
  assert.equal(state.dirty, false);
  state = refresh(state);
  assert.deepEqual(state.selected, ["saved-a", "saved-b"]);
  state = xiDraftReducer(state, { type: "toggle", playerId: "new" });
  state = xiDraftReducer(state, { type: "saved", revision });
  assert.equal(state.dirty, true);
});

test("locked transition uses server XI, updates readiness and refuses stale unlocks or edits", () => {
  let state = refresh(initialXiDraft());
  state = xiDraftReducer(state, { type: "toggle", playerId: "local" });
  const next = workspace(["locked-a", "locked-b"], true); next.all_ready = true;
  state = refresh(state, next, 3);
  assert.deepEqual(state.selected, ["locked-a", "locked-b"]);
  assert.equal(state.dirty, false);
  assert.equal(state.workspace?.all_ready, true);
  assert.strictEqual(refresh(state, workspace(), 2), state);
  assert.strictEqual(refresh(state, workspace(), 4), state);
  assert.strictEqual(xiDraftReducer(state, { type: "toggle", playerId: "local" }), state);
  assert.strictEqual(xiDraftReducer(state, { type: "move", from: 0, to: 1 }), state);
});

test("max eleven, deselection, invalid drag indices and uniqueness survive rapid actions", () => {
  let state = refresh(initialXiDraft(), workspace([]));
  for (let i = 0; i < 12; i++) state = xiDraftReducer(state, { type: "toggle", playerId: `p${i}` });
  assert.equal(state.selected.length, 11);
  assert.ok(!state.selected.includes("p11"));
  state = xiDraftReducer(state, { type: "toggle", playerId: "p0" });
  assert.equal(state.selected.length, 10);
  state = xiDraftReducer(state, { type: "toggle", playerId: "p11" });
  assert.equal(new Set(state.selected).size, 11);
  assert.strictEqual(xiDraftReducer(state, { type: "move", from: -1, to: 2 }), state);
});

test("a failed or out-of-order refresh cannot replace a newer workspace", () => {
  const state = refresh(initialXiDraft(), workspace(["newer"]), 2);
  assert.strictEqual(refresh(state, workspace(["older"]), 1), state);
});

test("new team and deliberate page reload hydrate their server XI", () => {
  let state = refresh(initialXiDraft());
  state = xiDraftReducer(state, { type: "toggle", playerId: "local" });
  const next = workspace(["another"]); next.squad.franchise_id = "MI";
  assert.deepEqual(refresh(state, next).selected, ["another"]);
  assert.deepEqual(refresh(initialXiDraft(), workspace()).selected, ["saved-b", "saved-a"]);
});
