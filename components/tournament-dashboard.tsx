"use client";

import Link from "next/link";
import { ArrowLeft, Gavel, Play, Trophy } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { getRoomSession, type RoomSession } from "@/lib/room-session";
import {
  Chip,
  Eyebrow,
  Surface,
  TeamMark,
} from "@/components/ui/auction-primitives";

type Snapshot = {
  stats_total_profiles: number;
  stats_verified_profiles: number;
  stats_missing_profiles: number;
  stats_ready: boolean;
  teams: Array<{
    franchise_code: string;
    team_ovr: number | null;
    qualification_status: string;
    xi_locked: boolean;
  }>;
  tournament: { status?: string; champion_franchise_id?: string | null } | null;
  matches: Array<{
    stage: string;
    match_number: number;
    home_franchise_id: string;
    away_franchise_id: string;
    home_score: string | null;
    away_score: string | null;
    result_text: string | null;
    conditions: string | null;
  }>;
  standings: Array<{
    franchise_code: string;
    played: number;
    won: number;
    lost: number;
    points: number;
    net_run_rate: number;
  }>;
};
async function readSnapshot(session: RoomSession) {
  const r = await fetch("/api/post-auction/tournament", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      roomId: session.roomId,
      sessionKey: session.sessionKey,
    }),
  });
  const data = (await r.json()) as { error?: string };
  if (!r.ok) throw new Error(data.error ?? "TOURNAMENT_FAILED");
  return data as unknown as Snapshot;
}
async function action(session: RoomSession, command: string) {
  const r = await fetch("/api/post-auction/action", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      roomId: session.roomId,
      sessionKey: session.sessionKey,
      command,
    }),
  });
  const data = (await r.json()) as { error?: string };
  if (!r.ok) throw new Error(data.error ?? "ACTION_FAILED");
  return data;
}
const teamFromId = (id: string, teams: Snapshot["teams"]) =>
  teams.find((team) => team.franchise_code === id)?.franchise_code ??
  id.slice(0, 4).toUpperCase();
const friendlyError = (error: unknown) => {
  const message = error instanceof Error ? error.message : "TOURNAMENT_FAILED";
  return message.includes("PLAYER_STATS_NOT_READY")
    ? "Tournament start is locked until verified player performance data is complete."
    : message;
};

