import { NextResponse } from "next/server";
import { broadcastRoom, callRpc } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { roomId: string; sessionKey: string };
    const settled = await callRpc<{ advanced?: boolean }>("settle_current_player", { p_room_id: body.roomId, p_session_key: body.sessionKey });
    if (settled?.advanced) await broadcastRoom(body.roomId, "auction_changed");
    const snapshot = await callRpc("get_auction_snapshot", { p_room_id: body.roomId, p_session_key: body.sessionKey });
    return NextResponse.json(snapshot);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "SNAPSHOT_FAILED" }, { status: 400 });
  }
}
