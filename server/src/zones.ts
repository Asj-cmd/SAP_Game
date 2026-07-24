// Shared world geometry + zone lookup used by GameRoom for all server-authoritative
// validation. This is a VERTICAL town-house model: two mirrored houses flank a
// shared neutral garden, and each house STACKS three floors on the SAME (x,y)
// footprint, disambiguated by a discrete `floor` axis:
//
//   floor +1  two bedrooms (both cash rooms, one logical zone)   <- top
//   floor  0  living room (spawn) + the garden + the backyards   <- ground
//   floor -1  basement (the jail)                                <- below
//
// The garden and the two private backyards exist only at ground level (floor 0).
// A house's bedrooms and basement are reached by WALKING across a connector -
// an interior staircase or a backyard ladder / cellar-steps - which flips the
// player's floor as they cross it (see CONNECTORS / resolveFloor). There is no
// button: you just walk, exactly like the old split-level, and the client
// renders the ramp/ladder so the climb reads as continuous.
//
// client/src/geometry/floorplan.ts mirrors this by hand - keep both in sync.

// Widens the whole floor plan relative to the original 2D layout (1600x900).
// All tables in this file stay written in original coordinates and are scaled
// at module load. The client applies the same factor (client/src/constants.ts
// WORLD_SCALE) - keep both in sync. Speeds and action ranges in GameRoom.ts
// scale with it too, so travel times and balance match the 2D-tuned values.
export const WORLD_SCALE = 5.0; // MUST match client/src/constants.ts WORLD_SCALE
const S = WORLD_SCALE;
// Depth (y-axis) squash - MUST match client/src/constants.ts MAP_DEPTH_SCALE.
// Compresses ONLY the y-axis so each stacked floor is a compact room rather
// than a long hall; x (the across-garden raid distance) is never squashed, so
// balance is unchanged. Applied to every y coordinate and y-axis connector mid.
const YS = 0.72;

export const WORLD_WIDTH = 1600 * S;
export const WORLD_HEIGHT = 900 * S * YS;

// Column boundaries, left to right: backyard B | house B | garden | house A | backyard A.
// Backyards were widened (was 140) so they don't feel cramped under the taller walls.
const YARD_B_MAX = 240 * S;
const HOUSE_B_MAX = 620 * S;
const GARDEN_MAX = 980 * S; // == HOUSE_A_MIN
const HOUSE_A_MAX = 1360 * S; // == YARD_A_MIN
const HOUSE_B_MIN = YARD_B_MAX;
const HOUSE_A_MIN = GARDEN_MAX;
// The two bedrooms split the top floor north/south at this latitude (a partition
// wall with a connecting door) - purely a layout split; both count as one zone.
const BEDROOM_SPLIT_Y = 450 * S;

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
  | "void"; // floor +1/-1 only exist over a house; anywhere else off-ground is void

// Floor-aware zone lookup. `floor` is the player's authoritative floor
// (-1 basement, 0 ground, +1 bedrooms); the same (x,y) maps to a different
// room on each floor because the house is stacked.
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
  // ground floor
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

// Own home = own living room (floor 0), own bedrooms (floor +1), or own BACKYARD
// (floor 0) - the yard is part of the property, so owners can lock intruders
// caught there too. (The bedroom is normally unreachable by the owning team -
// its connectors are sealed - but the check is kept for spec fidelity.)
export function isOwnHome(team: Team, x: number, y: number, floor: number): boolean {
  const zone = getZoneAt(x, y, floor);
  if (team === "B") return zone === "livingB" || zone === "bedroomB" || zone === "backyardB";
  return zone === "livingA" || zone === "bedroomA" || zone === "backyardA";
}

// The basement that holds a given team's jailed prisoners (i.e. the enemy's basement).
export function jailBasementForTeam(team: Team): "basementB" | "basementA" {
  return team === "A" ? "basementB" : "basementA";
}

const scalePoint = (p: { x: number; y: number }) => ({ x: p.x * S, y: p.y * S * YS });

export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
const scaleRect = (r: Rect): Rect => ({ x1: r.x1 * S, y1: r.y1 * S * YS, x2: r.x2 * S, y2: r.y2 * S * YS });

function inRect(x: number, y: number, r: Rect): boolean {
  return x >= r.x1 && x <= r.x2 && y >= r.y1 && y <= r.y2;
}

