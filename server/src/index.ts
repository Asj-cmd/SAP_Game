import { Server, matchMaker } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import express from "express";
import cors from "cors";
import { createServer } from "http";
import { GameRoom } from "./rooms/GameRoom";

const app = express();
app.use(cors());
app.use(express.json());

const httpServer = createServer(app);

const gameServer = new Server({
  transport: new WebSocketTransport({ server: httpServer }),
});

const handler = gameServer.define("game_room", GameRoom);

const codeToRoomId = new Map<string, string>();
const roomIdToCode = new Map<string, string>();

handler.on("create", (room) => {
  const code = (room as GameRoom).code;
  codeToRoomId.set(code, room.roomId);
  roomIdToCode.set(room.roomId, code);
});

handler.on("dispose", (room) => {
  const code = roomIdToCode.get(room.roomId);
  if (code) codeToRoomId.delete(code);
  roomIdToCode.delete(room.roomId);
});

app.post("/create-room", async (_req, res) => {
  try {
    const room = await matchMaker.createRoom("game_room", {});
    const code = roomIdToCode.get(room.roomId) || "";
    res.json({ roomId: room.roomId, code });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Failed to create room" });
  }
});

app.get("/rooms/:code", (req, res) => {
  const code = req.params.code.toUpperCase();
  const roomId = codeToRoomId.get(code);
  if (!roomId) {
    res.status(404).json({ error: "Room not found" });
    return;
  }
  res.json({ roomId });
});

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

const PORT = Number(process.env.PORT) || 2567;
httpServer.listen(PORT, () => {
  console.log(`Cash Grab server running on port ${PORT}`);
});
