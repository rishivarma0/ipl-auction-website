import assert from "node:assert/strict";
import test from "node:test";
import { formatAuctionPrice, getBidIncrement, getNextBidAmount } from "../lib/auction-pricing";
import gamePlayers from "../data/ipl-2025-auction/game_players.json";

test("formats auction prices at the lakh/crore boundary", () => {
  assert.equal(formatAuctionPrice(30), "₹30L"); assert.equal(formatAuctionPrice(75), "₹75L"); assert.equal(formatAuctionPrice(95), "₹95L");
  assert.equal(formatAuctionPrice(100), "₹1.00 Cr"); assert.equal(formatAuctionPrice(125), "₹1.25 Cr"); assert.equal(formatAuctionPrice(200), "₹2.00 Cr"); assert.equal(formatAuctionPrice(725), "₹7.25 Cr");
});

test("uses the IPL-style bid increment ladder", () => {
  assert.deepEqual([75,95,100,190,200,480,500,1000].map(getBidIncrement), [5,5,10,10,20,20,25,25]);
  assert.deepEqual([95,100,190,200,480,500,1000].map(getNextBidAmount), [100,110,200,220,500,525,1025]);
});

test("contains the complete 620-player game pool", () => {
  assert.equal(gamePlayers.length, 620);
  assert.equal(new Set(gamePlayers.map((player) => player.source_record_key)).size, 620);
  assert.equal(gamePlayers.filter((player) => player.official_set_code === "M0").length, 46);
  assert.equal(gamePlayers.filter((player) => player.source_type === "ADDITIONAL_MARQUEE" && player.base_price_lakh !== 200).length, 0);
});
