// Shared world geometry + zone lookup used by GameRoom for all server-authoritative
// validation. VERTICAL town-house: two mirrored houses flank a shared garden, each
// stacking three floors on the SAME (x,y) footprint, told apart by a discrete
// `floor` axis:
//
//   floor +1  two bedrooms (both cash rooms) off a landing   <- top
//   floor  0  living room (spawn) + garden + backyards       <- ground
//   floor -1  basement (the jail)                            <- below
//
// Top floor layout: the interior staircase rises from the living room into a
// LANDING; the landing has one door into each of the two bedrooms. Each bedroom
// also opens west onto its own BALCONY, and a wooden LADDER drops from that
// balcony to the backyard. So the backyard is reachable four ways: 2 balcony
// ladders + the living-room door + the basement's cellar steps.
//
// SCALE: everything below is authored directly in WORLD UNITS at WORLD_SCALE 1,
// sized against the ~83-unit-tall character (see client CHARACTER_SCALE): rooms
// are ~460x250 (about 5.5 x 3 character heights), doors 80-90 wide (2x the
// character's 40-unit diameter), stairs 120 wide. client/src/geometry/
// floorplan.ts mirrors this file by hand - keep both in sync.

export const WORLD_SCALE = 1.25; // MUST match client/src/constants.ts WORLD_SCALE
const S = WORLD_SCALE;
// Depth (y) multiplier - MUST match client's MAP_DEPTH_SCALE. Applied on top of
// WORLD_SCALE, so depth scales 1.25 * 1.2 = 1.5 while width scales 1.25.
const YS = 1.2;

const BASE_WIDTH = 1900;
const BASE_DEPTH = 700;

export const WORLD_WIDTH = BASE_WIDTH * S;
export const WORLD_HEIGHT = BASE_DEPTH * S * YS;

// Columns, left to right: backyard B | house B | garden | house A | backyard A.
const YARD_B_MAX = 260 * S;
const HOUSE_B_MAX = 720 * S;
const GARDEN_MAX = 1180 * S; // == HOUSE_A_MIN
const HOUSE_A_MAX = 1640 * S; // == YARD_A_MIN
const HOUSE_B_MIN = YARD_B_MAX;
const HOUSE_A_MIN = GARDEN_MAX;

// Mirror axis: house A is house B reflected through the map's centre line.
const MIRROR = BASE_WIDTH;

export type Team = "A" | "B";
export type ZoneId =
  | "backyardB"
  | "bedroomB"
  | "livingB"
  | "basementB"
  | "garden"
  | "bedroomA"
  | "livingA"
  | "basementA"
  | "backyardA"
  | "void"; // off-ground anywhere but inside a house (e.g. a balcony) - transit only

export function getZoneAt(x: number, y: number, floor: number): ZoneId {
  if (floor >= 1) {
    if (x >= HOUSE_B_MIN && x < HOUSE_B_MAX) return "bedroomB";
    if (x >= HOUSE_A_MIN && x < HOUSE_A_MAX) return "bedroomA";
    return "void";
  }
  if (floor <= -1) {
    if (x >= HOUSE_B_MIN && x < HOUSE_B_MAX) return "basementB";
    if (x >= HOUSE_A_MIN && x < HOUSE_A_MAX) return "basementA";
    return "void";
  }
  if (x < YARD_B_MAX) return "backyardB";
  if (x < HOUSE_B_MAX) return "livingB";
  if (x < GARDEN_MAX) return "garden";
  if (x < HOUSE_A_MAX) return "livingA";
  return "backyardA";
}