// ---- floor connectors (staircases / ladders / cellar-steps) ----
//
// A connector is a small footprint that joins two floors. While a player stands
// on it, their floor is FORCED by which side of `mid` (along `axis`) they're on:
// coord < mid -> floorLow, coord >= mid -> floorHigh. So walking across the
// connector flips the floor - "just walk and it takes you". A connector only
// acts on a player already on one of the two floors it joins (a bedroom player
// over the basement stairwell, say, is unaffected). `sealedFor` marks the
// connectors the OWNING team cannot use - its own bedroom/basement stairs and
// ladders - exactly like the old sealed doors: the enemy raids/rescues through
// them, the owner defends from the ground floor and can't camp its own cash/jail.
export interface Connector {
  id: string;
  rect: Rect;
  axis: "x" | "y";
  mid: number;
  floorLow: number; // floor when coord < mid
  floorHigh: number; // floor when coord >= mid
  sealedFor?: Team;
}

const scaleConnector = (c: Connector): Connector => ({
  ...c,
  rect: scaleRect(c.rect),
  mid: c.axis === "y" ? c.mid * S * YS : c.mid * S,
});

export const CONNECTORS: Connector[] = (
  [
    // ---- house B ----
    // Interior staircase living(0) <-> bedrooms(+1), north side. Walk NORTH up it.
    { id: "stairUpB", rect: { x1: 380, y1: 150, x2: 540, y2: 290 }, axis: "y", mid: 220, floorLow: 1, floorHigh: 0, sealedFor: "B" },
    // Interior staircase living(0) <-> basement(-1), opposite (south) side. Walk SOUTH down it.
    { id: "stairDownB", rect: { x1: 380, y1: 610, x2: 540, y2: 750 }, axis: "y", mid: 680, floorLow: 0, floorHigh: -1, sealedFor: "B" },
    // Backyard ladder to the top floor: cross the west wall (x=240) going EAST.
    { id: "ladderB", rect: { x1: 160, y1: 150, x2: 320, y2: 290 }, axis: "x", mid: 240, floorLow: 0, floorHigh: 1, sealedFor: "B" },
    // Backyard cellar-steps to the basement: cross the west wall going EAST.
    { id: "cellarB", rect: { x1: 160, y1: 610, x2: 320, y2: 750 }, axis: "x", mid: 240, floorLow: 0, floorHigh: -1, sealedFor: "B" },
    // ---- house A (mirror across the map centre) ----
    { id: "stairUpA", rect: { x1: 1060, y1: 150, x2: 1220, y2: 290 }, axis: "y", mid: 220, floorLow: 1, floorHigh: 0, sealedFor: "A" },
    { id: "stairDownA", rect: { x1: 1060, y1: 610, x2: 1220, y2: 750 }, axis: "y", mid: 680, floorLow: 0, floorHigh: -1, sealedFor: "A" },
    // Backyard A is on the EAST, so its ladder/cellar cross x=1360 going WEST:
    // house side (x < 1360) is the room, yard side (x >= 1360) is ground.
    { id: "ladderA", rect: { x1: 1280, y1: 150, x2: 1440, y2: 290 }, axis: "x", mid: 1360, floorLow: 1, floorHigh: 0, sealedFor: "A" },
    { id: "cellarA", rect: { x1: 1280, y1: 610, x2: 1440, y2: 750 }, axis: "x", mid: 1360, floorLow: -1, floorHigh: 0, sealedFor: "A" },
  ] as Connector[]
).map(scaleConnector);

// The floor a player ends up on after moving to (x,y), given the floor they
// were on. Outside every (usable) connector the floor is unchanged; on one it's
// forced by side. A connector sealed for `team` is skipped (the owner can't use
// its own stairs), and one that joins neither of the current floors is ignored.
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

// True if (x,y) sits on a connector this team may NOT use - a solid obstacle for
// the owner, mirroring the old sealed-door colliders. The enemy passes freely.
export function connectorBlocks(x: number, y: number, team: Team): boolean {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team && inRect(x, y, c.rect)) return true;
  }
  return false;
}

// ---- collision geometry (bots) ----
//
// Per-floor walls, hand-synced with client/src/geometry/floorplan.ts. Humans
// collide against these CLIENT-side; bots have no client, so GameRoom resolves
// bot movement against the walls of the bot's CURRENT floor plus its own sealed
// connectors. `floor: undefined` = applies on every floor (the world boundary).
export interface FloorRect extends Rect {
  floor?: number;
}
const scaleFloorRect = (r: FloorRect): FloorRect => ({ ...scaleRect(r), floor: r.floor });

