import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const secret = Deno.env.get("SUPABASE_SECRET_KEYS") ?? Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, secret, { auth: { autoRefreshToken: false, persistSession: false } });
const allowedOrigins = ["http://localhost:3000", "https://ipl-auction-website.vercel.app"];
const cors = (origin: string | null) => ({ "Access-Control-Allow-Origin": origin && allowedOrigins.includes(origin) ? origin : "https://ipl-auction-website.vercel.app", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" });

const hostCommands = new Set(["HOST_AUTO_LOCK", "CALCULATE_OVR", "START_TOURNAMENT", "SIMULATE_TOURNAMENT"]);
const teamCommands = new Set(["AUTO_PICK_XI", "AUTO_SET_ORDER", "SAVE_XI", "SAVE_BATTING_ORDER", "LOCK_TEAM"]);

async function authorize(roomId: unknown, sessionKey: unknown, hostRequired = false) {
  if (typeof roomId !== "string" || typeof sessionKey !== "string" || !roomId || !sessionKey) throw new Error("ROOM_SESSION_INVALID");
  const [{ data: room }, { data: member }] = await Promise.all([
    admin.from("rooms").select("id,host_member_id,status").eq("id", roomId).maybeSingle(),
    admin.from("room_members").select("id,room_id,franchise_id,status").eq("room_id", roomId).eq("session_key", sessionKey).maybeSingle(),
  ]);
  if (!room || !member || member.status === "LEFT" || member.room_id !== room.id) throw new Error("ROOM_SESSION_INVALID");
  const isHost = member.id === room.host_member_id;
  if (hostRequired && !isHost) throw new Error("NOT_HOST");
  return { room, member, isHost };
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (request.method !== "POST") return Response.json({ error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: cors(origin) });
  try {
    const body = await request.json() as { roomId?: string; sessionKey?: string; operation?: string; command?: string; payload?: Record<string, unknown> };
    const roomId = body.roomId; const sessionKey = body.sessionKey; const operation = body.operation ?? "action"; const command = body.command?.toUpperCase();
    if (operation === "workspace" || operation === "tournament") {
      await authorize(roomId, sessionKey);
      const rpc = operation === "workspace" ? "get_team_workspace" : "get_tournament_snapshot";
      const { data, error } = await admin.rpc(rpc, { p_room_id: roomId, p_session_key: sessionKey });
      if (error) throw new Error(error.message);
      return Response.json(data, { headers: cors(origin) });
    }
    if (!command || (!hostCommands.has(command) && !teamCommands.has(command))) throw new Error("UNKNOWN_AUCTION_COMMAND");
    const auth = await authorize(roomId, sessionKey, hostCommands.has(command));
    if (teamCommands.has(command) && !auth.member.franchise_id) throw new Error("NOT_TEAM_OWNER");
    const { data, error } = await admin.rpc("post_auction_command", { p_room_id: roomId, p_session_key: sessionKey, p_command: command, p_payload: body.payload ?? {} });
    if (error) throw new Error(error.message);
    return Response.json(data, { headers: cors(origin) });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "POST_AUCTION_GATEWAY_FAILED" }, { status: 403, headers: cors(origin) });
  }
});
