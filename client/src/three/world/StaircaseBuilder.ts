import * as THREE from "three";
import { COLORS, teamSideAt, STORY_HEIGHT } from "../../constants";
import { CONNECTORS, type Connector, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";

// Renders each floor CONNECTOR (staircase / ladder / cellar-steps) as a run of
// "wedding cake" step boxes rising from the lower floor to the higher one, so a
// character crossing it visibly climbs/descends. The step tops follow the same
// smoothstep curve HeightField.visualHeight eases a walking body through, so
// treads track the character's feet. Interior stairs and backyard ladders use
// the same builder - a ladder is just a steeper-looking run of the same steps.
const STEP_COUNT = 12;
const BOTTOM_MARGIN = 40; // world units below the lower floor, so no step floats

function smoothstep(t: number): number {
  const c = Math.max(0, Math.min(1, t));
  return c * c * (3 - 2 * c);
}

function stepRect(c: Connector, axisStart: number, axisEnd: number): Rect {
  return c.axis === "x"
    ? { x1: axisStart, x2: axisEnd, y1: c.rect.y1, y2: c.rect.y2 }
    : { x1: c.rect.x1, x2: c.rect.x2, y1: axisStart, y2: axisEnd };
}

function buildConnectorSteps(c: Connector): THREE.BufferGeometry[] {
  const axisStart = c.axis === "x" ? c.rect.x1 : c.rect.y1;
  const axisEnd = c.axis === "x" ? c.rect.x2 : c.rect.y2;
  const span = axisEnd - axisStart;
  const dw = span / STEP_COUNT;
  const loY = c.floorLow * STORY_HEIGHT;
  const hiY = c.floorHigh * STORY_HEIGHT;
  const bottomY = Math.min(loY, hiY) - BOTTOM_MARGIN;
  const color = teamSideAt((c.rect.x1 + c.rect.x2) / 2) === "B" ? COLORS.stairsB : COLORS.stairsA;

  const geoms: THREE.BufferGeometry[] = [];
  for (let i = 0; i < STEP_COUNT; i++) {
    const a0 = axisStart + i * dw;
    const a1 = axisStart + (i + 1) * dw;
    const t = smoothstep((i + 1) / STEP_COUNT);
    const treadY = loY + (hiY - loY) * t;
    const height = treadY - bottomY;
    if (height <= 0) continue;
    geoms.push(rectToBox(stepRect(c, a0, a1), height, bottomY + height / 2, color));
  }
  return geoms;
}

// Merged step geometry for every connector - folded into the floor mesh.
export function buildStaircaseGeoms(): THREE.BufferGeometry[] {
  return CONNECTORS.flatMap((c) => buildConnectorSteps(c));
}
