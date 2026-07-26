import * as THREE from "three";
import { COLORS, teamSideAt, STORY_HEIGHT, SURFACE_OVERLAP } from "../../constants";
import { CONNECTORS, type Connector, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";

// Renders each floor CONNECTOR as what it actually is: a `stair` is a run of
// "wedding cake" step boxes rising from the lower floor to the higher one, and
// a `ladder` is a real timber ladder - two side rails with rungs between them,
// leaning up the same slope. Both follow the same smoothstep curve
// HeightField.visualHeight eases a walking body through, so treads and rungs
// track the climber's feet either way.
//
// The backyard routes up to the balconies are ladders, and now read as ladders
// instead of a second flight of stairs; the interior staircase and the cellar
// steps stay stairs.
const STEP_COUNT = 12;
const RUNG_COUNT = 9;
const BOTTOM_MARGIN = 40; // world units below the lower floor, so no step floats
const RAIL_WIDTH = 7; // timber thickness of a ladder's side rails
const RUNG_THICKNESS = 5;

function smoothstep(t: number): number {
  const c = Math.max(0, Math.min(1, t));
  return c * c * (3 - 2 * c);
}

// Treads/rungs are drawn `visualPad` wider than the walkable rect on each side,
// so a flight sunk into a pit meets its retaining walls instead of leaving a
// slot of sky beside it. Purely visual - collision and floor flipping use
// c.rect.
function crossRange(c: Connector): { lo: number; hi: number } {
  const pad = c.visualPad ?? 0;
  return c.axis === "x"
    ? { lo: c.rect.y1 - pad, hi: c.rect.y2 + pad }
    : { lo: c.rect.x1 - pad, hi: c.rect.x2 + pad };
}

// Build a rect from a span along the connector's axis and one across it.
function spanRect(c: Connector, axisStart: number, axisEnd: number, crossLo: number, crossHi: number): Rect {
  return c.axis === "x"
    ? { x1: axisStart, x2: axisEnd, y1: crossLo, y2: crossHi }
    : { x1: crossLo, x2: crossHi, y1: axisStart, y2: axisEnd };
}

interface Run {
  axisStart: number;
  axisEnd: number;
  loY: number;
  hiY: number;
  color: number;
}

function runOf(c: Connector): Run {
  return {
    axisStart: c.axis === "x" ? c.rect.x1 : c.rect.y1,
    axisEnd: c.axis === "x" ? c.rect.x2 : c.rect.y2,
    loY: c.floorLow * STORY_HEIGHT,
    hiY: c.floorHigh * STORY_HEIGHT,
    color: teamSideAt((c.rect.x1 + c.rect.x2) / 2) === "B" ? COLORS.stairsB : COLORS.stairsA,
  };
}

// Height of the walking surface a fraction `t` along the run - the same curve
// HeightField eases a body through, lifted by a hair.
//
// That lift is the fix for the flicker at the ends of every flight. A run
// starts and finishes exactly at a floor level, so its first and last treads
// used to be perfectly coplanar with the slab they sit on - two upward-facing
// surfaces at the same depth, overlapping, which the depth buffer resolves
// differently from frame to frame as the camera moves. Raising the drawn
// surface by SURFACE_OVERLAP makes the tread win cleanly. It reads as a stair
// nosing, and the climber's feet are unaffected: they follow HeightField.
function surfaceY(run: Run, t: number): number {
  return run.loY + (run.hiY - run.loY) * smoothstep(t) + SURFACE_OVERLAP;
}

function buildSteps(c: Connector): THREE.BufferGeometry[] {
  const run = runOf(c);
  const { lo, hi } = crossRange(c);
  const span = run.axisEnd - run.axisStart;
  const dw = span / STEP_COUNT;
  const bottomY = Math.min(run.loY, run.hiY) - BOTTOM_MARGIN;

  const geoms: THREE.BufferGeometry[] = [];
  for (let i = 0; i < STEP_COUNT; i++) {
    // Steps are BUTTED, not overlapped. Two neighbouring risers meet on one
    // plane but face opposite ways, so only ever one of them is rasterised;
    // overlapping them instead would put their (same-facing) side walls on a
    // shared plane and stripe the flight with shimmer down both edges.
    const a0 = run.axisStart + i * dw;
    const a1 = run.axisStart + (i + 1) * dw;
    const treadY = surfaceY(run, (i + 1) / STEP_COUNT);
    const height = treadY - bottomY;
    if (height <= 0) continue;
    geoms.push(rectToBox(spanRect(c, a0, a1, lo, hi), height, bottomY + height / 2, run.color));
  }
  return geoms;
}

// A leaning timber ladder: two rails running the length of the slope with rungs
// bridging them. Both are built from short segments tracking the same surface
// curve, so the rungs stay under the climber's feet the whole way up.
function buildLadder(c: Connector): THREE.BufferGeometry[] {
  const run = runOf(c);
  const { lo, hi } = crossRange(c);
  const span = run.axisEnd - run.axisStart;
  const geoms: THREE.BufferGeometry[] = [];

  // Rails, segmented so they follow the slope. Butted, for the same reason the
  // steps are.
  const railSegments = RUNG_COUNT * 2;
  for (const side of [lo, hi - RAIL_WIDTH]) {
    for (let i = 0; i < railSegments; i++) {
      const t0 = i / railSegments;
      const t1 = (i + 1) / railSegments;
      const a0 = run.axisStart + t0 * span;
      const a1 = run.axisStart + t1 * span;
      const yMid = (surfaceY(run, t0) + surfaceY(run, t1)) / 2;
      // Rails stand proud of the climbing surface, like real ones - low enough
      // to step over from the balcony, high enough to read as a ladder.
      const rect = spanRect(c, a0, a1, side, side + RAIL_WIDTH);
      geoms.push(rectToBox(rect, RAIL_WIDTH * 2, yMid + RAIL_WIDTH, COLORS.ladderRail));
    }
  }

  // Rungs bridge BETWEEN the rails rather than running their full width, so
  // their ends are buried inside the rails instead of sharing a face with them.
  for (let i = 0; i < RUNG_COUNT; i++) {
    const t = (i + 0.5) / RUNG_COUNT;
    const a = run.axisStart + t * span;
    const rect = spanRect(c, a - RUNG_THICKNESS, a + RUNG_THICKNESS, lo + RAIL_WIDTH / 2, hi - RAIL_WIDTH / 2);
    geoms.push(rectToBox(rect, RUNG_THICKNESS, surfaceY(run, t), COLORS.ladderRung));
  }
  return geoms;
}

// Merged connector geometry for every connector - folded into the floor mesh.
export function buildStaircaseGeoms(): THREE.BufferGeometry[] {
  return CONNECTORS.flatMap((c) => (c.kind === "ladder" ? buildLadder(c) : buildSteps(c)));
}
