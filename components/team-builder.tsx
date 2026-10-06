"use client";

import Link from "next/link";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  ChevronUp,
  Gavel,
  GripVertical,
  Lock,
  ShieldCheck,
  Trophy,
  Users,
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
} from "react";
import { initialXiDraft, xiDraftReducer } from "@/lib/xi-draft";
import { formatAuctionPrice } from "@/lib/auction-pricing";
import { groupByPublicRole, normalizePublicRole } from "@/lib/player-roles";
import { getRoomSession, type RoomSession } from "@/lib/room-session";
import {
  Chip,
  Eyebrow,
  SegmentedTabs,
  Surface,
  TeamMark,
} from "@/components/ui/auction-primitives";

type Player = {
  id: string;
  full_name: string;
  country: string;
  specialism: string;
  overseas: boolean;
  wicketkeeper: boolean;
  bowling_style: string | null;
  purchase_price_lakh: number;
  batting_position: number;
};
type Workspace = {
  room: { status: string; room_code: string; minimum_squad_size: number };
  squad: {
    franchise_id: string;
    squad_count: number;
    qualification_status: string;
    xi_locked: boolean;
  };
  players: Player[];
  xi: Array<{ player_id: string; batting_position: number }>;
  qualified_teams: Array<{
    squad_id: string;
    franchise_code: string;
    owner_name: string;
    xi_locked: boolean;
  }>;
  qualified_count: number;
  locked_qualified_count: number;
  all_ready: boolean;
  verified_profiles: number;
  total_profiles: number;
  missing_profiles: number;
  stats_ready: boolean;
};

const errors: Record<string, string> = {
  XI_MUST_HAVE_11: "Select exactly 11 players.",
  XI_OVERSEAS_LIMIT: "Maximum 4 overseas players allowed.",
  XI_WICKETKEEPER_REQUIRED: "Your XI needs a wicketkeeper.",
  XI_BOWLING_CAPABILITY_REQUIRED: "Your XI needs enough bowling coverage.",
  TEAM_ALREADY_LOCKED: "This team is already locked.",
  TEAM_NOT_QUALIFIED: "Only qualified teams can select an XI.",
  NOT_ALL_TEAMS_READY: "Every qualified team must lock first.",
  TOURNAMENT_ALREADY_STARTED: "The tournament has already started.",
  PLAYER_STATS_NOT_READY: "Player performance data is still being prepared.",
};
const friendly = (raw: string) =>
  errors[raw.match(/[A-Z_]{4,}/)?.[0] ?? raw] ?? raw;

async function workspaceFor(session: RoomSession) {
  const response = await fetch("/api/post-auction/workspace", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      roomId: session.roomId,
      sessionKey: session.sessionKey,
    }),
  });
  const data = (await response.json()) as { error?: string };
  if (!response.ok) throw new Error(data.error ?? "WORKSPACE_FAILED");
  return data as unknown as Workspace;
}
async function sendCommand(
  session: RoomSession,
  command: string,
  payload: Record<string, unknown> = {},
) {
  const response = await fetch("/api/post-auction/action", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      roomId: session.roomId,
      sessionKey: session.sessionKey,
      command,
      payload,
    }),
  });
  const data = (await response.json()) as { error?: string };
  if (!response.ok) throw new Error(data.error ?? "ACTION_FAILED");
  return data;
}

