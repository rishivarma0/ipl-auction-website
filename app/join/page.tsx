"use client";
import Link from "next/link";
import { ArrowLeft, ArrowRight, Gavel, Users } from "lucide-react";
import { useState } from "react";
import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { saveRoomSession, type RoomSession } from "@/lib/room-session";
function JoinForm() {
  const router = useRouter(); const params = useSearchParams(); const [code, setCode] = useState(params.get("room") ?? ""); const [name, setName] = useState(""); const [error, setError] = useState(""); const [busy, setBusy] = useState(false);
  const join = async () => { setBusy(true); setError(""); try { const response = await fetch("/api/auction/room", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "join", roomCode: code, displayName: name || "Guest" }) }); const json = await response.json() as RoomSession & { error?: string }; if (!response.ok) throw new Error(json.error); saveRoomSession(json); router.push("/lobby"); } catch (e) { setError(e instanceof Error ? e.message : "Unable to join room"); } finally { setBusy(false); } };
  return <main className="site-shell"><nav className="topbar"><Link className="brand" href="/"><span className="brand-mark"><Gavel size={17} /></span><span>AUCTION<br /><i>ROOM</i></span></Link><Link href="/" className="nav-link"><ArrowLeft size={14} /> Back home</Link></nav><section className="form-shell"><div className="form-head"><p className="eyebrow"><span /> JOIN A ROOM</p><h1>Step into<br /><em>the room.</em></h1><p>Enter the six-character code shared by your host. You’ll choose an available franchise after joining.</p></div><div className="panel" style={{ maxWidth: 520, marginTop: 42 }}><label className="field">Room code<input autoFocus value={code} onChange={e => setCode(e.target.value.toUpperCase())} placeholder="5PJJZB" maxLength={6} /></label><label className="field">Display name<input value={name} onChange={e => setName(e.target.value)} placeholder="Your name" maxLength={40} /></label><div className="form-actions"><span className="muted"><Users size={14} /> 10 franchises per room</span><button className="lime-button" disabled={busy || code.length !== 6} onClick={() => void join()}>{busy ? "Joining…" : "Join room"} <ArrowRight size={17} /></button></div>{error && <p className="error-banner">{error}</p>}</div></section></main>;
}

export default function JoinPage() { return <Suspense fallback={<main className="site-shell"><section className="form-shell"><p className="eyebrow"><span /> JOIN A ROOM</p><h1>Loading the<br /><em>room form.</em></h1></section></main>}><JoinForm /></Suspense>; }
