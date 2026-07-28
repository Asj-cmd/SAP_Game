import type { Room } from "colyseus.js";
import { COLORS, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";
import { ZONE_RECTS, type Team } from "../geometry/floorplan";

function toHex(color: number): string {
  return "#" + color.toString(16).padStart(6, "0");
}

// Small enough to sit unobtrusively in the bottom-right corner; the aspect
// ratio tracks the world's automatically via MINIMAP_H below.
const MINIMAP_W = 176;
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
  private rematchBtn!: HTMLButtonElement;
  private minimapCanvas!: HTMLCanvasElement;
  private scoreOwnEl!: HTMLSpanElement;
  private scoreFoeEl!: HTMLSpanElement;
  private winPipsEl!: HTMLDivElement;
  private localTeam: Team;
  private onRematch: () => void;

  constructor(container: HTMLElement, localTeam: Team, onRematch: () => void) {
    this.localTeam = localTeam;
    this.onRematch = onRematch;
    this.root = document.createElement("div");
    this.root.innerHTML = HudOverlay.template(localTeam);
    container.appendChild(this.root);

    // Team accent colors drive every highlight in the HUD via CSS vars, so the
    // panels read as "yours" (own team) vs "theirs" at a glance.
    const own = toHex(localTeam === "B" ? COLORS.teamB : COLORS.teamA);
    const foe = toHex(localTeam === "B" ? COLORS.teamA : COLORS.teamB);
    this.root.style.setProperty("--team", own);
    this.root.style.setProperty("--foe", foe);

    this.timerEl = this.q("hud-timer");
    this.roundEl = this.q("hud-round");
    this.objectiveEl = this.q("hud-objective");
    this.promptEl = this.q("hud-prompt");
    this.jailEl = this.q("hud-jail");
    this.overlayBg = this.q("hud-overlay-bg");
    this.overlayTitle = this.q("hud-overlay-title");
    this.overlaySub = this.q("hud-overlay-sub");
    this.rematchBtn = this.q<HTMLButtonElement>("hud-rematch");
    this.scoreOwnEl = this.q<HTMLSpanElement>("hud-score-own");
    this.scoreFoeEl = this.q<HTMLSpanElement>("hud-score-foe");
    this.winPipsEl = this.q("hud-win-pips");
    this.minimapCanvas = this.q("hud-minimap") as unknown as HTMLCanvasElement;
    this.minimapCanvas.width = MINIMAP_W;
    this.minimapCanvas.height = MINIMAP_H;

    this.objectiveEl.style.color = own;

    this.rematchBtn.addEventListener("click", () => this.onRematch());
  }

  private q<T extends HTMLElement = HTMLDivElement>(id: string): T {
    return this.root.querySelector(`#${id}`) as T;
  }

  // Shown while the pointer is NOT locked, so players know how to get the
  // mouse-look camera back after pressing ESC (or before the first click).
  setMouseHint(show: boolean) {
    this.q("hud-mouse-hint").style.display = show ? "block" : "none";
  }

  // Confirms a graphics-quality change. It reuses the mouse-hint strip rather
  // than adding a second floating panel - the two can never be wanted at the
  // same time (one shows with the pointer free, the other on a keypress during
  // play) and one strip is one thing for the eye to learn.
  private qualityTimer?: number;
  showQuality(tier: string) {
    const strip = this.q("hud-mouse-hint");
    strip.textContent = `Graphics: ${tier.toUpperCase()}`;
    strip.style.display = "block";
    window.clearTimeout(this.qualityTimer);
    this.qualityTimer = window.setTimeout(() => {
      strip.textContent = "Click the game to enable mouse look • ESC frees the mouse";
      strip.style.display = "none";
    }, 1600);
  }

  private static template(localTeam: Team): string {
    // paint-order:stroke fill is the load-bearing part: without it the stroke
    // paints ON TOP of the glyph fill (centered on the outline), which at
    // 13-15px swallows the letterform entirely - text rendered as black
    // smudges. Behind-fill strokes can afford to be a touch wider, which is
    // what keeps white/team-colored fills readable over both the sunlit
    // garden and the dark basement.
    // paint-order:stroke fill is still load-bearing for the few labels that
    // sit DIRECTLY on the 3D scene (the action prompt, the mouse hint): without
    // it the stroke paints on top of the glyph fill and swallows the letters.
    // The panelled labels (timer/score/objective/controls) no longer need it -
    // they read against their own translucent backing instead.
    const strokeThin = "paint-order:stroke fill; -webkit-text-stroke:3px #000; text-shadow:0 1px 2px rgba(0,0,0,.6);";
    // Shared glass-panel look: translucent dark backing + hairline border +
    // soft drop shadow, blurred where the browser supports it. Keeps the HUD
    // legible over both the bright garden and the dark basement.
    const panel =
      "background:linear-gradient(180deg,rgba(30,40,54,.90),rgba(20,27,38,.80)); border:1px solid rgba(255,255,255,.10); border-radius:12px; box-shadow:0 10px 30px rgba(0,0,0,.45), inset 0 1px 0 rgba(255,255,255,.07); backdrop-filter:blur(14px) saturate(1.15); -webkit-backdrop-filter:blur(14px) saturate(1.15);";
    return `
      <style>
        #hud-root * { font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color:#eef3f8; box-sizing:border-box; }
        /* Top-left status panel: a team-accented left edge + timer, round line,
           and a live cash scoreboard with round-win pips. */
        #hud-topleft { position:fixed; top:16px; left:18px; padding:10px 16px 12px 14px; ${panel} border-left:4px solid var(--team); min-width:180px; }
        #hud-timer { font-size:36px; font-weight:800; line-height:1; letter-spacing:-.02em; font-variant-numeric:tabular-nums; }
        #hud-round { font-size:10.5px; font-weight:700; opacity:.5; margin-top:5px; letter-spacing:.14em; text-transform:uppercase; }
        #hud-score { display:flex; align-items:baseline; gap:8px; margin-top:8px; font-weight:800; font-variant-numeric:tabular-nums; }
        #hud-score .lab { font-size:11px; font-weight:700; opacity:.85; letter-spacing:.5px; }
        #hud-score-own { font-size:26px; color:var(--team); }
        #hud-score-foe { font-size:26px; color:var(--foe); }
        #hud-score .dash { font-size:18px; opacity:.5; font-weight:600; }
        #hud-win-pips { display:flex; gap:5px; margin-top:7px; align-items:center; }
        #hud-win-pips .pip { width:9px; height:9px; border-radius:50%; border:1.5px solid rgba(255,255,255,.35); }
        #hud-win-pips .pip.own { background:var(--team); border-color:var(--team); }
        #hud-win-pips .pip.foe { background:var(--foe); border-color:var(--foe); }
        #hud-win-pips .plabel { font-size:9.5px; font-weight:700; opacity:.45; letter-spacing:.14em; margin-right:3px; text-transform:uppercase; }
        /* Objective badge: team-tinted pill, top-right. */
        #hud-objective { position:fixed; top:16px; right:16px; font-size:13px; font-weight:800; text-align:right; padding:9px 15px; ${panel} border-right:3px solid var(--team); letter-spacing:.02em; }
        /* Controls: unobtrusive pill along the bottom. */
        #hud-controls { position:fixed; bottom:12px; left:50%; transform:translateX(-50%); font-size:11.5px; font-weight:600; text-align:center; padding:7px 18px; ${panel} opacity:.78; white-space:nowrap; letter-spacing:.01em; }
        /* bottom:78px keeps this clear of #hud-prompt (bottom:44px) - both can
           show at once (pointer unlocked next to an actionable). */
        #hud-mouse-hint { position:fixed; bottom:78px; left:50%; transform:translateX(-50%); font-size:12px; font-weight:600; color:#bcd; text-align:center; opacity:.8; ${panel} padding:5px 12px; display:none; }
        #hud-prompt { position:fixed; bottom:46px; left:50%; transform:translateX(-50%); font-size:16px; font-weight:800; color:#ffc93c; text-align:center; ${strokeThin} display:none; }
        /* Minimap: framed panel with a small header strip. */
        #hud-minimap-wrap { position:fixed; right:14px; bottom:14px; padding:6px; ${panel} }
        #hud-minimap-hdr { font-size:9px; font-weight:800; letter-spacing:.18em; opacity:.45; text-align:center; margin-bottom:5px; text-transform:uppercase; }
        #hud-minimap { display:block; border-radius:6px; }
        #hud-jail { position:fixed; top:50%; left:50%; transform:translate(-50%, 96px); font-size:18px; font-weight:800; color:#ffc93c; text-align:center; ${panel} border:1px solid rgba(255,201,60,.35); padding:12px 20px; white-space:pre-line; display:none; }
        #hud-overlay-bg { position:fixed; inset:0; background:radial-gradient(ellipse at center, rgba(0,0,0,.45), rgba(0,0,0,.72)); display:none; }
        #hud-overlay-title { position:fixed; top:50%; left:50%; transform:translate(-50%, -60px); font-size:clamp(30px,5vw,46px); font-weight:900; text-align:center; letter-spacing:-.02em; paint-order:stroke fill; -webkit-text-stroke:4px #000; text-shadow:0 6px 30px rgba(0,0,0,.7); display:none; }
        #hud-overlay-sub { position:fixed; top:50%; left:50%; transform:translate(-50%, -6px); font-size:17px; font-weight:600; text-align:center; opacity:.9; ${strokeThin} display:none; }
        /* #hud-root is pointer-events:none (see index.html); this button opts
           back in so it's actually clickable. */
        #hud-rematch { position:fixed; top:50%; left:50%; transform:translate(-50%, 44px); font-size:15px; font-weight:800; letter-spacing:.01em; padding:13px 36px; border:0; border-radius:10px; background:linear-gradient(180deg,#4ec96a,#2b9948); color:#fff; cursor:pointer; pointer-events:auto; box-shadow:0 10px 30px rgba(0,0,0,.45), inset 0 1px 0 rgba(255,255,255,.2); transition:transform .08s ease, filter .12s ease; display:none; }
        #hud-rematch:hover { filter:brightness(1.12); transform:translate(-50%, 42px); }
        #hud-rematch:active { transform:translate(-50%, 46px); }
      </style>
      <div id="hud-topleft">
        <div id="hud-timer">05:00</div>
        <div id="hud-round">Round 1 of 3</div>
        <div id="hud-score">
          <span class="lab" style="color:var(--team)">${localTeam}</span>
          <span id="hud-score-own">0</span>
          <span class="dash">-</span>
          <span id="hud-score-foe">0</span>
          <span class="lab" style="color:var(--foe)">${localTeam === "B" ? "A" : "B"}</span>
        </div>
        <div id="hud-win-pips"></div>
      </div>
      <div id="hud-objective"></div>
      <div id="hud-controls">Mouse / Right stick : Look &nbsp; W/A/S/D or Left stick : Move &nbsp;&nbsp; SPACE or A : Action &nbsp;&nbsp; M : Mute &nbsp;&nbsp; G : Graphics &nbsp;&nbsp; (cash deposits automatically at home)</div>
      <div id="hud-mouse-hint">Click the game to enable mouse look &nbsp;•&nbsp; ESC frees the mouse</div>
      <div id="hud-prompt"></div>
      <div id="hud-minimap-wrap"><div id="hud-minimap-hdr">MAP</div><canvas id="hud-minimap"></canvas></div>
      <div id="hud-jail"></div>
      <div id="hud-overlay-bg"></div>
      <div id="hud-overlay-title"></div>
      <div id="hud-overlay-sub"></div>
      <button id="hud-rematch">Rematch</button>
    `;
  }

  // No compass arrows here anymore: the camera rotates with the character now,
  // so screen-left/right no longer map to fixed world directions - the minimap
  // is the direction reference.
  private objectiveMessage(carrying: boolean): string {
    const teamLabel = `TEAM ${this.localTeam}`;
    return carrying ? `${teamLabel}  •  Bring the cash HOME` : `${teamLabel}  •  Steal the enemy's cash`;
  }

  // Best-of-3 tally: WINS_NEEDED (2) pips per side, filled as rounds are won,
  // own team's on the left. Rebuilt only when the counts change, so it isn't
  // churning DOM every frame.
  private lastPips = "";
  private renderWinPips(ownWins: number, foeWins: number) {
    const key = `${ownWins}:${foeWins}`;
    if (key === this.lastPips) return;
    this.lastPips = key;
    const NEEDED = 2;
    const pip = (filled: boolean, side: "own" | "foe") =>
      `<span class="pip ${filled ? side : ""}"></span>`;
    const own = Array.from({ length: NEEDED }, (_, i) => pip(i < ownWins, "own")).join("");
    const foe = Array.from({ length: NEEDED }, (_, i) => pip(i < foeWins, "foe")).join("");
    this.winPipsEl.innerHTML = `<span class="plabel">WINS</span>${own}<span class="dash" style="opacity:.4;margin:0 2px;">/</span>${foe}`;
  }

  private drawMinimap(room: Room) {
    const ctx = this.minimapCanvas.getContext("2d")!;
    ctx.clearRect(0, 0, MINIMAP_W, MINIMAP_H);

    // The town-house stacks floors on one footprint, so the minimap shows just
    // the local player's CURRENT floor - its zones and only the dots of players
    // on that same floor (someone a storey above/below isn't on your map).
    const localFloor: number = room.state.players.get(room.sessionId)?.floor ?? 0;

    // Zone fills come straight from the floor plan's ZONE_RECTS (this floor's).
    for (const z of ZONE_RECTS) {
      if (z.floor !== localFloor) continue;
      ctx.fillStyle = toHex(z.color);
      ctx.fillRect(z.xMin * MM_SCALE, z.yMin * MM_SCALE, (z.xMax - z.xMin) * MM_SCALE, (z.yMax - z.yMin) * MM_SCALE);
    }
    ctx.strokeStyle = "#222";
    ctx.lineWidth = 1.5;
    ctx.strokeRect(0, 0, MINIMAP_W, MINIMAP_H);

    room.state.players.forEach((p: any, id: string) => {
      if (id !== room.sessionId && p.floor !== localFloor) return; // other floor
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

    // Floor label so the stacked layout is legible at a glance.
    const label = localFloor > 0 ? "F1 · BEDROOMS" : localFloor < 0 ? "B1 · BASEMENT" : "GND · LIVING";
    ctx.fillStyle = "rgba(0,0,0,.55)";
    ctx.fillRect(0, 0, 96, 15);
    ctx.fillStyle = "#fff";
    ctx.font = "bold 9px sans-serif";
    ctx.textBaseline = "middle";
    ctx.fillText(label, 5, 8);
  }

  update(room: Room, promptText: string) {
    const state = room.state as any;

    const t = Math.max(0, Math.floor(state.roundTimer));
    const mins = Math.floor(t / 60).toString().padStart(2, "0");
    const secs = (t % 60).toString().padStart(2, "0");
    this.timerEl.textContent = `${mins}:${secs}`;
    // Timer turns urgent red inside the final 30 seconds.
    this.timerEl.style.color = t <= 30 ? "#ff5a4d" : "#fff";
    this.roundEl.textContent = `Round ${state.roundNumber} of 3  •  First to ${state.winScore || 5}`;

    // Live cash scoreboard, own team first, and best-of-3 round-win pips.
    const ownScore = this.localTeam === "B" ? state.scoreB : state.scoreA;
    const foeScore = this.localTeam === "B" ? state.scoreA : state.scoreB;
    this.scoreOwnEl.textContent = String(ownScore ?? 0);
    this.scoreFoeEl.textContent = String(foeScore ?? 0);
    this.renderWinPips(this.localTeam === "B" ? state.winsB : state.winsA, this.localTeam === "B" ? state.winsA : state.winsB);

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
      this.rematchBtn.style.display = "none";
    };

    if (state.phase === "countdown") {
      showOverlay(`ROUND ${state.roundNumber}`, `Get ready...  ${Math.max(0, Math.floor(state.countdown))}`);
      this.rematchBtn.style.display = "none";
    } else if (state.phase === "roundEnd") {
      const title = state.roundWinner
        ? `ROUND ${state.roundNumber}: TEAM ${state.roundWinner} WINS!`
        : `ROUND ${state.roundNumber}: TIE - REPLAY`;
      showOverlay(title, `Next round in ${Math.max(0, Math.floor(state.countdown))}...`);
      this.rematchBtn.style.display = "none";
    } else if (state.phase === "matchEnd") {
      // The host might quit right on the result screen - state.hostId is checked
      // fresh every frame (not cached at match-end time) so the button follows
      // whoever the server just reassigned host to, live.
      const isHost = state.hostId === room.sessionId;
      showOverlay(
        `TEAM ${state.matchWinner} WINS THE MATCH!`,
        isHost ? "Best of 3 complete" : "Waiting for the host to start a rematch..."
      );
      this.rematchBtn.style.display = isHost ? "block" : "none";
    } else {
      hideOverlay();
    }
  }

  dispose() {
    this.root.remove();
  }
}
