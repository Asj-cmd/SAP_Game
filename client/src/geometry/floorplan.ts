// Engine-agnostic floor plan data + zone logic - deliberately has no Phaser or
// Three.js imports (constants.ts is plain data, safe to depend on), so this can
// be shared by any renderer. Mirrors server/src/zones.ts BY HAND - keep both in
// sync.
//
// VERTICAL town-house model: two mirrored houses flank a shared garden, and each
// house stacks three floors on the SAME (x,y) footprint, told apart by a discrete
// `floor` (-1 basement, 0 ground/living, +1 bedrooms). The garden and backyards
// exist only at ground level. You move between floors by WALKING across a
// connector (interior staircase / backyard ladder / cellar-steps), which flips
// your floor as you cross it - see CONNECTORS / resolveFloor.
//
// All tables are written in the ORIGINAL 2D layout's coordinates (1600x900) and
// scaled by WORLD_SCALE at module load, exactly like the server - so the raw
// numbers stay hand-comparable between the two files.
import { COLORS, WORLD_SCALE } from "../constants";

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

// ---- zone lookup ----

// Columns, left to right: backyard B | house B | garden | house A | backyard A.
// Backyards widened (was 140) so they don't feel cramped under the taller walls.
const YARD_B_MAX = 240 * S;
const HOUSE_B_MAX = 620 * S;
const GARDEN_MAX = 980 * S; // == HOUSE_A_MIN
const HOUSE_A_MAX = 1360 * S; // == YARD_A_MIN
const HOUSE_B_MIN = YARD_B_MAX;
const HOUSE_A_MIN = GARDEN_MAX;
// The two bedrooms split the top floor north/south here (a partition + door).
export const BEDROOM_SPLIT_Y = 450 * S;

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

// The discrete floor a zone lives on - the single knob the renderer multiplies
// by STORY_HEIGHT to get the zone's floor elevation.
export function zoneFloor(zone: ZoneId): number {
  if (zone === "bedroomB" || zone === "bedroomA") return 1;
  if (zone === "basementB" || zone === "basementA") return -1;
  return 0;
}

// ---- static level geometry (per floor) ----

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
  return { ...z, xMin: z.xMin * S, xMax: z.xMax * S, yMin: z.yMin * S, yMax: z.yMax * S };
}

export const ZONE_RECTS: ZoneRect[] = (
  [
    // ---- floor 0 (ground) ----
    { id: "backyardB", label: "BACKYARD B", xMin: 0, xMax: 240, yMin: 0, yMax: 900, floor: 0, color: COLORS.backyard },
    { id: "livingB", label: "LIVING ROOM B", labelColor: "#8c3f10", xMin: 240, xMax: 620, yMin: 0, yMax: 900, floor: 0, color: COLORS.livingB },
    { id: "garden", label: "GARDEN", xMin: 620, xMax: 980, yMin: 0, yMax: 900, floor: 0, color: COLORS.garden },
    { id: "livingA", label: "LIVING ROOM A", labelColor: "#12467c", xMin: 980, xMax: 1360, yMin: 0, yMax: 900, floor: 0, color: COLORS.livingA },
    { id: "backyardA", label: "BACKYARD A", xMin: 1360, xMax: 1600, yMin: 0, yMax: 900, floor: 0, color: COLORS.backyard },
    // ---- floor +1 (top): two bedrooms per house, one logical cash zone ----
    { id: "bedroomB", label: "BEDROOMS B", xMin: 240, xMax: 620, yMin: 0, yMax: 900, floor: 1, color: COLORS.bedroom },
    { id: "bedroomA", label: "BEDROOMS A", xMin: 980, xMax: 1360, yMin: 0, yMax: 900, floor: 1, color: COLORS.bedroom },
    // ---- floor -1 (basement): the jails ----
    { id: "basementB", label: "BASEMENT B (jail: Team A)", xMin: 240, xMax: 620, yMin: 0, yMax: 900, floor: -1, color: COLORS.basement },
    { id: "basementA", label: "BASEMENT A (jail: Team B)", xMin: 980, xMax: 1360, yMin: 0, yMax: 900, floor: -1, color: COLORS.basement },
  ] as ZoneRect[]
).map(scaleZone);

