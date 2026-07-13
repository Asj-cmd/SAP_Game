// Top-down world (Brawl Stars style): a single flat plane, no gravity - see
// server/src/zones.ts + client/src/objects/Zone.ts for the floor plan this size
// matches (backyard | house | garden | house | backyard).
export const WORLD_WIDTH = 1600;
export const WORLD_HEIGHT = 900;

export const PLAYER_SPEED = 220;
export const CARRY_SPEED = 160;

export const MOVE_SEND_INTERVAL_MS = 50; // 20 times/sec
export const REMOTE_LERP = 0.2;

export const ACTION_RANGE = 60;
export const ROUND_TIME_DEFAULT = 300;

// 3D rendering constants (world-unit scale, same units as WORLD_WIDTH/HEIGHT).
export const WALL_HEIGHT = 140; // tall enough to fully occlude camera/character
export const FLOOR_HEIGHT = 4; // thin slab, purely visual
export const DOOR_MAT_HEIGHT = 1; // flat mat, sits just above the floor slab

export const COLORS = {
  bedroom: 0xf0997b, // cash rooms - same on both sides so "salmon = cash" reads instantly
  livingB: 0xf3d5bc, // Team B's living room, tinted toward B's orange
  livingA: 0xbfd9f2, // Team A's living room, tinted toward A's blue
  garden: 0xeaf3de,
  gardenAlt: 0xdcefc9,
  backyard: 0xcde3b1, // grassier green than the garden - reads as private yard
  basement: 0xb4b2a9,
  door: 0xefdfa8, // door mats drawn in every passable wall gap
  doorEdge: 0x8a774a,
  teamB: 0xe85d24,
  teamA: 0x185fa5,
  cash: 0xffd700,
  wall: 0x2b2b2b,
  void: 0x0d1926,
};
