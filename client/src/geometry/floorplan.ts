// Engine-agnostic floor plan data + zone logic - no Three.js imports, so it can
// be shared by any renderer. Mirrors server/src/zones.ts BY HAND (same numbers,
// same helpers) - keep both in sync.
//
// VERTICAL town-house: two mirrored houses flank a shared garden, each stacking
// three floors on the SAME (x,y) footprint, told apart by a discrete `floor`
// (-1 basement / 0 living+garden+backyards / +1 two bedrooms). The interior
// staircase rises into a LANDING with one door into each bedroom; each bedroom
// opens onto a BALCONY with a wooden LADDER down to the backyard.
//
// SCALE: authored directly in WORLD UNITS at WORLD_SCALE 1, sized against the
// ~83-unit-tall character - rooms ~460x250, doors 80-90 wide, stairs 120 wide.
import { COLORS, WORLD_SCALE, MAP_DEPTH_SCALE } from "../constants";

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
  | "void";

const S = WORLD_SCALE;
const YS = MAP_DEPTH_SCALE;

const BASE_WIDTH = 1900;
const BASE_DEPTH = 700;
// Mirror axis (pre-scale): house A is house B reflected through the centre line.
export const MIRROR_X = BASE_WIDTH;

const YARD_B_MAX = 260 * S;
const HOUSE_B_MAX = 720 * S;
const GARDEN_MAX = 1180 * S;
const HOUSE_A_MAX = 1640 * S;
const HOUSE_B_MIN = YARD_B_MAX;
const HOUSE_A_MIN = GARDEN_MAX;

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

export function isOwnHome(team: Team, x: number, y: number, floor: number): boolean {
  const zone = getZoneAt(x, y, floor);
  if (team === "B") return zone === "livingB" || zone === "bedroomB" || zone === "backyardB";
  return zone === "livingA" || zone === "bedroomA" || zone === "backyardA";
}

export function jailBasementForTeam(team: Team): ZoneId {
  return team === "A" ? "basementB" : "basementA";
}

export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
export interface FloorRect extends Rect {
  floor?: number;
}

const scaleRect = <T extends Rect>(r: T): T => ({
  ...r,
  x1: r.x1 * S,
  y1: r.y1 * S * YS,
  x2: r.x2 * S,
  y2: r.y2 * S * YS,
});
const mirrorRect = <T extends Rect>(r: T): T => ({ ...r, x1: MIRROR_X - r.x2, x2: MIRROR_X - r.x1 });

// ---- zone rects (per floor) ----

export interface ZoneRect {
  id: ZoneId;
  label: string;
  labelColor?: string;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  floor: number;
  color: number;
}

function scaleZone(z: ZoneRect): ZoneRect {
  return { ...z, xMin: z.xMin * S, xMax: z.xMax * S, yMin: z.yMin * S * YS, yMax: z.yMax * S * YS };
}

export const ZONE_RECTS: ZoneRect[] = (
  [
    // floor 0 (ground)
    { id: "backyardB", label: "BACKYARD B", xMin: 0, xMax: 260, yMin: 0, yMax: 700, floor: 0, color: COLORS.backyard },
    { id: "livingB", label: "LIVING ROOM B", labelColor: "#8c3f10", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: 0, color: COLORS.livingB },
    { id: "garden", label: "GARDEN", xMin: 720, xMax: 1180, yMin: 0, yMax: 700, floor: 0, color: COLORS.garden },
    { id: "livingA", label: "LIVING ROOM A", labelColor: "#12467c", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: 0, color: COLORS.livingA },
    { id: "backyardA", label: "BACKYARD A", xMin: 1640, xMax: 1900, yMin: 0, yMax: 700, floor: 0, color: COLORS.backyard },
    // floor +1 (two bedrooms + landing, one logical cash zone per house)
    { id: "bedroomB", label: "BEDROOMS B", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: 1, color: COLORS.bedroom },
    { id: "bedroomA", label: "BEDROOMS A", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: 1, color: COLORS.bedroom },
    // floor -1 (the jails)
    { id: "basementB", label: "BASEMENT B (jail: Team A)", xMin: 260, xMax: 720, yMin: 0, yMax: 700, floor: -1, color: COLORS.basement },
    { id: "basementA", label: "BASEMENT A (jail: Team B)", xMin: 1180, xMax: 1640, yMin: 0, yMax: 700, floor: -1, color: COLORS.basement },
  ] as ZoneRect[]
).map(scaleZone);

// ---- connectors (staircases / balcony ladders / cellar steps) ----

export interface Connector {
  id: string;
  rect: Rect;
  axis: "x" | "y";
  mid: number;
  floorLow: number;
  floorHigh: number;
  sealedFor?: Team;
  kind: "stair" | "ladder";
}

