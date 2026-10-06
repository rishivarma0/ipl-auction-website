import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}

export const supabaseServer = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
});

let adminClient: ReturnType<typeof createClient> | null = null;

export function getSupabaseAdmin() {
  const secret = process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !secret) throw new Error("SERVER_SUPABASE_SECRET_NOT_CONFIGURED");
  if (!adminClient) {
    adminClient = createClient(url, secret, { auth: { autoRefreshToken: false, persistSession: false } });
  }
  return adminClient;
}

export async function callRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabaseServer.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export async function callAdminRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await (getSupabaseAdmin().rpc as unknown as (rpcName: string, rpcArgs: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>)(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export type AuthorizedRoomSession = { roomId: string; memberId: string; franchiseId: string | null; isHost: boolean; status: string };
type AdminRow = Record<string, unknown>;
type AdminQuery = { select: (columns: string) => AdminFilter };
type AdminFilter = { eq: (column: string, value: unknown) => AdminFilter; maybeSingle: () => Promise<{ data: AdminRow | null; error: { message: string } | null }> };

export async function authorizeRoomSession(roomId: unknown, sessionKey: unknown, requireHost = false): Promise<AuthorizedRoomSession> {
  if (typeof roomId !== "string" || typeof sessionKey !== "string" || !roomId || !sessionKey) throw new Error("ROOM_SESSION_INVALID");
  const admin = getSupabaseAdmin() as unknown as { from: (table: string) => AdminQuery };
  const [{ data: room, error: roomError }, { data: member, error: memberError }] = await Promise.all([
    admin.from("rooms").select("id,host_member_id,status").eq("id", roomId).maybeSingle(),
    admin.from("room_members").select("id,room_id,franchise_id,status").eq("room_id", roomId).eq("session_key", sessionKey).maybeSingle(),
  ]);
  if (roomError || memberError || !room || !member || member.status === "LEFT") throw new Error("ROOM_SESSION_INVALID");
  const authorized = { roomId, memberId: member.id as string, franchiseId: member.franchise_id as string | null, isHost: member.id === room.host_member_id, status: room.status as string };
  if (requireHost && !authorized.isHost) throw new Error("NOT_HOST");
  return authorized;
}

export async function broadcastRoom(roomId: string, event: string) {
  const channel = supabaseServer.channel(`room:${roomId}`);
  await channel.send({ type: "broadcast", event, payload: { roomId, event } });
  await supabaseServer.removeChannel(channel);
}