export function TournamentDashboard() {
  const [session] = useState<RoomSession | null>(() => getRoomSession());
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    if (!session) return;
    try {
      setSnapshot(await readSnapshot(session));
      setError("");
    } catch (e) {
      setError(friendlyError(e));
    }
  }, [session]);
  useEffect(() => {
    const initial = window.setTimeout(() => void load(), 0);
    const id = window.setInterval(() => void load(), 2500);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(id);
    };
  }, [load]);
  const run = async (command: string) => {
    if (!session) return;
    setBusy(true);
    try {
      await action(session, command);
      await load();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };
  if (!session)
    return (
      <main className="app-background">
        <section className="loading-card">
          <Eyebrow>TOURNAMENT CENTRE</Eyebrow>
          <h1>
            Room session
            <br />
            <em>not found.</em>
          </h1>
          <Link href="/join" className="primary-button">
            Join a room
          </Link>
        </section>
      </main>
    );
  if (!snapshot)
    return (
      <main className="app-background">
        <section className="loading-card">
          <Eyebrow>TOURNAMENT CENTRE</Eyebrow>
          <h1>
            Loading the
            <br />
            <em>competition.</em>
          </h1>
          <p>{error || "Checking the room state…"}</p>
        </section>
      </main>
    );
  const completed = snapshot.matches.filter(
    (m) => m.home_score && m.away_score,
  );
  const playoff = completed.filter((m) => m.stage !== "LEAGUE");
  const qualified = snapshot.teams.filter(
    (team) => team.qualification_status === "QUALIFIED",
  );
  const canStart =
    session.isHost &&
    qualified.length >= 2 &&
    qualified.every((team) => team.xi_locked) &&
    !snapshot.tournament;
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
          <span className="room-pill-label">TOURNAMENT</span>
          <b>{session.roomCode}</b>
        </div>
        <Link href="/team" className="secondary-button compact-button">
          Team setup
        </Link>
      </nav>
      <div className="app-container tournament-container">
        <section className="tournament-hero">
          <div>
            <Eyebrow>{snapshot.tournament?.status ?? "READY"}</Eyebrow>
            <h1>
              From auction
              <br />
              <em>to champion.</em>
            </h1>
            <p>
              {qualified.length} qualified teams · saved results never reroll
              after refresh.
            </p>
          </div>
          <div className="tournament-actions">
            {canStart && (
              <button
                className="primary-button"
                disabled={busy || !snapshot.stats_ready}
                onClick={() => void run("START_TOURNAMENT")}
              >
                <Play size={15} /> Start tournament
              </button>
            )}
            {!snapshot.tournament && !canStart && (
              <span className="muted">
                Waiting for every qualified team to lock.
              </span>
            )}
          </div>
        </section>
        {!snapshot.stats_ready && !snapshot.tournament && session.isHost && (
          <div className="helper-banner" role="status">
            <strong>PLAYER PERFORMANCE DATA NOT READY</strong>
            <span>
              Verified profiles: {snapshot.stats_verified_profiles} / {snapshot.stats_total_profiles}
            </span>
            <span>Missing: {snapshot.stats_missing_profiles}</span>
            <small>
              Tournament start will unlock when verified performance data is complete.
            </small>
          </div>
        )}
        {error && <p className="error-banner">{error}</p>}
        {snapshot.tournament?.champion_franchise_id && (
          <section className="champion-card">
            <div className="champion-glow" />
            <Trophy size={34} />
            <Eyebrow accent={false}>CHAMPION</Eyebrow>
            <h2>
              {teamFromId(
                snapshot.tournament.champion_franchise_id,
                snapshot.teams,
              )}
            </h2>
            <p>
              The final result is saved and will remain unchanged after refresh.
            </p>
            <Chip tone="gold">🏆 Season winner</Chip>
          </section>
        )}
        <section className="strength-grid">
          {snapshot.tournament?.status === "COMPLETED" && (
            <Surface>
              <div className="panel-heading">
                <div>
                  <Eyebrow accent={false}>POWER RANKING</Eyebrow>
                  <h2>Team strength</h2>
                </div>
                <span className="muted">Hidden scores stay private</span>
              </div>
              <div className="ovr-grid">
                {snapshot.teams.map((team) => (
                  <div className="ovr-card" key={team.franchise_code}>
                    <div>
                      <TeamMark code={team.franchise_code} size="md" />
                      <div>
                        <strong>{team.franchise_code}</strong>
                        <small>
                          {team.xi_locked ? "XI locked" : "Selecting XI"}
                        </small>
                      </div>
                    </div>
                    <b>
                      {team.team_ovr ?? "—"}
                      <small>OVR</small>
                    </b>
                  </div>
                ))}
              </div>
            </Surface>
          )}
          <Surface>
            <div className="panel-heading">
              <div>
                <Eyebrow accent={false}>SEASON PROGRESS</Eyebrow>
                <h2>Match centre</h2>
              </div>
              <span className="muted">{completed.length} completed</span>
            </div>
            <div className="match-list modern-match-list">
              {completed.length ? (
                completed.slice(0, 5).map((match) => (
                  <article
                    className="modern-match-card"
                    key={match.match_number}
                  >
                    <div className="match-meta">
                      <span>
                        {match.stage} · MATCH {match.match_number}
                      </span>
                      <span>{match.conditions ?? "Balanced"}</span>
                    </div>
                    <div className="match-score">
                      <strong>
                        {teamFromId(match.home_franchise_id, snapshot.teams)}
                      </strong>
                      <b>{match.home_score ?? "—"}</b>
                      <span>vs</span>
                      <b>{match.away_score ?? "—"}</b>
                      <strong>
                        {teamFromId(match.away_franchise_id, snapshot.teams)}
                      </strong>
                    </div>
                    <small>{match.result_text ?? "Awaiting result"}</small>
                  </article>
                ))
              ) : (
                <div className="empty-state compact">
                  <span className="empty-state-mark">✦</span>
                  <p>
                    Matches will appear here once the host starts the
                    tournament.
                  </p>
                </div>
              )}
            </div>
          </Surface>
        </section>
        <Surface className="standings-surface">
          <div className="panel-heading">
            <div>
              <Eyebrow accent={false}>LEAGUE TABLE</Eyebrow>
              <h2>Points table</h2>
            </div>
            <span className="muted">Top four qualify for playoffs</span>
          </div>
          {snapshot.standings.length ? (
            <div className="standings-table">
              <div className="standings-head">
                <span>POS</span>
                <span>TEAM</span>
                <span>P</span>
                <span>W</span>
                <span>L</span>
                <span>PTS</span>
                <span>NRR</span>
              </div>
              {snapshot.standings.map((row, index) => (
                <div
                  className={`standings-row ${index < 4 ? "playoff-place" : ""}`}
                  key={row.franchise_code}
                >
                  <b>{index + 1}</b>
                  <span>
                    <TeamMark code={row.franchise_code} size="sm" />
                    {row.franchise_code}
                  </span>
                  <span>{row.played}</span>
                  <span>{row.won}</span>
                  <span>{row.lost}</span>
                  <strong>{row.points}</strong>
                  <span>{Number(row.net_run_rate ?? 0).toFixed(2)}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state compact">
              <p>League results will appear here.</p>
            </div>
          )}
        </Surface>
        <Surface className="playoff-surface">
          <div className="panel-heading">
            <div>
              <Eyebrow accent={false}>ROAD TO THE FINAL</Eyebrow>
              <h2>{playoff.length ? "Playoffs & final" : "Playoff bracket"}</h2>
            </div>
            <span className="muted">Qualifier · Eliminator · Final</span>
          </div>
          <div className="bracket">
            <div>
              <small>QUALIFIER 1</small>
              <strong>
                1st <span>vs</span> 2nd
              </strong>
              <p>Winner advances to final</p>
            </div>
            <div>
              <small>ELIMINATOR</small>
              <strong>
                3rd <span>vs</span> 4th
              </strong>
              <p>Winner faces Q1 loser</p>
            </div>
            <div>
              <small>QUALIFIER 2</small>
              <strong>
                Q1 loser <span>vs</span> Eliminator winner
              </strong>
              <p>
                {snapshot.tournament?.champion_franchise_id
                  ? "Champion crowned"
                  : "Winner faces Q1 loser"}
              </p>
            </div>
            <div className="final-bracket">
              <small>FINAL</small>
              <strong>🏆 Championship match</strong>
              <p>
                {snapshot.tournament?.champion_franchise_id
                  ? "Champion crowned"
                  : "Awaiting finalists"}
              </p>
            </div>
          </div>
        </Surface>
      </div>
    </main>
  );
}
