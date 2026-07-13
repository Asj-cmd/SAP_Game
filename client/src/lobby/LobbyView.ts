import { colyseusClient } from "../network/ColyseusClient";
import type { Room } from "colyseus.js";

const TEAM_B_COLOR = "#e85d24";
const TEAM_A_COLOR = "#185fa5";

// Plain-DOM port of the old Phaser LobbyScene (it was already just an HTML
// form wrapped in a Phaser DOM GameObject, so dropping the wrapper is
// mechanical). Milestone C behavior only: auto-starts once the room fills,
// same as the 2D game. Milestone D extends this same class with host
// controls (manual team assignment, bot count, a real "Start Game" button)
// rather than replacing it.
export class LobbyView {
  private root: HTMLDivElement;
  private panel?: HTMLDivElement;
  private roomCode = "";
  private started = false;

  constructor(
    private container: HTMLElement,
    private onGameStart: (room: Room) => void
  ) {
    this.root = document.createElement("div");
    this.root.style.cssText =
      "width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;font-family:system-ui,sans-serif;";
    this.container.appendChild(this.root);

    const title = document.createElement("div");
    title.innerHTML = `
      <div style="font-size:44px;font-weight:800;color:#fff;-webkit-text-stroke:4px #000;text-align:center;">CASH GRAB</div>
      <div style="font-size:14px;color:#ddd;-webkit-text-stroke:1.5px #000;text-align:center;margin-top:6px;">
        2v2, 3v3, or 4v4 — steal the other family's cash, jail the intruders
      </div>`;
    this.root.appendChild(title);

    this.showForm();
  }

