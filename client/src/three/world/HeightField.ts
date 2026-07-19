// Single source of truth for CLIENT-ONLY elevation. The server and the
// network model stay purely 2D (ground x/y, no height field of any kind) -
// every function here is a pure function of (x, z) ground position, so no
// amount of camera/prop/wall code calling into it can ever create a
// rule/network/bot-visible effect. Deliberately three.js-agnostic (like
// geometry/floorplan.ts), so it can be unit-tested or reused by a non-Three
// renderer without dragging in THREE.
//
// Each house becomes a split-level: the master bedroom wing rises one story
// (+FLOOR_RISE), the basement sinks one story (-FLOOR_RISE), and the living
// room stays at grade (0). The two houses mirror each other, so the two
// elevation tables below are literal mirrors by construction (see each
// corridor's provenance comment).
import { STORY_HEIGHT, WORLD_SCALE, WALL_HEIGHT } from "../../constants";
import { getZoneAt, type ZoneId, type Rect } from "../../geometry/floorplan";

const S = WORLD_SCALE;

// ---- per-zone story level ----
//
// Each zone lives on a STORY LEVEL and its floor sits at level * STORY_HEIGHT.
// This is the single knob for vertical layout: the master bedroom is one story
// up (+1), the basement one story down (-1), everything else at grade (0). To
// add rooms ON TOP later, give the new zones a higher level here (e.g. +2) and
// a ZONE_RECT - all vertical geometry (walls, ceilings, roofs, stairs, the
// camera cap) is derived from the level, so no other height math changes.
function zoneLevel(zone: ZoneId): number {
  if (zone === "bedroomB" || zone === "bedroomA") return 1;
  if (zone === "basementB" || zone === "basementA") return -1;
  return 0;
}

export function zoneBaseHeight(zone: ZoneId): number {
  return zoneLevel(zone) * STORY_HEIGHT;
}

// The Y a roofed zone's CEILING/roof plane sits at - the single source both
// RoofSystem (where it draws the slab) and CameraRig (where it caps the
// indoor camera) derive from, so they can never drift apart. A raised
// bedroom's ceiling rides up with its floor, but a SUNKEN basement's ceiling
// stays at grade+WALL_HEIGHT - level with the living room and, crucially,
// with the exterior walls around the pit. Rooting the basement roof at its
// own floor instead (-FLOOR_RISE + WALL_HEIGHT = grade) left it at the bottom
// of an open-topped well: from the garden you looked over the +WALL_HEIGHT
// exterior wall straight down into the basement interior. max(base,0) caps
// the pit at the top instead.
export function ceilingHeight(zone: ZoneId): number {
  return Math.max(zoneBaseHeight(zone), 0) + WALL_HEIGHT;
}

// ---- stair corridors ----
//
// A stair corridor is the 3D "ramp volume" occupying a door gap that connects
// two zones of different heights: `heightAt` smoothstep-interpolates across
// it instead of stepping instantly, so a character walking through visibly
// climbs/descends. Every number below is copied from geometry/floorplan.ts's
// DOORS table (pre-scale, i.e. the original 1600x900 layout) - NOT edited
// there, just re-derived here for the height field. Only the doors marked
// `sealedFor` in DOORS are stair doors (the owning team's own bedroom/
// basement doors); every other door (living<->garden, living<->backyard)
// connects two zones at the same height and is intentionally left out - it's
// flat, not a stair.
//
// `axis` is the traversal direction (crossing through the door - the
// direction you walk to go up/down); the corridor extends RAMP_EXTENT
// pre-scale units on each side of the door line along that axis. `cross` is
// the perpendicular span, bounded by the gap's own width (not extended) so
// the ramp never bleeds into the solid wall beside the door.
// Pre-scale units, each side of the door line. Widened (was 70) so the ramp
// run keeps pace with the taller STORY_HEIGHT rise - a full story over too
// short a run reads as a near-vertical ladder; this keeps the slope walkable.
// Still comfortably inside the adjacent rooms: 100 either side of a door line
// stays within the ~200-deep bedroom and the longer living/basement rooms.
const RAMP_EXTENT = 100;

