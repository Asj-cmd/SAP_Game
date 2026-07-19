import { Room, Client } from "colyseus";
import { GameState, PlayerState, CashBundleState } from "../schema/GameState";
import {
  getZoneAt,
  isEnemyBedroom,
  isOwnHome,
  jailBasementForTeam,
  SPAWN_POINTS,
  JAIL_POSITIONS,
  bundlePositions,
  scoreSlotPositions,
  WORLD_WIDTH,
  WORLD_HEIGHT,
  WORLD_SCALE,
  Team,
  BOT_WAYPOINTS,
  BotNodeId,
  findBotPath,
  nearestBotNode,
} from "../zones";

// Server ranges are a touch more generous than the client's prompt range so an
// action never gets rejected right when the prompt says it's available. Ranges
// and speeds scale with WORLD_SCALE, keeping balance identical to the original
// 2D-tuned values.
const PICKUP_RANGE = 72 * WORLD_SCALE;
const LOCK_RESCUE_RANGE = 82 * WORLD_SCALE;
const ROUND_TIME = 300;
const WINS_NEEDED = 2;
const PRE_ROUND_COUNTDOWN = 3;
const ROUND_END_PAUSE = 3;
const JAIL_TIME = 60;
// Matches the client's PLAYER_SPEED/CARRY_SPEED (world units/sec) so bots move
// at the same pace a human would.
const BOT_SPEED = 220 * WORLD_SCALE;
const BOT_CARRY_SPEED = 160 * WORLD_SCALE;
const BOT_TICK_MS = 250;

// ---- bot decision weights ----
// Utility-scored AI: every decide cycle a bot scores EVERY plausible action
// (score = value - cost*pathDistance - risk*threat - coordination + noise,
// plus a commit bonus on whatever it's already doing) and adopts the best.
// These are deliberately NAMED and grouped as one table: a future difficulty
// tier should be a different weight table swapped in here (sharper vision,
// less noise, faster re-scoring, different risk appetite) - never an edit to
// the scoring logic itself.
const BOT_DECIDE_MS = 1000; // re-score cadence: the bot's reaction speed
const BOT_DECIDE_JITTER_MS = 300; // de-syncs teammates' decide ticks
const BOT_VALUE_DEPOSIT = 100000; // carrying cash home is near-absolute
const BOT_VALUE_RESCUE = 6000; // a freed teammate outweighs any single bundle
const BOT_VALUE_DEFEND = 4000; // scaled by zeal per bot (see below)
const BOT_VALUE_BUNDLE = 3000; // every bundle is worth the same base
const BOT_VALUE_PATROL = 150; // fallback: wins only when everything else is bad
const BOT_COST_WEIGHT = 0.6; // score lost per world-unit of graph path distance
const BOT_RISK_WEIGHT = 1400; // score lost per enemy sitting on a chokepoint/target
const BOT_VISION_RADIUS = 420 * WORLD_SCALE; // how far away an enemy registers as a threat
const BOT_COMMIT_BONUS = 700; // stickiness: current task wins ties and near-ties
const BOT_COORD_PENALTY = 2600; // a teammate already handles it - usually pick something else
const BOT_CHOICE_NOISE = 250; // imperfection: +-jitter per candidate per re-score
const BOT_VIA_ARRIVE = 60 * WORLD_SCALE; // a route waypoint counts as reached inside this
// Defend pursuit keeps going this long after the intruder leaves home turf,
// so a doorway-hopping raider can't toggle the defender every tick.
const BOT_DEFEND_GRACE_MS = 1500;
// Patrol legs last this long (plus jitter) or until arrival, then re-roll.
const BOT_PATROL_MIN_MS = 3000;
const BOT_PATROL_VAR_MS = 4000;
const BOT_PATROL_ARRIVE = 40 * WORLD_SCALE;

type BotTask = "rescue" | "defend" | "deposit" | "raid" | "patrol";

interface BotOption {
  task: BotTask;
  targetId: string;
  score: number;
  // Route waypoint to pass through first (the enemy's backyard for the
  // yard-route variants of raid/rescue), or null for the direct route.
  via: BotNodeId | null;
}

// Server-side only - none of this is networked schema state; clients never
// see a bot's intentions, only the same position/velocity a human sends.
interface BotMind {
  task: BotTask | null;
  targetId: string; // player id (rescue/defend) or bundle id (raid)
  via: BotNodeId | null; // pending route waypoint (cleared on arrival)
  nextDecideAt: number; // clock ms of the next scheduled re-score
  lastSeenHomeAt: number; // defend: last tick the target was inside our home turf
  patrolNode: BotNodeId | null;
  patrolUntil: number;
  zeal: number; // 0..1 fixed per bot - scales defend value & pile-on willingness
}

// Loop through the map's shared spine - reachable by BOTH teams (only the
// sealed own-bedroom/basement gates are team-blocked in the graph).
const PATROL_NODES: BotNodeId[] = ["livingB", "gateB_garden", "garden", "gateA_garden", "livingA"];

