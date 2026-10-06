import { NextResponse } from "next/server";
import { broadcastRoom, callRpc } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { action: string; roomId: string; sessionKey: string; playerId?: string; franchiseCode?: string; timerSeconds?: number };
    if (typeof body.roomId !== "string" || !body.roomId || typeof body.sessionKey !== "string" || !body.sessionKey) return NextResponse.json({ error: "INVALID_REQUEST" }, { status: 400 });
    const args = { p_room_id: body.roomId, p_session_key: body.sessionKey };
    const result = body.action === "choose" ? await callRpc("choose_franchise_by_code", { ...args, p_franchise_code: body.franchiseCode })
      : body.action === "start" ? await callRpc("start_auction", args)
      : body.action === "pause" ? await callRpc("pause_auction", args)
        : body.action === "resume" ? await callRpc("resume_auction", args)
          : body.action === "end" ? await callRpc("end_auction", args)
          : body.action === "bid" ? await callRpc("place_bid", { ...args, p_expected_player_id: body.playerId })
            : body.action === "set_timer" ? await callRpc("set_auction_timer", { ...args, p_timer_seconds: body.timerSeconds })
            : await callRpc("heartbeat_auction_member", args);
    await broadcastRoom(body.roomId, "auction_changed");
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "ACTION_FAILED" }, { status: 400 });
  }
}
