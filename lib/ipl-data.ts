import players from "@/data/ipl-2025-auction/game_players.json";
import sets from "@/data/ipl-2025-auction/auction_sets.json";

export type AuctionPlayer = (typeof players)[number];
export type AuctionSet = (typeof sets)[number];

export function getPlayersForSet(setCode: string): AuctionPlayer[] {
  return players.filter((player) => player.official_set_code === setCode).sort((a, b) => a.full_name.localeCompare(b.full_name));
}

export const officialPlayers = players;
export const officialAuctionSets = sets;
