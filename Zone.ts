// World/zone constants mirrored from server/src/zones.ts (PRD Section 3).
// Deliberately duplicated rather than shared via tooling — see server file.

export const WORLD_WIDTH = 3200;
export const WORLD_HEIGHT = 1020;
export const GROUND_Y = 720;
export const WORLD_MIN_X = 60;
export const WORLD_MAX_X = 3140;

export const PLAYER_SPEED = 220;
export const PLAYER_SPEED_CARRYING = 160;
export const JUMP_VELOCITY = -520;
export const GRAVITY = 800;
export const ACTION_RANGE = 60;

export const COLORS = {
  bedroom: 0xf0997b,
  living: 0xb5d4f4,
  garden: 0xeaf3de,
  basement: 0xb4b2a9,
  ground: 0x8b6914,
  sky: 0xd6eeff,
  dirt: 0x6b4423,
  teamB: 0xe85d24,
  teamA: 0x185fa5,
  cash: 0xffd700,
} as const;

export interface ZoneRect {
  x: number;
  y: number;
  width: number;
  height: number;
  color: number;
  label: string;
}

export const ZONES: ZoneRect[] = [
  { x: 60, y: 0, width: 440, height: 720, color: COLORS.bedroom, label: "MASTER BEDROOM B" },
  { x: 500, y: 0, width: 480, height: 720, color: COLORS.living, label: "LIVING ROOM B" },
  { x: 980, y: 0, width: 1240, height: 720, color: COLORS.garden, label: "GARDEN" },
  { x: 2220, y: 0, width: 480, height: 720, color: COLORS.living, label: "LIVING ROOM A" },
  { x: 2700, y: 0, width: 440, height: 720, color: COLORS.bedroom, label: "MASTER BEDROOM A" },
  { x: 60, y: 720, width: 920, height: 300, color: COLORS.basement, label: "BASEMENT B" },
  { x: 980, y: 720, width: 1240, height: 300, color: COLORS.dirt, label: "" },
  { x: 2220, y: 720, width: 920, height: 300, color: COLORS.basement, label: "BASEMENT A" },
];

export interface WallSegment {
  x: number;
  y: number;
  width: number;
  height: number;
}

const WALL_T = 10;

// Outer boundary walls (left x=60, right x=3140), split around door/entry gaps.
export const BOUNDARY_WALLS: WallSegment[] = [
  // left wall, gaps at team B main door (y580-680) and basement B external entry (y820-920)
  { x: WORLD_MIN_X - WALL_T, y: 0, width: WALL_T, height: 580 },
  { x: WORLD_MIN_X - WALL_T, y: 680, width: WALL_T, height: 140 },
  { x: WORLD_MIN_X - WALL_T, y: 920, width: WALL_T, height: 100 },
  // right wall, gaps at team A main door (y580-680) and basement A external entry (y820-920)
  { x: WORLD_MAX_X, y: 0, width: WALL_T, height: 580 },
  { x: WORLD_MAX_X, y: 680, width: WALL_T, height: 140 },
  { x: WORLD_MAX_X, y: 920, width: WALL_T, height: 100 },
];

// Internal dividers with an always-open side door (no team restriction).
export const OPEN_DOOR_WALLS: WallSegment[] = [
  // livingB / garden divider at x=980, gap y580-680
  { x: 980, y: 0, width: WALL_T, height: 580 },
  { x: 980, y: 680, width: WALL_T, height: 40 },
  // garden / livingA divider at x=2220, gap y580-680
  { x: 2220, y: 0, width: WALL_T, height: 580 },
  { x: 2220, y: 680, width: WALL_T, height: 40 },
];

// Bedroom divider walls, solid outside the door gap (y560-660) and the
// high window gap (y380-480). Both gaps are team-conditional pass-throughs.
// NOTE: the PRD places windows in the top wall at Y=0, but that is
// unreachable with jump physics (max jump ~170px, rooms 720px tall) — so the
// window is a high opening in the divider wall instead, reached via platforms.
export const BEDROOM_DIVIDER_WALLS: WallSegment[] = [
  { x: 500, y: 0, width: WALL_T, height: 380 },
  { x: 500, y: 480, width: WALL_T, height: 80 },
  { x: 500, y: 660, width: WALL_T, height: 60 },
  { x: 2700, y: 0, width: WALL_T, height: 380 },
  { x: 2700, y: 480, width: WALL_T, height: 80 },
  { x: 2700, y: 660, width: WALL_T, height: 60 },
];

