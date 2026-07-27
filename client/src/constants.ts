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

// ONE speed for every character in every state. Carrying cash used to cut it to
// 160, which testers read as the game breaking rather than as a trade-off, so
// the penalty is gone and the base is a little quicker than it was.
export const MOVE_SPEED = 250 * WORLD_SCALE;

export const MOVE_SEND_INTERVAL_MS = 50; // 20 times/sec
export const REMOTE_LERP = 0.2;
// Rotation snapping reads as more jarring than position snapping at the same
// factor, so remote facing gets its own (higher) lerp constant.
export const ROTATION_LERP = 0.25;

// ---- character motion feel ----
// Velocity is eased toward the input direction instead of snapping to it, which
// is what gave movement its "unfinished" feel: instant full speed and instant
// dead stops read as a placeholder, and drove the walk animation as a binary
// on/off. Rates are exponential-approach per second, so the feel is identical at
// any frame rate. Tuned snappy (~0.1s to full tilt) - this is a party game, not
// a sim - but with enough ramp to give the character weight.
export const MOVE_ACCEL_RATE = 18;
export const MOVE_STOP_RATE = 22;
// Falling. Stepping off a balcony used to teleport you down a whole storey;
// now you fall. Tuned against STORY_HEIGHT so a one-floor drop takes ~0.35s.
export const GRAVITY = 3400;
// Rising ground (stairs, ramps) is eased rather than simulated - you walk UP
// stairs, you don't get launched by them.
export const STEP_UP_RATE = 16;
// Landing softer than this doesn't register as an impact (no thud, no shake).
export const LANDING_IMPACT_MIN = 260;

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

// Two coplanar surfaces (a tread stopping exactly on a wall face, a door mat
// flush with its slab, a wall top level with the floor above) tie in the depth
// buffer, and the tie is broken differently every frame as the camera moves -
// which is the shimmering the world used to show at every joint. The fix is
// always the same: overlap the surfaces by this much instead of abutting them,
// so the buried face is genuinely inside solid geometry and never rasterised.
// Small enough to be invisible; large enough to beat depth precision.
export const SURFACE_OVERLAP = 0.6;

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

// House/garden props - same "1 Blender unit ~= 1 metre" convention as the
// character/bundle rigs. Defined in shared/props.ts because the props are solid
// now, so the server needs the same number to derive their colliders.
export { PROP_SCALE } from "../../shared/props";

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

// ---- ART DIRECTION -------------------------------------------------------
//
// The old palette was flat cartoon primaries lit by a single lamp, which is why
// the game read as a blocky toy. This one is built as a real scheme instead:
// a narrow, slightly desaturated range of warm neutrals for the ARCHITECTURE,
// so the eye reads form and light rather than colour; and a small set of
// saturated ACCENTS reserved for the things the player must find instantly -
// the two families, the cash, the doors. Nothing else is allowed to shout.
//
// Values are authored as linear-ish sRGB and pass through ACES tone mapping,
// so they arrive on screen a little softer and darker than they look here.

export const COLORS = {
  // --- team accents. Everything a family owns wears one of these.
  teamB: 0xff6b35, // ember orange
  teamA: 0x2e86de, // signal blue

  // --- architecture: warm plaster and timber, low saturation on purpose.
  wall: 0xc4ac8c, // sunlit plaster - warm enough to survive a cool sky fill
  wallShade: 0x8f7c62, // the underside of a lintel/soffit - reads as a real shadow
  foundation: 0x6d5f4c,

  // --- floors, one per room so a glance tells you where you are.
  livingB: 0xcf9048, // warm oak
  livingA: 0x6e94b5, // cool slate
  bedroom: 0xe8865a, // terracotta - same in both houses: "this room = cash"
  basement: 0x5c5f63, // poured concrete
  ceilingB: 0xb8875c,
  ceilingA: 0x577693,

  // --- outdoors.
  garden: 0x86b054,
  gardenAlt: 0x79a248,
  backyard: 0x729a45,
  ground: 0x3f5233,
  roofB: 0xb0442a,
  roofA: 0x2f5570,

  // --- accents, used sparingly.
  cash: 0xffc93c,
  door: 0xe8c86a,
  doorFrameB: 0x8a4a2b,
  doorFrameA: 0x2f5a7a,
  glass: 0xbfe3f5,
  stairsB: 0xff6b35,
  stairsA: 0x2e86de,
  stairTrimB: 0x8f3413,
  stairTrimA: 0x0d3a6b,
  ladderRail: 0xb0793d,
  ladderRung: 0x8d5a26,
};

// Sky gradient + the sun disc smear (three/world/SkyDome.ts). Also feeds the
// environment map and the hemisphere fill, so changing these re-lights the
// entire world in one edit.
export const SKY = {
  top: 0x3f7fc4, // zenith
  horizon: 0xbcd3e4, // haze band
  ground: 0xa8895f, // what the world bounces back up - warm, so interiors are not grey
  sun: 0xfff2cf,
};

// The light rig. Ratios matter more than absolutes: a ~4:1 key-to-fill is what
// gives shape, and the rim is deliberately low - just enough to draw an edge.
export const LIGHTING = {
  sunDirection: [0.55, 0.72, 0.42] as [number, number, number],
  sunColor: 0xfff4e2,
  sunIntensity: 2.15,
  fillIntensity: 1.15,
  // The hemisphere fill has its OWN colours rather than reusing the sky's. A
  // hemisphere light is an outdoor approximation: it puts sky colour on every
  // up-facing surface, which indoors means a saturated blue wash across every
  // floor - and blue over a warm oak albedo lands on olive. Indoors the light
  // arriving on a floor has bounced off warm walls, so the fill is warm and the
  // blue is left to the environment map, which at least varies with direction.
  fillSky: 0xf2e4cf,
  fillGround: 0xb08d5c,
  rimColor: 0xbcd8ff,
  rimIntensity: 0.55,
  environmentIntensity: 0.62,
  exposure: 1.02,
  shadowMapSize: 4096,
  shadowSoftness: 2.5,
};

// How many world units one repeat of each surface texture covers. This is the
// SIZE CUE: a floorboard is ~20 units wide against an 83-unit character, which
// is what tells the eye how big a room is. Getting these wrong is what makes a
// textured world look like a scale model.
export const TILE = {
  plaster: 95,
  floorboards: 150,
  concrete: 210,
  turf: 130,
  painted: 70,
};

// Post-processing. Bloom is kept on the highlights only - a low threshold
// smears the whole image and reads as fog on the lens rather than as light.
export const POST = {
  bloomStrength: 0.34,
  bloomRadius: 0.7,
  bloomThreshold: 0.82,
  fogNear: 0.85,
  fogFar: 2.1,
  // Ambient occlusion. The radius is in WORLD units, so it is sized against the
  // room (a ~200-unit storey), not against the screen.
  aoRadius: 26,
  aoMinDistance: 0.002,
  aoMaxDistance: 0.12,
};
