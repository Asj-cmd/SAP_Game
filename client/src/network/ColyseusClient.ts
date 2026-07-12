import { Client, Room } from "colyseus.js";

// Resolves which server to talk to, in priority order:
// 1. ?server=host[:port] query param (share a link that points at a specific server)
// 2. VITE_SERVER_URL build-time env var (for a separately deployed client)
// 3. Vite dev mode -> same hostname on port 2567 (client on :5173, server on :2567;
//    also works for friends on the same LAN opening http://<your-lan-ip>:5173)
// 4. Production (client served BY the game server) -> the exact same origin the page
//    was loaded from. This is what makes single-URL play + tunnels "just work".
function resolveServerHost(): string {
  const strip = (s: string) => s.replace(/^wss?:\/\//, "").replace(/^https?:\/\//, "").replace(/\/$/, "");

  const params = new URLSearchParams(window.location.search);
  const fromQuery = params.get("server");
  if (fromQuery) return strip(fromQuery);

  const fromEnv = import.meta.env.VITE_SERVER_URL as string | undefined;
  if (fromEnv) return strip(fromEnv);

  if (import.meta.env.DEV) return `${window.location.hostname}:2567`;

  return window.location.host; // same origin (includes port) as the server that served this page
}

const isSecure = window.location.protocol === "https:";
const HOST = resolveServerHost();
const WS_URL = `${isSecure ? "wss" : "ws"}://${HOST}`;
const HTTP_URL = `${isSecure ? "https" : "http"}://${HOST}`;

class ColyseusClient {
  private client = new Client(WS_URL);
  room: Room | null = null;

  async createRoom(
    name: string,
    opts?: { teamSize?: number; bundles?: number }
  ): Promise<{ room: Room; code: string }> {
    const res = await fetch(`${HTTP_URL}/create-room`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(opts ?? {}),
    });
    if (!res.ok) throw new Error("Failed to create room");
    const { roomId, code } = await res.json();
    const room = await this.client.joinById(roomId, { name });
    this.room = room;
    return { room, code };
  }

  async joinRoomByCode(code: string, name: string): Promise<Room> {
    const res = await fetch(`${HTTP_URL}/rooms/${code.toUpperCase()}`);
    if (!res.ok) throw new Error("Room not found");
    const { roomId } = await res.json();
    const room = await this.client.joinById(roomId, { name });
    this.room = room;
    return room;
  }

  send(type: string, message?: any) {
    this.room?.send(type, message);
  }

  leave() {
    this.room?.leave();
    this.room = null;
  }
}

export const colyseusClient = new ColyseusClient();
