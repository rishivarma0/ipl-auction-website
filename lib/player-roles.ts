export const PUBLIC_PLAYER_ROLES = ["BATTER", "WICKET-KEEPER", "ALL-ROUNDER", "BOWLER"] as const;
export type PublicPlayerRole = (typeof PUBLIC_PLAYER_ROLES)[number];

export function normalizePublicRole(player: { specialism?: string | null; wicketkeeper?: boolean }) : PublicPlayerRole {
  if (player.wicketkeeper) return "WICKET-KEEPER";
  const source = (player.specialism ?? "").toUpperCase();
  if (source.includes("ALL-ROUNDER")) return "ALL-ROUNDER";
  if (source.includes("BOWL")) return "BOWLER";
  return "BATTER";
}

export function groupByPublicRole<T extends { specialism?: string | null; wicketkeeper?: boolean }>(players: T[]) {
  return PUBLIC_PLAYER_ROLES.map(role => ({ role, players: players.filter(player => normalizePublicRole(player) === role) })).filter(group => group.players.length > 0);
}
