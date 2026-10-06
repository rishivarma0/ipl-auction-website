import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
function getServerSecret() {
  const direct = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (direct) return direct;
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const defaultKey = typeof parsed.default === "string" ? parsed.default : null;
      if (defaultKey) return defaultKey;
      const firstKey = Object.values(parsed).find((value): value is string => typeof value === "string" && value.length > 0);
      if (firstKey) return firstKey;
    } catch {
      // The hosted project may expose this as JSON; never use the raw JSON as a key.
    }
  }
  throw new Error("SUPABASE_SERVER_SECRET_MISSING");
}

const admin = createClient(supabaseUrl, getServerSecret(), { auth: { autoRefreshToken: false, persistSession: false } });
const allowedOrigins = new Set(["http://localhost:3000", "https://ipl-auction-website-one.vercel.app"]);
const cors = (origin: string | null) => ({
  ...(origin && allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}),
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

class GatewayError extends Error {
  constructor(public code: string, public status = 403) { super(code); }
}

const hostCommands = new Set(["HOST_AUTO_LOCK", "CALCULATE_OVR", "START_TOURNAMENT", "SIMULATE_TOURNAMENT"]);
const teamCommands = new Set(["AUTO_PICK_XI", "AUTO_SET_ORDER", "SAVE_XI", "SAVE_BATTING_ORDER", "LOCK_TEAM"]);

async function authorize(roomId: unknown, sessionKey: unknown, hostRequired = false) {
  if (typeof roomId !== "string" || typeof sessionKey !== "string" || !roomId || !sessionKey) throw new GatewayError("ROOM_SESSION_INVALID");
  const { data: room, error: roomError } = await admin.from("rooms").select("id,host_member_id,status").eq("id", roomId).maybeSingle();
  if (roomError) throw new GatewayError("POST_AUCTION_GATEWAY_INTERNAL", 500);
  if (!room) throw new GatewayError("ROOM_SESSION_INVALID");
  const { data: memberId, error: sessionError } = await admin.rpc("assert_room_session", { p_room_id: roomId, p_session_key: sessionKey });
  if (sessionError) {
    if (sessionError.message.includes("ROOM_SESSION_INVALID")) throw new GatewayError("ROOM_SESSION_INVALID");
    throw new GatewayError("POST_AUCTION_GATEWAY_INTERNAL", 500);
  }
  const { data: member, error: memberError } = await admin.from("room_members").select("id,room_id,franchise_id,status").eq("id", memberId).maybeSingle();
  if (memberError) throw new GatewayError("POST_AUCTION_GATEWAY_INTERNAL", 500);
  if (!member || member.status === "LEFT" || member.room_id !== room.id) throw new GatewayError("ROOM_SESSION_INVALID");
  const isHost = member.id === room.host_member_id;
  if (hostRequired && !isHost) throw new GatewayError("NOT_HOST");
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
    if (!command || (!hostCommands.has(command) && !teamCommands.has(command))) throw new GatewayError("UNKNOWN_AUCTION_COMMAND", 400);
    const auth = await authorize(roomId, sessionKey, hostCommands.has(command));
    if (teamCommands.has(command) && !auth.member.franchise_id) throw new GatewayError("NOT_TEAM_OWNER");
    const { data, error } = await admin.rpc("post_auction_command", { p_room_id: roomId, p_session_key: sessionKey, p_command: command, p_payload: body.payload ?? {} });
    if (error) throw new Error(error.message);
    return Response.json(data, { headers: cors(origin) });
  } catch (error) {
    const gatewayError = error instanceof GatewayError ? error : new GatewayError("POST_AUCTION_GATEWAY_INTERNAL", 500);
    if (gatewayError.status >= 500) console.error(`post-auction-gateway:${gatewayError.code}`);
    return Response.json({ error: gatewayError.code }, { status: gatewayError.status, headers: cors(origin) });
  }
});
