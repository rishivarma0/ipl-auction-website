"use client";

import { useEffect, useState } from "react";
import { TeamBuilder } from "@/components/team-builder";
import { TournamentDashboard } from "@/components/tournament-dashboard";
import { getRoomSession, type RoomSession } from "@/lib/room-session";

export default function TeamHubPage() {
  const [session] = useState<RoomSession | null>(() => getRoomSession());
  const [status, setStatus] = useState<string | null>(null);

  useEffect(() => {
    if (!session) return;
    void fetch("/api/auction/snapshot", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ roomId: session.roomId, sessionKey: session.sessionKey }) })
      .then(response => response.json() as Promise<{ room?: { status?: string } }>)
      .then(snapshot => setStatus(snapshot.room?.status ?? "QUALIFICATION"))
      .catch(() => setStatus("QUALIFICATION"));
  }, [session]);

  if (status === "SIMULATING" || status === "COMPLETED") return <TournamentDashboard />;
  return <TeamBuilder />;
}
