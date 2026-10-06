import { NextResponse } from "next/server";
import { callPostAuctionGateway } from "@/lib/supabase-server";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { roomId: string; sessionKey: string };
    if (typeof body.roomId !== "string" || !body.roomId || typeof body.sessionKey !== "string" || !body.sessionKey) return NextResponse.json({ error: "INVALID_REQUEST" }, { status: 400 });
    return NextResponse.json(await callPostAuctionGateway({ roomId: body.roomId, sessionKey: body.sessionKey, operation: "tournament" }));
  } catch (error) {
    const status = typeof error === "object" && error && "status" in error && typeof error.status === "number" ? error.status : 403;
    return NextResponse.json({ error: error instanceof Error ? error.message : "TOURNAMENT_SNAPSHOT_FAILED" }, { status });
  }
}
