"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, Gavel, Pause, Play, Square, Timer, Users } from "lucide-react";
import { formatAuctionPrice, getNextBidAmount } from "@/lib/auction-pricing";
import { getRoomSession, type RoomSession } from "@/lib/room-session";
import { supabaseBrowser } from "@/lib/supabase-browser";
import type { RoomSnapshot } from "@/lib/auction-room";

const friendlyErrors: Record<string, string> = {
  AUCTION_PAUSED: "The auction is paused by the host.", AUCTION_NOT_RUNNING: "The auction is not running.", STALE_PLAYER: "This player has already changed. Refreshing the room.",
  ALREADY_HIGHEST_BIDDER: "You already hold the highest bid.", INSUFFICIENT_PURSE: "That bid would exceed your remaining purse.", MINIMUM_SQUAD_RESERVE_REQUIRED: "Keep enough purse to complete the minimum squad.",
  SQUAD_LIMIT_REACHED: "Your squad is full — 25/25.", OVERSEAS_LIMIT_REACHED: "Overseas squad limit reached — 8/8.", NOT_HOST: "Only the host can do that.",
};
const messageFor = (raw: string) => friendlyErrors[raw.match(/[A-Z_]{4,}/)?.[0] ?? raw] ?? raw;

async function snapshotFor(session: RoomSession) {
  const response = await fetch("/api/auction/snapshot", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ roomId: session.roomId, sessionKey: session.sessionKey }) });
  const json = await response.json() as RoomSnapshot & { error?: string };
  if (!response.ok) throw new Error(json.error ?? "ROOM_UNAVAILABLE");
  return json as RoomSnapshot;
}

async function invoke(session: RoomSession, action: string, playerId?: string, franchiseCode?: string) {
  const response = await fetch("/api/auction/action", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action, roomId: session.roomId, sessionKey: session.sessionKey, playerId, franchiseCode }) });
  const json = await response.json() as { error?: string };
  if (!response.ok) throw new Error(json.error ?? "ACTION_FAILED");
}

function useRoomSnapshot() {
  const [session] = useState<RoomSession | null>(() => getRoomSession());
  const [snapshot, setSnapshot] = useState<RoomSnapshot | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async () => { if (!session) return; try { setSnapshot(await snapshotFor(session)); setError(""); } catch (e) { setError(messageFor(e instanceof Error ? e.message : "ROOM_UNAVAILABLE")); } }, [session]);
  useEffect(() => { const id = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(id); }, [load]);
  useEffect(() => {
    if (!session) return;
    const channel = supabaseBrowser.channel(`room:${session.roomId}`).on("broadcast", { event: "auction_changed" }, () => void load()).subscribe();
    const interval = window.setInterval(() => void load(), 1000);
    return () => { window.clearInterval(interval); void supabaseBrowser.removeChannel(channel); };
  }, [session, load]);
  const run = async (name: string, playerId?: string, franchiseCode?: string) => { if (!session) return; try { await invoke(session, name, playerId, franchiseCode); await load(); } catch (e) { setError(messageFor(e instanceof Error ? e.message : "ACTION_FAILED")); } };
  return { session, snapshot, error, load, run };
}

function Header({ status, roomCode }: { status: string; roomCode: string }) {
  return <nav className="topbar"><Link className="brand" href="/"><span className="brand-mark"><Gavel size={17} /></span><span>AUCTION<br /><i>ROOM</i></span></Link><span className="topbar-status"><span className="live-dot" /> {status} · {roomCode}</span><Link href="/" className="nav-link">Exit room</Link></nav>;
}

