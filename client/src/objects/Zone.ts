import Phaser from "phaser";
import { COLORS, WORLD_WIDTH, GROUND_Y, WORLD_HEIGHT } from "../constants";

export type Team = "A" | "B";
export type ZoneId =
  | "bedroomB"
  | "livingB"
  | "garden"
  | "livingA"
  | "bedroomA"
  | "basementB"
  | "gardenPit"
  | "basementA";

// ---- zone lookup (mirrors server/src/zones.ts deliberately - kept in sync by hand) ----

export function getZoneAt(x: number, y: number): ZoneId {
  if (y < GROUND_Y) {
    if (x < 500) return "bedroomB";
    if (x < 980) return "livingB";
    if (x < 2220) return "garden";
    if (x < 2700) return "livingA";
    return "bedroomA";
  }
  if (x < 980) return "basementB";
  if (x < 2220) return "gardenPit";
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

// ---- static level geometry ----

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
  { id: "bedroomB", label: "MASTER BEDROOM B", xMin: 60, xMax: 500, yMin: 0, yMax: GROUND_Y, color: COLORS.bedroom },
  { id: "livingB", label: "LIVING ROOM B", xMin: 500, xMax: 980, yMin: 0, yMax: GROUND_Y, color: COLORS.livingRoom },
  { id: "garden", label: "GARDEN", xMin: 980, xMax: 2220, yMin: 0, yMax: GROUND_Y, color: COLORS.garden },
  { id: "livingA", label: "LIVING ROOM A", xMin: 2220, xMax: 2700, yMin: 0, yMax: GROUND_Y, color: COLORS.livingRoom },
  { id: "bedroomA", label: "MASTER BEDROOM A", xMin: 2700, xMax: 3140, yMin: 0, yMax: GROUND_Y, color: COLORS.bedroom },
  { id: "basementB", label: "BASEMENT B (jail: Team A)", xMin: 60, xMax: 980, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.basement },
  { id: "gardenPit", label: "", xMin: 980, xMax: 2220, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.dirt },
  { id: "basementA", label: "BASEMENT A (jail: Team B)", xMin: 2220, xMax: 3140, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.basement },
];

interface WallSeg {
  x: number;
  yTop: number;
  yBottom: number;
  width: number;
}

const WALL_THICKNESS = 8;

// Internal zone-separator walls: solid from the ceiling down to `yTop`,
// open (the door) from `yTop` down to the floor.
const DOOR_WALLS: WallSeg[] = [
  { x: 500, yTop: 0, yBottom: 560, width: WALL_THICKNESS }, // bedroomB | livingB
  { x: 980, yTop: 0, yBottom: 580, width: WALL_THICKNESS }, // livingB | garden
  { x: 2220, yTop: 0, yBottom: 580, width: WALL_THICKNESS }, // garden | livingA
  { x: 2700, yTop: 0, yBottom: 560, width: WALL_THICKNESS }, // livingA | bedroomA
];

// The two basements are never connected underground - fully sealed walls.
const SEALED_WALLS: WallSeg[] = [
  { x: 980, yTop: GROUND_Y, yBottom: WORLD_HEIGHT, width: WALL_THICKNESS },
  { x: 2220, yTop: GROUND_Y, yBottom: WORLD_HEIGHT, width: WALL_THICKNESS },
];

// World boundary walls, each with a ground-floor door + an underground door.
const BOUNDARY_WALLS: WallSeg[] = [
  { x: 60, yTop: 0, yBottom: 580, width: WALL_THICKNESS },
  { x: 60, yTop: GROUND_Y, yBottom: 820, width: WALL_THICKNESS },
  { x: 3140, yTop: 0, yBottom: 580, width: WALL_THICKNESS },
  { x: 3140, yTop: GROUND_Y, yBottom: 820, width: WALL_THICKNESS },
];

interface RoofSeg {
  xMin: number;
  xMax: number;
}

// Roof over the houses (y:0-40), open above the garden. Windows are gaps in this roof.
const ROOF_HEIGHT = 40;
const ROOF_SEGMENTS: RoofSeg[] = [
  { xMin: 60, xMax: 200 },
  { xMin: 260, xMax: 500 },
  { xMin: 500, xMax: 980 },
  { xMin: 2220, xMax: 2700 },
  { xMin: 2700, xMax: 2940 },
  { xMin: 3000, xMax: 3140 },
];

