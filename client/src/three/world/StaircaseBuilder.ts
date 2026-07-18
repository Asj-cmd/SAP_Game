import * as THREE from "three";
import { COLORS, teamSideAt, WALL_HEIGHT, WORLD_SCALE } from "../../constants";
import { getZoneAt, type Rect } from "../../geometry/floorplan";
import { STAIR_CORRIDORS, zoneBaseHeight, type StairCorridor } from "./HeightField";
import { rectToBox } from "../EnvironmentBuilder";

// Renders each stair corridor (HeightField.STAIR_CORRIDORS) as a run of solid
// "wedding cake" step boxes: box i's top face sits at the smoothstepped ramp
// height evaluated at that step's leading edge (matching heightAt's own
// curve, so the rendered treads visually track the height a walking
// character is actually eased through), and every box's bottom reaches well
// below the lower of the corridor's two endpoint heights, so there's never a
// gap or floating box regardless of which step you look under.
const STEP_COUNT = 11; // "~10-12 merged step boxes" per the brief
const BOTTOM_MARGIN = 30; // scaled units below the lower endpoint height

function clamp01(t: number): number {
  return Math.max(0, Math.min(1, t));
}

function smoothstep(t: number): number {
  const c = clamp01(t);
  return c * c * (3 - 2 * c);
}

function stepRect(c: StairCorridor, axisStart: number, axisEnd: number): Rect {
  return c.axis === "x"
    ? { x1: axisStart, x2: axisEnd, y1: c.crossMin, y2: c.crossMax }
    : { x1: c.crossMin, x2: c.crossMax, y1: axisStart, y2: axisEnd };
}

function buildCorridorSteps(c: StairCorridor): THREE.BufferGeometry[] {
  const span = c.axisMax - c.axisMin;
  const dw = span / STEP_COUNT;
  const bottomY = Math.min(c.heightAtMin, c.heightAtMax) - BOTTOM_MARGIN;

  const geoms: THREE.BufferGeometry[] = [];
  for (let i = 0; i < STEP_COUNT; i++) {
    const axisStart = c.axisMin + i * dw;
    const axisEnd = c.axisMin + (i + 1) * dw;
    const t = smoothstep((i + 1) / STEP_COUNT);
    const treadY = c.heightAtMin + (c.heightAtMax - c.heightAtMin) * t;
    const height = treadY - bottomY;
    if (height <= 0) continue;
    const rect = stepRect(c, axisStart, axisEnd);
    // Treads pick up the owning house's tint (warm wood in B, cool stone-blue
    // in A) - stair corridors only exist inside houses, so the rect's center
    // is always cleanly on one side.
    const color = teamSideAt((rect.x1 + rect.x2) / 2) === "B" ? COLORS.stairsB : COLORS.stairsA;
    geoms.push(rectToBox(rect, height, bottomY + height / 2, color));
  }
  return geoms;
}

// Merged geometry for every stair corridor in the map - callers fold this
// into an existing vertex-colored mesh (the floor mesh) rather than adding a
// new draw call.
export function buildStaircaseGeoms(): THREE.BufferGeometry[] {
  return STAIR_CORRIDORS.flatMap((c) => buildCorridorSteps(c));
}

// ---- stairwell side walls ----
//
// The walls flanking each ramp live HERE, not in the generic
// buildWallBoxes/wallSegments pipeline: that pipeline assumes two FLAT
// adjacent floors and bottoms every run at min(faceA, faceB), which can't
// hug a sloping ramp - its independently-sampled bottom diverged from the
// treads' quantized surface, leaving wedge gaps. Each wall box below instead
// reuses the EXACT per-step treadY and axis span from buildCorridorSteps, so
// the wall's bottom edge and the tread surface are the same curve by
// construction - then drops to the adjacent room's floor wherever that's
// lower (so the wall roots on the ground instead of floating), and rises to
// one fixed ceiling: WALL_HEIGHT above the corridor's higher end.
const SIDE_WALL_THICKNESS = 5 * WORLD_SCALE; // half a normal wall - a shaft liner, not a bearing wall
// Inner face tucks this far INSIDE the corridor: tread ends, door jambs, and
// abutting room-wall ends all terminate exactly on the crossMin/crossMax
// lines, so a flush face would z-fight with all of them.
const SIDE_WALL_INSET = 2;

// Both cross-spans of a corridor's side walls: [outer edge, inner face].
function sideSpans(c: StairCorridor): [number, number][] {
  return [
    [c.crossMin - SIDE_WALL_THICKNESS, c.crossMin + SIDE_WALL_INSET],
    [c.crossMax - SIDE_WALL_INSET, c.crossMax + SIDE_WALL_THICKNESS],
  ];
}

function spanRect(c: StairCorridor, axisStart: number, axisEnd: number, span: [number, number]): Rect {
  return c.axis === "x"
    ? { x1: axisStart, x2: axisEnd, y1: span[0], y2: span[1] }
    : { x1: span[0], x2: span[1], y1: axisStart, y2: axisEnd };
}

function buildCorridorSideWalls(c: StairCorridor): THREE.BufferGeometry[] {
  const span = c.axisMax - c.axisMin;
  const dw = span / STEP_COUNT;
  const ceilingY = Math.max(c.heightAtMin, c.heightAtMax) + WALL_HEIGHT;

  const geoms: THREE.BufferGeometry[] = [];
  for (const side of sideSpans(c)) {
    // Ground-floor probe just outside the wall's outer face, so the wall
    // drops to the neighboring room's floor where the ramp is above it.
    const outerProbe = side[0] < (c.crossMin + c.crossMax) / 2 ? side[0] - 4 : side[1] + 4;
    for (let i = 0; i < STEP_COUNT; i++) {
      const axisStart = c.axisMin + i * dw;
      const axisEnd = c.axisMin + (i + 1) * dw;
      const t = smoothstep((i + 1) / STEP_COUNT); // same leading-edge sample as the tread below it
      const treadY = c.heightAtMin + (c.heightAtMax - c.heightAtMin) * t;
      const axisMid = (axisStart + axisEnd) / 2;
      const outsideFloor = zoneBaseHeight(
        c.axis === "x" ? getZoneAt(axisMid, outerProbe) : getZoneAt(outerProbe, axisMid)
      );
      const bottomY = Math.min(treadY, outsideFloor);
      geoms.push(rectToBox(spanRect(c, axisStart, axisEnd, side), ceilingY - bottomY, (bottomY + ceilingY) / 2, COLORS.wall));
    }
  }
  return geoms;
}

export function buildStairwellWallGeoms(): THREE.BufferGeometry[] {
  return STAIR_CORRIDORS.flatMap((c) => buildCorridorSideWalls(c));
}

// Full-length collider footprint of the two side walls per corridor - the
// only thing standing between the ramp and the pit/void beside it.
export function stairwellWallRects(): Rect[] {
  return STAIR_CORRIDORS.flatMap((c) => sideSpans(c).map((side) => spanRect(c, c.axisMin, c.axisMax, side)));
}