export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export interface FloorRect extends Rect {
  floor?: number; // undefined = every floor (the world boundary)
}

function scaleRect<T extends Rect>(r: T): T {
  return { ...r, x1: r.x1 * S, y1: r.y1 * S, x2: r.x2 * S, y2: r.y2 * S };
}

// Per-floor wall segments (door/connector gaps left out). Mirrors
// server/src/zones.ts WALLS exactly (same pre-scale numbers). Used for the
// wall geometry AND, filtered by the player's current floor, for collision.
export const WALLS: FloorRect[] = (
  [
    // world boundary (all floors)
    { x1: 0, y1: 0, x2: 1600, y2: 10 },
    { x1: 0, y1: 890, x2: 1600, y2: 900 },
    { x1: 0, y1: 0, x2: 10, y2: 900 },
    { x1: 1590, y1: 0, x2: 1600, y2: 900 },

    // ===== floor 0: backyards | livings | garden =====
    // backyard B | living B (x=240): gaps ladder y[150,290], yard door y[370,450], cellar y[610,750]
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
    // living A | backyard A (x=1360): mirror of B
    { x1: 1355, y1: 10, x2: 1365, y2: 150, floor: 0 },
    { x1: 1355, y1: 290, x2: 1365, y2: 370, floor: 0 },
    { x1: 1355, y1: 450, x2: 1365, y2: 610, floor: 0 },
    { x1: 1355, y1: 750, x2: 1365, y2: 890, floor: 0 },

    // ===== floor +1: two bedrooms per house =====
    { x1: 235, y1: 0, x2: 245, y2: 150, floor: 1 },
    { x1: 235, y1: 290, x2: 245, y2: 900, floor: 1 },
    { x1: 615, y1: 0, x2: 625, y2: 900, floor: 1 },
    { x1: 240, y1: 0, x2: 620, y2: 10, floor: 1 },
    { x1: 240, y1: 890, x2: 620, y2: 900, floor: 1 },
    { x1: 240, y1: 445, x2: 400, y2: 455, floor: 1 }, // partition, door gap x[400,480]
    { x1: 480, y1: 445, x2: 620, y2: 455, floor: 1 },
    { x1: 1355, y1: 0, x2: 1365, y2: 150, floor: 1 },
    { x1: 1355, y1: 290, x2: 1365, y2: 900, floor: 1 },
    { x1: 975, y1: 0, x2: 985, y2: 900, floor: 1 },
    { x1: 980, y1: 0, x2: 1360, y2: 10, floor: 1 },
    { x1: 980, y1: 890, x2: 1360, y2: 900, floor: 1 },
    { x1: 980, y1: 445, x2: 1130, y2: 455, floor: 1 }, // partition, door gap x[1130,1210]
    { x1: 1210, y1: 445, x2: 1360, y2: 455, floor: 1 },

    // ===== floor -1: one open basement per house =====
    { x1: 235, y1: 0, x2: 245, y2: 610, floor: -1 },
    { x1: 235, y1: 750, x2: 245, y2: 900, floor: -1 },
    { x1: 615, y1: 0, x2: 625, y2: 900, floor: -1 },
    { x1: 240, y1: 0, x2: 620, y2: 10, floor: -1 },
    { x1: 240, y1: 890, x2: 620, y2: 900, floor: -1 },
    { x1: 1355, y1: 0, x2: 1365, y2: 610, floor: -1 },
    { x1: 1355, y1: 750, x2: 1365, y2: 900, floor: -1 },
    { x1: 975, y1: 0, x2: 985, y2: 900, floor: -1 },
    { x1: 980, y1: 0, x2: 1360, y2: 10, floor: -1 },
    { x1: 980, y1: 890, x2: 1360, y2: 900, floor: -1 },
  ] as FloorRect[]
).map((r) => ({ ...scaleRect(r), floor: r.floor }));

