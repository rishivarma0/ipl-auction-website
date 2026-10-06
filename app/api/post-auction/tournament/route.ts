import { NextResponse } from "next/server";
import { callPostAuctionGateway } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { roomId: string; sessionKey: string };
    return NextResponse.json(await callPostAuctionGateway({ roomId: body.roomId, sessionKey: body.sessionKey, operation: "tournament" }));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "TOURNAMENT_SNAPSHOT_FAILED" }, { status: 403 });
  }
}
