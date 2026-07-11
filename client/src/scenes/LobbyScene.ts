import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import type { Room } from "colyseus.js";

export class LobbyScene extends Phaser.Scene {
  private formEl?: Phaser.GameObjects.DOMElement;
  private waitingText?: Phaser.GameObjects.Text;
  private roomCode = "";
  private started = false;

  constructor() {
    super("LobbyScene");
  }

  create() {
    this.started = false;
    this.roomCode = "";

    this.add
      .text(this.scale.width / 2, 60, "CASH GRAB", { fontSize: "40px", color: "#ffffff", fontStyle: "bold" })
      .setOrigin(0.5);

    const html = `
      <div style="display:flex;flex-direction:column;gap:10px;align-items:center;font-family:sans-serif;background:#ffffffee;padding:24px;border-radius:12px;min-width:260px;">
        <input id="nameInput" placeholder="Your name" maxlength="16" style="padding:8px;font-size:14px;width:200px;box-sizing:border-box;" />
        <button id="createBtn" style="padding:8px 16px;font-size:14px;cursor:pointer;width:216px;">Create Room</button>
        <div style="display:flex;gap:6px;">
          <input id="codeInput" placeholder="Room code" maxlength="4" style="padding:8px;font-size:14px;width:110px;text-transform:uppercase;box-sizing:border-box;" />
          <button id="joinBtn" style="padding:8px 12px;font-size:14px;cursor:pointer;">Join Room</button>
        </div>
        <div id="statusText" style="font-size:13px;color:#333;min-height:18px;text-align:center;"></div>
      </div>
    `;

    this.formEl = this.add.dom(this.scale.width / 2, this.scale.height / 2 + 30).createFromHTML(html);

    const status = this.formEl.getChildByID("statusText") as HTMLDivElement;
    const nameInput = this.formEl.getChildByID("nameInput") as HTMLInputElement;
    const codeInput = this.formEl.getChildByID("codeInput") as HTMLInputElement;

    this.formEl.getChildByID("createBtn")!.addEventListener("click", async () => {
      const name = nameInput.value.trim() || "Player";
      status.textContent = "Connecting...";
      try {
        const { room, code } = await colyseusClient.createRoom(name);
        this.enterWaitingRoom(code);
        this.watchRoom(room);
      } catch (e) {
        status.textContent = "Failed to create room. Is the server running?";
      }
    });

    this.formEl.getChildByID("joinBtn")!.addEventListener("click", async () => {
      const name = nameInput.value.trim() || "Player";
      const code = codeInput.value.trim();
      if (!code) {
        status.textContent = "Enter a room code.";
        return;
      }
      status.textContent = "Connecting...";
      try {
        const room = await colyseusClient.joinRoomByCode(code, name);
        this.enterWaitingRoom();
        this.watchRoom(room);
      } catch (e) {
        status.textContent = "Room not found.";
      }
    });
  }

  private enterWaitingRoom(code?: string) {
    this.formEl?.destroy();
    this.formEl = undefined;
    if (code) this.roomCode = code;

    this.waitingText = this.add
      .text(this.scale.width / 2, this.scale.height / 2, this.waitingLines(0), {
        fontSize: "20px",
        color: "#ffffff",
        align: "center",
      })
      .setOrigin(0.5);
  }

  private waitingLines(count: number): string {
    const lines = [`Waiting for players... (${count}/4 connected)`];
    if (this.roomCode) lines.push(`Room code: ${this.roomCode}`);
    return lines.join("\n\n");
  }

  private watchRoom(room: Room) {
    room.onStateChange((state: any) => {
      if (this.started) return;
      this.waitingText?.setText(this.waitingLines(state.players.size));

      if (state.phase !== "waiting") {
        this.started = true;
        this.scene.start("GameScene");
        this.scene.launch("UIScene");
      }
    });
  }
}