const WINDOW_SILLS = [
  { xMin: 190, xMax: 270 },
  { xMin: 2930, xMax: 3010 },
];

interface FloorSeg {
  xMin: number;
  xMax: number;
}

const FLOOR_HEIGHT = 8;
// Ground floor, with gaps at the 3 staircases down to the underground.
// Note: the gaps are shifted away from x=750/x=2450 (Team B/A's 2nd/1st spawn
// points) so players don't fall straight into the basement the instant they spawn.
const FLOOR_SEGMENTS: FloorSeg[] = [
  { xMin: 60, xMax: 790 },
  { xMin: 975, xMax: 1450 },
  { xMin: 1750, xMax: 2225 },
  { xMin: 2410, xMax: 3140 },
];

const STAIR_MARKERS = [
  { xMin: 790, xMax: 975 },
  { xMin: 1450, xMax: 1750 },
  { xMin: 2225, xMax: 2410 },
];

// The basement on a team's own side (Basement B is under Team B's house, Basement A
// under Team A's). A team is blocked from its OWN basement so it can't camp the
// entrance the enemy uses to rescue captured teammates; the enemy can still drop in.
// The gap indices line up with STAIR_MARKERS above.
const OWN_BASEMENT_GAP: Record<Team, { xMin: number; xMax: number }> = {
  B: STAIR_MARKERS[0], // gap 790-975
  A: STAIR_MARKERS[2], // gap 2225-2410
};

// Climb-out ledges inside each floor gap, so anyone who ends up underground - a
// teammate who dropped in to rescue, a player auto-released from jail, or someone
// who simply fell into the garden pit - can jump back up to the ground floor.
// Each ledge is within one jump (~169px rise) of the surface below it, and the
// top ledge is set back from the exit edge so there is horizontal runway to clear
// onto the floor rather than pinning against its edge. A max jump covers ~90px
// horizontally by the time it has risen ~146px, and much less rise needs even less
// run, which is what sizes these.
//
// The two basements each have a sealed side wall (x=980 for B, x=2220 for A), so
// B climbs out to the LEFT (into Living Room B) and A climbs out to the RIGHT
// (into Living Room A); the open garden pit climbs out to the right onto the lawn.
const STAIR_STEP_H = 16;
interface StairStep {
  xMin: number;
  xMax: number;
  yTop: number;
}
const STAIRCASES: StairStep[] = [
  // Basement B (gap 790-975) -> exit LEFT onto floor[60,790].
  { xMin: 900, xMax: 975, yTop: 912 }, // low ledge (reached from the underground floor)
  { xMin: 845, xMax: 935, yTop: 816 }, // high ledge (set back ~55px from the exit edge)
  // Garden pit (gap 1450-1750) -> exit RIGHT onto floor[1750,2270]. One wide gap,
  // so a single mid-ledge with a full run-up is enough.
  { xMin: 1520, xMax: 1700, yTop: 866 },
  // Basement A (gap 2225-2410) -> exit RIGHT onto floor[2410,3140] (mirror of B).
  { xMin: 2225, xMax: 2300, yTop: 912 }, // low ledge
  { xMin: 2265, xMax: 2355, yTop: 816 }, // high ledge (set back ~55px from the exit edge)
];

