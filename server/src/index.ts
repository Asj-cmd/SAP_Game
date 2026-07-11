import { Server, matchMaker } from "colyseus";
import { WebSocketTransport } from "@colyseus/ws-transport";
import express from "express";
import cors from "cors";
import { createServer } from "http";
import path from "path";
import fs from "fs";
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

// Serve the built client (if present) from this same server, so the whole game -
// client + server - is reachable on ONE port/URL. This is what makes "friends just
// open one link" work: run `npm run build` in client/, then start this server.
// (In local dev you instead run the Vite dev server on :5173; the client detects
// dev mode and points itself back at this server on :2567.)
const clientDist = path.resolve(__dirname, "../../client/dist");
if (fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  // SPA fallback for any non-API GET route.
  app.get("*", (_req, res) => {
    res.sendFile(path.join(clientDist, "index.html"));
  });
  console.log(`Serving built client from ${clientDist}`);
} else {
  console.log("No built client found (client/dist). Run `npm run build` in client/ to serve it from here.");
}

const PORT = Number(process.env.PORT) || 2567;
httpServer.listen(PORT, () => {
  console.log(`Cash Grab server running on port ${PORT}`);
});
