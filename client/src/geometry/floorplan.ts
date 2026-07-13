// Engine-agnostic floor plan data + zone logic - deliberately has no Phaser or
// Three.js imports (constants.ts is plain data, safe to depend on), so this can
// be shared by any renderer. Mirrors server/src/zones.ts by hand - keep both in
// sync.
import { COLORS } from "../constants";

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
  | "backyardA";

// ---- zone lookup ----

// Columns, left to right: backyard B | house B | garden | house A | backyard A
const YARD_B_MAX = 140;
const HOUSE_B_MAX = 540;
const HOUSE_A_MIN = 1060;
const YARD_A_MIN = 1460;
// Rows within a house column: bedroom | living | basement
const BEDROOM_MAX_Y = 200;
const BASEMENT_MIN_Y = 620;

export function getZoneAt(x: number, y: number): ZoneId {
  if (x < YARD_B_MAX) return "backyardB";
  if (x < HOUSE_B_MAX) {
    if (y < BEDROOM_MAX_Y) return "bedroomB";
    if (y < BASEMENT_MIN_Y) return "livingB";
    return "basementB";
  }
  if (x < HOUSE_A_MIN) return "garden";
  if (x < YARD_A_MIN) {
    if (y < BEDROOM_MAX_Y) return "bedroomA";
    if (y < BASEMENT_MIN_Y) return "livingA";
    return "basementA";
  }
  return "backyardA";
}

