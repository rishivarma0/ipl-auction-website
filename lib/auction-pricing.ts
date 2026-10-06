export function formatAuctionPrice(amountLakh: number): string {
  if (!Number.isInteger(amountLakh) || amountLakh < 0) throw new Error("Auction price must be a non-negative integer number of lakhs");
  return amountLakh < 100 ? `₹${amountLakh}L` : `₹${(amountLakh / 100).toFixed(2)} Cr`;
}

export function getBidIncrement(currentBidLakh: number): number {
  if (!Number.isInteger(currentBidLakh) || currentBidLakh < 0) throw new Error("Current bid must be a non-negative integer number of lakhs");
  if (currentBidLakh < 100) return 5;
  if (currentBidLakh < 200) return 10;
  if (currentBidLakh < 500) return 20;
  return 25;
}

export function getNextBidAmount(currentBidLakh: number): number {
  return currentBidLakh + getBidIncrement(currentBidLakh);
}
