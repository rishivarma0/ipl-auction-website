#!/usr/bin/env python3
"""Build and validate the 620-player game pool from official + declared M0 data."""
import json, sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "data" / "ipl-2025-auction"
OFFICIAL = json.loads((ROOT / "players.json").read_text())
ADDITIONAL = json.loads((ROOT / "additional_players.json").read_text())

if len(OFFICIAL) != 574: raise SystemExit(f"official records must be 574, got {len(OFFICIAL)}")
if len(ADDITIONAL) != 46: raise SystemExit(f"additional records must be 46, got {len(ADDITIONAL)}")
official_names = {p["full_name"].casefold() for p in OFFICIAL}
additional_names = [p["full_name"].casefold() for p in ADDITIONAL]
if len(set(additional_names)) != 46: raise SystemExit("duplicate additional player names")
overlap = official_names.intersection(additional_names)
if overlap: raise SystemExit(f"additional players already in official list: {sorted(overlap)}")

game = []
for p in OFFICIAL:
    game.append({**p, "source_type": "OFFICIAL_AUCTION", "source_record_key": f"OFFICIAL-{p['official_list_sr_no']}", "game_set_code": p["official_set_code"]})
for p in ADDITIONAL:
    first, *surname = p["full_name"].split(" ", 1)
    game.append({
        "official_list_sr_no": None, "official_set_no": 0, "official_set_code": "M0", "first_name": first,
        "surname": surname[0] if surname else "", "full_name": p["full_name"], "country": p["country"],
        "state_association": None, "specialism": p["specialism"], "capped_status": None,
        "overseas": p["country"] != "India", "batting_style": None, "bowling_style": None,
        "wicketkeeper": "WICKETKEEPER" in p["specialism"], "base_price_lakh": 200, "image_url": None,
        "source_type": "ADDITIONAL_MARQUEE", "source_record_key": p["source_record_key"], "game_set_code": "M0",
    })
if len(game) != 620: raise SystemExit(f"game pool must be 620, got {len(game)}")
if len({p["source_record_key"] for p in game}) != 620: raise SystemExit("duplicate source records")
duplicate_names = {name for name, count in Counter(p["full_name"].casefold() for p in game).items() if count > 1}
if any(len({p["source_record_key"] for p in game if p["full_name"].casefold() == name}) != sum(1 for p in game if p["full_name"].casefold() == name) for name in duplicate_names): raise SystemExit("duplicate player source records")
if any(not p["full_name"] or not p["base_price_lakh"] or not p["game_set_code"] for p in game): raise SystemExit("missing required game fields")
if any(p["base_price_lakh"] != 200 for p in game if p["source_type"] == "ADDITIONAL_MARQUEE"): raise SystemExit("M0 base price mismatch")
if sum(not p["overseas"] for p in game) != 402 or sum(p["overseas"] for p in game) != 218: raise SystemExit("overseas totals mismatch")

set_counts = Counter(p["game_set_code"] for p in game)
official_sets = [s for s in json.loads((ROOT / "auction_sets.json").read_text()) if s["official_set_code"] != "M0"]
if set(p["official_set_code"] for p in official_sets) != set_counts.keys() - {"M0"}: raise SystemExit("set references do not resolve")
sets = [{"official_set_no": 0, "official_set_code": "M0", "display_name": "MARQUEE", "set_order": 0, "player_count": 46}]
sets += [{**s, "set_order": order} for order, s in enumerate(official_sets, start=1)]
(ROOT / "game_players.json").write_text(json.dumps(game, indent=2, ensure_ascii=False) + "\n")
(ROOT / "auction_sets.json").write_text(json.dumps(sets, indent=2) + "\n")
def sql(value):
    if value is None: return "NULL"
    if isinstance(value, bool): return "TRUE" if value else "FALSE"
    if isinstance(value, int): return str(value)
    return "'" + str(value).replace("'", "''") + "'"
seed = ["-- Generated from game_players.json; rerun scripts/build-game-player-pool.py to refresh.", "begin;", "insert into auction_sets (official_set_no, official_set_code, display_name, set_order, player_count) values"]
seed.append(",\n".join(f"({s['official_set_no']}, {sql(s['official_set_code'])}, {sql(s['display_name'])}, {s['set_order']}, {s['player_count']})" for s in sets) + " on conflict (official_set_no, official_set_code) do update set display_name=excluded.display_name, set_order=excluded.set_order, player_count=excluded.player_count;")
seed.append("insert into players (official_list_sr_no, official_set_no, official_set_code, full_name, country, state_association, specialism, capped_status, overseas, batting_style, bowling_style, wicketkeeper, base_price_lakh, image_url, first_name, surname, source_type, source_record_key) values")
seed.append(",\n".join("(" + ", ".join(sql(p.get(k)) for k in ["official_list_sr_no","official_set_no","official_set_code","full_name","country","state_association","specialism","capped_status","overseas","batting_style","bowling_style","wicketkeeper","base_price_lakh","image_url","first_name","surname","source_type","source_record_key"]) + ")" for p in game) + " on conflict (source_record_key) do update set full_name=excluded.full_name, country=excluded.country, official_set_no=excluded.official_set_no, official_set_code=excluded.official_set_code, specialism=excluded.specialism, capped_status=excluded.capped_status, overseas=excluded.overseas, base_price_lakh=excluded.base_price_lakh, first_name=excluded.first_name, surname=excluded.surname, source_type=excluded.source_type;")
seed += ["commit;", ""]
(Path(__file__).resolve().parents[1] / "supabase" / "seed" / "002_game_player_pool.sql").write_text("\n".join(seed))
print(json.dumps({"official_players":574,"additional_players":46,"total_players":620,"auction_sets":len(sets),"m0_players":46,"indian":402,"overseas":218,"first_official_serial":1,"last_official_serial":574,"duplicate_name_groups":sorted(duplicate_names)}, indent=2))
