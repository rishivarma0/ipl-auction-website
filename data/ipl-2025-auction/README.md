# IPL 2025 auction data

`players.json` contains the 574 official records parsed from the supplied mirror. `additional_players.json` contains the 46 explicitly declared game additions. `game_players.json` and `auction_sets.json` are reproducible outputs: the game pool contains 620 normal auction players and starts with the `M0` marquee set before the 79 official sets.

Source row list: https://images.assettype.com/outlookindia/2024-11-15/k09tbib8/1731674068078_TATA_IPL_2025__Auction_List__15_11_24.pdf

Aggregate reference: https://www.iplt20.com/news/article/tata-ipl-2025-player-auction-list-announced

Run the reproducible parser and game-pool builder from the project root:

```bash
python3 scripts/parse-ipl-2025-auction.py
python3 scripts/build-game-player-pool.py
```

The parser fails rather than guessing if the source does not produce exactly 574 serials, the expected Indian/overseas counts, or the official reserve-price distribution. The builder fails on duplicate source records, duplicate additional records, official/additional overlap, missing sets, or a final pool other than 620. Player images are intentionally nullable. No ratings or performance data are included in this phase.
