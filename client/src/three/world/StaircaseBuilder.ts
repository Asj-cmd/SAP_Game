import * as THREE from "three";
import { COLORS, teamSideAt } from "../../constants";
import type { Rect } from "../../geometry/floorplan";
import { STAIR_CORRIDORS, type StairCorridor } from "./HeightField";
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
