// Central tunables for the whole client. The floor plan itself is defined once
// in shared/worldGeometry.ts and re-exported by geometry/floorplan.ts.
//
// WORLD_SCALE scales the entire floor plan - and, with it, speeds and action
// ranges, so travel times and gameplay balance stay put at any map size. The
// CHARACTER, PROPS and the chase camera deliberately do NOT scale: they are
// authored at true human proportion (character ~83 units tall, a bed ~90 long),
// so raising WORLD_SCALE simply gives the player more room to move without
// making the furniture look like toys.
// Map scale + dimensions come from the shared geometry module, so the client
// cannot drift out of step with the authoritative server.
export { WORLD_SCALE, MAP_DEPTH_SCALE, WORLD_WIDTH, WORLD_HEIGHT } from "../../shared/worldGeometry";
import { WORLD_SCALE, WORLD_WIDTH } from "../../shared/worldGeometry";

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
//
// STORY_HEIGHT is the ONE vertical unit the building derives from: a room's
// floor-to-ceiling height AND the rise between stacked floors. Heights never
// scale with WORLD_SCALE - they are fixed against the character. Everything
// vertical (walls, ceilings, roofs, stair rises, the camera's indoor cap)
// derives from this, so adding a floor needs no new height math.
// 210 ~= 2.5x the character's ~83-unit height (a believable room, not a hangar).
// The chase camera below is sized to sit UNDER this without the indoor clamp
// fighting it: the camera rides LOOK_HEIGHT + 95 = 140 above ground, clear of
// the 210 ceiling minus CameraRig's margin.
export const STORY_HEIGHT = 210;
export const WALL_HEIGHT = STORY_HEIGHT; // room floor-to-ceiling
export const FLOOR_HEIGHT = 4; // thin slab, purely visual
export const DOOR_MAT_HEIGHT = 1; // flat mat, sits just above the floor slab
export const DOOR_HEIGHT = 130; // top of a door opening (~1.6x character height); lintel fills up to WALL_HEIGHT
export const DOOR_JAMB = 12; // how far the frame trim extends past each side of an opening

// Rise between adjacent floors - EQUAL to STORY_HEIGHT by design, so a stacked
// floor's slab sits exactly on the ceiling line of the one below it.
export const FLOOR_RISE = STORY_HEIGHT;

// The Blender character rig (assets/blender/build_character.py) is ~1.85
// "Blender units" tall; scaled up so its ~0.84-unit arm span roughly matches
// CharacterController's 40-unit (2x radius) collision circle.
export const CHARACTER_SCALE = 45;

// 3rd-person chase camera (see three/CameraRig.ts).
// Spherical orbit radius around the look-at point. Sized to the real room: the
// rig sits 200 behind and 95 above the look point, so the camera rides 140
// above ground - comfortably under the ceiling, meaning the indoor clamp almost
// never fires during normal play.
export const FOLLOW_DISTANCE = Math.hypot(200, 95); // ~221.4
export const LOOK_HEIGHT = 45; // roughly chest height on the character
// Default camera elevation (pitch, radians): the atan2(vertical, horizontal)
// angle the offset above implies, so dir(DEFAULT_PITCH) * FOLLOW_DISTANCE lands
// exactly 200 behind and 95 up.
export const DEFAULT_PITCH = Math.atan2(95, 200); // ~0.44 rad
export const MOUSE_SENSITIVITY = 0.003; // radians of camera yaw per pixel of mouse movement

// The Blender cash bundle prop (assets/blender/build_cashbundle.py) is ~0.3
// Blender units wide; scaled up to read clearly next to the character.
export const BUNDLE_SCALE = 130;

// House/garden props (client/src/three/world/) - same "1 Blender unit ~= 1
// meter" convention as the character/bundle rigs, scaled up to world units.
export const PROP_SCALE = 45;

// Roof trim thickness (client/src/three/world/RoofSystem.ts). Roofs are always
// fully opaque: CameraRig's indoor Y clamp keeps the camera under the ceiling.
export const ROOF_THICKNESS = 8;

// Window openings (client/src/three/world/WindowBuilder.ts). Heights, so never
// scaled by WORLD_SCALE - sized against the character like everything vertical.
export const WINDOW_SILL = 55;
export const WINDOW_HEAD = 135;

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