export type Axis = "x" | "z";

export interface StairCorridor {
  axis: Axis;
  // Bounds along `axis` (the travel direction), scaled world units.
  axisMin: number;
  axisMax: number;
  // Bounds along the cross axis, scaled world units.
  crossMin: number;
  crossMax: number;
  // Ground height at axisMin and axisMax respectively, three-y units.
  heightAtMin: number;
  heightAtMax: number;
}

// x1/x2 give the pre-scale door-line center used to build axisMin/axisMax;
// crossA/crossB give the pre-scale gap span used as-is (already a range, not
// extended).
function corridor(
  axis: Axis,
  doorLine: number,
  crossA: number,
  crossB: number,
  heightAtMin: number,
  heightAtMax: number
): StairCorridor {
  return {
    axis,
    axisMin: (doorLine - RAMP_EXTENT) * S,
    axisMax: (doorLine + RAMP_EXTENT) * S,
    crossMin: crossA * S,
    crossMax: crossB * S,
    heightAtMin,
    heightAtMax,
  };
}

// Stair corridors span exactly one story between grade and a raised/sunken
// zone, so the ramp's endpoint height is one STORY_HEIGHT.
const RISE = STORY_HEIGHT;

export const STAIR_CORRIDORS: StairCorridor[] = [
  // ---- house B ----
  // bedroom B <-> living B (DOORS: {x1:300,y1:193,x2:380,y2:207}, y=200 line).
  // Traveling along y/z: y<200 is bedroomB (+RISE), y>200 is livingB (0).
  corridor("z", 200, 300, 380, RISE, 0),
  // living B <-> basement B (DOORS: {x1:300,y1:613,x2:380,y2:627}, y=620 line).
  // y<620 is livingB (0), y>620 is basementB (-RISE).
  corridor("z", 620, 300, 380, 0, -RISE),
  // bedroom B <-> backyard B (DOORS: {x1:133,y1:60,x2:147,y2:140}, x=140 line).
  // Traveling along x: x<140 is backyardB (0), x>140 is bedroomB (+RISE).
  corridor("x", 140, 60, 140, 0, RISE),
  // basement B <-> backyard B (DOORS: {x1:133,y1:700,x2:147,y2:780}, x=140 line).
  // x<140 is backyardB (0), x>140 is basementB (-RISE).
  corridor("x", 140, 700, 780, 0, -RISE),

  // ---- house A (mirror: x' = 1600 - x, y unchanged) ----
  // bedroom A <-> living A (DOORS: {x1:1220,y1:193,x2:1300,y2:207}, y=200 line).
  corridor("z", 200, 1220, 1300, RISE, 0),
  // living A <-> basement A (DOORS: {x1:1220,y1:613,x2:1300,y2:627}, y=620 line).
  corridor("z", 620, 1220, 1300, 0, -RISE),
  // bedroom A <-> backyard A (DOORS: {x1:1453,y1:60,x2:1467,y2:140}, x=1460 line).
  // Traveling along x: x<1460 is bedroomA (+RISE), x>1460 is backyardA (0).
  corridor("x", 1460, 60, 140, RISE, 0),
  // basement A <-> backyard A (DOORS: {x1:1453,y1:700,x2:1467,y2:780}, x=1460 line).
  corridor("x", 1460, 700, 780, -RISE, 0),
];

// The corridor's full 2D ground-plane footprint, as a Rect - used by
// EnvironmentBuilder to carve the stairwell opening out of a raised
// bedroom's solid foundation fill (the ramp has to stay open, not buried).
export function corridorBBox(c: StairCorridor): Rect {
  return c.axis === "x"
    ? { x1: c.axisMin, x2: c.axisMax, y1: c.crossMin, y2: c.crossMax }
    : { x1: c.crossMin, x2: c.crossMax, y1: c.axisMin, y2: c.axisMax };
}