export function isEnemyBedroom(team: Team, x: number, y: number, floor: number): boolean {
  const zone = getZoneAt(x, y, floor);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

// Own home = own living room, own bedrooms, or own BACKYARD - the yard is part
// of the property, so owners can lock intruders caught there too.
export function isOwnHome(team: Team, x: number, y: number, floor: number): boolean {
  const zone = getZoneAt(x, y, floor);
  if (team === "B") return zone === "livingB" || zone === "bedroomB" || zone === "backyardB";
  return zone === "livingA" || zone === "bedroomA" || zone === "backyardA";
}

export function jailBasementForTeam(team: Team): "basementB" | "basementA" {
  return team === "A" ? "basementB" : "basementA";
}

export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
export interface FloorRect extends Rect {
  floor?: number; // undefined = every floor (the world boundary)
}

const scalePoint = (p: { x: number; y: number }) => ({ x: p.x * S, y: p.y * S * YS });
const scaleRect = <T extends Rect>(r: T): T => ({
  ...r,
  x1: r.x1 * S,
  y1: r.y1 * S * YS,
  x2: r.x2 * S,
  y2: r.y2 * S * YS,
});

// Reflect house-B geometry into house A (x' = MIRROR - x, so x1/x2 swap).
const mirrorRect = <T extends Rect>(r: T): T => ({ ...r, x1: MIRROR - r.x2, x2: MIRROR - r.x1 });
const mirrorPoint = (p: { x: number; y: number }) => ({ ...p, x: MIRROR - p.x });

function inRect(x: number, y: number, r: Rect): boolean {
  return x >= r.x1 && x <= r.x2 && y >= r.y1 && y <= r.y2;
}

// ---- floor connectors (staircases / balcony ladders / cellar steps) ----
//
// A connector joins two floors. While standing on it, the floor is FORCED by
// which side of `mid` (along `axis`) you are: coord < mid -> floorLow, else
// floorHigh. Walking across therefore changes floor - no button. `sealedFor`
// marks the connectors the OWNING team cannot use (its own bedroom/basement
// routes), exactly like the old sealed doors: raiders pass, owners defend from
// the ground floor.
export interface Connector {
  id: string;
  rect: Rect;
  axis: "x" | "y";
  mid: number;
  floorLow: number;
  floorHigh: number;
  sealedFor?: Team;
  kind: "stair" | "ladder"; // purely cosmetic hint for the renderer
}

// House B connectors, authored once and mirrored for house A below.
// Placement rule: an owner's own connectors are SOLID to them, so no connector
// may sit across a doorway or against a wall - that would trap the owner (and
// its bots) in a dead pocket. Both interior staircases therefore stand clear of
// the walls, leaving a walkable ring around them on the ground floor.
const HOUSE_B_CONNECTORS: Connector[] = [
  // Interior staircase living(0) <-> landing(+1), mid-room. Walk NORTH to climb.
  { id: "stairUpB", rect: { x1: 450, y1: 260, x2: 570, y2: 420 }, axis: "y", mid: 340, floorLow: 1, floorHigh: 0, sealedFor: "B", kind: "stair" },
  // Interior staircase living(0) <-> basement(-1), south-west. Walk SOUTH to descend.
  { id: "stairDownB", rect: { x1: 290, y1: 480, x2: 410, y2: 640 }, axis: "y", mid: 560, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair" },
  // Balcony LADDERS: short, steep runs from the yard up to each bedroom's
  // balcony. They stop at the balcony's outer edge (x=200) - the balcony itself
  // (x 200..260) is flat at floor +1, so you step off the ladder onto it.
  { id: "ladderB_N", rect: { x1: 140, y1: 80, x2: 200, y2: 160 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  { id: "ladderB_S", rect: { x1: 140, y1: 540, x2: 200, y2: 620 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  // Cellar steps: descend in the YARD (outside the wall) and enter the basement
  // through the floor -1 doorway, so they never pierce the living-room floor.
  { id: "cellarB", rect: { x1: 150, y1: 440, x2: 260, y2: 520 }, axis: "x", mid: 205, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair" },
];

const mirrorConnector = (c: Connector): Connector => ({
  ...c,
  id: c.id.replace("B", "A"),
  rect: mirrorRect(c.rect),
  // An x-axis connector's low/high sides swap when mirrored; a y-axis one is
  // unaffected (only x is reflected).
  mid: c.axis === "x" ? MIRROR - c.mid : c.mid,
  floorLow: c.axis === "x" ? c.floorHigh : c.floorLow,
  floorHigh: c.axis === "x" ? c.floorLow : c.floorHigh,
  sealedFor: "A",
});

const scaleConnector = (c: Connector): Connector => ({
  ...c,
  rect: scaleRect(c.rect),
  mid: c.axis === "x" ? c.mid * S : c.mid * S * YS,
});

export const CONNECTORS: Connector[] = [
  ...HOUSE_B_CONNECTORS,
  ...HOUSE_B_CONNECTORS.map(mirrorConnector),
].map(scaleConnector);

// The floor a player ends up on after moving to (x,y) from `floor`. Outside every
// usable connector the floor is unchanged; on one it is forced by side.
export function resolveFloor(x: number, y: number, floor: number, team: Team): number {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team) continue;
    if (!inRect(x, y, c.rect)) continue;
    if (floor !== c.floorLow && floor !== c.floorHigh) continue;
    const coord = c.axis === "x" ? x : y;
    return coord < c.mid ? c.floorLow : c.floorHigh;
  }
  return floor;
}

// True if (x,y) sits on a connector this team may NOT use - solid for the owner.
export function connectorBlocks(x: number, y: number, team: Team): boolean {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team && inRect(x, y, c.rect)) return true;
  }
  return false;
}

// ---- walls ----
// Per-floor solid segments; door/connector gaps are simply absent. Humans
// collide client-side, bots server-side, against the walls of their CURRENT
// floor plus their own sealed connectors.
const T = 7; // wall half-thickness

// House B walls, mirrored for house A below. House B spans x[260,720], y[0,700].
const HOUSE_B_WALLS: FloorRect[] = [
  // ===== floor 0 (living room) =====
  // west wall x=260, gap = living<->backyard door y[300,380]
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 300, floor: 0 },
  { x1: 260 - T, y1: 380, x2: 260 + T, y2: 700, floor: 0 },
  // east wall x=720, 3 garden doors y[120,200], y[320,400], y[520,600]
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 120, floor: 0 },
  { x1: 720 - T, y1: 200, x2: 720 + T, y2: 320, floor: 0 },
  { x1: 720 - T, y1: 400, x2: 720 + T, y2: 520, floor: 0 },
  { x1: 720 - T, y1: 600, x2: 720 + T, y2: 700, floor: 0 },

  // north/south END walls, per floor. The map's world-boundary rects double as
  // the house's end walls at GROUND level, but they carry no floor tag and are
  // therefore only drawn at floor 0 - leaving the bedrooms and basement open to
  // the sky (walls you could not walk through but could see straight past).
  // These close both stacked floors properly.
  { x1: 260, y1: 0, x2: 720, y2: T, floor: 1 },
  { x1: 260, y1: 700 - T, x2: 720, y2: 700, floor: 1 },
  { x1: 260, y1: 0, x2: 720, y2: T, floor: -1 },
  { x1: 260, y1: 700 - T, x2: 720, y2: 700, floor: -1 },
  // ===== floor +1 (two bedrooms off a landing) =====
  // west wall x=260, gaps = the two balcony doors y[80,160] and y[540,620]
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 80, floor: 1 },
  { x1: 260 - T, y1: 160, x2: 260 + T, y2: 540, floor: 1 },
  { x1: 260 - T, y1: 620, x2: 260 + T, y2: 700, floor: 1 },
  // east wall x=720 solid
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 700, floor: 1 },
  // partition: bedroom N | landing at y=250, door gap x[300,390]
  { x1: 260, y1: 250 - T, x2: 300, y2: 250 + T, floor: 1 },
  { x1: 390, y1: 250 - T, x2: 720, y2: 250 + T, floor: 1 },
  // partition: landing | bedroom S at y=430, door gap x[300,390]
  { x1: 260, y1: 430 - T, x2: 300, y2: 430 + T, floor: 1 },
  { x1: 390, y1: 430 - T, x2: 720, y2: 430 + T, floor: 1 },
  // balcony + ladder railings (floor 1) - keep you on the balcony/ladder run
  { x1: 140, y1: 80 - T, x2: 260, y2: 80, floor: 1 },
  { x1: 140, y1: 160, x2: 260, y2: 160 + T, floor: 1 },
  { x1: 140, y1: 540 - T, x2: 260, y2: 540, floor: 1 },
  { x1: 140, y1: 620, x2: 260, y2: 620 + T, floor: 1 },

  // ===== floor -1 (basement) =====
  // west wall x=260, gap = cellar doorway y[440,520]
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 440, floor: -1 },
  { x1: 260 - T, y1: 520, x2: 260 + T, y2: 700, floor: -1 },
  // cellar-pit retaining walls (floor -1): the steps descend in the OPEN yard,
  // so without these you could step sideways off them into the void at basement
  // level. The pit's outer end needs none - past mid you are back on floor 0.
  { x1: 150, y1: 440 - T, x2: 260, y2: 440, floor: -1 },
  { x1: 150, y1: 520, x2: 260, y2: 520 + T, floor: -1 },
  // east wall x=720 solid
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 700, floor: -1 },
];

