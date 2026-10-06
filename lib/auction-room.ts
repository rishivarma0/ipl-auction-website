export type RoomSnapshot = {
  room: { id: string; room_code: string; status: string; minimum_squad_size: number; maximum_squad_size: number; starting_purse_lakh: number; auction_timer_seconds: number; privacy: string };
  state: { status: string; current_set_no: number | null; current_set_code: string | null; current_player_id: string | null; current_bid_lakh: number; highest_bidder_team_id: string | null; highest_bidder_team_code?: string | null; timer_ends_at: string | null; timer_remaining_ms_when_paused: number | null; };
  self: { id: string; display_name: string; franchise_id: string | null; franchise_code?: string | null; is_host: boolean; status: string };
  members: Array<{ id: string; display_name: string; franchise_id: string | null; franchise_code?: string | null; is_host: boolean; status: string }>;
  squads: Array<{ id: string; franchise_id: string; franchise_code?: string | null; purse_remaining_lakh: number; overseas_count: number; squad_count: number; qualification_status: string; players: Array<{ player_id: string; full_name: string; country: string; specialism: string; overseas: boolean; purchase_price_lakh: number; acquired_at: string }> }>;
  current_set_players: Array<{ id: string; full_name: string; country: string; specialism: string; overseas: boolean; base_price_lakh: number; status: string; sale_price_lakh: number | null; winning_franchise_id: string | null; winning_franchise_code?: string | null }>;
  events: Array<{ id: string; event_type: string; player_id: string | null; franchise_id: string | null; amount_lakh: number | null; payload: Record<string, unknown>; created_at: string }>;
};

export function apiErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/^.*ERROR:\s*\d+:\s*/, "").trim();
}