  private showForm() {
    this.panel?.remove();
    const panel = document.createElement("div");
    panel.style.cssText =
      "font-family:system-ui,sans-serif;background:#ffffffee;padding:22px 24px;border-radius:14px;min-width:300px;box-shadow:0 6px 24px #0006;";
    panel.innerHTML = `
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
        </div>`;
    this.root.appendChild(panel);
    this.panel = panel;

    const status = panel.querySelector("#statusText") as HTMLDivElement;
    const nameInput = panel.querySelector("#nameInput") as HTMLInputElement;
    const codeInput = panel.querySelector("#codeInput") as HTMLInputElement;
    const modeInput = panel.querySelector("#modeInput") as HTMLSelectElement;
    const bundleInput = panel.querySelector("#bundleInput") as HTMLSelectElement;
    const winInfo = panel.querySelector("#winInfo") as HTMLDivElement;

    const winTargetFor = (bundles: number) => bundles * 2 - 1;
    const updateWinInfo = () => {
      const bundles = parseInt(bundleInput.value, 10) || 3;
      winInfo.textContent = `First team with ${winTargetFor(bundles)} bundles in their bedroom wins the round`;
    };
    updateWinInfo();
    bundleInput.addEventListener("change", updateWinInfo);

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

    panel.querySelector("#createBtn")!.addEventListener("click", create);
    panel.querySelector("#joinBtn")!.addEventListener("click", join);
    codeInput.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") join();
    });
    nameInput.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") create();
    });
  }

  private showWaiting(room: Room) {
    this.panel?.remove();

    const shareUrl = window.location.href.split("?")[0];
    const codeBlock = this.roomCode
      ? `<div style="text-align:center;margin-bottom:12px;">
           <div style="font-size:12px;color:#666;">ROOM CODE</div>
           <div style="font-size:40px;font-weight:800;letter-spacing:6px;color:#111;">${this.roomCode}</div>
           <div style="font-size:12px;color:#666;margin-top:6px;">Share this page's link + the code with your friends:</div>
           <div style="font-size:12px;color:#1565c0;word-break:break-all;margin-top:2px;">${shareUrl}</div>
         </div>`
      : "";

    const panel = document.createElement("div");
    panel.style.cssText =
      "font-family:system-ui,sans-serif;background:#ffffffee;padding:22px 26px;border-radius:14px;min-width:340px;box-shadow:0 6px 24px #0006;";
    panel.innerHTML = `
        ${codeBlock}
        <div id="waitCount" style="text-align:center;font-size:16px;font-weight:600;color:#111;">Waiting for players...</div>
        <div id="modeInfo" style="text-align:center;font-size:12px;color:#777;margin-top:2px;"></div>
        <div id="playerList" style="margin-top:12px;display:flex;flex-direction:column;gap:6px;"></div>
        <div id="youAre" style="text-align:center;margin-top:12px;font-size:13px;color:#555;"></div>
        <div id="hostControls" style="margin-top:14px;padding-top:12px;border-top:1px solid #eee;"></div>`;
    this.root.appendChild(panel);
    this.panel = panel;

    this.watchRoom(room);
  }

  private watchRoom(room: Room) {
    const countOnTeam = (state: any, team: string) => {
      let c = 0;
      state.players.forEach((p: any) => {
        if (p.team === team) c++;
      });
      return c;
    };
    const countBotsOnTeam = (state: any, team: string) => {
      let c = 0;
      state.players.forEach((p: any) => {
        if (p.team === team && p.isBot) c++;
      });
      return c;
    };

    const render = (state: any) => {
      if (!this.panel) return;
      const teamSize = state.teamSize || 2;
      const isHost = !!state.hostId && state.hostId === room.sessionId;

      const waitCount = this.panel.querySelector("#waitCount") as HTMLDivElement | null;
      const modeInfo = this.panel.querySelector("#modeInfo") as HTMLDivElement | null;
      const list = this.panel.querySelector("#playerList") as HTMLDivElement | null;
      const youAre = this.panel.querySelector("#youAre") as HTMLDivElement | null;
      const hostControls = this.panel.querySelector("#hostControls") as HTMLDivElement | null;

      const countB = countOnTeam(state, "B");
      const countA = countOnTeam(state, "A");
      if (waitCount) waitCount.textContent = `Team B ${countB}/${teamSize}  •  Team A ${countA}/${teamSize}`;
      if (modeInfo) modeInfo.textContent = `${teamSize} v ${teamSize}  •  first to ${state.winScore || teamSize} cash wins`;

      if (list) {
        let rows = "";
        state.players.forEach((p: any) => {
          const color = p.team === "B" ? TEAM_B_COLOR : TEAM_A_COLOR;
          const you = p.id === room.sessionId ? " (you)" : "";
          const botTag = p.isBot ? " (BOT)" : "";
          const otherTeam = p.team === "B" ? "A" : "B";
          const swapBtn = isHost
            ? `<button data-swap="${p.id}" data-team="${otherTeam}"
                 style="margin-left:8px;font-size:11px;padding:3px 7px;border-radius:5px;border:1px solid #ccc;background:#fff;cursor:pointer;">
                 → Team ${otherTeam}
               </button>`
            : "";
          rows += `<div style="display:flex;align-items:center;gap:8px;font-size:14px;">
              <span style="width:12px;height:12px;border-radius:50%;background:${color};display:inline-block;"></span>
              <span style="color:#222;">${p.name}${you}${botTag}</span>
              <span style="margin-left:auto;color:${color};font-weight:600;">Team ${p.team}</span>
              ${swapBtn}
            </div>`;
        });
        list.innerHTML = rows;

        if (isHost) {
          list.querySelectorAll<HTMLButtonElement>("[data-swap]").forEach((btn) => {
            btn.addEventListener("click", () => {
              colyseusClient.send("assignTeam", { targetId: btn.dataset.swap, team: btn.dataset.team });
            });
          });
        }
      }

      const me = state.players.get(room.sessionId);
      if (youAre && me) {
        const color = me.team === "B" ? TEAM_B_COLOR : TEAM_A_COLOR;
        youAre.innerHTML = isHost
          ? `You are <b style="color:${color};">Team ${me.team}</b> (Host) — fill both rosters and press Start.`
          : `You are <b style="color:${color};">Team ${me.team}</b> — waiting for the host to start.`;
      }

      if (hostControls) {
        if (!isHost) {
          hostControls.style.display = "none";
          hostControls.innerHTML = "";
        } else {
          hostControls.style.display = "block";
          const canStart = countB === teamSize && countA === teamSize;
          const needBText = Math.max(0, teamSize - countB);
          const needAText = Math.max(0, teamSize - countA);
          const startLabel = canStart
            ? "Start Game"
            : `Need ${needBText} more on B, ${needAText} more on A (or add bots)`;

          hostControls.innerHTML = `
            <div style="display:flex;justify-content:space-between;gap:16px;margin-bottom:10px;">
              ${(["B", "A"] as const)
                .map(
                  (team) => `
                <div style="text-align:center;flex:1;">
                  <div style="font-size:11px;color:#666;">Team ${team} bots</div>
                  <div style="display:flex;align-items:center;justify-content:center;gap:8px;margin-top:4px;">
                    <button data-bot-dec="${team}"
                      style="width:26px;height:26px;border-radius:6px;border:1px solid #ccc;background:#fff;cursor:pointer;">−</button>
                    <span style="min-width:14px;font-weight:600;">${countBotsOnTeam(state, team)}</span>
                    <button data-bot-inc="${team}"
                      style="width:26px;height:26px;border-radius:6px;border:1px solid #ccc;background:#fff;cursor:pointer;">+</button>
                  </div>
                </div>`
                )
                .join("")}
            </div>
            <button id="startGameBtn" ${canStart ? "" : "disabled"}
              style="width:100%;padding:10px;font-size:14px;font-weight:700;border:0;border-radius:8px;
                     cursor:${canStart ? "pointer" : "not-allowed"};
                     background:${canStart ? "#2e7d32" : "#aaa"};color:#fff;">
              ${startLabel}
            </button>`;

          hostControls.querySelectorAll<HTMLButtonElement>("[data-bot-inc]").forEach((btn) => {
            btn.addEventListener("click", () => {
              const team = btn.dataset.botInc!;
              colyseusClient.send("setBotCount", { team, count: countBotsOnTeam(state, team) + 1 });
            });
          });
          hostControls.querySelectorAll<HTMLButtonElement>("[data-bot-dec]").forEach((btn) => {
            btn.addEventListener("click", () => {
              const team = btn.dataset.botDec!;
              colyseusClient.send("setBotCount", { team, count: Math.max(0, countBotsOnTeam(state, team) - 1) });
            });
          });
          hostControls.querySelector("#startGameBtn")?.addEventListener("click", () => {
            colyseusClient.send("startGame");
          });
        }
      }

      const started = ["countdown", "playing", "roundEnd", "matchEnd"].includes(state.phase);
      if (started && !this.started) {
        this.started = true;
        this.dispose();
        this.onGameStart(room);
      }
    };

    room.onStateChange(render);
    render(room.state);
  }

  dispose() {
    this.root.remove();
  }
}