export const WALLS: FloorRect[] = [
  // world boundary (all floors)
  { x1: 0, y1: 0, x2: BASE_WIDTH, y2: T },
  { x1: 0, y1: BASE_DEPTH - T, x2: BASE_WIDTH, y2: BASE_DEPTH },
  { x1: 0, y1: 0, x2: T, y2: BASE_DEPTH },
  { x1: BASE_WIDTH - T, y1: 0, x2: BASE_WIDTH, y2: BASE_DEPTH },
  ...HOUSE_B_WALLS,
  ...HOUSE_B_WALLS.map(mirrorRect),
].map(scaleRect);

// ---- spawns / jail / cash ----

// Living room, clear of both stairwell openings and every doorway.
const SPAWNS_B = [
  { x: 330, y: 120 },
  { x: 470, y: 120 },
  { x: 330, y: 240 },
  { x: 470, y: 240 },
];

export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: SPAWNS_B.map(scalePoint),
  A: SPAWNS_B.map(mirrorPoint).map(scalePoint),
};

// Jail spot inside each basement (floor -1), clear of the stair footprint.
export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: scalePoint({ x: 560, y: 560 }),
  basementA: scalePoint(mirrorPoint({ x: 560, y: 560 })),
};

// Safe interiors of the two bedrooms (floor +1), inset from walls/partitions so
// randomly placed bundles never land inside geometry.
const BEDROOM_AREAS_B: Rect[] = [
  { x1: 300, y1: 40, x2: 690, y2: 210 }, // north bedroom
  { x1: 300, y1: 470, x2: 690, y2: 660 }, // south bedroom
];
const BEDROOM_AREAS: Record<"B" | "A", Rect[]> = {
  B: BEDROOM_AREAS_B,
  A: BEDROOM_AREAS_B.map(mirrorRect),
};

