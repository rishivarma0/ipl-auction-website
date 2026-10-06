export type DraftWorkspace = {
  squad: { franchise_id: string; xi_locked: boolean };
  xi: Array<{ player_id: string; batting_position: number }>;
};

export type XiDraftState<W extends DraftWorkspace> = {
  workspace: W | null;
  selected: string[];
  dirty: boolean;
  revision: number;
  requestId: number;
};

export type XiDraftAction<W extends DraftWorkspace> =
  | { type: "workspace"; workspace: W; requestId: number }
  | { type: "toggle"; playerId: string }
  | { type: "move"; from: number; to: number }
  | { type: "saved"; revision: number };

export function initialXiDraft<W extends DraftWorkspace>(): XiDraftState<W> {
  return { workspace: null, selected: [], dirty: false, revision: 0, requestId: 0 };
}

export function xiDraftReducer<W extends DraftWorkspace>(state: XiDraftState<W>, action: XiDraftAction<W>): XiDraftState<W> {
  if (action.type === "workspace") {
    if (action.requestId <= state.requestId) return state;
    const next = action.workspace;
    const sameTeam = state.workspace?.squad.franchise_id === next.squad.franchise_id;
    // Locking is terminal. A pre-lock response must never reopen editing.
    if (sameTeam && state.workspace?.squad.xi_locked && !next.squad.xi_locked) return state;
    const hydrate = !state.workspace || !sameTeam || next.squad.xi_locked;
    return {
      ...state, workspace: next, requestId: action.requestId,
      selected: hydrate ? [...new Set([...next.xi].sort((a, b) => a.batting_position - b.batting_position).map(item => item.player_id))] : state.selected,
      dirty: hydrate ? false : state.dirty,
    };
  }
  if (action.type === "saved") {
    // A save response acknowledges only the submitted draft, never later edits.
    return action.revision === state.revision ? { ...state, dirty: false } : state;
  }
  if (!state.workspace || state.workspace.squad.xi_locked) return state;
  let selected: string[];
  if (action.type === "toggle") {
    if (state.selected.includes(action.playerId)) selected = state.selected.filter(id => id !== action.playerId);
    else if (state.selected.length < 11) selected = [...state.selected, action.playerId];
    else return state;
  } else {
    const { from, to } = action;
    if (from === to || from < 0 || to < 0 || from >= state.selected.length || to >= state.selected.length) return state;
    selected = [...state.selected];
    selected.splice(to, 0, selected.splice(from, 1)[0]);
  }
  return { ...state, selected, dirty: true, revision: state.revision + 1 };
}