// ---- floor connectors (staircases / ladders / cellar-steps) ----
// Mirror of server/src/zones.ts CONNECTORS. A connector forces the floor by
// which side of `mid` (along `axis`) you're on; `sealedFor` marks the ones the
// owning team can't use (its own bedroom/basement stairs & ladders).
export interface Connector {
  id: string;
  rect: Rect;
  axis: "x" | "y";
  mid: number;
  floorLow: number;
  floorHigh: number;
  sealedFor?: Team;
}

const scaleConnector = (c: Connector): Connector => ({ ...c, rect: scaleRect(c.rect), mid: c.mid * S });

export const CONNECTORS: Connector[] = (
  [
    { id: "stairUpB", rect: { x1: 380, y1: 150, x2: 540, y2: 290 }, axis: "y", mid: 220, floorLow: 1, floorHigh: 0, sealedFor: "B" },
    { id: "stairDownB", rect: { x1: 380, y1: 610, x2: 540, y2: 750 }, axis: "y", mid: 680, floorLow: 0, floorHigh: -1, sealedFor: "B" },
    { id: "ladderB", rect: { x1: 160, y1: 150, x2: 320, y2: 290 }, axis: "x", mid: 240, floorLow: 0, floorHigh: 1, sealedFor: "B" },
    { id: "cellarB", rect: { x1: 160, y1: 610, x2: 320, y2: 750 }, axis: "x", mid: 240, floorLow: 0, floorHigh: -1, sealedFor: "B" },
    { id: "stairUpA", rect: { x1: 1060, y1: 150, x2: 1220, y2: 290 }, axis: "y", mid: 220, floorLow: 1, floorHigh: 0, sealedFor: "A" },
    { id: "stairDownA", rect: { x1: 1060, y1: 610, x2: 1220, y2: 750 }, axis: "y", mid: 680, floorLow: 0, floorHigh: -1, sealedFor: "A" },
    { id: "ladderA", rect: { x1: 1280, y1: 150, x2: 1440, y2: 290 }, axis: "x", mid: 1360, floorLow: 1, floorHigh: 0, sealedFor: "A" },
    { id: "cellarA", rect: { x1: 1280, y1: 610, x2: 1440, y2: 750 }, axis: "x", mid: 1360, floorLow: -1, floorHigh: 0, sealedFor: "A" },
  ] as Connector[]
).map(scaleConnector);

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
  return floor;
}

export function connectorBlocks(x: number, y: number, team: Team): boolean {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team && inRect(x, y, c.rect)) return true;
  }
  return false;
}

// ---- passable ground-floor doors (flat mats, no floor change) ----
// The vertical connectors above carry all the between-floor doorways; these are
// the same-level openings: living<->garden (x3 per house) and living<->backyard.
export const DOORS: Rect[] = (
  [
    // house B
    { x1: 233, y1: 370, x2: 247, y2: 450 }, // living <-> backyard
    { x1: 613, y1: 230, x2: 627, y2: 290 }, // living <-> garden (top)
    { x1: 613, y1: 380, x2: 627, y2: 440 }, // living <-> garden (middle)
    { x1: 613, y1: 530, x2: 627, y2: 590 }, // living <-> garden (bottom)
    // house A (mirror)
    { x1: 1353, y1: 370, x2: 1367, y2: 450 },
    { x1: 973, y1: 230, x2: 987, y2: 290 },
    { x1: 973, y1: 380, x2: 987, y2: 440 },
    { x1: 973, y1: 530, x2: 987, y2: 590 },
  ] as Rect[]
).map(scaleRect);