// Match config bounds. Team size 2/3/4 (2v2, 3v3, 4v4). The host only picks bundles
// per bedroom (3-5); the win target is derived from that: 3 bundles -> win at 5,
// 4 -> win at 7, 5 -> win at 9 (winScore = bundles*2 - 1).
const MIN_TEAM_SIZE = 2;
const MAX_TEAM_SIZE = 4;
const MIN_BUNDLES = 3;
const MAX_BUNDLES = 5;

function winScoreForBundles(bundles: number): number {
  return bundles * 2 - 1;
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

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

export class GameRoom extends Room<GameState> {
  maxClients = 4;
  code = generateRoomCode();

  private teamSize = 2;
  private bundlesPerBedroom = 5;
  private bundlePos: Record<"bedroomB" | "bedroomA", { x: number; y: number }[]> = { bedroomB: [], bedroomA: [] };
  private scoreSlots: Record<Team, { x: number; y: number }[]> = { A: [], B: [] };

  private slots = new Map<string, { team: Team; slot: number }>();
  // Tracks bundles that were carried away from an enemy's SCORED pile, so that if the
  // thief is caught the point is restored to the team that had earned it (closes the
  // "steal a scored bundle and suicide to drain the enemy for free" loophole).
  private stolenFrom = new Map<string, Team>();
  // Synthetic-id bots, tracked separately from `this.clients` so onLeave (which is
  // only ever called for real connections) never touches them.
  private botIds = new Set<string>();
  // Per-bot decision state (see BotMind) - lazily created, purely internal.
  private botMinds = new Map<string, BotMind>();

  private originPosition(bundleId: string): { x: number; y: number } {
    const bedroom = originBedroom(bundleId);
    const idx = Math.max(0, parseInt(bundleId.slice(1), 10) - 1);
    const list = this.bundlePos[bedroom];
    return list[Math.min(idx, list.length - 1)];
  }

  onCreate(options: { teamSize?: number; bundles?: number }) {
    this.teamSize = clampInt(options?.teamSize, MIN_TEAM_SIZE, MAX_TEAM_SIZE, 2);
    // Bundles-per-team defaults to teamSize+1 (3 for 2v2, 4 for 3v3, 5 for 4v4); the
    // host can pick any of 3/4/5 regardless of mode.
    const defaultBundles = this.teamSize + 1;
    this.bundlesPerBedroom = clampInt(options?.bundles, MIN_BUNDLES, MAX_BUNDLES, defaultBundles);
    this.maxClients = this.teamSize * 2;

    this.bundlePos = {
      bedroomB: bundlePositions("bedroomB", this.bundlesPerBedroom),
      bedroomA: bundlePositions("bedroomA", this.bundlesPerBedroom),
    };
    // A team can end up banking every bundle in the match (its enemy's N plus its
    // own N stolen back), so the visible score stack needs 2N distinct slots - not
    // N, which made the 4th+ pile overlap the 3rd and "disappear".
    this.scoreSlots = {
      B: scoreSlotPositions("B", this.bundlesPerBedroom * 2),
      A: scoreSlotPositions("A", this.bundlesPerBedroom * 2),
    };

    this.setState(new GameState());
    this.state.teamSize = this.teamSize;
    this.state.winScore = winScoreForBundles(this.bundlesPerBedroom);

    this.onMessage("move", (client, msg) => this.handleMove(client.sessionId, msg));
    this.onMessage("pickupCash", (client, msg) => this.handlePickup(client.sessionId, msg));
    this.onMessage("depositCash", (client, msg) => this.handleDeposit(client.sessionId, msg));
    this.onMessage("lockPlayer", (client, msg) => this.handleLock(client.sessionId, msg));
    this.onMessage("rescuePlayer", (client, msg) => this.handleRescue(client.sessionId, msg));
    this.onMessage("stealScored", (client, msg) => this.handleStealScored(client.sessionId, msg));
    this.onMessage("startGame", (client) => this.handleStartGame(client));
    this.onMessage("assignTeam", (client, msg) => this.handleAssignTeam(client, msg));
    this.onMessage("setBotCount", (client, msg) => this.handleSetBotCount(client, msg));
    this.onMessage("rematch", (client) => this.handleRematch(client));

    this.clock.setInterval(() => this.tick(), 1000);
    this.clock.setInterval(() => this.botTick(), BOT_TICK_MS);
  }

  onJoin(client: Client, options: { name?: string }) {
    if (!this.state.hostId) this.state.hostId = client.sessionId;

    const teamB = this.countTeam("B");
    const teamA = this.countTeam("A");
    let team: Team;
    if (teamB < this.teamSize) team = "B";
    else if (teamA < this.teamSize) team = "A";
    else {
      // Both rosters are already full (bots can occupy slots ahead of a
      // human joining) - maxClients is kept in sync with bot count so this
      // should be rare, but bail out safely rather than overfilling a team.
      client.leave();
      return;
    }
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
  }

  onLeave(client: Client) {
    // Free any bundle this player was carrying so it doesn't vanish from play.
    const bundle = this.findCarriedBundle(client.sessionId);
    if (bundle) this.returnCarriedBundle(bundle);

    this.state.players.delete(client.sessionId);
    this.slots.delete(client.sessionId);
    this.deriveScores();
    this.checkWin(); // the returned bundle can put a team at the target

    if (client.sessionId === this.state.hostId) {
      const nextHost = this.clients.find((c) => c.sessionId !== client.sessionId);
      this.state.hostId = nextHost?.sessionId ?? "";
    }

    // state.players no longer includes the leaving client (deleted above), so
    // subtracting bots tells us how many real connections remain.
    if (this.state.players.size - this.botIds.size <= 0) {
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

  // ---- host controls (lobby only) ----

  private handleStartGame(client: Client) {
    if (client.sessionId !== this.state.hostId) return;
    if (this.state.phase !== "waiting") return;
    if (this.countTeam("B") !== this.teamSize || this.countTeam("A") !== this.teamSize) return;
    this.startCountdown();
  }

  // Only the host, and only from the result screen, can restart a match. Rosters
  // are allowed to be under `teamSize` here even though handleStartGame requires a
  // full roster - that fill check is a gate for STARTING the very first match, not
  // a property the game needs at every subsequent one. A player can leave while the
  // result screen is up (onLeave already reassigns hostId and frees their carried
  // bundle); any seat that emptied gets backfilled with a bot below, so a
  // rage-quit never turns "one more round" into an unfair shorthanded round.
  // startCountdown()'s resetRoundState() rebuilds bundles/scores and respawns
  // everyone still in `this.slots` (humans and bots alike).
  private handleRematch(client: Client) {
    if (client.sessionId !== this.state.hostId) return;
    if (this.state.phase !== "matchEnd") return;

    // Backfill seats vacated since the match started - same addBot path the
    // lobby's bot stepper uses, so the new bots get real slots/spawns.
    for (const team of ["B", "A"] as Team[]) {
      while (this.countTeam(team) < this.teamSize) this.addBot(team);
    }
    // Same human-connection-ceiling bookkeeping as handleSetBotCount: a human
    // must not be able to join into a seat a bot now occupies.
    this.maxClients = this.teamSize * 2 - this.botIds.size;

    this.state.winsA = 0;
    this.state.winsB = 0;
    this.state.roundNumber = 1;
    this.state.matchWinner = "";
    this.state.roundWinner = "";
    this.startCountdown();
  }

  private handleAssignTeam(client: Client, msg: { targetId?: string; team?: string }) {
    if (client.sessionId !== this.state.hostId) return;
    if (this.state.phase !== "waiting") return;
    const target = this.state.players.get(msg?.targetId ?? "");
    const team: Team | null = msg?.team === "A" ? "A" : msg?.team === "B" ? "B" : null;
    if (!target || !team || target.team === team) return;
    if (this.countTeam(team) >= this.teamSize) return; // destination team already full

    target.team = team;
    const slot = this.firstFreeSlot(team);
    this.slots.set(target.id, { team, slot });
    const spawn = SPAWN_POINTS[team][slot];
    target.x = spawn.x;
    target.y = spawn.y;
  }

  private countHumansOnTeam(team: Team): number {
    let count = 0;
    this.state.players.forEach((p, id) => {
      if (p.team === team && !this.botIds.has(id)) count++;
    });
    return count;
  }

  // Bot ids on `team`, ordered by slot ascending (so callers can remove the
  // highest-slot bots first, matching the plan's "remove newest bot first").
  private botsOnTeam(team: Team): string[] {
    const entries: { id: string; slot: number }[] = [];
    this.botIds.forEach((id) => {
      const p = this.state.players.get(id);
      if (p && p.team === team) entries.push({ id, slot: this.slots.get(id)?.slot ?? 0 });
    });
    entries.sort((a, b) => a.slot - b.slot);
    return entries.map((e) => e.id);
  }

  private addBot(team: Team) {
    const slot = this.firstFreeSlot(team);
    const id = `bot-${team}-${slot}-${Math.random().toString(36).slice(2, 8)}`;
    this.slots.set(id, { team, slot });
    this.botIds.add(id);

    const spawn = SPAWN_POINTS[team][slot];
    const bot = new PlayerState();
    bot.id = id;
    bot.name = `Bot ${team}${slot + 1}`;
    bot.team = team;
    bot.isBot = true;
    bot.x = spawn.x;
    bot.y = spawn.y;
    this.state.players.set(id, bot);
  }

  private removeBot(id: string) {
    const bundle = this.findCarriedBundle(id);
    if (bundle) this.returnCarriedBundle(bundle);
    this.state.players.delete(id);
    this.slots.delete(id);
    this.botIds.delete(id);
    this.botMinds.delete(id);
    this.deriveScores();
  }

  private handleSetBotCount(client: Client, msg: { team?: string; count?: number }) {
    if (client.sessionId !== this.state.hostId) return;
    if (this.state.phase !== "waiting") return;
    const team: Team | null = msg?.team === "A" ? "A" : msg?.team === "B" ? "B" : null;
    if (!team) return;

    const maxBots = Math.max(0, this.teamSize - this.countHumansOnTeam(team));
    const targetCount = clampInt(msg?.count, 0, maxBots, 0);
    const currentBots = this.botsOnTeam(team);

    if (targetCount < currentBots.length) {
      for (const id of currentBots.slice(targetCount)) this.removeBot(id);
    } else if (targetCount > currentBots.length) {
      for (let i = currentBots.length; i < targetCount; i++) this.addBot(team);
    }

    // Keep the human-connection ceiling in sync so a human can never join
    // into a slot a bot is already occupying.
    this.maxClients = this.teamSize * 2 - this.botIds.size;
  }

  private findCarriedBundle(playerId: string): CashBundleState | undefined {
    let found: CashBundleState | undefined;
    this.state.cashBundles.forEach((b) => {
      if (b.location === `carried:${playerId}`) found = b;
    });
    return found;
  }

  // Score is DERIVED from bundle state: a team's score is the number of bundles
  // currently sitting in ITS master bedroom - its own originals that haven't been
  // stolen PLUS everything it has banked. With N bundles per team both sides start
  // at N, and the first-to-(2N-1) target means winning the exchange by 2. Deriving
  // (never incrementing) makes score drift impossible.
  private deriveScores() {
    let a = 0;
    let b = 0;
    this.state.cashBundles.forEach((bundle) => {
      if (bundle.location === "scored:A" || bundle.location === "bedroomA") a++;
      else if (bundle.location === "scored:B" || bundle.location === "bedroomB") b++;
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
      const pos = this.freeScoreSlot(restoredTeam);
      bundle.location = `scored:${restoredTeam}`;
      bundle.isScored = true;
      bundle.x = pos.x;
      bundle.y = pos.y;
    } else {
      const pos = this.originPosition(bundle.id);
      bundle.location = originBedroom(bundle.id);
      bundle.isScored = false;
      bundle.x = pos.x;
      bundle.y = pos.y;
    }
    this.stolenFrom.delete(bundle.id);
  }

  // First score-stack slot not already occupied by one of `team`'s scored bundles.
  // Placing into a free slot (rather than slot[count]) means no two piles can ever
  // land on the same position - previously a deposit past the slot capacity, or a
  // bundle returned after its thief was jailed, rendered exactly underneath an
  // existing pile and looked like it had vanished.
  private freeScoreSlot(team: Team): { x: number; y: number } {
    const slots = this.scoreSlots[team];
    const occupied = new Set<string>();
    this.state.cashBundles.forEach((b) => {
      if (b.location === `scored:${team}`) occupied.add(`${b.x},${b.y}`);
    });
    for (const pos of slots) {
      if (!occupied.has(`${pos.x},${pos.y}`)) return pos;
    }
    return slots[slots.length - 1];
  }

  // ---- message handlers ----

  private handleMove(sessionId: string, msg: { x: number; y: number; vx: number; vy: number }) {
    const player = this.state.players.get(sessionId);
    if (!player || this.state.phase !== "playing" || player.isJailed) return;
    if (typeof msg?.x !== "number" || typeof msg?.y !== "number") return;
    player.x = clamp(msg.x, 0, WORLD_WIDTH);
    player.y = clamp(msg.y, 0, WORLD_HEIGHT);
    player.vx = msg.vx ?? 0;
    player.vy = msg.vy ?? 0;
  }

  private handlePickup(sessionId: string, msg: { bundleId: string }) {
    const player = this.state.players.get(sessionId);
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
    this.deriveScores(); // the victim's bedroom count drops the moment it's grabbed
  }

  private handleStealScored(sessionId: string, msg: { bundleId: string }) {
    const player = this.state.players.get(sessionId);
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

  private handleDeposit(sessionId: string, msg: { bundleId: string }) {
    const player = this.state.players.get(sessionId);
    if (!player || this.state.phase !== "playing" || !player.isCarryingCash) return;
    const bundle = this.state.cashBundles.get(msg?.bundleId);
    if (!bundle || bundle.location !== `carried:${player.id}`) return;
    if (!isOwnHome(player.team as Team, player.x, player.y)) return;

    const team = player.team as Team;
    const pos = this.freeScoreSlot(team);
    bundle.location = `scored:${team}`;
    bundle.isScored = true;
    bundle.x = pos.x;
    bundle.y = pos.y;
    this.stolenFrom.delete(bundle.id); // deposit completed - no longer restorable
    player.isCarryingCash = false;

    this.deriveScores();
    this.checkWin();
  }

  private handleLock(sessionId: string, msg: { targetId: string }) {
    const player = this.state.players.get(sessionId);
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

  private handleRescue(sessionId: string, msg: { targetId: string }) {
    const player = this.state.players.get(sessionId);
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
    if (this.state.scoreA >= this.state.winScore) this.finalizeRound("A");
    else if (this.state.scoreB >= this.state.winScore) this.finalizeRound("B");
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
    this.bundlePos.bedroomB.forEach((pos, i) => {
      const bundle = new CashBundleState();
      bundle.id = `b${i + 1}`;
      bundle.x = pos.x;
      bundle.y = pos.y;
      bundle.location = "bedroomB";
      bundle.isScored = false;
      this.state.cashBundles.set(bundle.id, bundle);
    });
    this.bundlePos.bedroomA.forEach((pos, i) => {
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

  // ---- AI bots ----
  // Bots call the exact same handleX methods a real client's message would
  // (with a synthetic sessionId), so they're subject to the same zone/range/
  // phase validation as a human - no special-cased bypass of any rule. The
  // waypoint graph (zones.ts) only decides *how a bot moves*; every action
  // still gates on the real isOwnHome/isEnemyBedroom/distance checks below.

  private botTick() {
    if (this.state.phase !== "playing" || this.botIds.size === 0) return;
    const dt = BOT_TICK_MS / 1000;
    this.botIds.forEach((id) => this.stepBot(id, dt));
  }

  private botMind(id: string): BotMind {
    let m = this.botMinds.get(id);
    if (!m) {
      m = {
        task: null,
        targetId: "",
        via: null,
        nextDecideAt: 0,
        lastSeenHomeAt: 0,
        patrolNode: null,
        patrolUntil: 0,
        zeal: 0.2 + Math.random() * 0.8,
      };
      this.botMinds.set(id, m);
    }
    return m;
  }

  // Decide/move decoupling: movement runs every BOT_TICK_MS toward the
  // committed target, but the full utility re-score only runs every
  // BOT_DECIDE_MS (or immediately when the current task resolves) - bounded
  // server cost and a human-ish reaction delay in one.
  private stepBot(id: string, dt: number) {
    const bot = this.state.players.get(id);
    if (!bot) return;
    const mind = this.botMind(id);
    if (bot.isJailed) {
      bot.vx = 0;
      bot.vy = 0;
      mind.task = null; // re-decide fresh on release
      return;
    }

    const team = bot.team as Team;
    const now = this.clock.currentTime;

    this.validateBotTask(bot, mind, team, now);
    if (!mind.task || now >= mind.nextDecideAt) this.decideBotTask(bot, id, mind, team, now);
    this.executeBotTask(bot, id, mind, team, now, dt);
  }

  // Does the committed task still make sense between re-scores? Clears it on
  // resolution so the bot re-decides immediately instead of executing on a
  // dead target until the next decide tick.
  private validateBotTask(bot: PlayerState, mind: BotMind, team: Team, now: number) {
    switch (mind.task) {
      case "rescue": {
        const t = this.state.players.get(mind.targetId);
        if (!t || !t.isJailed || t.team !== team || bot.isCarryingCash) mind.task = null;
        break;
      }
      case "defend": {
        const t = this.state.players.get(mind.targetId);
        if (!t || t.isJailed || bot.isCarryingCash) {
          mind.task = null;
          break;
        }
        // Grace window: a raider hopping in and out of a doorway shouldn't
        // toggle the defender's whole plan every tick.
        if (isOwnHome(team, t.x, t.y)) mind.lastSeenHomeAt = now;
        else if (now - mind.lastSeenHomeAt > BOT_DEFEND_GRACE_MS) mind.task = null;
        break;
      }
      case "deposit":
        if (!bot.isCarryingCash) mind.task = null;
        break;
      case "raid": {
        const b = this.state.cashBundles.get(mind.targetId);
        if (bot.isCarryingCash || !b || b.location !== this.enemyBedroomOf(team)) mind.task = null;
        break;
      }
      case "patrol":
        break; // filler - always droppable, re-rolled in execute
    }
    if (!mind.task) {
      mind.targetId = "";
      mind.via = null;
    }
  }

  // The core: score every plausible candidate action and commit to the best.
  private decideBotTask(bot: PlayerState, id: string, mind: BotMind, team: Team, now: number) {
    mind.nextDecideAt = now + BOT_DECIDE_MS + Math.random() * BOT_DECIDE_JITTER_MS;

    const options: BotOption[] = [];
    const noise = () => (Math.random() * 2 - 1) * BOT_CHOICE_NOISE;

    // The enemy house's route landmarks: front = in through the living room
    // to the interior stair doors; yard = through the living room's yard door
    // and around the OUTSIDE, entering bedroom/basement by their backyard
    // doors (sealed only for the owners). Scoring both routes per target is
    // what makes bots actually USE the yard: it wins whenever the interior
    // stair gates are the guarded part.
    const enemyYard: BotNodeId = team === "B" ? "backyardA" : "backyardB";
    const enemyYardPos = BOT_WAYPOINTS[enemyYard];
    const enemyYardBedGate = BOT_WAYPOINTS[team === "B" ? "gateA_yardBedroom" : "gateB_yardBedroom"];
    const enemyYardBaseGate = BOT_WAYPOINTS[team === "B" ? "gateA_yardBasement" : "gateB_yardBasement"];
    const enemyBedGate = BOT_WAYPOINTS[team === "B" ? "gateA_bedroom" : "gateB_bedroom"];
    const enemyBaseGate = BOT_WAYPOINTS[team === "B" ? "gateA_basement" : "gateB_basement"];

    if (bot.isCarryingCash) {
      // Dropping cash mid-map to do anything else is always worse - deposit
      // is the only candidate while carrying (near-hard priority by value).
      const homeNode: BotNodeId = team === "B" ? "livingB" : "livingA";
      const cost = this.botPathCost(bot, team, homeNode, BOT_WAYPOINTS[homeNode]);
      options.push({ task: "deposit", targetId: "", via: null, score: BOT_VALUE_DEPOSIT - BOT_COST_WEIGHT * cost });
    } else {
      // Rescue: one candidate per jailed teammate PER route. Guarded routes
      // score lower; a teammate already en route makes it near-worthless
      // (double penalty - two rescuers in one basement is a gift).
      const jailZone = jailBasementForTeam(team);
      const jailPos = JAIL_POSITIONS[jailZone];
      this.state.players.forEach((p, pid) => {
        if (pid === id || p.team !== team || !p.isJailed) return;
        const coord = this.someBotTasked(team, "rescue", pid, id) ? BOT_COORD_PENALTY * 2 : 0;
        const frontCost = this.botPathCost(bot, team, jailZone as BotNodeId, p);
        if (Number.isFinite(frontCost)) {
          const risk = Math.max(this.threatAt(team, enemyBaseGate), this.threatAt(team, jailPos));
          options.push({
            task: "rescue",
            targetId: pid,
            via: null,
            score: BOT_VALUE_RESCUE - BOT_COST_WEIGHT * frontCost - BOT_RISK_WEIGHT * risk - coord + noise(),
          });
        }
        const yardCost =
          this.botPathCost(bot, team, enemyYard, enemyYardPos) +
          distance(enemyYardPos, enemyYardBaseGate) +
          distance(enemyYardBaseGate, p);
        if (Number.isFinite(yardCost)) {
          const risk = Math.max(this.threatAt(team, enemyYardPos), this.threatAt(team, jailPos));
          options.push({
            task: "rescue",
            targetId: pid,
            via: enemyYard,
            score: BOT_VALUE_RESCUE - BOT_COST_WEIGHT * yardCost - BOT_RISK_WEIGHT * risk - coord + noise(),
          });
        }
      });

      // Defend: one candidate per intruder in home turf. Zeal scales how much
      // a bot values defense at all; the coordination penalty (softened by
      // zeal) lets one nearby hot-head still pile on while calm teammates
      // keep raiding.
      this.state.players.forEach((p, pid) => {
        if (pid === id || p.team === team || p.isJailed) return;
        if (!isOwnHome(team, p.x, p.y)) return;
        const { node, aim } = this.defendApproach(team, p, id);
        const cost = this.botPathCost(bot, team, node, aim);
        if (!Number.isFinite(cost)) return;
        const value = BOT_VALUE_DEFEND * (0.8 + 0.4 * mind.zeal);
        const coord = this.someBotTasked(team, "defend", pid, id) ? BOT_COORD_PENALTY * (1 - mind.zeal) : 0;
        options.push({
          task: "defend",
          targetId: pid,
          via: null,
          score: value - BOT_COST_WEIGHT * cost - coord + noise(),
        });
      });

      // Steal: one candidate PER available bundle PER route (not just the
      // nearest). Cost is the real route; risk probes what each route must
      // actually pass - the interior stair gate for the front route, the
      // enemy yard for the yard route (both funnel through the enemy living
      // room, so a guard THERE discounts both equally). A camped route
      // discounts the raid without flatly forbidding it.
      const bedroom = this.enemyBedroomOf(team);
      const chokeNode: BotNodeId = team === "B" ? "livingA" : "livingB";
      const chokePos = BOT_WAYPOINTS[chokeNode];
      this.state.cashBundles.forEach((b) => {
        if (b.location !== bedroom) return;
        const coord = this.someBotTasked(team, "raid", b.id, id) ? BOT_COORD_PENALTY : 0;
        const frontCost = this.botPathCost(bot, team, bedroom as BotNodeId, b);
        if (Number.isFinite(frontCost)) {
          const risk = Math.max(this.threatAt(team, chokePos), this.threatAt(team, enemyBedGate), this.threatAt(team, b));
          options.push({
            task: "raid",
            targetId: b.id,
            via: null,
            score: BOT_VALUE_BUNDLE - BOT_COST_WEIGHT * frontCost - BOT_RISK_WEIGHT * risk - coord + noise(),
          });
        }
        const yardCost =
          this.botPathCost(bot, team, enemyYard, enemyYardPos) +
          distance(enemyYardPos, enemyYardBedGate) +
          distance(enemyYardBedGate, b);
        if (Number.isFinite(yardCost)) {
          const risk = Math.max(this.threatAt(team, chokePos), this.threatAt(team, enemyYardPos), this.threatAt(team, b));
          options.push({
            task: "raid",
            targetId: b.id,
            via: enemyYard,
            score: BOT_VALUE_BUNDLE - BOT_COST_WEIGHT * yardCost - BOT_RISK_WEIGHT * risk - coord + noise(),
          });
        }
      });

      // Patrol: the floor under everything - "do something" beats freezing,
      // and when raids are heavily guarded it doubles as lurking until the
      // guard moves off.
      options.push({ task: "patrol", targetId: "", via: null, score: BOT_VALUE_PATROL + noise() });
    }

    let best: BotOption | undefined;
    for (const o of options) {
      // Commitment within the new structure: the currently-held choice gets a
      // flat bonus, so a marginal score difference doesn't flip the plan on
      // every re-score - only a meaningful change does.
      const score = o.score + (o.task === mind.task && o.targetId === mind.targetId ? BOT_COMMIT_BONUS : 0);
      if (!best || score > best.score) best = { ...o, score };
    }
    if (!best) return;
    if (best.task !== mind.task || best.targetId !== mind.targetId) {
      mind.task = best.task;
      mind.targetId = best.targetId;
      mind.via = best.via;
      if (best.task === "defend") mind.lastSeenHomeAt = now;
      if (best.task !== "patrol") mind.patrolNode = null;
    }
  }

  private enemyBedroomOf(team: Team): "bedroomA" | "bedroomB" {
    return team === "B" ? "bedroomA" : "bedroomB";
  }

  // How threatened `point` is for `team`'s bots: each living enemy inside
  // BOT_VISION_RADIUS contributes linearly with proximity (0..1 each).
  private threatAt(team: Team, point: { x: number; y: number }): number {
    let threat = 0;
    this.state.players.forEach((p) => {
      if (p.team === team || p.isJailed) return;
      const d = distance(p, point);
      if (d < BOT_VISION_RADIUS) threat += 1 - d / BOT_VISION_RADIUS;
    });
    return threat;
  }

  // Real route length through the waypoint graph (not straight-line), so the
  // cost term reflects how far the bot would actually travel. Infinity =
  // unreachable for this team (its own sealed gates).
  private botPathCost(bot: PlayerState, team: Team, targetNode: BotNodeId, targetPoint: { x: number; y: number }): number {
    const startNode = nearestBotNode(bot.x, bot.y);
    if (startNode === targetNode) return distance(bot, targetPoint);
    const path = findBotPath(team, startNode, targetNode);
    if (path.length < 2) return Infinity;
    let cost = distance(bot, BOT_WAYPOINTS[path[0]]);
    for (let i = 1; i < path.length; i++) {
      cost += distance(BOT_WAYPOINTS[path[i - 1]], BOT_WAYPOINTS[path[i]]);
    }
    cost += distance(BOT_WAYPOINTS[path[path.length - 1]], targetPoint);
    return cost;
  }

  private someBotTasked(team: Team, task: BotTask, targetId: string, exceptId: string): boolean {
    let found = false;
    this.botIds.forEach((bid) => {
      if (found || bid === exceptId) return;
      const p = this.state.players.get(bid);
      if (!p || p.team !== team || p.isJailed) return;
      const m = this.botMind(bid);
      if (m.task === task && m.targetId === targetId) found = true;
    });
    return found;
  }

  // Where to route a defender: chase directly in the living room and (now
  // that the yard is on the waypoint graph) in the OWN BACKYARD too. Only
  // the own bedroom stays a guard-the-exits case - this team can't enter it
  // at all. It has TWO exits (interior stairs and the yard door), so the
  // first defender covers the living-side stairs and any pile-on defender
  // covers the yard-side door from inside the yard.
  private defendApproach(team: Team, intruder: PlayerState, selfId: string): { node: BotNodeId; aim: { x: number; y: number } } {
    const S = WORLD_SCALE;
    const living: BotNodeId = team === "B" ? "livingB" : "livingA";
    const yard: BotNodeId = team === "B" ? "backyardB" : "backyardA";
    const zone = getZoneAt(intruder.x, intruder.y);
    if (zone === "bedroomB" || zone === "bedroomA") {
      if (this.someBotTasked(team, "defend", intruder.id, selfId)) {
        const aim = team === "B" ? { x: 110 * S, y: 100 * S } : { x: 1490 * S, y: 100 * S };
        return { node: yard, aim }; // in the yard, at the bedroom's yard door
      }
      const aim = team === "B" ? { x: 340 * S, y: 290 * S } : { x: 1260 * S, y: 290 * S };
      return { node: living, aim }; // just past the stair corridor's living end
    }
    if (zone === "backyardB" || zone === "backyardA") {
      return { node: yard, aim: intruder }; // chase them down in our own yard
    }
    return { node: living, aim: intruder };
  }

  private executeBotTask(bot: PlayerState, id: string, mind: BotMind, team: Team, now: number, dt: number) {
    // Yard-route detour: head to the route waypoint first; once there, the
    // ordinary graph routing continues to the real target - and from the
    // enemy yard, BFS's fewest-hops path IS the yard door.
    if (mind.via && (mind.task === "rescue" || mind.task === "raid")) {
      if (distance(bot, BOT_WAYPOINTS[mind.via]) > BOT_VIA_ARRIVE) {
        this.botMoveToward(bot, team, mind.via, BOT_WAYPOINTS[mind.via], dt);
        return;
      }
      mind.via = null;
    }
    switch (mind.task) {
      case "rescue": {
        const target = this.state.players.get(mind.targetId)!;
        const jailZone = jailBasementForTeam(team);
        this.botMoveToward(bot, team, jailZone as BotNodeId, target, dt);
        if (getZoneAt(bot.x, bot.y) === jailZone && distance(bot, target) <= LOCK_RESCUE_RANGE) {
          this.handleRescue(id, { targetId: target.id });
        }
        return;
      }
      case "defend": {
        const target = this.state.players.get(mind.targetId)!;
        const { node, aim } = this.defendApproach(team, target, id);
        this.botMoveToward(bot, team, node, aim, dt);
        if (isOwnHome(team, bot.x, bot.y) && distance(bot, target) <= LOCK_RESCUE_RANGE) {
          this.handleLock(id, { targetId: target.id });
        }
        return;
      }
      case "deposit": {
        const homeNode: BotNodeId = team === "B" ? "livingB" : "livingA";
        const bundle = this.findCarriedBundle(id);
        this.botMoveToward(bot, team, homeNode, BOT_WAYPOINTS[homeNode], dt);
        if (bundle && isOwnHome(team, bot.x, bot.y)) {
          this.handleDeposit(id, { bundleId: bundle.id });
        }
        return;
      }
      case "raid": {
        const bundle = this.state.cashBundles.get(mind.targetId)!;
        const bedroomNode = this.enemyBedroomOf(team) as BotNodeId;
        this.botMoveToward(bot, team, bedroomNode, bundle, dt);
        if (isEnemyBedroom(team, bot.x, bot.y) && distance(bot, bundle) <= PICKUP_RANGE) {
          this.handlePickup(id, { bundleId: bundle.id });
        }
        return;
      }
      case "patrol": {
        if (
          !mind.patrolNode ||
          now > mind.patrolUntil ||
          distance(bot, BOT_WAYPOINTS[mind.patrolNode]) < BOT_PATROL_ARRIVE
        ) {
          const options = PATROL_NODES.filter((n) => n !== mind.patrolNode);
          mind.patrolNode = options[Math.floor(Math.random() * options.length)];
          mind.patrolUntil = now + BOT_PATROL_MIN_MS + Math.random() * BOT_PATROL_VAR_MS;
        }
        this.botMoveToward(bot, team, mind.patrolNode, BOT_WAYPOINTS[mind.patrolNode], dt);
        return;
      }
      default:
        bot.vx = 0;
        bot.vy = 0;
    }
  }

  // Steers `bot` one tick closer to `finalTarget`, routing through the
  // waypoint graph until it's in the same node/room as the target, then
  // beelining the rest of the way (safe: same room means no walls between).
  private botMoveToward(bot: PlayerState, team: Team, targetNode: BotNodeId, finalTarget: { x: number; y: number }, dt: number) {
    const currentNode = nearestBotNode(bot.x, bot.y);
    const speed = bot.isCarryingCash ? BOT_CARRY_SPEED : BOT_SPEED;

    let aim: { x: number; y: number };
    if (currentNode === targetNode) {
      aim = finalTarget;
    } else {
      const path = findBotPath(team, currentNode, targetNode);
      const next = path.length > 1 ? path[1] : targetNode;
      aim = BOT_WAYPOINTS[next];
    }

    const dx = aim.x - bot.x;
    const dy = aim.y - bot.y;
    const dist = Math.hypot(dx, dy);
    if (dist < 1) {
      bot.vx = 0;
      bot.vy = 0;
      return;
    }
    const step = Math.min(dist, speed * dt);
    const nx = dx / dist;
    const ny = dy / dist;
    bot.x = clamp(bot.x + nx * step, 0, WORLD_WIDTH);
    bot.y = clamp(bot.y + ny * step, 0, WORLD_HEIGHT);
    bot.vx = nx * speed;
    bot.vy = ny * speed;
  }
}