function randInt(min: number, max: number): number {
  return min + Math.floor(Math.random() * (max - min + 1));
}

// One random point in `house`'s two bedrooms - used for the initial scatter AND
// every re-deposit, so banking cash re-hides it just like the start of a round.
export function randomBedroomPoint(house: "B" | "A"): { x: number; y: number } {
  const areas = BEDROOM_AREAS[house];
  const a = areas[Math.floor(Math.random() * areas.length)];
  return { x: randInt(a.x1 * S, a.x2 * S), y: randInt(a.y1 * S * YS, a.y2 * S * YS) };
}

export function randomBedroomPoints(house: "B" | "A", count: number): { x: number; y: number }[] {
  const out: { x: number; y: number }[] = [];
  for (let i = 0; i < count; i++) out.push(randomBedroomPoint(house));
  return out;
}

// ---- bot pathing graph ----
// Floor-aware waypoints; edges crossing a connector are `blockedFor` its owner,
// so a bot only routes through gates its team may actually use.
export type BotNodeId = string;

interface BotNode {
  x: number;
  y: number;
  floor: number;
}

// House B nodes, mirrored for house A. Names ending in _N/_S are the two bedrooms.
// Ground-floor nodes sit on the open RING around the two stair blocks (up:
// x[450,570] y[260,420]; down: x[290,410] y[480,640]); every edge below is a
// straight line through open space, so a bot never beelines into its own sealed
// staircase and wedges.
const HOUSE_B_NODES: Record<string, BotNode> = {
  livingB: { x: 620, y: 400, floor: 0 }, // hub (east corridor) - deposit/patrol target
  livingB_N: { x: 620, y: 150, floor: 0 },
  livingB_W: { x: 350, y: 300, floor: 0 },
  livingB_S: { x: 500, y: 670, floor: 0 },
  gateB_garden: { x: 720, y: 360, floor: 0 },
  gateB_yard: { x: 260, y: 340, floor: 0 },
  backyardB: { x: 100, y: 350, floor: 0 },
  yardB_ladderN: { x: 120, y: 120, floor: 0 },
  yardB_ladderS: { x: 120, y: 580, floor: 0 },
  yardB_cellar: { x: 170, y: 480, floor: 0 },
  stairUpB_base: { x: 510, y: 450, floor: 0 },
  stairUpB_top: { x: 510, y: 300, floor: 1 },
  landingB: { x: 345, y: 340, floor: 1 },
  bedroomB_N: { x: 345, y: 140, floor: 1 },
  bedroomB_S: { x: 345, y: 560, floor: 1 },
  balconyB_N: { x: 230, y: 120, floor: 1 },
  balconyB_S: { x: 230, y: 580, floor: 1 },
  stairDownB_base: { x: 350, y: 455, floor: 0 },
  stairDownB_bot: { x: 350, y: 600, floor: -1 },
  basementB: { x: 520, y: 500, floor: -1 },
  cellarB_bot: { x: 300, y: 480, floor: -1 },
};