export function isEnemyBedroom(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

// Own home = own living room, own master bedroom, or own BACKYARD - the yard is
// part of the property, so owners can lock intruders caught there too.
export function isOwnHome(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  if (team === "B") return zone === "livingB" || zone === "bedroomB" || zone === "backyardB";
  return zone === "livingA" || zone === "bedroomA" || zone === "backyardA";
}

export function jailBasementForTeam(team: Team): ZoneId {
  return team === "A" ? "basementB" : "basementA";
}

// ---- static level geometry (top-down floor plan) ----

export interface ZoneRect {
  id: ZoneId;
  label: string;
  labelColor?: string;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  color: number;
}

export const ZONE_RECTS: ZoneRect[] = [
  { id: "backyardB", label: "BACKYARD B", xMin: 0, xMax: 140, yMin: 0, yMax: 900, color: COLORS.backyard },
  { id: "bedroomB", label: "MASTER BEDROOM B", xMin: 140, xMax: 540, yMin: 0, yMax: 200, color: COLORS.bedroom },
  {
    id: "livingB",
    label: "LIVING ROOM B",
    labelColor: "#8c3f10",
    xMin: 140,
    xMax: 540,
    yMin: 200,
    yMax: 620,
    color: COLORS.livingB,
  },
  {
    id: "basementB",
    label: "BASEMENT B (jail: Team A)",
    xMin: 140,
    xMax: 540,
    yMin: 620,
    yMax: 900,
    color: COLORS.basement,
  },
  { id: "garden", label: "GARDEN", xMin: 540, xMax: 1060, yMin: 0, yMax: 900, color: COLORS.garden },
  { id: "bedroomA", label: "MASTER BEDROOM A", xMin: 1060, xMax: 1460, yMin: 0, yMax: 200, color: COLORS.bedroom },
  {
    id: "livingA",
    label: "LIVING ROOM A",
    labelColor: "#12467c",
    xMin: 1060,
    xMax: 1460,
    yMin: 200,
    yMax: 620,
    color: COLORS.livingA,
  },
  {
    id: "basementA",
    label: "BASEMENT A (jail: Team B)",
    xMin: 1060,
    xMax: 1460,
    yMin: 620,
    yMax: 900,
    color: COLORS.basement,
  },
  { id: "backyardA", label: "BACKYARD A", xMin: 1460, xMax: 1600, yMin: 0, yMax: 900, color: COLORS.backyard },
];

export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

// Every solid wall segment in the map. Door gaps are simply left out of this list;
// the DOORS list below fills each gap with either a visible mat (passable) or a
// sealed block (the owning team can't use its own bedroom/basement doors).
export const WALLS: Rect[] = [
  // world boundary
  { x1: 0, y1: 0, x2: 1600, y2: 10 },
  { x1: 0, y1: 890, x2: 1600, y2: 900 },
  { x1: 0, y1: 0, x2: 10, y2: 900 },
  { x1: 1590, y1: 0, x2: 1600, y2: 900 },
  // backyard B | house B (x=140): gaps bedroom y[60,140], living y[370,450], basement y[700,780]
  { x1: 135, y1: 0, x2: 145, y2: 60 },
  { x1: 135, y1: 140, x2: 145, y2: 370 },
  { x1: 135, y1: 450, x2: 145, y2: 700 },
  { x1: 135, y1: 780, x2: 145, y2: 900 },
  // house B | garden (x=540): 3 living-room door gaps y[230,290], y[380,440], y[530,590]
  { x1: 535, y1: 0, x2: 545, y2: 230 },
  { x1: 535, y1: 290, x2: 545, y2: 380 },
  { x1: 535, y1: 440, x2: 545, y2: 530 },
  { x1: 535, y1: 590, x2: 545, y2: 900 },
  // bedroom B | living B (y=200): gap x[300,380]
  { x1: 140, y1: 195, x2: 300, y2: 205 },
  { x1: 380, y1: 195, x2: 540, y2: 205 },
  // living B | basement B (y=620): gap x[300,380]
  { x1: 140, y1: 615, x2: 300, y2: 625 },
  { x1: 380, y1: 615, x2: 540, y2: 625 },
  // garden | house A (x=1060): 3 living-room door gaps (mirror)
  { x1: 1055, y1: 0, x2: 1065, y2: 230 },
  { x1: 1055, y1: 290, x2: 1065, y2: 380 },
  { x1: 1055, y1: 440, x2: 1065, y2: 530 },
  { x1: 1055, y1: 590, x2: 1065, y2: 900 },
  // house A | backyard A (x=1460): gaps (mirror of B)
  { x1: 1455, y1: 0, x2: 1465, y2: 60 },
  { x1: 1455, y1: 140, x2: 1465, y2: 370 },
  { x1: 1455, y1: 450, x2: 1465, y2: 700 },
  { x1: 1455, y1: 780, x2: 1465, y2: 900 },
  // bedroom A | living A (y=200): gap x[1220,1300]
  { x1: 1060, y1: 195, x2: 1220, y2: 205 },
  { x1: 1300, y1: 195, x2: 1460, y2: 205 },
  // living A | basement A (y=620): gap x[1220,1300]
  { x1: 1060, y1: 615, x2: 1220, y2: 625 },
  { x1: 1300, y1: 615, x2: 1460, y2: 625 },
];

// The 8 doors per house from the concept sketch: 3 house entry/exit (living <->
// garden), 2 for the master bedroom (living side + backyard side), 2 for the
// basement (living side + backyard side), 1 living <-> backyard. `sealedFor`
// marks doors the OWNING team cannot pass (their own bedroom/basement doors), so
// they can't camp the rooms the enemy needs to raid - the enemy walks through
// freely.
export interface Door extends Rect {
  sealedFor?: Team;
}

export const DOORS: Door[] = [
  // ---- house B ----
  { x1: 133, y1: 60, x2: 147, y2: 140, sealedFor: "B" }, // bedroom <-> backyard
  { x1: 300, y1: 193, x2: 380, y2: 207, sealedFor: "B" }, // bedroom <-> living
  { x1: 133, y1: 370, x2: 147, y2: 450 }, // living <-> backyard
  { x1: 533, y1: 230, x2: 547, y2: 290 }, // living <-> garden (top)
  { x1: 533, y1: 380, x2: 547, y2: 440 }, // living <-> garden (middle)
  { x1: 533, y1: 530, x2: 547, y2: 590 }, // living <-> garden (bottom)
  { x1: 300, y1: 613, x2: 380, y2: 627, sealedFor: "B" }, // basement <-> living
  { x1: 133, y1: 700, x2: 147, y2: 780, sealedFor: "B" }, // basement <-> backyard
  // ---- house A (mirror) ----
  { x1: 1453, y1: 60, x2: 1467, y2: 140, sealedFor: "A" }, // bedroom <-> backyard
  { x1: 1220, y1: 193, x2: 1300, y2: 207, sealedFor: "A" }, // bedroom <-> living
  { x1: 1453, y1: 370, x2: 1467, y2: 450 }, // living <-> backyard
  { x1: 1053, y1: 230, x2: 1067, y2: 290 }, // living <-> garden (top)
  { x1: 1053, y1: 380, x2: 1067, y2: 440 }, // living <-> garden (middle)
  { x1: 1053, y1: 530, x2: 1067, y2: 590 }, // living <-> garden (bottom)
  { x1: 1220, y1: 613, x2: 1300, y2: 627, sealedFor: "A" }, // basement <-> living
  { x1: 1453, y1: 700, x2: 1467, y2: 780, sealedFor: "A" }, // basement <-> backyard
];
