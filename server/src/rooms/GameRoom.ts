import { Room, Client } from "colyseus";
import { GameState, PlayerState, CashBundleState } from "../schema/GameState";
import {
  getZoneAt,
  isEnemyBedroom,
  isOwnHome,
  jailBasementForTeam,
  SPAWN_POINTS,
  JAIL_POSITIONS,
  BUNDLE_POSITIONS,
  SCORE_SLOT_POSITIONS,
  WORLD_WIDTH,
  WORLD_HEIGHT,
  Team,
} from "../zones";

// Server ranges are a touch more generous than the client's prompt range (60px)
// so an action never gets rejected right when the prompt says it's available.
const PICKUP_RANGE = 72;
const LOCK_RESCUE_RANGE = 82;
const ROUND_TIME = 300;
const WIN_SCORE = 5;
const WINS_NEEDED = 2;
const PRE_ROUND_COUNTDOWN = 3;
const ROUND_END_PAUSE = 3;
const JAIL_TIME = 60;

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateRoomCode(): string {
  let code = "";
  for (let i = 0; i < 4; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function distance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

// A bundle's home team is encoded in its id: "b*" belongs to Team B, "a*" to Team A.
function originBedroom(bundleId: string): "bedroomA" | "bedroomB" {
  return bundleId.startsWith("b") ? "bedroomB" : "bedroomA";
}

function originPosition(bundleId: string): { x: number; y: number } {
  const bedroom = originBedroom(bundleId);
  const idx = Math.max(0, parseInt(bundleId.slice(1), 10) - 1);
  const list = BUNDLE_POSITIONS[bedroom];
  return list[Math.min(idx, list.length - 1)];
}

export class GameRoom extends Room<GameState> {
  maxClients = 4;
  code = generateRoomCode();

  private slots = new Map<string, { team: Team; slot: number }>();
  // Tracks bundles that were carried away from an enemy's SCORED pile, so that if the
  // thief is caught the point is restored to the team that had earned it (closes the
  // "steal a scored bundle and suicide to drain the enemy for free" loophole).
  private stolenFrom = new Map<string, Team>();

  onCreate() {
    this.setState(new GameState());

    this.onMessage("move", (client, msg) => this.handleMove(client, msg));
    this.onMessage("pickupCash", (client, msg) => this.handlePickup(client, msg));
    this.onMessage("depositCash", (client, msg) => this.handleDeposit(client, msg));
    this.onMessage("lockPlayer", (client, msg) => this.handleLock(client, msg));
    this.onMessage("rescuePlayer", (client, msg) => this.handleRescue(client, msg));
    this.onMessage("stealScored", (client, msg) => this.handleStealScored(client, msg));

    this.clock.setInterval(() => this.tick(), 1000);
  }

  onJoin(client: Client, options: { name?: string }) {
    const team: Team = this.countTeam("B") < 2 ? "B" : "A";
    const slot = this.firstFreeSlot(team);

    this.slots.set(client.sessionId, { team, slot });

    const spawn = SPAWN_POINTS[team][slot];
    const player = new PlayerState();
    player.id = client.sessionId;
    player.name = (options?.name || "Player").slice(0, 16) || "Player";
    player.team = team;
    player.x = spawn.x;
    player.y = spawn.y;
    this.state.players.set(client.sessionId, player);

    if (this.state.players.size === 4 && this.state.phase === "waiting") {
      this.startCountdown();
    }
  }

  onLeave(client: Client) {
    // Free any bundle this player was carrying so it doesn't vanish from play.
    const bundle = this.findCarriedBundle(client.sessionId);
    if (bundle) this.returnCarriedBundle(bundle);

    this.state.players.delete(client.sessionId);
    this.slots.delete(client.sessionId);
    this.deriveScores();

    if (this.state.players.size === 0) {
      this.disconnect();
    }
  }

  private countTeam(team: Team): number {
    let count = 0;
    this.state.players.forEach((p) => {
      if (p.team === team) count++;
    });
    return count;
  }

  private firstFreeSlot(team: Team): number {
    const taken = new Set<number>();
    this.slots.forEach((s) => {
      if (s.team === team) taken.add(s.slot);
    });
    let slot = 0;
    while (taken.has(slot)) slot++;
    return Math.min(slot, SPAWN_POINTS[team].length - 1);
  }

  private findCarriedBundle(playerId: string): CashBundleState | undefined {
    let found: CashBundleState | undefined;
    this.state.cashBundles.forEach((b) => {
      if (b.location === `carried:${playerId}`) found = b;
    });
    return found;
  }

  // Score is DERIVED from bundle state (count of bundles currently scored in each
  // bedroom). This makes score drift impossible and keeps every client in agreement.
  private deriveScores() {
    let a = 0;
    let b = 0;
    this.state.cashBundles.forEach((bundle) => {
      if (bundle.location === "scored:A") a++;
      else if (bundle.location === "scored:B") b++;
    });
    this.state.scoreA = a;
    this.state.scoreB = b;
  }

  // Send a carried bundle home. If it was stolen from a scored pile and the carrier
  // never completed the deposit, restore it to the team that had earned it; otherwise
  // it returns to its original bedroom as a fresh (unscored) target.
  private returnCarriedBundle(bundle: CashBundleState) {
    const restoredTeam = this.stolenFrom.get(bundle.id);
    if (restoredTeam) {
      const count = this.countScored(restoredTeam);
      const slots = SCORE_SLOT_POSITIONS[restoredTeam];
      const pos = slots[Math.min(count, slots.length - 1)];
      bundle.location = `scored:${restoredTeam}`;
      bundle.isScored = true;
      bundle.x = pos.x;
      bundle.y = pos.y;
    } else {
      const pos = originPosition(bundle.id);
      bundle.location = originBedroom(bundle.id);
      bundle.isScored = false;
      bundle.x = pos.x;
      bundle.y = pos.y;
    }
    this.stolenFrom.delete(bundle.id);
  }

  private countScored(team: Team): number {
    let count = 0;
    this.state.cashBundles.forEach((b) => {
      if (b.location === `scored:${team}`) count++;
    });
    return count;
  }

  // ---- message handlers ----

  private handleMove(client: Client, msg: { x: number; y: number; vx: number; vy: number }) {
    const player = this.state.players.get(client.sessionId);
    if (!player || this.state.phase !== "playing" || player.isJailed) return;
    if (typeof msg?.x !== "number" || typeof msg?.y !== "number") return;
    player.x = clamp(msg.x, 0, WORLD_WIDTH);
    player.y = clamp(msg.y, 0, WORLD_HEIGHT);
    player.vx = msg.vx ?? 0;
    player.vy = msg.vy ?? 0;
  }

  private handlePickup(client: Client, msg: { bundleId: string }) {
    const player = this.state.players.get(client.sessionId);
    if (!player || this.state.phase !== "playing" || player.isJailed || player.isCarryingCash) return;
    const bundle = this.state.cashBundles.get(msg?.bundleId);
    if (!bundle) return;

    const enemyBedroom = player.team === "B" ? "bedroomA" : "bedroomB";
    if (bundle.location !== enemyBedroom) return;
    if (!isEnemyBedroom(player.team as Team, player.x, player.y)) return;
    if (distance(player, bundle) > PICKUP_RANGE) return;

    bundle.location = `carried:${player.id}`;
    bundle.isScored = false;
    this.stolenFrom.delete(bundle.id);
    player.isCarryingCash = true;
  }

  private handleStealScored(client: Client, msg: { bundleId: string }) {
    const player = this.state.players.get(client.sessionId);
    if (!player || this.state.phase !== "playing" || player.isJailed || player.isCarryingCash) return;
    const bundle = this.state.cashBundles.get(msg?.bundleId);
    if (!bundle) return;

    const enemyTeam: Team = player.team === "B" ? "A" : "B";
    if (bundle.location !== `scored:${enemyTeam}`) return;
    if (!isEnemyBedroom(player.team as Team, player.x, player.y)) return;
    if (distance(player, bundle) > PICKUP_RANGE) return;

    bundle.location = `carried:${player.id}`;
    bundle.isScored = false;
    this.stolenFrom.set(bundle.id, enemyTeam); // remember to restore if the thief is caught
    player.isCarryingCash = true;
    this.deriveScores(); // enemy's count drops immediately on pickup (per checklist)
  }

  private handleDeposit(client: Client, msg: { bundleId: string }) {
    const player = this.state.players.get(client.sessionId);
    if (!player || this.state.phase !== "playing" || !player.isCarryingCash) return;
    const bundle = this.state.cashBundles.get(msg?.bundleId);
    if (!bundle || bundle.location !== `carried:${player.id}`) return;
    if (!isOwnHome(player.team as Team, player.x, player.y)) return;

    const team = player.team as Team;
    const idx = Math.min(this.countScored(team), SCORE_SLOT_POSITIONS[team].length - 1);
    const pos = SCORE_SLOT_POSITIONS[team][idx];
    bundle.location = `scored:${team}`;
    bundle.isScored = true;
    bundle.x = pos.x;
    bundle.y = pos.y;
    this.stolenFrom.delete(bundle.id); // deposit completed - no longer restorable
    player.isCarryingCash = false;

    this.deriveScores();
    this.checkWin();
  }

  private handleLock(client: Client, msg: { targetId: string }) {
    const player = this.state.players.get(client.sessionId);
    const target = this.state.players.get(msg?.targetId);
    if (!player || !target || this.state.phase !== "playing") return;
    if (player.team === target.team) return;
    if (player.isJailed || target.isJailed) return;

    const myZone = getZoneAt(player.x, player.y);
    const targetZone = getZoneAt(target.x, target.y);
    if (myZone !== targetZone) return;
    if (!isOwnHome(player.team as Team, player.x, player.y)) return;
    if (distance(player, target) > LOCK_RESCUE_RANGE) return;

    if (target.isCarryingCash) {
      const bundle = this.findCarriedBundle(target.id);
      if (bundle) this.returnCarriedBundle(bundle);
      target.isCarryingCash = false;
    }

    target.isJailed = true;
    target.jailTimer = JAIL_TIME;
    const jailZone = jailBasementForTeam(target.team as Team);
    const jailPos = JAIL_POSITIONS[jailZone];
    target.x = jailPos.x;
    target.y = jailPos.y;
    target.vx = 0;
    target.vy = 0;

    this.deriveScores();
    this.checkWin();
  }

  private handleRescue(client: Client, msg: { targetId: string }) {
    const player = this.state.players.get(client.sessionId);
    const target = this.state.players.get(msg?.targetId);
    if (!player || !target || this.state.phase !== "playing") return;
    if (player.isJailed) return; // a jailed player can't rescue anyone
    if (player.team !== target.team) return;
    if (!target.isJailed) return;

    const requiredZone = jailBasementForTeam(player.team as Team);
    if (getZoneAt(player.x, player.y) !== requiredZone) return;
    if (distance(player, target) > LOCK_RESCUE_RANGE) return;

    target.isJailed = false;
    target.jailTimer = 0;
  }

  // ---- round / match flow ----

  private checkWin() {
    if (this.state.phase !== "playing") return;
    if (this.state.scoreA >= WIN_SCORE) this.finalizeRound("A");
    else if (this.state.scoreB >= WIN_SCORE) this.finalizeRound("B");
  }

  private finalizeRound(winner: "A" | "B") {
    this.state.roundWinner = winner;
    if (winner === "A") this.state.winsA += 1;
    else this.state.winsB += 1;

    this.state.phase = "roundEnd";
    this.state.countdown = ROUND_END_PAUSE;

    if (this.state.winsA >= WINS_NEEDED || this.state.winsB >= WINS_NEEDED) {
      this.state.matchWinner = this.state.winsA > this.state.winsB ? "A" : "B";
    }
  }

  private finishRoundByTimeout() {
    if (this.state.phase !== "playing") return;
    if (this.state.scoreA === this.state.scoreB) {
      this.state.roundWinner = "";
      this.state.phase = "roundEnd";
      this.state.countdown = ROUND_END_PAUSE;
    } else {
      const winner = this.state.scoreA > this.state.scoreB ? "A" : "B";
      this.finalizeRound(winner);
    }
  }

  private startCountdown() {
    this.resetRoundState();
    this.state.phase = "countdown";
    this.state.countdown = PRE_ROUND_COUNTDOWN;
  }

  private resetRoundState() {
    this.state.roundWinner = "";
    this.stolenFrom.clear();

    this.state.cashBundles.clear();
    this.initCashBundles();
    this.deriveScores();

    this.state.players.forEach((player, sessionId) => {
      player.isCarryingCash = false;
      player.isJailed = false;
      player.jailTimer = 0;
      player.vx = 0;
      player.vy = 0;
      const slot = this.slots.get(sessionId);
      if (slot) {
        const spawn = SPAWN_POINTS[slot.team][slot.slot];
        player.x = spawn.x;
        player.y = spawn.y;
      }
    });
  }

  private initCashBundles() {
    BUNDLE_POSITIONS.bedroomB.forEach((pos, i) => {
      const bundle = new CashBundleState();
      bundle.id = `b${i + 1}`;
      bundle.x = pos.x;
      bundle.y = pos.y;
      bundle.location = "bedroomB";
      bundle.isScored = false;
      this.state.cashBundles.set(bundle.id, bundle);
    });
    BUNDLE_POSITIONS.bedroomA.forEach((pos, i) => {
      const bundle = new CashBundleState();
      bundle.id = `a${i + 1}`;
      bundle.x = pos.x;
      bundle.y = pos.y;
      bundle.location = "bedroomA";
      bundle.isScored = false;
      this.state.cashBundles.set(bundle.id, bundle);
    });
  }

  private tick() {
    if (this.state.phase === "countdown") {
      this.state.countdown -= 1;
      if (this.state.countdown <= 0) {
        this.state.phase = "playing";
        this.state.roundTimer = ROUND_TIME;
      }
    } else if (this.state.phase === "playing") {
      this.state.roundTimer -= 1;

      this.state.players.forEach((player) => {
        if (player.isJailed) {
          player.jailTimer -= 1;
          if (player.jailTimer <= 0) {
            player.jailTimer = 0;
            player.isJailed = false;
          }
        }
      });

      if (this.state.roundTimer <= 0) {
        this.state.roundTimer = 0;
        this.finishRoundByTimeout();
      }
    } else if (this.state.phase === "roundEnd") {
      this.state.countdown -= 1;
      if (this.state.countdown <= 0) {
        if (this.state.matchWinner) {
          this.state.phase = "matchEnd";
        } else {
          if (this.state.roundWinner !== "") {
            this.state.roundNumber += 1;
          }
          this.startCountdown();
        }
      }
    }
  }
}
