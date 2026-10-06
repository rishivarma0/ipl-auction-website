import { NextResponse } from "next/server";
import { callRpc } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { action: "create" | "join"; displayName: string; franchiseCode?: string; minimumSquadSize?: number; timerSeconds?: number; privacy?: string; roomCode?: string; sessionKey?: string };
    const result = body.action === "create"
      ? await callRpc("create_auction_room", { p_display_name: body.displayName, p_franchise_code: body.franchiseCode, p_minimum_squad_size: body.minimumSquadSize, p_timer_seconds: body.timerSeconds, p_privacy: body.privacy ?? "PRIVATE" })
      : await callRpc("join_auction_room", { p_room_code: body.roomCode, p_display_name: body.displayName, p_session_key: body.sessionKey ?? null });
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "REQUEST_FAILED" }, { status: 400 });
  }
}
