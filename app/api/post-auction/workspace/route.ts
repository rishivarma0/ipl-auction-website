import { NextResponse } from "next/server";
import { authorizeRoomSession, callAdminRpc } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { roomId: string; sessionKey: string };
    await authorizeRoomSession(body.roomId, body.sessionKey);
    return NextResponse.json(await callAdminRpc("get_team_workspace", { p_room_id: body.roomId, p_session_key: body.sessionKey }));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "WORKSPACE_FAILED" }, { status: 403 });
  }
}
