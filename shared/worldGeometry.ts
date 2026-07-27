// THE canonical world geometry - the single source of truth for the floor plan,
// shared verbatim by the authoritative server and the renderer. It was
// previously duplicated in server/src/zones.ts and client/src/geometry/
// floorplan.ts and kept in step by hand, which drifted and produced real bugs
// (invisible walls the client collided with but the server did not know about).
// There is now exactly one copy; both sides re-export from here.
//
// Deliberately DEPENDENCY-FREE and engine-agnostic: pure numbers and pure
// functions, no Three.js, no Colyseus, no colours or labels (those are
// presentation and live client-side). That is what makes it portable - a Godot
// port re-implements only the renderer and reads the same geometry, and this
// module can be dumped straight to JSON for any other engine to consume.
//
// VERTICAL town-house: two mirrored houses flank a shared garden, each stacking
// three floors on the SAME (x,y) footprint, told apart by a discrete `floor`:
//
//   floor +1  two bedrooms (both cash rooms) off a landing   <- top
//   floor  0  living room (spawn) + garden + backyards       <- ground
//   floor -1  basement (the jail)                            <- below
//
// The interior staircase rises from the living room into a LANDING with one
// door into each bedroom; each bedroom also opens west onto a BALCONY whose
// LADDER drops to the backyard. The yard is reachable four ways: 2 balcony
// ladders + the living-room door + the basement's cellar steps.
//
// SCALE: authored directly in WORLD UNITS, sized against the ~83-unit-tall
// character - rooms ~575x375, doors 100-150 wide, stairs 150 wide.

// Scales the whole plan - and, with it, the speeds and action ranges derived
// from it, so travel times and balance stay put at any map size. The character,
// props and camera are authored at true human proportion and deliberately do
// NOT scale, so raising this simply gives players more room.
export const WORLD_SCALE = 1.25;
const S = WORLD_SCALE;
// Depth (y) multiplier applied on top of WORLD_SCALE: depth scales 1.25 * 1.2 =
// 1.5 while width scales 1.25.
export const MAP_DEPTH_SCALE = 1.2;
const YS = MAP_DEPTH_SCALE;

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
export const MIRROR_X = BASE_WIDTH;
const MIRROR = MIRROR_X;

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
  // RENDER-ONLY widening of the step run across its cross axis, in pre-scale
  // units. The walkable rect is deliberately inset from the surrounding walls
  // (so a floor flip can never land a body inside one), which would otherwise
  // leave a visible slot of open sky between the steps and the wall beside
  // them. This pads the drawn treads out to meet that wall without touching
  // the collision/floor-flip footprint. Sized to run a little PAST the wall
  // face rather than exactly onto it: two surfaces that stop on the same plane
  // z-fight, so the treads are sunk into the wall instead.
  visualPad?: number;
  // Draw this flight as a FILLED run of steps rather than the open-tread
  // staircase. The cellar steps sit in a pit open to the sky, so an open flight
  // let daylight through every tread and read as a set of blinds.
  filled?: boolean;
}

