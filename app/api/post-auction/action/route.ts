import { NextResponse } from "next/server";
import { callPostAuctionGateway } from "@/lib/supabase-server";

const HOST_COMMANDS = new Set(["HOST_AUTO_LOCK", "CALCULATE_OVR", "START_TOURNAMENT", "SIMULATE_TOURNAMENT"]);
const TEAM_COMMANDS = new Set(["AUTO_PICK_XI", "AUTO_SET_ORDER", "SAVE_XI", "SAVE_BATTING_ORDER", "LOCK_TEAM"]);

export async function POST(request: Request) {
  try {
    const body = await request.json() as { roomId: string; sessionKey: string; command: string; payload?: Record<string, unknown> };
    const command = body.command?.toUpperCase();
    if (!HOST_COMMANDS.has(command) && !TEAM_COMMANDS.has(command)) throw new Error("UNKNOWN_AUCTION_COMMAND");
    const result = await callPostAuctionGateway({ roomId: body.roomId, sessionKey: body.sessionKey, operation: "action", command, payload: body.payload ?? {} });
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "POST_AUCTION_ACTION_FAILED" }, { status: 403 });
  }
}