export function TeamBuilder() {
  const [session] = useState<RoomSession | null>(() => getRoomSession());
  const [draft, dispatch] = useReducer(
    xiDraftReducer<Workspace>,
    initialXiDraft<Workspace>(),
  );
  const { workspace, selected } = draft;
  const requestSequence = useRef(0);
  const mutationPending = useRef(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<"squad" | "order">("squad");
  const [dragging, setDragging] = useState<string | null>(null);
  const load = useCallback(async () => {
    if (!session) return;
    const requestId = ++requestSequence.current;
    try {
      const next = await workspaceFor(session);
      dispatch({ type: "workspace", workspace: next, requestId });
    } catch (e) {
      if (requestId === requestSequence.current)
        setError(friendly(e instanceof Error ? e.message : "WORKSPACE_FAILED"));
    }
  }, [session]);
  useEffect(() => {
    const id = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(id);
  }, [load]);
  useEffect(() => {
    const id = window.setInterval(() => void load(), 2500);
    return () => window.clearInterval(id);
  }, [load]);
  const chosen = useMemo(
    () =>
      selected
        .map((id) => workspace?.players.find((player) => player.id === id))
        .filter(Boolean) as Player[],
    [selected, workspace],
  );
  const overseas = chosen.filter((player) => player.overseas).length;
  const hasKeeper = chosen.some((player) => player.wicketkeeper);
  const bowlers = chosen.filter(
    (player) =>
      player.specialism.includes("BOWL") ||
      player.specialism.includes("ALL-ROUNDER") ||
      player.bowling_style,
  ).length;
  const legal =
    selected.length === 11 && overseas <= 4 && hasKeeper && bowlers >= 4;
  const run = async (
    command: string,
    payload: Record<string, unknown> = {},
  ) => {
    if (!session || mutationPending.current) return false;
    mutationPending.current = true;
    setBusy(true);
    const revision = draft.revision;
    try {
      await sendCommand(session, command, payload);
      if (command === "SAVE_XI") dispatch({ type: "saved", revision });
      setError("");
      await load();
      return true;
    } catch (e) {
      setError(friendly(e instanceof Error ? e.message : "ACTION_FAILED"));
      return false;
    } finally {
      mutationPending.current = false;
      setBusy(false);
    }
  };
  const lock = async () => {
    if (!session || mutationPending.current) return;
    mutationPending.current = true;
    setBusy(true);
    try {
      await sendCommand(session, "SAVE_XI", { player_ids: selected });
      await sendCommand(session, "SAVE_BATTING_ORDER", {
        player_ids: selected,
      });
      await sendCommand(session, "LOCK_TEAM");
      dispatch({ type: "saved", revision: draft.revision });
      setError("");
      await load();
    } catch (e) {
      setError(friendly(e instanceof Error ? e.message : "ACTION_FAILED"));
    } finally {
      mutationPending.current = false;
      setBusy(false);
    }
  };
  const start = async () => {
    if (session?.isHost && (await run("START_TOURNAMENT")))
      window.location.reload();
  };
  const toggle = (id: string) => {
    if (!mutationPending.current) dispatch({ type: "toggle", playerId: id });
  };
  const move = (index: number, delta: number) => {
    if (!mutationPending.current)
      dispatch({ type: "move", from: index, to: index + delta });
  };
  const drop = (id: string) => {
    if (!dragging || mutationPending.current) return;
    dispatch({
      type: "move",
      from: selected.indexOf(dragging),
      to: selected.indexOf(id),
    });
    setDragging(null);
  };
  if (!session || !workspace)
    return (
      <main className="app-background">
        <section className="loading-card">
          <Eyebrow>TEAM BUILDER</Eyebrow>
          <h1>
            Loading your
            <br />
            <em>qualified squad.</em>
          </h1>
          <p>{error || "Restoring your secure room session…"}</p>
        </section>
      </main>
    );
  if (workspace.squad.qualification_status !== "QUALIFIED")
    return (
      <main className="app-background">
        <section className="completion-card">
          <Eyebrow>AUCTION COMPLETE</Eyebrow>
          <h1>
            Team
            <br />
            <em>eliminated.</em>
          </h1>
          <p>
            This squad did not reach the room minimum of{" "}
            {workspace.room.minimum_squad_size} players.
          </p>
          <Link href="/team" className="secondary-button">
            View room results <ArrowRight size={15} />
          </Link>
        </section>
      </main>
    );
  const groups = groupByPublicRole(workspace.players);
  return (
    <main className="app-background">
      <nav className="game-topbar">
        <Link className="game-back" href="/auction">
          <ArrowLeft size={18} />
        </Link>
        <Link className="game-brand" href="/">
          <span className="brand-mark">
            <Gavel size={16} />
          </span>
          <span>
            AUCTION
            <br />
            <i>ROOM</i>
          </span>
        </Link>
        <div className="room-pill">
          <span className="room-pill-label">TEAM SETUP</span>
          <b>{workspace.room.room_code}</b>
        </div>
        <Link href="/auction" className="secondary-button compact-button">
          <ArrowLeft size={14} /> <span className="desktop-only">Auction</span>
        </Link>
      </nav>
      <div className="app-container builder-container">
        <section className="builder-title">
          <div>
            <Eyebrow>
              QUALIFIED TEAM · {workspace.squad.squad_count} PLAYERS
            </Eyebrow>
            <h1>
              Pick your <em>Playing XI.</em>
            </h1>
            <p>
              Choose your eleven manually, then set the exact batting order.
            </p>
          </div>
        </section>
        <div className="builder-summary">
          <div>
            <small>SELECTED</small>
            <strong>
              {selected.length}
              <i>/11</i>
            </strong>
          </div>
          <div>
            <small>OVERSEAS</small>
            <strong>
              {overseas}
              <i>/4</i>
            </strong>
          </div>
          <div>
            <small>KEEPER</small>
            <strong className={hasKeeper ? "ok" : "warn"}>
              {hasKeeper ? "READY" : "NEEDED"}
            </strong>
          </div>
          <div>
            <small>BOWLING</small>
            <strong className={bowlers >= 4 ? "ok" : "warn"}>
              {bowlers}
              <i>/4+</i>
            </strong>
          </div>
        </div>
        <div className="validation-row">
          <Chip tone={selected.length === 11 ? "green" : "neutral"}>
            {selected.length === 11 ? <Check size={13} /> : "○"} Exactly 11
          </Chip>
          <Chip tone={overseas <= 4 ? "green" : "red"}>
            {overseas <= 4 ? <Check size={13} /> : "!"} Max 4 overseas
          </Chip>
          <Chip tone={hasKeeper ? "green" : "red"}>
            {hasKeeper ? <Check size={13} /> : "!"} Wicketkeeper
          </Chip>
          <Chip tone={bowlers >= 4 ? "green" : "red"}>
            {bowlers >= 4 ? <Check size={13} /> : "!"} Bowling coverage
          </Chip>
        </div>
        <div className="builder-mobile-tabs">
          <SegmentedTabs
            value={tab}
            onChange={setTab}
            items={[
              { value: "squad", label: "Squad", icon: <Users size={15} /> },
              {
                value: "order",
                label: "Batting order",
                icon: <Trophy size={15} />,
              },
            ]}
          />
        </div>
        <div className="builder-grid">
          <Surface
            className={`squad-panel ${tab === "order" ? "mobile-hidden-panel" : ""}`}
          >
            <div className="panel-heading">
              <div>
                <Eyebrow accent={false}>YOUR AUCTION SQUAD</Eyebrow>
                <h2>Choose your XI</h2>
              </div>
            </div>
            <div className="squad-list redesigned-squad-list">
              {groups.map((group) => (
                <section className="role-group" key={group.role}>
                  <h3>
                    {group.role} <span>({group.players.length})</span>
                  </h3>
                  {group.players.map((player) => (
                    <button
                      className={`squad-player redesigned-player ${selected.includes(player.id) ? "picked" : ""}`}
                      key={player.id}
                      onClick={() => toggle(player.id)}
                    >
                      <span className="player-initial">
                        {player.full_name.charAt(0)}
                      </span>
                      <span className="player-info">
                        <b>{player.full_name}</b>
                        <small>
                          {group.role} · {player.country}
                          {player.overseas ? " · OVERSEAS" : ""}
                        </small>
                      </span>
                      <span className="player-price">
                        {formatAuctionPrice(player.purchase_price_lakh)}
                      </span>
                      {selected.includes(player.id) && <Check size={17} />}
                    </button>
                  ))}
                </section>
              ))}
            </div>
          </Surface>
          <Surface
            className={`order-panel ${tab === "squad" ? "mobile-hidden-panel" : ""}`}
          >
            <div className="panel-heading">
              <div>
                <Eyebrow accent={false}>MATCHDAY PLAN</Eyebrow>
                <h2>Batting order</h2>
              </div>
            </div>
            {selected.length !== 11 ? (
              <div className="order-empty">
                <Trophy size={25} />
                <strong>Choose eleven players first</strong>
                <p>Then arrange the exact order your team will use.</p>
              </div>
            ) : (
              <div className="batting-order redesigned-order">
                {chosen.map((player, index) => (
                  <div
                    className={`order-row redesigned-order-row ${dragging === player.id ? "dragging" : ""}`}
                    draggable={!workspace.squad.xi_locked}
                    onDragStart={() => setDragging(player.id)}
                    onDragOver={(event) => event.preventDefault()}
                    onDrop={() => drop(player.id)}
                    key={player.id}
                  >
                    <span className="drag-handle">
                      <GripVertical size={15} />
                    </span>
                    <b>{index + 1}</b>
                    <span className="order-player">
                      <strong>{player.full_name}</strong>
                      <small>{normalizePublicRole(player)}</small>
                    </span>
                    <button
                      aria-label="Move player up"
                      disabled={index === 0 || workspace.squad.xi_locked}
                      onClick={() => move(index, -1)}
                    >
                      <ChevronUp size={15} />
                    </button>
                    <button
                      aria-label="Move player down"
                      disabled={
                        index === chosen.length - 1 || workspace.squad.xi_locked
                      }
                      onClick={() => move(index, 1)}
                    >
                      <ChevronDown size={15} />
                    </button>
                  </div>
                ))}
              </div>
            )}
            {selected.length === 11 && !workspace.squad.xi_locked && (
              <>
                <button
                  className="secondary-button full-width"
                  disabled={busy}
                  onClick={() => void run("SAVE_XI", { player_ids: selected })}
                >
                  Save Playing XI
                </button>
                <button
                  className="primary-button full-width"
                  disabled={busy || !legal}
                  onClick={() => {
                    if (
                      window.confirm(
                        "Lock this XI and batting order for the tournament?",
                      )
                    )
                      void lock();
                  }}
                >
                  <Lock size={15} /> Lock Team
                </button>
              </>
            )}
            {workspace.squad.xi_locked && (
              <div className="locked-banner redesigned-locked">
                <ShieldCheck size={17} />
                <div>
                  <strong>PLAYING XI LOCKED</strong>
                  <small>
                    {workspace.all_ready
                      ? "All qualified teams are ready."
                      : "Waiting for the other qualified teams."}
                  </small>
                </div>
              </div>
            )}
          </Surface>
        </div>
        {
          <section className="tournament-readiness">
            <Eyebrow>TOURNAMENT READINESS</Eyebrow>
            <div className="readiness-list">
              {workspace.qualified_teams.map((team) => (
                <div key={team.squad_id}>
                  <TeamMark code={team.franchise_code} size="sm" />
                  <strong>{team.franchise_code}</strong>
                  <span className={team.xi_locked ? "ready" : "selecting"}>
                    {team.xi_locked ? "READY" : "SELECTING"}
                  </span>
                </div>
              ))}
            </div>
            <p className="readiness-count">
              {workspace.locked_qualified_count} / {workspace.qualified_count}{" "}
              TEAMS READY
            </p>
            {workspace.all_ready && session.isHost ? (
              <>
                {!workspace.stats_ready && (
                  <div className="stats-blocked-banner" role="status">
                    <strong>PLAYER PERFORMANCE DATA NOT READY</strong>
                    <span>
                      Verified profiles: {workspace.verified_profiles} / {workspace.total_profiles}
                    </span>
                    <span>Missing: {workspace.missing_profiles}</span>
                    <small>
                      Tournament start will unlock when verified performance data is complete.
                    </small>
                  </div>
                )}
                <button
                  className="primary-button full-width"
                  disabled={busy || !workspace.stats_ready}
                  onClick={() => void start()}
                >
                  <Trophy size={16} /> START TOURNAMENT
                </button>
              </>
            ) : workspace.all_ready ? (
              <div className="success-banner">
                ALL TEAMS READY · Waiting for host to start.
              </div>
            ) : (
              <p className="muted">Waiting for every qualified team to lock.</p>
            )}
            <small className="stats-note">
              Performance database: {workspace.verified_profiles} /{" "}
              {workspace.total_profiles} verified profiles · {workspace.missing_profiles} still need verified data
            </small>
          </section>
        }
        {error && <p className="error-banner">{error}</p>}
      </div>
    </main>
  );
}