// House B connectors, authored once and mirrored for house A below.
// Placement rule: an owner's own connectors are SOLID to them, so no connector
// may sit across a doorway or against a wall - that would trap the owner (and
// its bots) in a dead pocket. Both interior staircases therefore stand clear of
// the walls, leaving a walkable ring around them on the ground floor.
// A flight also needs CLEAR FLOOR AT BOTH ENDS: its sides are solid (see
// CONNECTOR_SIDES), so the only way on or off is the two ends, and a run that
// stops short of a wall by less than a body width is a dead end.
const HOUSE_B_CONNECTORS: Connector[] = [
  // Interior staircase living(0) <-> landing(+1), mid-room. Walk NORTH to climb.
  // The top stops 38 clear of the landing's north partition, so you can step off
  // and walk west to the bedroom doors.
  { id: "stairUpB", rect: { x1: 450, y1: 285, x2: 570, y2: 422 }, axis: "y", mid: 353, floorLow: 1, floorHigh: 0, sealedFor: "B", kind: "stair" },
  // Interior staircase living(0) <-> basement(-1), south-west. Walk SOUTH to
  // descend. It used to run to y=675, 18 short of the south wall - no room to
  // step off, so the only way out of the basement was over the flight's side.
  { id: "stairDownB", rect: { x1: 290, y1: 500, x2: 410, y2: 630 }, axis: "y", mid: 565, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair" },
  // Balcony LADDERS: short, steep runs from the yard up to each bedroom's
  // balcony. They stop at the balcony's outer edge (x=200) - the balcony itself
  // (x 200..260) is flat at floor +1, so you step off the ladder onto it.
  { id: "ladderB_N", rect: { x1: 140, y1: 85, x2: 200, y2: 155 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  { id: "ladderB_S", rect: { x1: 140, y1: 545, x2: 200, y2: 615 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  // Cellar steps: descend in the YARD (outside the wall) and enter the basement
  // through the floor -1 doorway, so they never pierce the living-room floor.
  { id: "cellarB", rect: { x1: 150, y1: 430, x2: 260, y2: 500 }, axis: "x", mid: 205, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair", visualPad: 24, filled: true },
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
  // Cross axis of an x-axis connector is y (and vice versa).
  visualPad: c.visualPad === undefined ? undefined : c.visualPad * (c.axis === "x" ? S * YS : S),
});

export const CONNECTORS: Connector[] = [
  ...HOUSE_B_CONNECTORS,
  ...HOUSE_B_CONNECTORS.map(mirrorConnector),
].map(scaleConnector);

// The floor a player ends up on after moving to (x,y) from `floor`. Outside every
// usable connector the floor is unchanged; on one it is forced by side.
// Balconies: the only place an upper floor exists OUTSIDE a house's footprint.
// Each hangs off a bedroom's west wall, and its ladder drops from the outer edge.
const HOUSE_B_BALCONIES: Rect[] = [
  { x1: 200, y1: 80, x2: 260, y2: 160 },
  { x1: 200, y1: 540, x2: 260, y2: 620 },
];

export const BALCONIES: Rect[] = [
  ...HOUSE_B_BALCONIES,
  ...HOUSE_B_BALCONIES.map(mirrorRect),
].map(scaleRect);

export function resolveFloor(x: number, y: number, floor: number, team: Team): number {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team) continue;
    if (!inRect(x, y, c.rect)) continue;
    if (floor !== c.floorLow && floor !== c.floorHigh) continue;
    const coord = c.axis === "x" ? x : y;
    return coord < c.mid ? c.floorLow : c.floorHigh;
  }
  // Off every connector: an upper/lower floor only EXISTS inside a house (plus
  // the balconies hanging off one). Anywhere else, step off and you are simply
  // back on the ground. This is what lets the ladders and cellar steps be bare
  // steps with no flanking walls: walking off the side just puts you in the
  // yard instead of leaving you stranded in mid-air on a floor that isn't there.
  if (floor !== 0 && getZoneAt(x, y, floor) === "void" && !onBalcony(x, y, floor)) return 0;
  return floor;
}

function onBalcony(x: number, y: number, floor: number): boolean {
  return floor === 1 && BALCONIES.some((b) => inRect(x, y, b));
}

// True if (x,y) sits on a connector this team may NOT use - solid for the owner.
// True when a connector should be SOLID to the team that owns it.
// Only the routes that climb are: their staircase/ladder geometry is visibly in
// the way, so bumping into it reads correctly. A sealed route DOWN is instead
// covered by a solid lid at floor level (see EnvironmentBuilder) - you walk over
// your own basement hatch rather than being stopped by an invisible block.
export function connectorSealsOwner(c: Connector): boolean {
  return Math.max(c.floorLow, c.floorHigh) > 0;
}

// A connector only EXISTS on the two floors it joins - the living room's
// staircase is not present down in the basement, which shares its footprint.
function connectorServesFloor(c: Connector, floor: number): boolean {
  return floor === c.floorLow || floor === c.floorHigh;
}

// True where `team` is blocked by one of its OWN connectors. `floor` is optional
// only so a caller with no floor to hand gets the conservative answer.
export function connectorBlocks(x: number, y: number, team: Team, floor?: number): boolean {
  for (const c of CONNECTORS) {
    if (c.sealedFor !== team || !connectorSealsOwner(c)) continue;
    if (floor !== undefined && !connectorServesFloor(c, floor)) continue;
    if (inRect(x, y, c.rect)) return true;
  }
  return false;
}

// ---- connector side rails ----
//
// A flight is a SOLID OBJECT, and you may only get on or off it at its two
// ends. Without this, walking into the flank of the staircase simply put you
// on top of it: the floor height is a function of position alone, so crossing
// the footprint from the side lifted the body straight up the ramp.
//
// The rails are collision-only - nothing is drawn for them. The flight's own
// steps and stringers are the visible obstacle, and their footprint is exactly
// this; adding drawn walls beside a flight was tried before and looked like
// scaffolding.
//
// They are laid just OUTSIDE the walkable rect so the full width of the run
// stays usable, and they are PER FLOOR, each stopping short of the end where
// the climbing surface meets that floor. Over that last stretch the surface is
// within a step of the floor it meets, so stepping on from the side there is a
// step rather than a launch - and leaving it open is what keeps the floor
// around the flight walkable at the top and the bottom.
const SIDE_RAIL_INSET = 0.28; // fraction of the run left open at the meeting end
const SIDE_RAIL_T = 10;

export interface ConnectorSide extends FloorRect {
  floor: number;
  // The owner walks OVER this connector (a sealed route down is a lid, not a
  // block), so its rails must not exist for them or they would bump into
  // invisible geometry in the middle of their own room.
  skipFor?: Team;
}

export const CONNECTOR_SIDES: ConnectorSide[] = CONNECTORS.flatMap((c) => {
  const skipFor = connectorSealsOwner(c) ? undefined : c.sealedFor;
  const alongX = c.axis === "x";
  const a1 = alongX ? c.rect.x1 : c.rect.y1;
  const a2 = alongX ? c.rect.x2 : c.rect.y2;
  const inset = (a2 - a1) * SIDE_RAIL_INSET;
  const sides: ConnectorSide[] = [];
  for (const floor of [c.floorLow, c.floorHigh]) {
    // Low axis end == floorLow, high end == floorHigh (see resolveFloor).
    const from = floor === c.floorLow ? a1 + inset : a1;
    const to = floor === c.floorHigh ? a2 - inset : a2;
    if (to <= from) continue;
    if (alongX) {
      sides.push({ x1: from, y1: c.rect.y1 - SIDE_RAIL_T, x2: to, y2: c.rect.y1, floor, skipFor });
      sides.push({ x1: from, y1: c.rect.y2, x2: to, y2: c.rect.y2 + SIDE_RAIL_T, floor, skipFor });
    } else {
      sides.push({ x1: c.rect.x1 - SIDE_RAIL_T, y1: from, x2: c.rect.x1, y2: to, floor, skipFor });
      sides.push({ x1: c.rect.x2, y1: from, x2: c.rect.x2 + SIDE_RAIL_T, y2: to, floor, skipFor });
    }
  }
  return sides;
});

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
  // partition: bedroom N | landing at y=240, door gap x[300,390]
  { x1: 260, y1: 240 - T, x2: 300, y2: 240 + T, floor: 1 },
  { x1: 390, y1: 240 - T, x2: 720, y2: 240 + T, floor: 1 },
  // partition: landing | bedroom S at y=450, door gap x[300,390]
  { x1: 260, y1: 450 - T, x2: 300, y2: 450 + T, floor: 1 },
  { x1: 390, y1: 450 - T, x2: 720, y2: 450 + T, floor: 1 },

  // ===== floor -1 (basement) =====
  // west wall x=260, gap = cellar doorway y[410,520], wider than the steps so the
  // doorway jambs never clip a body stepping through them
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 410, floor: -1 },
  { x1: 260 - T, y1: 520, x2: 260 + T, y2: 700, floor: -1 },
  // east wall x=720 solid
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 700, floor: -1 },
  // Cellar-pit sides. These are the EARTH walls of the sunken stairwell, not
  // posts flanking the steps: they exist only on floor -1, so they span the pit
  // depth and are entirely below ground - invisible from the yard, but without
  // them you see open sky through the sides of the pit from inside the basement.
  { x1: 150, y1: 410 - T, x2: 260, y2: 410, floor: -1 },
  { x1: 150, y1: 520, x2: 260, y2: 520 + T, floor: -1 },
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

// ---- doorways ----
// Passable openings in the walls above. The renderer draws a mat in each; the
// simulation needs them only as the gaps they already are (walls omit them).
const HOUSE_B_DOORWAYS: FloorRect[] = [
  { x1: 260 - T, y1: 300, x2: 260 + T, y2: 380, floor: 0 }, // living <-> backyard
  { x1: 720 - T, y1: 120, x2: 720 + T, y2: 200, floor: 0 }, // living <-> garden x3
  { x1: 720 - T, y1: 320, x2: 720 + T, y2: 400, floor: 0 },
  { x1: 720 - T, y1: 520, x2: 720 + T, y2: 600, floor: 0 },
  { x1: 300, y1: 240 - T, x2: 390, y2: 240 + T, floor: 1 }, // landing <-> bedroom N
  { x1: 300, y1: 450 - T, x2: 390, y2: 450 + T, floor: 1 }, // landing <-> bedroom S
  { x1: 260 - T, y1: 80, x2: 260 + T, y2: 160, floor: 1 }, // bedroom N <-> balcony
  { x1: 260 - T, y1: 540, x2: 260 + T, y2: 620, floor: 1 }, // bedroom S <-> balcony
  { x1: 260 - T, y1: 410, x2: 260 + T, y2: 520, floor: -1 }, // basement <-> cellar steps
];

export const DOORWAYS: FloorRect[] = [
  ...HOUSE_B_DOORWAYS,
  ...HOUSE_B_DOORWAYS.map(mirrorRect),
].map(scaleRect);

// ---- zone bounds (per floor) ----
// Footprints only - colours and labels are presentation and stay in the client.
export interface ZoneBounds {
  id: ZoneId;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  floor: number;
}

export const ZONE_BOUNDS: ZoneBounds[] = (
  [
    { id: "backyardB", xMin: 0, xMax: 260, yMin: 0, yMax: 700, floor: 0 },
    { id: "livingB", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: 0 },
    { id: "garden", xMin: 720, xMax: 1180, yMin: 0, yMax: 700, floor: 0 },
    { id: "livingA", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: 0 },
    { id: "backyardA", xMin: 1640, xMax: 1900, yMin: 0, yMax: 700, floor: 0 },
    { id: "bedroomB", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: 1 },
    { id: "bedroomA", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: 1 },
    { id: "basementB", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: -1 },
    { id: "basementA", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: -1 },
  ] as ZoneBounds[]
).map((z) => ({ ...z, xMin: z.xMin * S, xMax: z.xMax * S, yMin: z.yMin * S * YS, yMax: z.yMax * S * YS }));

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
  { x1: 300, y1: 480, x2: 690, y2: 660 }, // south bedroom
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
  yardB_cellar: { x: 170, y: 465, floor: 0 },
  stairUpB_base: { x: 510, y: 450, floor: 0 },
  // Head of the flight, standing just NORTH of its footprint - not on it. The
  // sides are solid, so the route off the top has to leave by the end and then
  // run west along the landing's north strip.
  stairUpB_top: { x: 510, y: 275, floor: 1 },
  landingB: { x: 345, y: 275, floor: 1 },
  bedroomB_N: { x: 345, y: 140, floor: 1 },
  bedroomB_S: { x: 345, y: 560, floor: 1 },
  balconyB_N: { x: 230, y: 120, floor: 1 },
  balconyB_S: { x: 230, y: 580, floor: 1 },
  stairDownB_base: { x: 350, y: 475, floor: 0 },
  // Foot of the flight, on the strip SOUTH of it, and the corner that carries
  // the route east before it turns north into the basement proper.
  stairDownB_bot: { x: 350, y: 675, floor: -1 },
  basementB_S: { x: 496, y: 675, floor: -1 },
  basementB: { x: 520, y: 400, floor: -1 },
  cellarB_bot: { x: 300, y: 465, floor: -1 },
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
  // stairUpB_top stands ON the staircase, which is SOLID to house B - so the
  // whole leg is blocked for the owner, not just the climb. Without this a B
  // bot could still legally route to the top node from the landing and would
  // walk straight into its own stairs and wedge there.
  { a: "stairUpB_top", b: "landingB", blockedFor: "B" },
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
  { a: "stairDownB_bot", b: "basementB_S" },
  { a: "basementB_S", b: "basementB" },
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

// Which waypoint a body at (x, y, floor) counts as standing at - the start of
// every route, and the node a chase/defend target is resolved to.
//
// Nearest by straight line is NOT good enough, because the nearest node can be
// on the far side of a wall. A bot in house A's living room sits ~250 units
// from the backyard ladder node but ~270 from the living-room node, so it
// resolved to the yard - and then every path from there set off due EAST,
// straight into the exterior wall, where it pressed until the round ended.
// (Symmetrical in house B; it is why a bot appeared to have "the wrong
// coordinates for the door".) Matching the ZONE first keeps the answer inside
// the room the body is actually in, which is exactly the walled-off unit the
// graph's edges are authored against.
//
// Nodes standing on a connector the team may not use (stairUpB_top is the head
// of house B's own staircase) are skipped outright: handing one back would send
// a defender walking into its own solid stairs.
export function nearestBotNode(x: number, y: number, floor: number, team?: Team): BotNodeId {
  const zone = getZoneAt(x, y, floor);
  let visible: BotNodeId | null = null;
  let visibleDist = Infinity;
  let sameZone: BotNodeId | null = null;
  let sameZoneDist = Infinity;
  let sameFloor: BotNodeId = "garden";
  let sameFloorDist = Infinity;
  let anywhere: BotNodeId = "garden";
  let anywhereDist = Infinity;
  for (const id of Object.keys(BOT_WAYPOINTS)) {
    const p = BOT_WAYPOINTS[id];
    if (team && connectorBlocks(p.x, p.y, team, p.floor)) continue;
    const d = Math.hypot(p.x - x, p.y - y);
    if (d < anywhereDist) {
      anywhereDist = d;
      anywhere = id;
    }
    if (p.floor !== floor) continue;
    if (d < sameFloorDist) {
      sameFloorDist = d;
      sameFloor = id;
    }
    if (d < visibleDist && !segmentBlocked(x, y, p.x, p.y, floor, team)) {
      visibleDist = d;
      visible = id;
    }
    if (getZoneAt(p.x, p.y, p.floor) === zone && d < sameZoneDist) {
      sameZoneDist = d;
      sameZone = id;
    }
  }
  if (visible) return visible;
  if (sameZone) return sameZone;
  return sameFloorDist === Infinity ? anywhere : sameFloor;
}

// Does the straight line from (x1,y1) to (x2,y2) cross anything solid on
// `floor`? Slab test per rect, so it costs a handful of comparisons each.
// Furniture is deliberately NOT considered: a sofa between you and a waypoint
// is something you walk around, not a different room.
function segmentBlocked(x1: number, y1: number, x2: number, y2: number, floor: number, team?: Team): boolean {
  for (const w of WALLS) {
    if (w.floor !== undefined && w.floor !== floor) continue;
    if (segmentHitsRect(x1, y1, x2, y2, w)) return true;
  }
  for (const s of CONNECTOR_SIDES) {
    if (s.floor !== floor || (team && s.skipFor === team)) continue;
    if (segmentHitsRect(x1, y1, x2, y2, s)) return true;
  }
  if (team) {
    for (const c of CONNECTORS) {
      if (c.sealedFor !== team || !connectorSealsOwner(c)) continue;
      if (floor !== c.floorLow && floor !== c.floorHigh) continue;
      if (segmentHitsRect(x1, y1, x2, y2, c.rect)) return true;
    }
  }
  return false;
}

function segmentHitsRect(x1: number, y1: number, x2: number, y2: number, r: Rect): boolean {
  let tMin = 0;
  let tMax = 1;
  const axes: [number, number, number][] = [
    [x2 - x1, r.x1 - x1, r.x2 - x1],
    [y2 - y1, r.y1 - y1, r.y2 - y1],
  ];
  for (const [delta, near, far] of axes) {
    if (Math.abs(delta) < 1e-9) {
      // Parallel to this axis: only crosses if it already lies inside the slab.
      if (near > 0 || far < 0) return false;
      continue;
    }
    let a = near / delta;
    let b = far / delta;
    if (a > b) [a, b] = [b, a];
    tMin = Math.max(tMin, a);
    tMax = Math.min(tMax, b);
    if (tMin > tMax) return false;
  }
  return true;
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
