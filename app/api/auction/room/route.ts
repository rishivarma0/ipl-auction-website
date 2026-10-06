import { NextResponse } from "next/server";
import { callRpc } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { action: "create" | "join"; displayName: string; franchiseCode?: string; minimumSquadSize?: number; timerSeconds?: number; privacy?: string; roomCode?: string; sessionKey?: string };
    const result = body.action === "create"
      ? await callRpc("create_auction_room", { p_display_name: body.displayName, p_franchise_code: body.franchiseCode ?? null, p_minimum_squad_size: body.minimumSquadSize, p_timer_seconds: body.timerSeconds, p_privacy: body.privacy ?? "PRIVATE" })
      : await callRpc("join_auction_room", { p_room_code: body.roomCode, p_display_name: body.displayName, p_session_key: body.sessionKey ?? null });
    const session = result as { room_id: string; room_code: string; member_id: string; session_key: string; is_host: boolean };
    return NextResponse.json({ roomId: session.room_id, roomCode: session.room_code, memberId: session.member_id, sessionKey: session.session_key, isHost: session.is_host });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "REQUEST_FAILED" }, { status: 400 });
  }
}
