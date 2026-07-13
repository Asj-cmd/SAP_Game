// Top-down world (Brawl Stars style): a single flat plane, no gravity - see
// server/src/zones.ts + client/src/objects/Zone.ts for the floor plan this size
// matches (backyard | house | garden | house | backyard).
export const WORLD_WIDTH = 1600;
export const WORLD_HEIGHT = 900;

export const PLAYER_SPEED = 220;
export const CARRY_SPEED = 160;

export const MOVE_SEND_INTERVAL_MS = 50; // 20 times/sec
export const REMOTE_LERP = 0.2;
// Rotation snapping reads as more jarring than position snapping at the same
// factor, so remote facing gets its own (higher) lerp constant.
export const ROTATION_LERP = 0.25;

export const ACTION_RANGE = 60;
export const ROUND_TIME_DEFAULT = 300;

// 3D rendering constants (world-unit scale, same units as WORLD_WIDTH/HEIGHT).
export const WALL_HEIGHT = 140; // tall enough to fully occlude camera/character
export const FLOOR_HEIGHT = 4; // thin slab, purely visual
export const DOOR_MAT_HEIGHT = 1; // flat mat, sits just above the floor slab

// The Blender character rig (assets/blender/build_character.py) is ~1.85
// "Blender units" tall; scaled up so its ~0.84-unit arm span roughly matches
// CharacterController's 40-unit (2x radius) collision circle.
export const CHARACTER_SCALE = 45;

// 3rd-person chase camera (see three/CameraRig.ts).
export const FOLLOW_DISTANCE = 240; // behind the character, world units
export const FOLLOW_HEIGHT = 160; // above LOOK_HEIGHT
export const LOOK_HEIGHT = 55; // roughly chest height on the scaled character
export const MAX_YAW_SPEED = Math.PI * 2.5; // ~0.4s to swing a 180 degree reversal

// The Blender cash bundle prop (assets/blender/build_cashbundle.py) is ~0.3
// Blender units wide; scaled up to read clearly next to the character.
export const BUNDLE_SCALE = 100;

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
