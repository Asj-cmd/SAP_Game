import { Client, Room } from "colyseus.js";

// Resolves which server to talk to, in priority order:
// 1. ?server=host[:port] query param (share a link that points at a deployed/tunnelled server)
// 2. VITE_SERVER_URL build-time env var (set this when deploying the client to point at your server)
// 3. same hostname the page was loaded from, port 2567 (works out of the box on localhost
//    and for friends on the same LAN when the client dev server is started with --host)
function resolveServerHost(): string {
  const params = new URLSearchParams(window.location.search);
  const fromQuery = params.get("server");
  if (fromQuery) return fromQuery.replace(/^wss?:\/\//, "").replace(/^https?:\/\//, "");

  const fromEnv = import.meta.env.VITE_SERVER_URL as string | undefined;
  if (fromEnv) return fromEnv.replace(/^wss?:\/\//, "").replace(/^https?:\/\//, "");

  return `${window.location.hostname}:2567`;
}

const isSecure = window.location.protocol === "https:";
const HOST = resolveServerHost();
const WS_URL = `${isSecure ? "wss" : "ws"}://${HOST}`;
const HTTP_URL = `${isSecure ? "https" : "http"}://${HOST}`;

class ColyseusClient {
  private client = new Client(WS_URL);
  room: Room | null = null;

  async createRoom(name: string): Promise<{ room: Room; code: string }> {
    const res = await fetch(`${HTTP_URL}/create-room`, { method: "POST" });
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
