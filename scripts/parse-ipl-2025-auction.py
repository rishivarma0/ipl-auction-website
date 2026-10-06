#!/usr/bin/env python3
"""Parse the supplied IPL 2025 auction-list PDF into checked JSON.

The PDF is the row-level source. This script deliberately fails on any
unexpected row instead of guessing missing values.
"""
import json, re, sys
from collections import Counter
from pathlib import Path
from pypdf import PdfReader

EXPECTED_TOTAL = 574
EXPECTED_PRICES = {200:81,150:27,125:18,100:23,75:92,50:8,40:5,30:320}
COUNTRIES = ["South Africa", "New Zealand", "West Indies", "Afghanistan", "Bangladesh", "Sri Lanka", "Australia", "England", "India", "USA", "Scotland", "Zimbabwe", "Ireland", "Netherlands", "Nepal"]
SPECIALISMS = {"BATTER", "BOWLER", "ALL-ROUNDER", "WICKETKEEPER"}
STATUSES = {"Capped", "Uncapped", "Associate"}
DATE_RE = re.compile(r"\d{2}/\d{2}/\d{4}")
ROW_RE = re.compile(r"^(\d+)\s+(\d+)\s+(\S+)\s+(.*)$")

def fail(message: str) -> None:
    raise SystemExit(f"VALIDATION FAILED: {message}")

def parse_row(line: str) -> dict:
    match = ROW_RE.match(line.strip())
    if not match:
        fail(f"unparseable row: {line[:120]}")
    serial, set_no, set_code, rest = match.groups()
    date_match = DATE_RE.search(rest)
    if not date_match:
        fail(f"missing DOB boundary for serial {serial}")
    identity, after_date = rest[:date_match.start()].strip(), rest[date_match.end():].strip()
    identity_tokens = identity.split()
    country = next((c for c in COUNTRIES if c in identity), None)
    if not country:
        fail(f"missing country for serial {serial}")
    country_tokens = country.split()
    country_index = len(identity_tokens) - len(country_tokens) - (0 if country != "India" else 1)
    if country_index < 1:
        fail(f"missing name for serial {serial}")
    full_name = " ".join(identity_tokens[:country_index]).strip()
    state = " ".join(identity_tokens[country_index + len(country_tokens):]).strip() or None
    if country != "India":
        state = None
    body = after_date.split()
    if len(body) < 3:
        fail(f"incomplete row for serial {serial}")
    age = body.pop(0)
    specialism_index = next((i for i, token in enumerate(body) if token in SPECIALISMS), None)
    if specialism_index is None:
        fail(f"missing specialism for serial {serial}")
    specialism = body.pop(specialism_index)
    reserve = body[-1]
    status = body[-2]
    if status not in STATUSES or not reserve.isdigit():
        fail(f"missing status/reserve price for serial {serial}: {line[-80:]}")
    body = body[:-2]
    batting_style = body[0] if body and body[0] in {"RHB", "LHB"} else None
    bowling_style = " ".join(body[1:] if batting_style else body).strip() or None
    first_name, *surname = full_name.split(" ", 1)
    return {
        "official_list_sr_no": int(serial), "official_set_no": int(set_no), "official_set_code": set_code,
        "first_name": first_name, "surname": surname[0] if surname else "", "full_name": full_name,
        "country": country, "state_association": state, "specialism": specialism,
        "capped_status": status, "overseas": country != "India", "batting_style": batting_style,
        "bowling_style": bowling_style, "wicketkeeper": specialism == "WICKETKEEPER",
        "base_price_lakh": int(reserve), "image_url": None,
    }

def main() -> None:
    source = Path(sys.argv[1] if len(sys.argv) > 1 else "data/ipl-2025-auction/source-auction-list.pdf")
    output = Path(sys.argv[2] if len(sys.argv) > 2 else "data/ipl-2025-auction/players.json")
    lines = []
    for page in PdfReader(str(source)).pages:
        lines.extend((page.extract_text() or "").splitlines())
    rows = [parse_row(line) for line in lines if ROW_RE.match(line.strip())]
    rows.sort(key=lambda row: row["official_list_sr_no"])
    serials = [row["official_list_sr_no"] for row in rows]
    prices = Counter(row["base_price_lakh"] for row in rows)
    sets = Counter((row["official_set_no"], row["official_set_code"]) for row in rows)
    errors = []
    if len(rows) != EXPECTED_TOTAL: errors.append(f"total={len(rows)} expected={EXPECTED_TOTAL}")
    if serials != list(range(1, EXPECTED_TOTAL + 1)): errors.append("serials are not exactly 1..574")
    if len(set(serials)) != len(serials): errors.append("duplicate serials")
    if any(not row["full_name"] for row in rows): errors.append("missing names")
    if any(not row["official_set_code"] or not row["official_set_no"] for row in rows): errors.append("missing sets")
    if any(row["base_price_lakh"] not in EXPECTED_PRICES for row in rows): errors.append("invalid reserve price")
    if prices != EXPECTED_PRICES: errors.append(f"reserve distribution={dict(prices)}")
    if sum(not row["overseas"] for row in rows) != 366: errors.append("Indian count mismatch")
    if sum(row["overseas"] for row in rows) != 208: errors.append("overseas count mismatch")
    if errors: fail("; ".join(errors))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
    sets_out = [{"official_set_no": no, "official_set_code": code, "display_name": code, "set_order": order, "player_count": count} for order, ((no, code), count) in enumerate(sorted(sets.items()), start=1)]
    (output.parent / "auction_sets.json").write_text(json.dumps(sets_out, indent=2) + "\n")
    print(json.dumps({"total_players": len(rows), "indian": 366, "overseas": 208, "auction_sets": len(sets_out), "first_serial": serials[0], "last_serial": serials[-1], "reserve_prices": dict(sorted(prices.items())), "players_per_set": {code: count for (_, code), count in sorted(sets.items())}}, indent=2))

if __name__ == "__main__": main()