export const WALLS: FloorRect[] = (
  [
    // world boundary (all floors)
    { x1: 0, y1: 0, x2: 1600, y2: 10 },
    { x1: 0, y1: 890, x2: 1600, y2: 900 },
    { x1: 0, y1: 0, x2: 10, y2: 900 },
    { x1: 1590, y1: 0, x2: 1600, y2: 900 },

    // ===== floor 0 (ground): backyards | livings | garden =====
    // backyard B | living B (x=240): gaps at ladder y[150,290], yard door y[370,450], cellar y[610,750]
    { x1: 235, y1: 10, x2: 245, y2: 150, floor: 0 },
    { x1: 235, y1: 290, x2: 245, y2: 370, floor: 0 },
    { x1: 235, y1: 450, x2: 245, y2: 610, floor: 0 },
    { x1: 235, y1: 750, x2: 245, y2: 890, floor: 0 },
    // living B | garden (x=620): 3 door gaps y[230,290], y[380,440], y[530,590]
    { x1: 615, y1: 10, x2: 625, y2: 230, floor: 0 },
    { x1: 615, y1: 290, x2: 625, y2: 380, floor: 0 },
    { x1: 615, y1: 440, x2: 625, y2: 530, floor: 0 },
    { x1: 615, y1: 590, x2: 625, y2: 890, floor: 0 },
    // garden | living A (x=980): mirror
    { x1: 975, y1: 10, x2: 985, y2: 230, floor: 0 },
    { x1: 975, y1: 290, x2: 985, y2: 380, floor: 0 },
    { x1: 975, y1: 440, x2: 985, y2: 530, floor: 0 },
    { x1: 975, y1: 590, x2: 985, y2: 890, floor: 0 },
    // living A | backyard A (x=1360): gaps at ladder/yard-door/cellar (mirror of B)
    { x1: 1355, y1: 10, x2: 1365, y2: 150, floor: 0 },
    { x1: 1355, y1: 290, x2: 1365, y2: 370, floor: 0 },
    { x1: 1355, y1: 450, x2: 1365, y2: 610, floor: 0 },
    { x1: 1355, y1: 750, x2: 1365, y2: 890, floor: 0 },

    // ===== floor +1 (top): two bedrooms per house =====
    // house B perimeter: west x=240 (gap at ladder y[150,290]), east x=620 solid, N/S caps
    { x1: 235, y1: 0, x2: 245, y2: 150, floor: 1 },
    { x1: 235, y1: 290, x2: 245, y2: 900, floor: 1 },
    { x1: 615, y1: 0, x2: 625, y2: 900, floor: 1 },
    { x1: 240, y1: 0, x2: 620, y2: 10, floor: 1 },
    { x1: 240, y1: 890, x2: 620, y2: 900, floor: 1 },
    // house B partition y=450, door gap x[400,480]
    { x1: 240, y1: 445, x2: 400, y2: 455, floor: 1 },
    { x1: 480, y1: 445, x2: 620, y2: 455, floor: 1 },
    // house A perimeter: east x=1360 (gap at ladder), west x=980 solid, N/S caps
    { x1: 1355, y1: 0, x2: 1365, y2: 150, floor: 1 },
    { x1: 1355, y1: 290, x2: 1365, y2: 900, floor: 1 },
    { x1: 975, y1: 0, x2: 985, y2: 900, floor: 1 },
    { x1: 980, y1: 0, x2: 1360, y2: 10, floor: 1 },
    { x1: 980, y1: 890, x2: 1360, y2: 900, floor: 1 },
    // house A partition y=450, door gap x[1130,1210]
    { x1: 980, y1: 445, x2: 1130, y2: 455, floor: 1 },
    { x1: 1210, y1: 445, x2: 1360, y2: 455, floor: 1 },

    // ===== floor -1 (basement): one open room per house =====
    // house B: west x=240 (gap at cellar y[610,750]), east x=620 solid, N/S caps
    { x1: 235, y1: 0, x2: 245, y2: 610, floor: -1 },
    { x1: 235, y1: 750, x2: 245, y2: 900, floor: -1 },
    { x1: 615, y1: 0, x2: 625, y2: 900, floor: -1 },
    { x1: 240, y1: 0, x2: 620, y2: 10, floor: -1 },
    { x1: 240, y1: 890, x2: 620, y2: 900, floor: -1 },
    // house A: east x=1360 (gap at cellar), west x=980 solid, N/S caps
    { x1: 1355, y1: 0, x2: 1365, y2: 610, floor: -1 },
    { x1: 1355, y1: 750, x2: 1365, y2: 900, floor: -1 },
    { x1: 975, y1: 0, x2: 985, y2: 900, floor: -1 },
    { x1: 980, y1: 0, x2: 1360, y2: 10, floor: -1 },
    { x1: 980, y1: 890, x2: 1360, y2: 900, floor: -1 },
  ] as FloorRect[]
).map(scaleFloorRect);

