// Top-down world (Brawl Stars style): a single flat plane, no gravity - see
// server/src/zones.ts + client/src/geometry/floorplan.ts for the floor plan this
// size matches (backyard | house | garden | house | backyard).
//
// WORLD_SCALE widens the whole floor plan relative to the original 2D layout
// (1600x900) without touching the character's size, so rooms feel like rooms
// instead of corridors. Speeds and action ranges scale with it, which keeps
// travel times and gameplay balance identical to the 2D-tuned values.
// server/src/zones.ts applies the same factor - keep both in sync.
// 2.0 (was 1.5): rooms felt cramped - the character barely cleared doors and
// the chase camera's wall avoidance pulled in tight indoors. At 2.0 the
// camera sits at full FOLLOW_DISTANCE inside a living room. Character, props,
// and vertical proportions deliberately do NOT scale with this.
export const WORLD_SCALE = 2.0;
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

// Split-level verticality (client/src/three/world/HeightField.ts): one full
// story of rise/sink for the bedroom wing (up) and basement (down). Equal to
// WALL_HEIGHT by design - a "story" is exactly one wall's height, so a
// character walking up the stairs into the raised bedroom clears the living
// room's ceiling line exactly as they arrive. Purely a client-side rendering
// height; the server/network model stays 2D (ground x/y only).
export const FLOOR_RISE = 140;

// The Blender character rig (assets/blender/build_character.py) is ~1.85
// "Blender units" tall; scaled up so its ~0.84-unit arm span roughly matches
// CharacterController's 40-unit (2x radius) collision circle.
export const CHARACTER_SCALE = 45;

// 3rd-person chase camera (see three/CameraRig.ts).
// Spherical orbit radius around the look-at point. The pre-pitch rig sat 260
// world units behind and 160 above the look-at point, so its TRUE distance
// was the hypotenuse (~305.3) - using that exact value (not the old 260
// horizontal component) keeps the untouched-mouse default view pixel-identical
// to the pre-pitch camera, not merely angle-identical.
export const FOLLOW_DISTANCE = Math.hypot(260, 160); // ~305.3
export const LOOK_HEIGHT = 55; // roughly chest height on the scaled character
// Default camera elevation (pitch, radians) above the horizontal: the same
// atan2(vertical, horizontal) angle the old fixed offset implied. Together
// with FOLLOW_DISTANCE above, dir(DEFAULT_PITCH) * FOLLOW_DISTANCE lands on
// exactly the old camera position (260 behind, 160 up).
export const DEFAULT_PITCH = Math.atan2(160, 260); // ~0.55 rad
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
// The roof over the room you're standing in fades to THIS, not to invisible:
// low enough that the chase camera (which sits above roof height and doesn't
// raycast against roofs) still shows the character clearly, high enough that
// every room always reads as having a ceiling instead of open sky.
// (0.25 read as tinted haze from below rather than a ceiling; 0.35 keeps the
// slab clearly present without meaningfully obscuring the top-down view.)
export const ROOF_REVEAL_OPACITY = 0.35;

// Window openings (client/src/three/world/WindowBuilder.ts), three-y units,
// NOT scaled by WORLD_SCALE (heights never are - see floorplan.ts's header).
export const WINDOW_SILL = 45;
export const WINDOW_HEAD = 100;

// Which family's half of the map a scaled world-x sits in - house B owns the
// west half, house A the east. Used to give each house's trim (roof, door and
// window frames, stair treads) a hint of its team's hue so a house reads as
// belonging to its family from a distance, without touching the gameplay
// palette semantics below.
export function teamSideAt(x: number): "A" | "B" {
  return x < WORLD_WIDTH / 2 ? "B" : "A";
}

// Palette conventions (do not break): bedroom stays a warm salmon/coral family
// on BOTH sides so "this room = cash" reads instantly; teamB and everything
// B-flavored leans orange, teamA leans blue; door/foundation/stairs stay
// mutually distinct. Deliberately vivid (Fall Guys / Overcooked energy, not
// pastel): ACES tone mapping compresses midtones, so pastels grey out - the
// palette has to arrive saturated for the render to leave it readable.
export const COLORS = {
  bedroom: 0xef8054, // cash rooms - vivid coral, same on both sides
  livingB: 0xe3a45c, // Team B's living room, saturated amber
  livingA: 0x6ea6d8, // Team A's living room, saturated steel blue
  garden: 0xa8d178,
  gardenAlt: 0x97c464,
  backyard: 0x8dbd5e, // grassier green than the garden - reads as private yard
  basement: 0x8d8b83,
  door: 0xe6c964, // door mats drawn in every passable wall gap
  doorFrameB: 0x9a5a28, // honey-oak trim, hinting team B's orange
  doorFrameA: 0x4d6280, // slate-blue walnut trim, hinting team A's blue
  doorPanel: 0x5c3d24, // closed-door fill for the local team's own sealed doors
  ground: 0x3b5231, // lawn plane surrounding the whole map (replaces black void)
  teamB: 0xe85d24,
  teamA: 0x185fa5,
  cash: 0xffd700,
  wall: 0x9b8a74, // warm plaster, richer than the old grey-beige
  void: 0x0d1926,
  roofB: 0xc2502a, // hot terracotta - house B's crown, visible across the map
  roofA: 0x33628f, // deep slate blue - house A's
  glass: 0xa8d8f0,
  stairsB: 0x9a7040, // warm wood treads (B house)
  stairsA: 0x5c6c85, // cool stone-blue treads (A house)
  foundation: 0x655c50, // darker than wall - the solid fill under a raised bedroom wing
};