const HOUSE_B_CONNECTORS: Connector[] = [
  { id: "stairUpB", rect: { x1: 450, y1: 268, x2: 570, y2: 422 }, axis: "y", mid: 340, floorLow: 1, floorHigh: 0, sealedFor: "B", kind: "stair" },
  { id: "stairDownB", rect: { x1: 290, y1: 520, x2: 410, y2: 675 }, axis: "y", mid: 597, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair" },
  { id: "ladderB_N", rect: { x1: 140, y1: 85, x2: 200, y2: 155 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  { id: "ladderB_S", rect: { x1: 140, y1: 545, x2: 200, y2: 615 }, axis: "x", mid: 170, floorLow: 0, floorHigh: 1, sealedFor: "B", kind: "ladder" },
  { id: "cellarB", rect: { x1: 150, y1: 430, x2: 260, y2: 500 }, axis: "x", mid: 205, floorLow: 0, floorHigh: -1, sealedFor: "B", kind: "stair" },
];

const mirrorConnector = (c: Connector): Connector => ({
  ...c,
  id: c.id.replace("B", "A"),
  rect: mirrorRect(c.rect),
  mid: c.axis === "x" ? MIRROR_X - c.mid : c.mid,
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

function inRect(x: number, y: number, r: Rect): boolean {
  return x >= r.x1 && x <= r.x2 && y >= r.y1 && y <= r.y2;
}

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
  // back on the ground - which is what lets the ladders and cellar steps be bare
  // steps with no flanking walls. Mirrors server/src/zones.ts.
  if (floor !== 0 && getZoneAt(x, y, floor) === "void" && !onBalcony(x, y, floor)) return 0;
  return floor;
}

function onBalcony(x: number, y: number, floor: number): boolean {
  return floor === 1 && BALCONIES.some((b) => inRect(x, y, b));
}

export function connectorBlocks(x: number, y: number, team: Team): boolean {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team && inRect(x, y, c.rect)) return true;
  }
  return false;
}

// ---- walls ----

const T = 7; // wall half-thickness

const HOUSE_B_WALLS: FloorRect[] = [
  // ===== floor 0 (living room) =====
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 300, floor: 0 },
  { x1: 260 - T, y1: 380, x2: 260 + T, y2: 700, floor: 0 },
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
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 80, floor: 1 },
  { x1: 260 - T, y1: 160, x2: 260 + T, y2: 540, floor: 1 },
  { x1: 260 - T, y1: 620, x2: 260 + T, y2: 700, floor: 1 },
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 700, floor: 1 },
  { x1: 260, y1: 240 - T, x2: 300, y2: 240 + T, floor: 1 },
  { x1: 390, y1: 240 - T, x2: 720, y2: 240 + T, floor: 1 },
  { x1: 260, y1: 450 - T, x2: 300, y2: 450 + T, floor: 1 },
  { x1: 390, y1: 450 - T, x2: 720, y2: 450 + T, floor: 1 },
  // ===== floor -1 (basement) =====
  { x1: 260 - T, y1: 0, x2: 260 + T, y2: 410, floor: -1 },
  { x1: 260 - T, y1: 520, x2: 260 + T, y2: 700, floor: -1 },
  { x1: 720 - T, y1: 0, x2: 720 + T, y2: 700, floor: -1 },
];

export const WALLS: FloorRect[] = [
  { x1: 0, y1: 0, x2: BASE_WIDTH, y2: T },
  { x1: 0, y1: BASE_DEPTH - T, x2: BASE_WIDTH, y2: BASE_DEPTH },
  { x1: 0, y1: 0, x2: T, y2: BASE_DEPTH },
  { x1: BASE_WIDTH - T, y1: 0, x2: BASE_WIDTH, y2: BASE_DEPTH },
  ...HOUSE_B_WALLS,
  ...HOUSE_B_WALLS.map(mirrorRect),
].map(scaleRect);

// ---- passable doorways (flat mats, no floor change) ----

const HOUSE_B_DOORS: FloorRect[] = [
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

export const DOORS: FloorRect[] = [...HOUSE_B_DOORS, ...HOUSE_B_DOORS.map(mirrorRect)].map(scaleRect);

// ---- balconies ----
// Flat platforms at floor +1 hanging off each bedroom's west wall; the ladder
// drops from their outer edge to the backyard.
const HOUSE_B_BALCONIES: Rect[] = [
  { x1: 200, y1: 80, x2: 260, y2: 160 },
  { x1: 200, y1: 540, x2: 260, y2: 620 },
];

export const BALCONIES: Rect[] = [...HOUSE_B_BALCONIES, ...HOUSE_B_BALCONIES.map(mirrorRect)].map(scaleRect);
