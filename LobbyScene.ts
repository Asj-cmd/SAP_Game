import { Client, Room } from "colyseus.js";

const WS_URL = "ws://localhost:2567";
const HTTP_URL = "http://localhost:2567";

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
}

export const colyseusClient = new ColyseusClient();
