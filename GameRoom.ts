import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import type { Room } from "colyseus.js";

export class LobbyScene extends Phaser.Scene {
  private overlay!: HTMLDivElement;
  private transitioned = false;

  constructor() {
    super("LobbyScene");
  }

  create() {
    this.transitioned = false;
    this.buildOverlay();
  }

  private buildOverlay() {
    const overlay = document.createElement("div");
    overlay.style.cssText = `
      position: fixed; inset: 0; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 12px;
      font-family: sans-serif; color: #fff; background: #1b1b1b; z-index: 10;
    `;
    overlay.innerHTML = `
      <h1 style="margin:0">Cash Grab</h1>
      <input id="cg-name" placeholder="Your name" maxlength="16" style="padding:8px;font-size:14px;" />
      <div style="display:flex; gap:8px;">
        <button id="cg-create" style="padding:8px 16px;">Create Room</button>
        <input id="cg-code" placeholder="Room code" maxlength="4" style="padding:8px;width:80px;text-transform:uppercase;" />
        <button id="cg-join" style="padding:8px 16px;">Join Room</button>
      </div>
      <div id="cg-status" style="min-height:24px;"></div>
    `;
    document.body.appendChild(overlay);
    this.overlay = overlay;

    const nameInput = overlay.querySelector("#cg-name") as HTMLInputElement;
    const codeInput = overlay.querySelector("#cg-code") as HTMLInputElement;
    const status = overlay.querySelector("#cg-status") as HTMLDivElement;
    const createBtn = overlay.querySelector("#cg-create") as HTMLButtonElement;
    const joinBtn = overlay.querySelector("#cg-join") as HTMLButtonElement;

    const getName = () => nameInput.value.trim() || "Player";

    createBtn.onclick = async () => {
      status.textContent = "Creating room...";
      try {
        const { room, code } = await colyseusClient.createRoom(getName());
        this.watchRoom(room, status, code);
      } catch (e) {
        console.error(e);
        status.textContent = "Failed to create room.";
      }
    };

    joinBtn.onclick = async () => {
      const code = codeInput.value.trim();
      if (!code) return;
      status.textContent = "Joining room...";
      try {
        const room = await colyseusClient.joinRoomByCode(code, getName());
        status.textContent = "Waiting for players...";
        this.watchRoom(room, status);
      } catch (e) {
        console.error(e);
        status.textContent = "Room not found.";
      }
    };
  }

  private watchRoom(room: Room, status: HTMLDivElement, code?: string) {
    const prefix = code ? `Room code: ${code} — ` : "";
    const update = () => {
      if (this.transitioned) return;
      const count = room.state.players.size;
      if (room.state.phase === "waiting") {
        status.textContent = `${prefix}Waiting for players... (${count}/4 connected)`;
      } else if (room.state.phase === "countdown" || room.state.phase === "playing") {
        this.transitioned = true;
        this.overlay.remove();
        this.scene.start("GameScene");
        this.scene.launch("UIScene");
      }
    };
    room.onStateChange(update);
    update();
  }

  shutdown() {
    this.overlay?.remove();
  }
}