export function LobbyRoom() {
  const { session, snapshot, error, run } = useRoomSnapshot();
  if (!session || !snapshot) return <main className="site-shell"><section className="form-shell"><p className="eyebrow"><span /> RECONNECTING</p><h1>Returning to<br /><em>the lobby.</em></h1><p className="muted">{error || "Restoring your room session…"}</p><Link href="/join" className="lime-button">Join a room</Link></section></main>;
  return <main className="site-shell"><Header status="WAITING LOBBY" roomCode={snapshot.room.room_code} /><section className="form-shell"><div className="form-head"><p className="eyebrow"><span /> ROOM READY FOR LIFTOFF</p><h1>Waiting for<br /><em>the room.</em></h1><p>Invite your friends, claim your colours, and get ready to bid.</p></div><div className="room-card"><div className="panel"><p className="eyebrow">ROOM CODE</p><div className="room-code">{snapshot.room.room_code}</div><button className="outline-button" onClick={() => navigator.clipboard?.writeText(`${window.location.origin}/join?room=${snapshot.room.room_code}`)}>Copy invite link</button><div className="room-list" style={{ marginTop: 25 }}>{snapshot.members.map(member => <div key={member.id}><span><b>{member.franchise_code ?? "OPEN"}</b> · {member.display_name}</span><b style={{ color: "var(--lime)" }}>{member.is_host ? "HOST" : "READY"}</b></div>)}</div></div><div className="panel"><p className="eyebrow">AUCTION CONFIG</p><div className="room-list"><div><span>Status</span><b>{snapshot.room.status}</b></div><div><span>Minimum squad</span><b>{snapshot.room.minimum_squad_size} players</b></div><div><span>Maximum squad</span><b>25 players</b></div><div><span>Starting purse</span><b>₹120 CR</b></div><div><span>Player database</span><b>620 players</b></div></div>{snapshot.self.franchise_id === null && snapshot.room.status === "WAITING" && <label className="field">Choose franchise<select defaultValue="" onChange={event => { if (event.target.value) void run("choose", undefined, event.target.value); }}><option value="" disabled>Select an available franchise</option>{["RCB", "MI", "CSK", "KKR", "SRH", "RR", "DC", "PBKS", "GT", "LSG"].filter(code => !snapshot.members.some(member => member.franchise_code === code)).map(code => <option key={code} value={code}>{code}</option>)}</select></label>}{session.isHost && snapshot.room.status === "WAITING" ? <button className="lime-button full-button" onClick={() => void run("start")}>Start auction <Play size={17} /></button> : snapshot.room.status !== "WAITING" ? <Link href="/auction" className="lime-button full-button">Open auction <ArrowLeft size={17} /></Link> : <p className="muted"><Users size={13} /> Only the host can start.</p>}</div></div>{error && <p className="error-banner">{error}</p>}</section></main>;
}