function clamp01(t: number): number {
  return Math.max(0, Math.min(1, t));
}

function smoothstep(t: number): number {
  const c = clamp01(t);
  return c * c * (3 - 2 * c);
}

function corridorHeight(c: StairCorridor, x: number, z: number): number {
  const along = c.axis === "x" ? x : z;
  const t = smoothstep((along - c.axisMin) / (c.axisMax - c.axisMin));
  return c.heightAtMin + (c.heightAtMax - c.heightAtMin) * t;
}

function inCorridor(c: StairCorridor, x: number, z: number): boolean {
  const along = c.axis === "x" ? x : z;
  const cross = c.axis === "x" ? z : x;
  return along >= c.axisMin && along <= c.axisMax && cross >= c.crossMin && cross <= c.crossMax;
}

// (x, z): scaled world coords (three-space; z is floorplan's "y"). Returns
// the three-y ground height a character/prop standing there should sit at.
export function heightAt(x: number, z: number): number {
  for (const c of STAIR_CORRIDORS) {
    if (inCorridor(c, x, z)) return corridorHeight(c, x, z);
  }
  return zoneBaseHeight(getZoneAt(x, z));
}

// ---- wall-adjacency helper (EnvironmentBuilder/WindowBuilder) ----
//
// Splits a wall rect into height-uniform run segments by sampling heightAt
// just off both faces - no hand-authored table of "which wall is next to
// which raised/sunk room": a wall rect only ever needs splitting where the
// ground height actually changes along its run (a house's row/column
// boundary, or a corridor's cross-range edge), and SAMPLE_STEP is fine enough
// to land on every such boundary in this floor plan. Each segment reports the
// lowest and highest of its two face heights, so the caller can extrude a box
// from `low` to `high + WALL_HEIGHT` - low enough to root a sunken basement's
// retaining wall in the pit floor, high enough to close the gap above a
// raised bedroom's foundation.
const SAMPLE_STEP = 10; // scaled units
const FACE_EPS = 4; // scaled units, just off the wall's own thickness

export interface WallSpanSegment {
  rect: Rect;
  low: number;
  high: number;
}

function probeSpan(vertical: boolean, faceLow: number, faceHigh: number, run: number): { low: number; high: number } {
  const hA = vertical ? heightAt(faceLow, run) : heightAt(run, faceLow);
  const hB = vertical ? heightAt(faceHigh, run) : heightAt(run, faceHigh);
  return { low: Math.min(hA, hB), high: Math.max(hA, hB) };
}

export function wallSegments(r: Rect): WallSpanSegment[] {
  const vertical = r.x2 - r.x1 < r.y2 - r.y1;
  const runMin = vertical ? r.y1 : r.x1;
  const runMax = vertical ? r.y2 : r.x2;
  const faceLow = vertical ? r.x1 - FACE_EPS : r.y1 - FACE_EPS;
  const faceHigh = vertical ? r.x2 + FACE_EPS : r.y2 + FACE_EPS;

  const makeRect = (start: number, end: number): Rect =>
    vertical ? { x1: r.x1, x2: r.x2, y1: start, y2: end } : { x1: start, x2: end, y1: r.y1, y2: r.y2 };

  const segments: WallSpanSegment[] = [];
  let segStart = runMin;
  let current = probeSpan(vertical, faceLow, faceHigh, Math.min(runMin + 0.5, runMax));

  for (let s = runMin + SAMPLE_STEP; s < runMax; s += SAMPLE_STEP) {
    const sample = probeSpan(vertical, faceLow, faceHigh, s);
    if (Math.abs(sample.low - current.low) > 0.01 || Math.abs(sample.high - current.high) > 0.01) {
      segments.push({ rect: makeRect(segStart, s), low: current.low, high: current.high });
      segStart = s;
      current = sample;
    }
  }
  segments.push({ rect: makeRect(segStart, runMax), low: current.low, high: current.high });
  return segments;
}
