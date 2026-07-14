// Top-down world (Brawl Stars style): a single flat plane, no gravity - see
// server/src/zones.ts + client/src/geometry/floorplan.ts for the floor plan this
// size matches (backyard | house | garden | house | backyard).
//
// WORLD_SCALE widens the whole floor plan relative to the original 2D layout
// (1600x900) without touching the character's size, so rooms feel like rooms
// instead of corridors. Speeds and action ranges scale with it, which keeps
// travel times and gameplay balance identical to the 2D-tuned values.
// server/src/zones.ts applies the same factor - keep both in sync.
export const WORLD_SCALE = 1.5;
export const WORLD_WIDTH = 1600 * WORLD_SCALE;
export const WORLD_HEIGHT = 900 * WORLD_SCALE;

export const PLAYER_SPEED = 220 * WORLD_SCALE;
export const CARRY_SPEED = 160 * WORLD_SCALE;

export const MOVE_SEND_INTERVAL_MS = 50; // 20 times/sec
export const REMOTE_LERP = 0.2;
// Rotation snapping reads as more jarring than position snapping at the same
// factor, so remote facing gets its own (higher) lerp constant.
export const ROTATION_LERP = 0.25;

export const ACTION_RANGE = 60 * WORLD_SCALE;
export const ROUND_TIME_DEFAULT = 300;

// 3D rendering constants (world-unit scale, same units as WORLD_WIDTH/HEIGHT).
export const WALL_HEIGHT = 140; // tall enough to fully occlude camera/character
export const FLOOR_HEIGHT = 4; // thin slab, purely visual
export const DOOR_MAT_HEIGHT = 1; // flat mat, sits just above the floor slab
export const DOOR_HEIGHT = 105; // top of a door opening; lintel fills up to WALL_HEIGHT
export const DOOR_JAMB = 12; // how far the frame trim extends past each side of an opening

// The Blender character rig (assets/blender/build_character.py) is ~1.85
// "Blender units" tall; scaled up so its ~0.84-unit arm span roughly matches
// CharacterController's 40-unit (2x radius) collision circle.
export const CHARACTER_SCALE = 45;

// 3rd-person chase camera (see three/CameraRig.ts).
export const FOLLOW_DISTANCE = 260; // behind the character, world units
export const FOLLOW_HEIGHT = 160; // above LOOK_HEIGHT
export const LOOK_HEIGHT = 55; // roughly chest height on the scaled character
export const MOUSE_SENSITIVITY = 0.003; // radians of camera yaw per pixel of mouse movement

// The Blender cash bundle prop (assets/blender/build_cashbundle.py) is ~0.3
// Blender units wide; scaled up to read clearly next to the character.
export const BUNDLE_SCALE = 130;

// House/garden props (client/src/three/world/) - same "1 Blender unit ~= 1
// meter" convention as the character/bundle rigs, scaled up to world units.
export const PROP_SCALE = 45;

// Phase 3 roof slabs (client/src/three/world/RoofSystem.ts).
export const ROOF_BASE = WALL_HEIGHT; // roofs sit right on top of the walls
export const ROOF_THICKNESS = 8;
export const ROOF_FADE_SPEED = 4; // opacity units/sec, clamped lerp toward the target

// Window openings (client/src/three/world/WindowBuilder.ts), three-y units,
// NOT scaled by WORLD_SCALE (heights never are - see floorplan.ts's header).
export const WINDOW_SILL = 45;
export const WINDOW_HEAD = 100;

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
  doorFrame: 0x7a5230, // wooden lintel + jamb trim around every opening
  doorPanel: 0x5c3d24, // closed-door fill for the local team's own sealed doors
  ground: 0x37452e, // lawn plane surrounding the whole map (replaces black void)
  teamB: 0xe85d24,
  teamA: 0x185fa5,
  cash: 0xffd700,
  wall: 0x8a8075, // warm plaster instead of near-black, so interiors read as rooms
  void: 0x0d1926,
  roof: 0x9c5340,
  glass: 0xa8d8f0,
};
