import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import type { Room } from "colyseus.js";

const TEAM_B_COLOR = "#e85d24";
const TEAM_A_COLOR = "#185fa5";

export class LobbyScene extends Phaser.Scene {
  private panel?: Phaser.GameObjects.DOMElement;
  private roomCode = "";
  private started = false;

  constructor() {
    super("LobbyScene");
  }

  create() {
    this.started = false;
    this.roomCode = "";

    this.add
      .text(this.scale.width / 2, 46, "CASH GRAB", {
        fontSize: "44px",
        color: "#ffffff",
        fontStyle: "bold",
        stroke: "#000000",
        strokeThickness: 6,
      })
      .setOrigin(0.5);

    this.add
      .text(this.scale.width / 2, 82, "2v2, 3v3, or 4v4 — steal the other family's cash, jail the intruders", {
        fontSize: "14px",
        color: "#dddddd",
        stroke: "#000000",
        strokeThickness: 3,
      })
      .setOrigin(0.5);

    this.showForm();
  }

  private showForm() {
    const html = `
      <div style="font-family:system-ui,sans-serif;background:#ffffffee;padding:22px 24px;border-radius:14px;min-width:300px;box-shadow:0 6px 24px #0006;">
        <div style="display:flex;flex-direction:column;gap:10px;align-items:stretch;">
          <input id="nameInput" placeholder="Your name" maxlength="16"
                 style="padding:10px;font-size:15px;border:1px solid #ccc;border-radius:8px;" />
          <div style="display:flex;gap:8px;">
            <label style="flex:1;font-size:11px;color:#666;">Mode
              <select id="modeInput" style="width:100%;padding:9px;font-size:14px;border:1px solid #ccc;border-radius:8px;margin-top:2px;">
                <option value="2">2 v 2</option>
                <option value="3">3 v 3</option>
                <option value="4">4 v 4</option>
              </select>
            </label>
            <label style="flex:1;font-size:11px;color:#666;">Bundles per team
              <select id="bundleInput" style="width:100%;padding:9px;font-size:14px;border:1px solid #ccc;border-radius:8px;margin-top:2px;">
                <option value="3">3</option><option value="4">4</option><option value="5">5</option>
              </select>
            </label>
          </div>
          <div id="winInfo" style="font-size:12px;color:#555;text-align:center;font-weight:600;"></div>
          <div style="font-size:11px;color:#999;text-align:center;margin-top:-2px;">Host sets these; they apply to everyone in the room.</div>
          <button id="createBtn"
                 style="padding:10px;font-size:15px;font-weight:600;cursor:pointer;border:0;border-radius:8px;background:#2e7d32;color:#fff;">
            Create Room
          </button>
          <div style="display:flex;gap:8px;align-items:center;color:#888;font-size:12px;">
            <div style="flex:1;height:1px;background:#ddd;"></div>OR<div style="flex:1;height:1px;background:#ddd;"></div>
          </div>
          <div style="display:flex;gap:8px;">
            <input id="codeInput" placeholder="ROOM CODE" maxlength="4"
                 style="flex:1;padding:10px;font-size:15px;text-transform:uppercase;border:1px solid #ccc;border-radius:8px;letter-spacing:2px;" />
            <button id="joinBtn"
                 style="padding:10px 16px;font-size:15px;font-weight:600;cursor:pointer;border:0;border-radius:8px;background:#1565c0;color:#fff;">
              Join
            </button>
          </div>
          <div id="statusText" style="font-size:13px;color:#c62828;min-height:18px;text-align:center;"></div>
        </div>
        <div style="margin-top:14px;padding-top:12px;border-top:1px solid #eee;font-size:12px;color:#555;line-height:1.5;">
          <b>How to play:</b> Move with WASD or arrow keys (any direction). Sneak into the enemy
          bedroom, grab cash and carry it home (it banks automatically). Catch intruders anywhere
          on your property — house or backyard — with <b>SPACE</b> to jail them. Your score is the
          cash in your bedroom — what you've kept plus what you've banked. First to the target
          (shown above) wins the round — best of 3.
        </div>
      </div>`;

    this.panel = this.add.dom(this.scale.width / 2, this.scale.height / 2 + 40).createFromHTML(html);

    const status = this.panel.getChildByID("statusText") as HTMLDivElement;
    const nameInput = this.panel.getChildByID("nameInput") as HTMLInputElement;
    const codeInput = this.panel.getChildByID("codeInput") as HTMLInputElement;
    const modeInput = this.panel.getChildByID("modeInput") as HTMLSelectElement;
    const bundleInput = this.panel.getChildByID("bundleInput") as HTMLSelectElement;
    const winInfo = this.panel.getChildByID("winInfo") as HTMLDivElement;

    // The win target isn't picked directly - it's derived from bundles per team:
    // 3 bundles -> win at 5, 4 -> win at 7, 5 -> win at 9.
    const winTargetFor = (bundles: number) => bundles * 2 - 1;
    const updateWinInfo = () => {
      const bundles = parseInt(bundleInput.value, 10) || 3;
      winInfo.textContent = `First team with ${winTargetFor(bundles)} bundles in their bedroom wins the round`;
    };
    updateWinInfo();
    bundleInput.addEventListener("change", updateWinInfo);

    // Default bundles-per-team to the mode when the host changes it (3 for 2v2,
    // 4 for 3v3, 5 for 4v4).
    modeInput.addEventListener("change", () => {
      bundleInput.value = String(parseInt(modeInput.value, 10) + 1);
      updateWinInfo();
    });

    const create = async () => {
      const name = nameInput.value.trim() || "Player";
      const teamSize = parseInt(modeInput.value, 10) || 2;
      const bundles = parseInt(bundleInput.value, 10) || 5;
      status.style.color = "#555";
      status.textContent = "Connecting...";
      try {
        const { room, code } = await colyseusClient.createRoom(name, { teamSize, bundles });
        this.roomCode = code;
        this.showWaiting(room);
      } catch (e) {
        status.style.color = "#c62828";
        status.textContent = "Couldn't reach the server. Is it running?";
      }
    };

    const join = async () => {
      const name = nameInput.value.trim() || "Player";
      const code = codeInput.value.trim().toUpperCase();
      if (!code) {
        status.style.color = "#c62828";
        status.textContent = "Enter a room code to join.";
        return;
      }
      status.style.color = "#555";
      status.textContent = "Connecting...";
      try {
        const room = await colyseusClient.joinRoomByCode(code, name);
        this.showWaiting(room);
      } catch (e) {
        status.style.color = "#c62828";
        status.textContent = "Room not found — check the code.";
      }
    };

    this.panel.getChildByID("createBtn")!.addEventListener("click", create);
    this.panel.getChildByID("joinBtn")!.addEventListener("click", join);
    codeInput.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") join();
    });
    nameInput.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") create();
    });
  }

  private showWaiting(room: Room) {
    this.panel?.destroy();

    const shareUrl = window.location.href.split("?")[0];
    const codeBlock = this.roomCode
      ? `<div style="text-align:center;margin-bottom:12px;">
           <div style="font-size:12px;color:#666;">ROOM CODE</div>
           <div style="font-size:40px;font-weight:800;letter-spacing:6px;color:#111;">${this.roomCode}</div>
           <div style="font-size:12px;color:#666;margin-top:6px;">Share this page's link + the code with your friends:</div>
           <div style="font-size:12px;color:#1565c0;word-break:break-all;margin-top:2px;">${shareUrl}</div>
         </div>`
      : "";

    const html = `
      <div style="font-family:system-ui,sans-serif;background:#ffffffee;padding:22px 26px;border-radius:14px;min-width:320px;box-shadow:0 6px 24px #0006;">
        ${codeBlock}
        <div id="waitCount" style="text-align:center;font-size:16px;font-weight:600;color:#111;">Waiting for players...</div>
        <div id="modeInfo" style="text-align:center;font-size:12px;color:#777;margin-top:2px;"></div>
        <div id="playerList" style="margin-top:12px;display:flex;flex-direction:column;gap:6px;"></div>
        <div id="youAre" style="text-align:center;margin-top:12px;font-size:13px;color:#555;"></div>
      </div>`;

    this.panel = this.add.dom(this.scale.width / 2, this.scale.height / 2 + 30).createFromHTML(html);
    this.watchRoom(room);
  }

  private watchRoom(room: Room) {
    const render = (state: any) => {
      if (!this.panel) return;
      const count = state.players.size;
      const teamSize = state.teamSize || 2;
      const total = teamSize * 2;
      const waitCount = this.panel.getChildByID("waitCount") as HTMLDivElement | null;
      const modeInfo = this.panel.getChildByID("modeInfo") as HTMLDivElement | null;
      const list = this.panel.getChildByID("playerList") as HTMLDivElement | null;
      const youAre = this.panel.getChildByID("youAre") as HTMLDivElement | null;
      if (waitCount) waitCount.textContent = `Waiting for players... (${count}/${total})`;
      if (modeInfo) modeInfo.textContent = `${teamSize} v ${teamSize}  •  first to ${state.winScore || teamSize} cash wins`;

      if (list) {
        let rows = "";
        state.players.forEach((p: any) => {
          const color = p.team === "B" ? TEAM_B_COLOR : TEAM_A_COLOR;
          const you = p.id === room.sessionId ? " (you)" : "";
          rows += `<div style="display:flex;align-items:center;gap:8px;font-size:14px;">
              <span style="width:12px;height:12px;border-radius:50%;background:${color};display:inline-block;"></span>
              <span style="color:#222;">${p.name}${you}</span>
              <span style="margin-left:auto;color:${color};font-weight:600;">Team ${p.team}</span>
            </div>`;
        });
        list.innerHTML = rows;
      }

      const me = state.players.get(room.sessionId);
      if (youAre && me) {
        const color = me.team === "B" ? TEAM_B_COLOR : TEAM_A_COLOR;
        youAre.innerHTML = `You are <b style="color:${color};">Team ${me.team}</b> — game starts automatically at ${total} players.`;
      }

      // Only transition on an explicit in-game phase. (Right after join the schema
      // may not be synced yet and phase reads as "" - checking `!== "waiting"` there
      // would wrongly start the game with a single player.)
      const started = ["countdown", "playing", "roundEnd", "matchEnd"].includes(state.phase);
      if (started && !this.started) {
        this.started = true;
        this.panel?.destroy();
        this.panel = undefined;
        this.scene.start("GameScene");
        this.scene.launch("UIScene");
      }
    };

    room.onStateChange(render);
    render(room.state);
  }
}