const SHARED_NODES: Record<string, BotNode> = {
  garden: { x: 950, y: 350, floor: 0 },
  gateA_garden: { x: 1180, y: 360, floor: 0 },
};

function buildWaypoints(): Record<string, { x: number; y: number; floor: number }> {
  const out: Record<string, { x: number; y: number; floor: number }> = {};
  for (const [id, n] of Object.entries(HOUSE_B_NODES)) {
    out[id] = { ...scalePoint(n), floor: n.floor };
    const mirroredId = id.replace("B", "A");
    const m = mirrorPoint(n);
    out[mirroredId] = { ...scalePoint(m), floor: n.floor };
  }
  for (const [id, n] of Object.entries(SHARED_NODES)) {
    out[id] = { ...scalePoint(n), floor: n.floor };
  }
  return out;
}

export const BOT_WAYPOINTS = buildWaypoints();

interface BotEdge {
  a: BotNodeId;
  b: BotNodeId;
  blockedFor?: Team;
}

// House B edges (mirrored for A). `blockedFor: "B"` marks a leg that crosses one
// of house B's own sealed connectors - usable only by the raiding team.
const HOUSE_B_EDGES: BotEdge[] = [
  // ground-floor ring around the stair blocks
  { a: "livingB", b: "livingB_N" },
  { a: "livingB", b: "livingB_S" },
  { a: "livingB", b: "gateB_garden" },
  { a: "livingB_N", b: "livingB_W" },
  { a: "livingB_S", b: "livingB_W" },
  { a: "livingB_W", b: "gateB_yard" },
  { a: "gateB_yard", b: "backyardB" },
  { a: "backyardB", b: "yardB_ladderN" },
  { a: "backyardB", b: "yardB_ladderS" },
  { a: "backyardB", b: "yardB_cellar" },
  // up the interior staircase to the landing, then a door into each bedroom
  { a: "livingB_S", b: "stairUpB_base" },
  { a: "stairUpB_base", b: "stairUpB_top", blockedFor: "B" },
  { a: "stairUpB_top", b: "landingB" },
  { a: "landingB", b: "bedroomB_N" },
  { a: "landingB", b: "bedroomB_S" },
  // balcony ladders: yard <-> balcony <-> bedroom
  { a: "yardB_ladderN", b: "balconyB_N", blockedFor: "B" },
  { a: "balconyB_N", b: "bedroomB_N" },
  { a: "yardB_ladderS", b: "balconyB_S", blockedFor: "B" },
  { a: "balconyB_S", b: "bedroomB_S" },
  // down the interior staircase, and in from the yard by the cellar steps
  { a: "livingB_W", b: "stairDownB_base" },
  { a: "stairDownB_base", b: "stairDownB_bot", blockedFor: "B" },
  { a: "stairDownB_bot", b: "basementB" },
  { a: "yardB_cellar", b: "cellarB_bot", blockedFor: "B" },
  { a: "cellarB_bot", b: "basementB" },
];

