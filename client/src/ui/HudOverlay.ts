import type { Room } from "colyseus.js";
import { COLORS, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";
import { ZONE_RECTS, type Team } from "../geometry/floorplan";

function toHex(color: number): string {
  return "#" + color.toString(16).padStart(6, "0");
}

const MINIMAP_W = 240;
const MINIMAP_H = (MINIMAP_W / WORLD_WIDTH) * WORLD_HEIGHT;
const MM_SCALE = MINIMAP_W / WORLD_WIDTH;

// Plain DOM/CSS + a 2D canvas minimap - a mechanical port of UIScene.ts, which
// only ever drew text and simple shapes (no reason to keep a whole second
// rendering engine alive just for a HUD overlay). CSS positioning replaces
// Phaser's per-resize layout() math entirely, so there's no resize handler
// needed for anything except redrawing the minimap contents each frame.
export class HudOverlay {
  private root: HTMLDivElement;
  private timerEl!: HTMLDivElement;
  private roundEl!: HTMLDivElement;
  private objectiveEl!: HTMLDivElement;
  private promptEl!: HTMLDivElement;
  private jailEl!: HTMLDivElement;
  private overlayBg!: HTMLDivElement;
  private overlayTitle!: HTMLDivElement;
  private overlaySub!: HTMLDivElement;
  private minimapCanvas!: HTMLCanvasElement;
  private localTeam: Team;

  constructor(container: HTMLElement, localTeam: Team) {
    this.localTeam = localTeam;
    this.root = document.createElement("div");
    this.root.innerHTML = HudOverlay.template();
    container.appendChild(this.root);

    this.timerEl = this.q("hud-timer");
    this.roundEl = this.q("hud-round");
    this.objectiveEl = this.q("hud-objective");
    this.promptEl = this.q("hud-prompt");
    this.jailEl = this.q("hud-jail");
    this.overlayBg = this.q("hud-overlay-bg");
    this.overlayTitle = this.q("hud-overlay-title");
    this.overlaySub = this.q("hud-overlay-sub");
    this.minimapCanvas = this.q("hud-minimap") as unknown as HTMLCanvasElement;
    this.minimapCanvas.width = MINIMAP_W;
    this.minimapCanvas.height = MINIMAP_H;

    const color = toHex(localTeam === "B" ? COLORS.teamB : COLORS.teamA);
    this.objectiveEl.style.color = color;
  }

  private q<T extends HTMLElement = HTMLDivElement>(id: string): T {
    return this.root.querySelector(`#${id}`) as T;
  }

  private static template(): string {
    const strokeStyle = "-webkit-text-stroke:3px #000; text-shadow:0 1px 3px rgba(0,0,0,.6);";
    const strokeThin = "-webkit-text-stroke:1.5px #000; text-shadow:0 1px 2px rgba(0,0,0,.6);";
    return `
      <style>
        #hud-root * { font-family: system-ui, sans-serif; color: #fff; }
        #hud-topleft { position:fixed; top:14px; left:20px; display:flex; flex-direction:column; gap:4px; }
        #hud-timer { font-size:34px; font-weight:800; ${strokeStyle} }
        #hud-round { font-size:15px; ${strokeThin} }
        #hud-objective { position:fixed; top:12px; right:14px; font-size:15px; font-weight:800; text-align:right; ${strokeStyle} }
        #hud-controls { position:fixed; bottom:10px; left:50%; transform:translateX(-50%); font-size:13px; text-align:center; ${strokeThin} }
        #hud-prompt { position:fixed; bottom:38px; left:50%; transform:translateX(-50%); font-size:16px; font-weight:700; color:#ffff66; text-align:center; ${strokeThin} display:none; }
        #hud-minimap-wrap { position:fixed; top:8px; left:50%; transform:translateX(-50%); background:rgba(0,0,0,.35); padding:3px; border-radius:4px; }
        #hud-minimap { display:block; border:1.5px solid #222; }
        #hud-jail { position:fixed; top:50%; left:50%; transform:translate(-50%, 90px); font-size:20px; font-weight:700; color:#ffdd55; text-align:center; background:rgba(0,0,0,.65); padding:8px 12px; border-radius:8px; white-space:pre-line; display:none; }
        #hud-overlay-bg { position:fixed; inset:0; background:rgba(0,0,0,.55); display:none; }
        #hud-overlay-title { position:fixed; top:50%; left:50%; transform:translate(-50%, -56px); font-size:30px; font-weight:800; text-align:center; ${strokeStyle} display:none; }
        #hud-overlay-sub { position:fixed; top:50%; left:50%; transform:translate(-50%, -4px); font-size:18px; text-align:center; ${strokeThin} display:none; }
      </style>
      <div id="hud-topleft">
        <div id="hud-timer">05:00</div>
        <div id="hud-round">Round 1 of 3</div>
      </div>
      <div id="hud-objective"></div>
      <div id="hud-controls">W/&#8593; : Forward &nbsp; A/D : Veer &nbsp; S/&#8595; : Back up &nbsp;&nbsp; SPACE : Action &nbsp;&nbsp; (cash deposits automatically at home)</div>
      <div id="hud-prompt"></div>
      <div id="hud-minimap-wrap"><canvas id="hud-minimap"></canvas></div>
      <div id="hud-jail"></div>
      <div id="hud-overlay-bg"></div>
      <div id="hud-overlay-title"></div>
      <div id="hud-overlay-sub"></div>
    `;
  }

  // No compass arrows here anymore: the camera rotates with the character now,
  // so screen-left/right no longer map to fixed world directions - the minimap
  // is the direction reference.
  private objectiveMessage(carrying: boolean): string {
    const teamLabel = `TEAM ${this.localTeam}`;
    return carrying ? `${teamLabel}  •  Bring the cash HOME` : `${teamLabel}  •  Steal the enemy's cash`;
  }

  private drawMinimap(room: Room) {
    const ctx = this.minimapCanvas.getContext("2d")!;
    ctx.clearRect(0, 0, MINIMAP_W, MINIMAP_H);

    // Zone fills come straight from the floor plan's ZONE_RECTS, so the
    // minimap can never drift out of sync with the world geometry.
    for (const z of ZONE_RECTS) {
      ctx.fillStyle = toHex(z.color);
      ctx.fillRect(z.xMin * MM_SCALE, z.yMin * MM_SCALE, (z.xMax - z.xMin) * MM_SCALE, (z.yMax - z.yMin) * MM_SCALE);
    }
    ctx.strokeStyle = "#222";
    ctx.lineWidth = 1.5;
    ctx.strokeRect(0, 0, MINIMAP_W, MINIMAP_H);

    room.state.players.forEach((p: any, id: string) => {
      const px = p.x * MM_SCALE;
      const py = p.y * MM_SCALE;
      const color = toHex(p.team === "B" ? COLORS.teamB : COLORS.teamA);
      if (id === room.sessionId) {
        ctx.fillStyle = "#fff";
        ctx.beginPath();
        ctx.arc(px, py, 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(px, py, 3.2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.globalAlpha = p.isJailed ? 0.4 : 1;
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(px, py, 3.2, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
      }
    });
  }

  update(room: Room, promptText: string) {
    const state = room.state as any;

    const t = Math.max(0, Math.floor(state.roundTimer));
    const mins = Math.floor(t / 60).toString().padStart(2, "0");
    const secs = (t % 60).toString().padStart(2, "0");
    this.timerEl.textContent = `${mins}:${secs}`;
    this.roundEl.textContent = `Round ${state.roundNumber} of 3  •  First to ${state.winScore || 5}`;

    const self = room.state.players.get(room.sessionId);
    this.objectiveEl.textContent = this.objectiveMessage(!!self?.isCarryingCash);

    this.promptEl.textContent = promptText;
    this.promptEl.style.display = promptText ? "block" : "none";

    this.drawMinimap(room);

    if (self?.isJailed) {
      const secsLeft = Math.max(0, Math.ceil(self.jailTimer));
      this.jailEl.style.display = "block";
      this.jailEl.textContent = `JAILED  •  A teammate can free you\nAuto-release in ${secsLeft}s`;
    } else {
      this.jailEl.style.display = "none";
    }

    const showOverlay = (title: string, sub: string) => {
      this.overlayBg.style.display = "block";
      this.overlayTitle.style.display = "block";
      this.overlayTitle.textContent = title;
      this.overlaySub.style.display = sub.length > 0 ? "block" : "none";
      this.overlaySub.textContent = sub;
    };
    const hideOverlay = () => {
      this.overlayBg.style.display = "none";
      this.overlayTitle.style.display = "none";
      this.overlaySub.style.display = "none";
    };

    if (state.phase === "countdown") {
      showOverlay(`ROUND ${state.roundNumber}`, `Get ready...  ${Math.max(0, Math.floor(state.countdown))}`);
    } else if (state.phase === "roundEnd") {
      const title = state.roundWinner
        ? `ROUND ${state.roundNumber}: TEAM ${state.roundWinner} WINS!`
        : `ROUND ${state.roundNumber}: TIE - REPLAY`;
      showOverlay(title, `Next round in ${Math.max(0, Math.floor(state.countdown))}...`);
    } else if (state.phase === "matchEnd") {
      showOverlay(`TEAM ${state.matchWinner} WINS THE MATCH!`, "Refresh the page to play again");
    } else {
      hideOverlay();
    }
  }

  dispose() {
    this.root.remove();
  }
}