// Up to 4 spawn points per team, inside the ground-floor living room, clear of
// the stair footprints and door gaps. Every spawn is floor 0.
export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 300, y: 420 },
    { x: 460, y: 420 },
    { x: 300, y: 520 },
    { x: 460, y: 520 },
  ].map(scalePoint),
  A: [
    { x: 1100, y: 420 },
    { x: 1260, y: 420 },
    { x: 1100, y: 520 },
    { x: 1260, y: 520 },
  ].map(scalePoint),
};

// Jail spot inside each basement (floor -1), clear of the stair/cellar footprints.
export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: scalePoint({ x: 430, y: 830 }),
  basementA: scalePoint({ x: 1170, y: 830 }),
};

// A house's bedroom safe area (floor +1) as two rects - the north room and the
// south room - kept clear of the perimeter, the partition, and the stairwell so
// randomly placed bundles never land inside a wall.
const BEDROOM_AREAS: Record<"B" | "A", Rect[]> = {
  B: [
    { x1: 270, y1: 40, x2: 590, y2: 410 }, // north room (avoids the up-stair? see below)
    { x1: 270, y1: 490, x2: 590, y2: 860 }, // south room
  ],
  A: [
    { x1: 1010, y1: 40, x2: 1330, y2: 410 },
    { x1: 1010, y1: 490, x2: 1330, y2: 860 },
  ],
};

function randInt(min: number, max: number): number {
  return min + Math.floor(Math.random() * (max - min + 1));
}

// One random point somewhere in `house`'s two bedrooms (floor +1). Used for both
// the initial bundle scatter and every re-deposit, so banking cash feels like
// the same "hidden somewhere in the enemy bedrooms" hunt each time.
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

// ---- Bot pathing graph ----
// A waypoint graph AI bots route through, now floor-aware: every node carries the
// floor it lives on, and the edges that span a staircase/ladder are the ones the
// bot's floor flips across (resolveFloor does the actual flip as it walks). As
// before, the owner's own bedroom/basement connectors are `blockedFor` that team,
// so a bot only ever routes through the gates its team can actually use.
export type BotNodeId = string;

export const BOT_WAYPOINTS: Record<string, { x: number; y: number; floor: number }> = {
  // ---- house B ----
  livingB: { ...scalePoint({ x: 340, y: 470 }), floor: 0 },
  gateB_garden: { ...scalePoint({ x: 620, y: 410 }), floor: 0 },
  gateB_yard: { ...scalePoint({ x: 240, y: 410 }), floor: 0 },
  backyardB: { ...scalePoint({ x: 110, y: 470 }), floor: 0 },
  yardB_ladder: { ...scalePoint({ x: 150, y: 220 }), floor: 0 },
  yardB_cellar: { ...scalePoint({ x: 150, y: 680 }), floor: 0 },
  stairUpB_base: { ...scalePoint({ x: 460, y: 270 }), floor: 0 },
  stairDownB_base: { ...scalePoint({ x: 460, y: 630 }), floor: 0 },
  stairUpB_top: { ...scalePoint({ x: 460, y: 170 }), floor: 1 },
  ladderB_top: { ...scalePoint({ x: 300, y: 220 }), floor: 1 },
  bedroomB_N: { ...scalePoint({ x: 330, y: 110 }), floor: 1 },
  bedroomB_mid: { ...scalePoint({ x: 440, y: 450 }), floor: 1 },
  bedroomB_S: { ...scalePoint({ x: 330, y: 650 }), floor: 1 },
  stairDownB_bot: { ...scalePoint({ x: 460, y: 770 }), floor: -1 },
  cellarB_bot: { ...scalePoint({ x: 300, y: 680 }), floor: -1 },
  basementB: { ...scalePoint({ x: 430, y: 700 }), floor: -1 },
  // ---- garden (shared spine, floor 0) ----
  garden: { ...scalePoint({ x: 800, y: 450 }), floor: 0 },
  gateA_garden: { ...scalePoint({ x: 980, y: 410 }), floor: 0 },
  // ---- house A (mirror) ----
  livingA: { ...scalePoint({ x: 1260, y: 470 }), floor: 0 },
  gateA_yard: { ...scalePoint({ x: 1360, y: 410 }), floor: 0 },
  backyardA: { ...scalePoint({ x: 1490, y: 470 }), floor: 0 },
  yardA_ladder: { ...scalePoint({ x: 1450, y: 220 }), floor: 0 },
  yardA_cellar: { ...scalePoint({ x: 1450, y: 680 }), floor: 0 },
  stairUpA_base: { ...scalePoint({ x: 1100, y: 270 }), floor: 0 },
  stairDownA_base: { ...scalePoint({ x: 1100, y: 630 }), floor: 0 },
  stairUpA_top: { ...scalePoint({ x: 1100, y: 170 }), floor: 1 },
  ladderA_top: { ...scalePoint({ x: 1300, y: 220 }), floor: 1 },
  bedroomA_N: { ...scalePoint({ x: 1270, y: 110 }), floor: 1 },
  bedroomA_mid: { ...scalePoint({ x: 1170, y: 450 }), floor: 1 },
  bedroomA_S: { ...scalePoint({ x: 1270, y: 650 }), floor: 1 },
  stairDownA_bot: { ...scalePoint({ x: 1100, y: 770 }), floor: -1 },
  cellarA_bot: { ...scalePoint({ x: 1300, y: 680 }), floor: -1 },
  basementA: { ...scalePoint({ x: 1170, y: 700 }), floor: -1 },
};