const mirrorEdge = (e: BotEdge): BotEdge => ({
  a: e.a.replace("B", "A"),
  b: e.b.replace("B", "A"),
  blockedFor: e.blockedFor ? "A" : undefined,
});

const BOT_EDGES: BotEdge[] = [
  ...HOUSE_B_EDGES,
  ...HOUSE_B_EDGES.map(mirrorEdge),
  // shared garden spine
  { a: "gateB_garden", b: "garden" },
  { a: "garden", b: "gateA_garden" },
  { a: "gateA_garden", b: "livingA" },
];

// Nearest waypoint ON the given floor (stacked floors share (x,y), so the floor
// is what disambiguates which room's node is meant).
export function nearestBotNode(x: number, y: number, floor: number): BotNodeId {
  let best: BotNodeId = "garden";
  let bestDist = Infinity;
  let fallback: BotNodeId = "garden";
  let fallbackDist = Infinity;
  for (const id of Object.keys(BOT_WAYPOINTS)) {
    const p = BOT_WAYPOINTS[id];
    const d = Math.hypot(p.x - x, p.y - y);
    if (d < fallbackDist) {
      fallbackDist = d;
      fallback = id;
    }
    if (p.floor === floor && d < bestDist) {
      bestDist = d;
      best = id;
    }
  }
  return bestDist === Infinity ? fallback : best;
}

// BFS shortest path (hop count) respecting which gates `team` may use.
export function findBotPath(team: Team, from: BotNodeId, to: BotNodeId): BotNodeId[] {
  if (from === to) return [from];

  const adjacency = new Map<BotNodeId, BotNodeId[]>();
  for (const edge of BOT_EDGES) {
    if (edge.blockedFor === team) continue;
    if (!adjacency.has(edge.a)) adjacency.set(edge.a, []);
    if (!adjacency.has(edge.b)) adjacency.set(edge.b, []);
    adjacency.get(edge.a)!.push(edge.b);
    adjacency.get(edge.b)!.push(edge.a);
  }

  const queue: BotNodeId[] = [from];
  const cameFrom = new Map<BotNodeId, BotNodeId>();
  const visited = new Set<BotNodeId>([from]);
  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current === to) break;
    for (const next of adjacency.get(current) ?? []) {
      if (visited.has(next)) continue;
      visited.add(next);
      cameFrom.set(next, current);
      queue.push(next);
    }
  }

  if (!visited.has(to)) return [from];
  const path: BotNodeId[] = [to];
  while (path[0] !== from) path.unshift(cameFrom.get(path[0])!);
  return path;
}
