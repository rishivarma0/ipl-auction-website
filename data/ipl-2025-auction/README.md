# IPL 2025 auction data

`players.json` and `auction_sets.json` are generated from the supplied mirror of the IPL 2025 Auction List PDF. The mirror is used for row-level extraction; aggregate checks are cross-checked against the official IPL announcement.

Source row list: https://images.assettype.com/outlookindia/2024-11-15/k09tbib8/1731674068078_TATA_IPL_2025__Auction_List__15_11_24.pdf

Aggregate reference: https://www.iplt20.com/news/article/tata-ipl-2025-player-auction-list-announced

Run the reproducible parser from the project root:

```bash
python3 scripts/parse-ipl-2025-auction.py
```

The parser fails rather than guessing if the source does not produce exactly 574 serials, the expected Indian/overseas counts, or the official reserve-price distribution. Player images are intentionally nullable. No ratings or performance data are included in this phase.