export function AuctionRoom() {
  const { session, snapshot, error, load, run } = useRoomSnapshot();
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { const id = window.setInterval(() => setNow(Date.now()), 100); return () => window.clearInterval(id); }, []);
  const current = useMemo(() => snapshot?.current_set_players.find(player => player.id === snapshot.state.current_player_id), [snapshot]);
  if (!session || !snapshot) return <main className="site-shell"><section className="form-shell"><p className="eyebrow"><span /> RECONNECTING</p><h1>Returning to<br /><em>the auction.</em></h1><p className="muted">{error || "Restoring the authoritative room state…"}</p></section></main>;
  const squad = snapshot.squads.find(item => item.franchise_id === snapshot.self.franchise_id);
  const remaining = snapshot.state.timer_ends_at ? Math.max(0, new Date(snapshot.state.timer_ends_at).getTime() - now) : snapshot.state.timer_remaining_ms_when_paused ?? 0;
  const nextBid = snapshot.state.current_bid_lakh === 0 ? current?.base_price_lakh ?? 0 : getNextBidAmount(snapshot.state.current_bid_lakh);
  const highestCode = snapshot.squads.find(item => item.franchise_id === snapshot.state.highest_bidder_team_id)?.franchise_code;
  return <main className="site-shell"><Header status="LIVE AUCTION" roomCode={snapshot.room.room_code} /><section className="auction-layout"><aside className="panel auction-side"><p className="eyebrow">YOUR FRANCHISE</p><h2>{snapshot.self.franchise_code ?? "UNASSIGNED"}</h2><div className="big-money">{formatAuctionPrice(squad?.purse_remaining_lakh ?? 12000)}</div><div className="room-list"><div><span>Squad</span><b>{squad?.squad_count ?? 0} / 25</b></div><div><span>Overseas</span><b>{squad?.overseas_count ?? 0} / 8</b></div><div><span>Minimum</span><b>{snapshot.room.minimum_squad_size}</b></div></div>{session.isHost && snapshot.state.status === "RUNNING" && <button className="outline-button full-button" onClick={() => void run("pause")}><Pause size={15} /> Pause auction</button>}{session.isHost && snapshot.state.status === "PAUSED" && <button className="lime-button full-button" onClick={() => void run("resume")}><Play size={15} /> Resume auction</button>}{session.isHost && ["RUNNING", "PAUSED"].includes(snapshot.state.status) && <button className="danger-button full-button" onClick={() => { if (window.confirm("Are you sure you want to end the auction? This is irreversible.")) void run("end"); }}><Square size={15} /> End auction</button>}</aside><section className="auction-center"><div className="auction-kicker"><span className="eyebrow"><span /> SET {snapshot.state.current_set_code ?? "—"}</span><span className="muted">{snapshot.current_set_players.filter(p => ["SOLD", "UNSOLD"].includes(p.status)).length} / {snapshot.current_set_players.length} completed</span></div>{current ? <div className="current-card panel"><div className="player-orb large-orb">♛</div><p className="eyebrow">CURRENT PLAYER · {current.country.toUpperCase()}</p><h1>{current.full_name}</h1><p className="role-line">{current.specialism} · {current.overseas ? "OVERSEAS" : "INDIAN"}</p><div className="auction-numbers"><div><span className="kicker">BASE PRICE</span><strong>{formatAuctionPrice(current.base_price_lakh)}</strong></div><div><span className="kicker">CURRENT BID</span><strong>{formatAuctionPrice(snapshot.state.current_bid_lakh || current.base_price_lakh)}</strong></div><div className="timer"><Timer size={17} /><b>{String(Math.floor(remaining / 1000)).padStart(2, "0")}</b><span>{snapshot.state.status === "PAUSED" ? "PAUSED" : "seconds"}</span></div></div><p className="highest">Highest bidder: <b>{highestCode ?? "OPEN BID"}</b></p><button className="bid-button" disabled={snapshot.state.status !== "RUNNING" || snapshot.state.highest_bidder_team_id === snapshot.self.franchise_id} onClick={() => void run("bid", current.id)}>BID {formatAuctionPrice(nextBid)} <small>+{formatAuctionPrice(nextBid - snapshot.state.current_bid_lakh)}</small></button></div> : <div className="panel current-card"><h1>{snapshot.state.status}</h1><button className="outline-button" onClick={() => void load()}>Refresh state</button></div>}<p className="error-banner">{error}</p></section><aside className="panel set-panel"><p className="eyebrow">PLAYERS IN SET · {snapshot.state.current_set_code}</p><div className="set-player-list">{snapshot.current_set_players.map(player => <div key={player.id}><span>{player.full_name}</span><b className={player.status.toLowerCase()}>{player.status === "SOLD" ? `SOLD ${formatAuctionPrice(player.sale_price_lakh ?? 0)}` : player.status}</b></div>)}</div></aside><aside className="panel activity-panel"><p className="eyebrow">LIVE ACTIVITY</p>{snapshot.events.slice(0, 12).map(event => <div className="activity-item" key={event.id}><b>{event.event_type.replaceAll("_", " ")}</b><span>{event.amount_lakh ? formatAuctionPrice(event.amount_lakh) : new Date(event.created_at).toLocaleTimeString()}</span></div>)}</aside></section></main>;
}