interface BotEdge {
  a: BotNodeId;
  b: BotNodeId;
  blockedFor?: Team; // the connector here is sealed for this team
}

const BOT_EDGES: BotEdge[] = [
  // ---- house B ground floor ----
  { a: "livingB", b: "gateB_garden" },
  { a: "livingB", b: "gateB_yard" },
  { a: "livingB", b: "stairUpB_base" },
  { a: "livingB", b: "stairDownB_base" },
  { a: "gateB_yard", b: "backyardB" },
  { a: "backyardB", b: "yardB_ladder" },
  { a: "backyardB", b: "yardB_cellar" },
  // B vertical transitions (sealed for B - only team A raids/rescues here)
  { a: "stairUpB_base", b: "stairUpB_top", blockedFor: "B" },
  { a: "stairUpB_top", b: "bedroomB_N" },
  { a: "yardB_ladder", b: "ladderB_top", blockedFor: "B" },
  { a: "ladderB_top", b: "bedroomB_N" },
  { a: "bedroomB_N", b: "bedroomB_mid" },
  { a: "bedroomB_mid", b: "bedroomB_S" },
  { a: "stairDownB_base", b: "stairDownB_bot", blockedFor: "B" },
  { a: "stairDownB_bot", b: "basementB" },
  { a: "yardB_cellar", b: "cellarB_bot", blockedFor: "B" },
  { a: "cellarB_bot", b: "basementB" },
  // ---- garden ----
  { a: "gateB_garden", b: "garden" },
  { a: "garden", b: "gateA_garden" },
  { a: "gateA_garden", b: "livingA" },
  // ---- house A ground floor ----
  { a: "livingA", b: "gateA_yard" },
  { a: "livingA", b: "stairUpA_base" },
  { a: "livingA", b: "stairDownA_base" },
  { a: "gateA_yard", b: "backyardA" },
  { a: "backyardA", b: "yardA_ladder" },
  { a: "backyardA", b: "yardA_cellar" },
  // A vertical transitions (sealed for A - only team B raids/rescues here)
  { a: "stairUpA_base", b: "stairUpA_top", blockedFor: "A" },
  { a: "stairUpA_top", b: "bedroomA_N" },
  { a: "yardA_ladder", b: "ladderA_top", blockedFor: "A" },
  { a: "ladderA_top", b: "bedroomA_N" },
  { a: "bedroomA_N", b: "bedroomA_mid" },
  { a: "bedroomA_mid", b: "bedroomA_S" },
  { a: "stairDownA_base", b: "stairDownA_bot", blockedFor: "A" },
  { a: "stairDownA_bot", b: "basementA" },
  { a: "yardA_cellar", b: "cellarA_bot", blockedFor: "A" },
  { a: "cellarA_bot", b: "basementA" },
];

// Nearest waypoint ON the given floor (a stacked house shares (x,y) across
// floors, so the floor is what disambiguates which room's node is meant).
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

// BFS shortest path (by hop count) between two nodes, respecting which gates
// `team` may use. Falls back to staying put if unreachable.
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
