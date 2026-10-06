import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}

export const supabaseServer = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
});

export async function callRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabaseServer.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export async function broadcastRoom(roomId: string, event: string) {
  const channel = supabaseServer.channel(`room:${roomId}`);
  await channel.send({ type: "broadcast", event, payload: { roomId, event } });
  await supabaseServer.removeChannel(channel);
}
