import { readFileSync } from "node:fs";
import { resolve } from "node:path";

type Player = { official_list_sr_no:number; official_set_no:number; official_set_code:string; full_name:string; country:string; capped_status:string; overseas:boolean; base_price_lakh:number };
const root = resolve(process.cwd(), "data/ipl-2025-auction");
const players = JSON.parse(readFileSync(resolve(root, "players.json"), "utf8")) as Player[];
const sets = JSON.parse(readFileSync(resolve(root, "auction_sets.json"), "utf8")) as Array<{official_set_no:number;official_set_code:string;player_count:number}>;
const prices = new Map<number, number>([[200,81],[150,27],[125,18],[100,23],[75,92],[50,8],[40,5],[30,320]]);
const serials = players.map((player) => player.official_list_sr_no);
const actualPrices = new Map<number, number>();
for (const player of players) actualPrices.set(player.base_price_lakh, (actualPrices.get(player.base_price_lakh) ?? 0) + 1);
const errors: string[] = [];
if (players.length !== 574) errors.push(`expected 574 players, got ${players.length}`);
if (JSON.stringify([...serials].sort((a,b)=>a-b)) !== JSON.stringify(Array.from({length:574},(_,i)=>i+1))) errors.push("serials are not exactly 1..574");
if (players.some((player) => !player.full_name || !player.official_set_code || !player.official_set_no || !player.base_price_lakh)) errors.push("missing required player fields");
if (players.filter((player) => player.overseas).length !== 208 || players.filter((player) => !player.overseas).length !== 366) errors.push("Indian/overseas counts mismatch");
for (const [price, expected] of prices) if (actualPrices.get(price) !== expected) errors.push(`price ${price} mismatch`);
if (!sets.length || sets.some((set) => set.player_count !== players.filter((player) => player.official_set_code === set.official_set_code).length)) errors.push("set counts mismatch");
if (errors.length) { console.error(errors.join("\n")); process.exit(1); }
console.log(JSON.stringify({ total_players: players.length, indian: 366, overseas: 208, auction_sets: sets.length, first_serial: serials[0], last_serial: serials[serials.length - 1], reserve_prices: Object.fromEntries(actualPrices) }, null, 2));
