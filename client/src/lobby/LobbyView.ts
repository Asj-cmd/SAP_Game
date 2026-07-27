import { colyseusClient } from "../network/ColyseusClient";
import type { Room } from "colyseus.js";
import { installTheme, TEAM_B_COLOR, TEAM_A_COLOR } from "../ui/theme";

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
    installTheme();
    const scroller = document.createElement("div");
    scroller.className = "cg-root";
    scroller.style.cssText = "width:100%;height:100%;overflow-y:auto;overflow-x:hidden;";
    this.root = document.createElement("div");
    this.root.style.cssText =
      "min-height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:20px;padding:28px 20px;";
    scroller.appendChild(this.root);
    this.container.appendChild(scroller);

    // paint-order:stroke fill keeps the outline BEHIND the glyphs (a centered
    // stroke on top eats small text entirely - same fix as the HUD); the
    // layered soft shadow replaces the hard offset that read as a default.
    const title = document.createElement("div");
    title.className = "cg-rise";
    title.style.cssText = "text-align:center;";
    title.innerHTML = `
      <div class="cg-display">CASH GRAB</div>
      <div class="cg-tagline" style="margin-top:10px;">
        Two families. One street. Whoever ends the night with the most cash wins.
      </div>
      <div style="margin-top:12px;display:flex;gap:8px;justify-content:center;">
        <span class="cg-chip cg-chip-b">Family B</span>
        <span class="cg-chip cg-chip-a">Family A</span>
      </div>`;
    this.root.appendChild(title);

    this.showForm();
  }

  private showForm() {
    this.panel?.remove();
    const panel = document.createElement("div");
    // Clamped width: without a max-width the long how-to-play copy stretched
    // the card toward full-bleed on wide screens.
    panel.className = "cg-panel cg-rise";
    panel.style.cssText = "padding:22px 24px;width:min(92vw, 440px);";
    panel.innerHTML = `
        <div style="display:flex;flex-direction:column;gap:10px;align-items:stretch;">
          <input id="nameInput" class="cg-input" placeholder="Your name" maxlength="16" />
          <div style="display:flex;gap:8px;">
            <label style="flex:1;" class="cg-label">Mode
              <select id="modeInput" class="cg-select" style="margin-top:5px;">
                <option value="2">2 v 2</option>
                <option value="3">3 v 3</option>
                <option value="4">4 v 4</option>
              </select>
            </label>
            <label style="flex:1;" class="cg-label">Bundles per team
              <select id="bundleInput" class="cg-select" style="margin-top:5px;">
                <option value="3">3</option><option value="4">4</option><option value="5">5</option>
              </select>
            </label>
          </div>
          <div id="winInfo" class="cg-hint" style="text-align:center;font-weight:600;color:var(--cg-cash);"></div>
          <div class="cg-hint" style="text-align:center;margin-top:-4px;">Host sets these; they apply to everyone in the room.</div>
          <button id="createBtn" class="cg-btn cg-btn-primary">Create Room</button>
          <div class="cg-divider">OR</div>
          <div style="display:flex;gap:8px;">
            <input id="codeInput" class="cg-input" placeholder="ROOM CODE" maxlength="4"
                   style="flex:1;text-transform:uppercase;letter-spacing:4px;font-weight:700;text-align:center;" />
            <button id="joinBtn" class="cg-btn cg-btn-join" style="flex:0 0 auto;">Join</button>
          </div>
          <div id="statusText" style="font-size:13px;color:var(--cg-danger);min-height:18px;text-align:center;"></div>
        </div>
        <div style="margin-top:16px;padding-top:14px;border-top:1px solid var(--cg-line);">
          <div class="cg-label" style="margin-bottom:7px;">How to play</div>
          <div class="cg-hint">
            Click the game to grab the mouse — mouse looks, WASD moves.
            Sneak into the other family's bedrooms, grab a bundle and carry it home;
            it banks the moment you are back on your own property.
            Catch an intruder anywhere on YOUR property with <b>SPACE</b> and they go to
            your basement until a family member frees them or the clock runs out.
            Your score is the cash sitting in your bedrooms. First to the target wins
            the round — best of three.
          </div>
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
      status.style.color = "var(--cg-text-dim)";
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
      status.style.color = "var(--cg-text-dim)";
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
      ? `<div style="text-align:center;margin-bottom:16px;">
           <div class="cg-label">Room code</div>
           <div class="cg-num" style="font-size:46px;font-weight:800;letter-spacing:10px;margin:4px 0 2px;
                       background:linear-gradient(180deg,#fff,#ffd98a);-webkit-background-clip:text;background-clip:text;color:transparent;">${this.roomCode}</div>
           <div class="cg-hint">Send your friends this link and the code</div>
           <div class="cg-hint" style="color:var(--cg-a);word-break:break-all;">${shareUrl}</div>
         </div>`
      : "";

    const panel = document.createElement("div");
    panel.className = "cg-panel cg-rise";
    panel.style.cssText = "padding:22px 26px;width:min(92vw, 460px);";
    panel.innerHTML = `
        ${codeBlock}
        <div id="waitCount" style="text-align:center;font-size:17px;font-weight:700;">Waiting for players…</div>
        <div id="modeInfo" class="cg-hint" style="text-align:center;margin-top:3px;"></div>
        <div id="playerList" style="margin-top:14px;display:flex;flex-direction:column;gap:7px;"></div>
        <div id="youAre" class="cg-hint" style="text-align:center;margin-top:14px;"></div>
        <div id="hostControls" style="margin-top:16px;padding-top:14px;border-top:1px solid var(--cg-line);"></div>`;
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
            ? `<button class="cg-btn" data-swap="${p.id}" data-team="${otherTeam}"
                 style="margin-left:8px;font-size:11px;padding:4px 9px;font-weight:600;">→ ${otherTeam}</button>`
            : "";
          rows += `<div style="display:flex;align-items:center;gap:10px;font-size:14px;padding:7px 10px;
                        background:rgba(0,0,0,.22);border:1px solid var(--cg-line);border-radius:var(--cg-r-sm);">
              <span style="width:9px;height:9px;border-radius:50%;background:${color};box-shadow:0 0 10px ${color};display:inline-block;"></span>
              <span style="font-weight:600;">${p.name}${you}</span>
              ${p.isBot ? `<span class="cg-label" style="color:var(--cg-text-faint);">bot</span>` : ""}
              <span style="margin-left:auto;color:${color};font-weight:800;font-size:12px;letter-spacing:.06em;">${p.team}</span>
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
                  <div class="cg-label">Team ${team} bots</div>
                  <div style="display:flex;align-items:center;justify-content:center;gap:10px;margin-top:6px;">
                    <button class="cg-btn" data-bot-dec="${team}" style="width:30px;height:30px;padding:0;font-size:17px;">−</button>
                    <span class="cg-num" style="min-width:16px;font-weight:800;font-size:16px;">${countBotsOnTeam(state, team)}</span>
                    <button class="cg-btn" data-bot-inc="${team}" style="width:30px;height:30px;padding:0;font-size:17px;">+</button>
                  </div>
                </div>`
                )
                .join("")}
            </div>
            <button id="startGameBtn" class="cg-btn ${canStart ? "cg-btn-go" : ""}" ${canStart ? "" : "disabled"}
              style="width:100%;">${startLabel}</button>`;

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