export function drawZones(scene: Phaser.Scene, localTeam: Team) {
  const g = scene.add.graphics();
  const ownGap = OWN_BASEMENT_GAP[localTeam];

  // sky + dirt backgrounds
  g.fillStyle(COLORS.sky, 1);
  g.fillRect(0, 0, WORLD_WIDTH, GROUND_Y);
  g.fillStyle(COLORS.dirt, 1);
  g.fillRect(0, GROUND_Y, WORLD_WIDTH, WORLD_HEIGHT - GROUND_Y);

  // zone fills + labels
  for (const zone of ZONE_RECTS) {
    g.fillStyle(zone.color, 1);
    g.fillRect(zone.xMin, zone.yMin, zone.xMax - zone.xMin, zone.yMax - zone.yMin);
    if (zone.label) {
      scene.add
        .text((zone.xMin + zone.xMax) / 2, zone.yMin + 20, zone.label, {
          fontSize: "16px",
          color: "#33261a",
          fontStyle: "bold",
        })
        .setOrigin(0.5, 0);
    }
  }

  // stair markers (visual cue for the floor gap) - skip the local team's own
  // basement, whose gap is sealed off for them below.
  g.fillStyle(0x000000, 0.25);
  for (const s of STAIR_MARKERS) {
    if (s === ownGap) continue;
    g.fillRect(s.xMin, GROUND_Y - 10, s.xMax - s.xMin, 20);
  }

  // walls (dark stroke outlines matching the collider geometry)
  g.lineStyle(4, COLORS.wall, 1);
  const allWalls = [...DOOR_WALLS, ...SEALED_WALLS, ...BOUNDARY_WALLS];
  for (const w of allWalls) {
    g.strokeRect(w.x - w.width / 2, w.yTop, w.width, w.yBottom - w.yTop);
  }

  // roof segments
  g.fillStyle(COLORS.wall, 1);
  for (const r of ROOF_SEGMENTS) {
    g.fillRect(r.xMin, 0, r.xMax - r.xMin, ROOF_HEIGHT);
  }

  // window sills (decorative jump platform)
  g.fillStyle(0x7a5230, 1);
  for (const s of WINDOW_SILLS) {
    g.fillRect(s.xMin, 90, s.xMax - s.xMin, 8);
  }

  // ground floor segments
  g.fillStyle(COLORS.ground, 1);
  for (const f of FLOOR_SEGMENTS) {
    g.fillRect(f.xMin, GROUND_Y, f.xMax - f.xMin, FLOOR_HEIGHT);
  }
  // seal the local team's own-basement gap with floor (they can't go down there)
  g.fillRect(ownGap.xMin, GROUND_Y, ownGap.xMax - ownGap.xMin, FLOOR_HEIGHT);

  // staircase steps (climb-out platforms in each gap)
  for (const s of STAIRCASES) {
    g.fillStyle(COLORS.ground, 1);
    g.fillRect(s.xMin, s.yTop, s.xMax - s.xMin, STAIR_STEP_H);
    g.lineStyle(3, COLORS.wall, 1);
    g.strokeRect(s.xMin, s.yTop, s.xMax - s.xMin, STAIR_STEP_H);
  }
}

export function createWallColliders(scene: Phaser.Scene, localTeam: Team): Phaser.Physics.Arcade.StaticGroup {
  const group = scene.physics.add.staticGroup();

  const addRect = (x: number, y: number, w: number, h: number) => {
    const rect = scene.add.rectangle(x + w / 2, y + h / 2, w, h);
    rect.setVisible(false);
    group.add(rect);
    const body = rect.body as Phaser.Physics.Arcade.StaticBody;
    body.updateFromGameObject();
    return rect;
  };

  for (const w of [...DOOR_WALLS, ...SEALED_WALLS, ...BOUNDARY_WALLS]) {
    addRect(w.x - w.width / 2, w.yTop, w.width, w.yBottom - w.yTop);
  }

  for (const r of ROOF_SEGMENTS) {
    addRect(r.xMin, 0, r.xMax - r.xMin, ROOF_HEIGHT);
  }

  for (const s of WINDOW_SILLS) {
    addRect(s.xMin, 90, s.xMax - s.xMin, 8);
  }

  for (const f of FLOOR_SEGMENTS) {
    addRect(f.xMin, GROUND_Y, f.xMax - f.xMin, FLOOR_HEIGHT);
  }

  // staircase steps (climb-out platforms in each gap)
  for (const s of STAIRCASES) {
    addRect(s.xMin, s.yTop, s.xMax - s.xMin, STAIR_STEP_H);
  }

  // underground floor
  addRect(60, WORLD_HEIGHT - FLOOR_HEIGHT, 3080, FLOOR_HEIGHT);

  // Own team cannot enter their own master bedroom - block their own door + window.
  if (localTeam === "B") {
    addRect(498, 560, 4, 160); // bedroomB door gap
    addRect(190, 0, 80, 98); // bedroomB window gap + sill
  } else {
    addRect(2698, 560, 4, 160); // bedroomA door gap
    addRect(2930, 0, 80, 98); // bedroomA window gap + sill
  }

  // Own team cannot enter their own basement - seal its floor gap so they can't
  // drop in and camp the entrance the enemy uses for rescues.
  const ownGap = OWN_BASEMENT_GAP[localTeam];
  addRect(ownGap.xMin, GROUND_Y, ownGap.xMax - ownGap.xMin, FLOOR_HEIGHT);

  return group;
}
