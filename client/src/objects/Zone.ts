import Phaser from "phaser";
import { COLORS, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";

export type Team = "A" | "B";
export type ZoneId = "bedroomB" | "livingB" | "garden" | "livingA" | "bedroomA" | "basementB" | "basementA";

// ---- zone lookup (mirrors server/src/zones.ts deliberately - kept in sync by hand) ----

const COL_B_MAX = 300;
const COL_A_MIN = 1100;
const BEDROOM_MAX_Y = 180;
const BASEMENT_MIN_Y = 620;

export function getZoneAt(x: number, y: number): ZoneId {
  if (x < COL_B_MAX) {
    if (y < BEDROOM_MAX_Y) return "bedroomB";
    if (y < BASEMENT_MIN_Y) return "livingB";
    return "basementB";
  }
  if (x < COL_A_MIN) return "garden";
  if (y < BEDROOM_MAX_Y) return "bedroomA";
  if (y < BASEMENT_MIN_Y) return "livingA";
  return "basementA";
}

export function isEnemyBedroom(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

export function isOwnHome(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  if (team === "B") return zone === "livingB" || zone === "bedroomB";
  return zone === "livingA" || zone === "bedroomA";
}

export function jailBasementForTeam(team: Team): ZoneId {
  return team === "A" ? "basementB" : "basementA";
}

// ---- static level geometry (top-down floor plan) ----

interface ZoneRect {
  id: ZoneId;
  label: string;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  color: number;
}

const ZONE_RECTS: ZoneRect[] = [
  { id: "bedroomB", label: "MASTER BEDROOM B", xMin: 0, xMax: 300, yMin: 0, yMax: 180, color: COLORS.bedroom },
  { id: "livingB", label: "LIVING ROOM B", xMin: 0, xMax: 300, yMin: 180, yMax: 620, color: COLORS.livingRoom },
  {
    id: "basementB",
    label: "BASEMENT B (jail: Team A)",
    xMin: 0,
    xMax: 300,
    yMin: 620,
    yMax: 900,
    color: COLORS.basement,
  },
  { id: "garden", label: "GARDEN", xMin: 300, xMax: 1100, yMin: 0, yMax: 900, color: COLORS.garden },
  { id: "livingA", label: "LIVING ROOM A", xMin: 1100, xMax: 1400, yMin: 180, yMax: 620, color: COLORS.livingRoom },
  { id: "bedroomA", label: "MASTER BEDROOM A", xMin: 1100, xMax: 1400, yMin: 0, yMax: 180, color: COLORS.bedroom },
  {
    id: "basementA",
    label: "BASEMENT A (jail: Team B)",
    xMin: 1100,
    xMax: 1400,
    yMin: 620,
    yMax: 900,
    color: COLORS.basement,
  },
];

interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

// Every solid wall segment in the map (door/window gaps are simply left out of
// this list - that's what makes them passable).
const WALLS: Rect[] = [
  // vertical divider: Team B house | Garden (x=300)
  { x1: 295, y1: 0, x2: 305, y2: 180 },
  { x1: 295, y1: 180, x2: 305, y2: 220 },
  { x1: 295, y1: 300, x2: 305, y2: 500 },
  { x1: 295, y1: 580, x2: 305, y2: 620 },
  { x1: 295, y1: 620, x2: 305, y2: 900 },
  // vertical divider: Garden | Team A house (x=1100)
  { x1: 1095, y1: 0, x2: 1105, y2: 180 },
  { x1: 1095, y1: 180, x2: 1105, y2: 220 },
  { x1: 1095, y1: 300, x2: 1105, y2: 500 },
  { x1: 1095, y1: 580, x2: 1105, y2: 620 },
  { x1: 1095, y1: 620, x2: 1105, y2: 900 },
  // bedroomB | livingB internal door (y=180), gap x[110,190]
  { x1: 0, y1: 175, x2: 110, y2: 185 },
  { x1: 190, y1: 175, x2: 300, y2: 185 },
  // bedroomA | livingA internal door (y=180), gap x[1210,1290]
  { x1: 1100, y1: 175, x2: 1210, y2: 185 },
  { x1: 1290, y1: 175, x2: 1400, y2: 185 },
  // livingB | basementB internal door (y=620), gap x[110,190]
  { x1: 0, y1: 615, x2: 110, y2: 625 },
  { x1: 190, y1: 615, x2: 300, y2: 625 },
  // livingA | basementA internal door (y=620), gap x[1210,1290]
  { x1: 1100, y1: 615, x2: 1210, y2: 625 },
  { x1: 1290, y1: 615, x2: 1400, y2: 625 },
  // top boundary: bedroomB window x[90,210], garden side-doors x[450,550]/x[850,950], bedroomA window x[1190,1310]
  { x1: 0, y1: 0, x2: 90, y2: 10 },
  { x1: 210, y1: 0, x2: 450, y2: 10 },
  { x1: 550, y1: 0, x2: 850, y2: 10 },
  { x1: 950, y1: 0, x2: 1190, y2: 10 },
  { x1: 1310, y1: 0, x2: 1400, y2: 10 },
  // bottom boundary: garden main door x[550,650], garage entry x[750,850]
  { x1: 0, y1: 890, x2: 550, y2: 900 },
  { x1: 650, y1: 890, x2: 750, y2: 900 },
  { x1: 850, y1: 890, x2: 1400, y2: 900 },
  // left boundary: basementB external entries y[680,740] and y[800,860]
  { x1: 0, y1: 0, x2: 10, y2: 680 },
  { x1: 0, y1: 740, x2: 10, y2: 800 },
  { x1: 0, y1: 860, x2: 10, y2: 900 },
  // right boundary: basementA external entries y[680,740] and y[800,860]
  { x1: 1390, y1: 0, x2: 1400, y2: 680 },
  { x1: 1390, y1: 740, x2: 1400, y2: 800 },
  { x1: 1390, y1: 860, x2: 1400, y2: 900 },
];

// Gaps that are blocked ONLY for the team that owns that room - the enemy can
// still walk through to steal cash or rescue a teammate, but the owner can't camp
// their own entrances (window, internal door, or external entries).
const OWN_BEDROOM_BLOCKS: Record<Team, Rect[]> = {
  B: [
    { x1: 90, y1: 0, x2: 210, y2: 10 }, // window
    { x1: 110, y1: 175, x2: 190, y2: 185 }, // internal door
  ],
  A: [
    { x1: 1190, y1: 0, x2: 1310, y2: 10 },
    { x1: 1210, y1: 175, x2: 1290, y2: 185 },
  ],
};

const OWN_BASEMENT_BLOCKS: Record<Team, Rect[]> = {
  B: [
    { x1: 110, y1: 615, x2: 190, y2: 625 }, // internal door
    { x1: 0, y1: 680, x2: 10, y2: 740 }, // external entry 1
    { x1: 0, y1: 800, x2: 10, y2: 860 }, // external entry 2
  ],
  A: [
    { x1: 1210, y1: 615, x2: 1290, y2: 625 },
    { x1: 1390, y1: 680, x2: 1400, y2: 740 },
    { x1: 1390, y1: 800, x2: 1400, y2: 860 },
  ],
};

export function drawZones(scene: Phaser.Scene, localTeam: Team) {
  const g = scene.add.graphics();

  g.fillStyle(COLORS.void, 1);
  g.fillRect(0, 0, WORLD_WIDTH, WORLD_HEIGHT);

  for (const zone of ZONE_RECTS) {
    if (zone.id === "garden") {
      // Cosmetic split into the two team-facing halves from the floor plan;
      // functionally still one neutral zone (no wall, no locking difference).
      const mid = (zone.xMin + zone.xMax) / 2;
      g.fillStyle(COLORS.garden, 1);
      g.fillRect(zone.xMin, zone.yMin, mid - zone.xMin, zone.yMax - zone.yMin);
      g.fillStyle(COLORS.gardenAlt, 1);
      g.fillRect(mid, zone.yMin, zone.xMax - mid, zone.yMax - zone.yMin);
      g.lineStyle(2, 0xffffff, 0.35);
      g.lineBetween(mid, zone.yMin, mid, zone.yMax);
    } else {
      g.fillStyle(zone.color, 1);
      g.fillRect(zone.xMin, zone.yMin, zone.xMax - zone.xMin, zone.yMax - zone.yMin);
    }
    if (zone.label) {
      scene.add
        .text((zone.xMin + zone.xMax) / 2, zone.yMin + 14, zone.label, {
          fontSize: "13px",
          color: "#33261a",
          fontStyle: "bold",
        })
        .setOrigin(0.5, 0);
    }
  }

  // walls (solid everywhere except door/window gaps)
  g.fillStyle(COLORS.wall, 1);
  for (const w of WALLS) {
    g.fillRect(w.x1, w.y1, w.x2 - w.x1, w.y2 - w.y1);
  }
  // the local team's own entries are sealed - draw them as solid wall too, so
  // what you see matches what you can actually walk through.
  for (const w of [...OWN_BEDROOM_BLOCKS[localTeam], ...OWN_BASEMENT_BLOCKS[localTeam]]) {
    g.fillRect(w.x1, w.y1, w.x2 - w.x1, w.y2 - w.y1);
  }
}

export function createWallColliders(scene: Phaser.Scene, localTeam: Team): Phaser.Physics.Arcade.StaticGroup {
  const group = scene.physics.add.staticGroup();

  const addRect = (r: Rect) => {
    const w = r.x2 - r.x1;
    const h = r.y2 - r.y1;
    const rect = scene.add.rectangle(r.x1 + w / 2, r.y1 + h / 2, w, h);
    rect.setVisible(false);
    group.add(rect);
    const body = rect.body as Phaser.Physics.Arcade.StaticBody;
    body.updateFromGameObject();
  };

  for (const w of WALLS) addRect(w);
  for (const w of OWN_BEDROOM_BLOCKS[localTeam]) addRect(w);
  for (const w of OWN_BASEMENT_BLOCKS[localTeam]) addRect(w);

  return group;
}
