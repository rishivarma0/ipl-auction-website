export function remainingMilliseconds(timerEndsAt: string | null, now = Date.now()) {
  if (!timerEndsAt) return 0;
  return Math.max(0, new Date(timerEndsAt).getTime() - now);
}

export function resumeTimerEndsAt(remainingMs: number, now = Date.now()) {
  return new Date(now + Math.max(0, remainingMs)).toISOString();
}