// One climb platform per side of each window, hugging the wall. From floor
// (720) jump to platform (592, 128px ✓); from platform the ~170px jump apex
// carries the body through the window gap (380–480). Both sides get one so
// invaders can climb back out of the bedroom.
export const WINDOW_PLATFORMS: WallSegment[] = [
  { x: 435, y: 592, width: 60, height: 10 }, // bedroom B side
  { x: 515, y: 592, width: 60, height: 10 }, // living room B side
  { x: 2625, y: 592, width: 60, height: 10 }, // living room A side
  { x: 2715, y: 592, width: 60, height: 10 }, // bedroom A side
];

export interface BedroomDoor {
  x: number;
  yTop: number;
  yBottom: number;
  ownTeam: "A" | "B"; // team blocked from passing through (owner of the bedroom)
}

export const BEDROOM_DOORS: BedroomDoor[] = [
  { x: 500, yTop: 560, yBottom: 660, ownTeam: "B" },
  { x: 2700, yTop: 560, yBottom: 660, ownTeam: "A" },
  // Window gaps — same one-way rule as the doors.
  { x: 500, yTop: 380, yBottom: 480, ownTeam: "B" },
  { x: 2700, yTop: 380, yBottom: 480, ownTeam: "A" },
];

// Ground floor (y=720), solid except at the 3 staircases down to underground.
export const GROUND_FLOOR_SEGMENTS: WallSegment[] = [
  { x: WORLD_MIN_X, y: GROUND_Y, width: 700 - WORLD_MIN_X, height: WALL_T },
  { x: 800, y: GROUND_Y, width: 1450 - 800, height: WALL_T },
  { x: 1750, y: GROUND_Y, width: 2400 - 1750, height: WALL_T },
  { x: 2500, y: GROUND_Y, width: WORLD_MAX_X - 2500, height: WALL_T },
];

// Underground floor (world bottom), solid across the full width.
export const UNDERGROUND_FLOOR: WallSegment = {
  x: WORLD_MIN_X,
  y: WORLD_HEIGHT - WALL_T,
  width: WORLD_MAX_X - WORLD_MIN_X,
  height: WALL_T,
};

// Basements must NOT be connected underground (PRD 3.3) — solid dividers
// between each basement and the central dirt zone.
export const UNDERGROUND_DIVIDER_WALLS: WallSegment[] = [
  { x: 980, y: GROUND_Y, width: WALL_T, height: 300 },
  { x: 2220, y: GROUND_Y, width: WALL_T, height: 300 },
];

// Climbable steps inside each stair opening. Max jump height is ~170px
// (v²/2g = 520²/1600), so steps are spaced ≤140px vertically.
// Basement floor top is at y=1010.
export const STAIR_STEPS: WallSegment[] = [
  // Living room B -> Basement B (gap x: 700–800)
  { x: 750, y: 940, width: 50, height: 10 },
  { x: 700, y: 860, width: 50, height: 10 },
  // Garden -> underground dead zone (gap x: 1450–1750)
  { x: 1450, y: 940, width: 100, height: 10 },
  { x: 1550, y: 860, width: 100, height: 10 },
  { x: 1650, y: 790, width: 100, height: 10 },
  // Living room A -> Basement A (gap x: 2400–2500)
  { x: 2400, y: 940, width: 50, height: 10 },
  { x: 2450, y: 860, width: 50, height: 10 },
];

export interface EntryMarker {
  x: number;
  y: number;
  width: number;
  height: number;
  label: string;
}

// Visual-only highlights for every usable opening (no colliders).
export const ENTRY_MARKERS: EntryMarker[] = [
  { x: 490, y: 560, width: 30, height: 100, label: "DOOR" },
  { x: 970, y: 580, width: 30, height: 100, label: "DOOR" },
  { x: 2210, y: 580, width: 30, height: 100, label: "DOOR" },
  { x: 2690, y: 560, width: 30, height: 100, label: "DOOR" },
  { x: 700, y: 700, width: 100, height: 30, label: "STAIRS" },
  { x: 1450, y: 700, width: 300, height: 30, label: "STAIRS" },
  { x: 2400, y: 700, width: 100, height: 30, label: "STAIRS" },
  { x: 490, y: 380, width: 30, height: 100, label: "WINDOW" },
  { x: 2690, y: 380, width: 30, height: 100, label: "WINDOW" },
];
