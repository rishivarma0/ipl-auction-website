export type RoomSession = {
  roomId: string;
  roomCode: string;
  memberId: string;
  sessionKey: string;
  isHost: boolean;
};

const STORAGE_KEY = "ipl-auction-room-session";

export function saveRoomSession(session: RoomSession) {
  if (typeof window !== "undefined") localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
}

export function getRoomSession(): RoomSession | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as RoomSession) : null;
  } catch {
    return null;
  }
}

export function clearRoomSession() {
  if (typeof window !== "undefined") localStorage.removeItem(STORAGE_KEY);
}
