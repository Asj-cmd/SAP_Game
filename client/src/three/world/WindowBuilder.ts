import * as THREE from "three";
import { WINDOW_SILL, WINDOW_HEAD, COLORS, teamSideAt, WORLD_SCALE } from "../../constants";
import { WALLS, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";
import { floorY } from "./HeightField";

// Adds windows to the houses' exterior-facing SIDE walls so they read as homes,
// not blank boxes. Floor-aware: each window sits at WINDOW_SILL..WINDOW_HEAD
// above ITS wall's floor. Deliberately decorative (a glass pane + wooden frame
// proud of the wall, no punched opening) - simple and robust; see-through
// openings can come later. Frames merge into the walls mesh; glass panes are
// returned separately for their own translucent material.

// A wall qualifies if it's a vertical side wall (runs along z, thin in x) sitting
// on a house<->garden or house<->backyard boundary - the faces you see from the
// garden/yard during play. Basement walls (floor -1) are below grade, so skipped.
const BOUNDARY_XS = [240, 620, 980, 1360]; // pre-scale house side-wall lines
const BOUNDARY_EPS = 30; // scaled slack when matching a wall's centre x

const WINDOW_W = 95; // pane width along the wall (world units, unscaled like sills)
const WINDOW_GAP = 150; // min clear run between panes
const FRAME_BAND = 10;
const MIN_SEG = 200; // don't window a wall run shorter than this (scaled)

function isExteriorSideWall(w: Rect & { floor?: number }): boolean {
  if (w.floor === -1) return false; // basement is underground
  const thinInX = w.x2 - w.x1 < w.y2 - w.y1;
  if (!thinInX) return false;
  const cx = (w.x1 + w.x2) / 2;
  return BOUNDARY_XS.some((bx) => Math.abs(cx - bx * WORLD_SCALE) < BOUNDARY_EPS);
}

export interface WindowBuildResult {
  frameGeoms: THREE.BufferGeometry[];
  glassGeoms: THREE.BufferGeometry[];
}

export function buildWindows(): WindowBuildResult {
  const frameGeoms: THREE.BufferGeometry[] = [];
  const glassGeoms: THREE.BufferGeometry[] = [];

  for (const w of WALLS) {
    if (!isExteriorSideWall(w)) continue;
    const base = floorY(w.floor ?? 0);
    const cx = (w.x1 + w.x2) / 2;
    const halfX = (w.x2 - w.x1) / 2 + 4; // proud of the wall face on both sides
    const runLen = w.y2 - w.y1;
    if (runLen < MIN_SEG) continue;

    const count = Math.max(1, Math.min(4, Math.floor(runLen / (WINDOW_W + WINDOW_GAP))));
    const frameColor = teamSideAt(cx) === "B" ? COLORS.doorFrameB : COLORS.doorFrameA;
    const sillY = base + WINDOW_SILL;
    const headY = base + WINDOW_HEAD;
    const paneH = headY - sillY;
    const midY = (sillY + headY) / 2;

    for (let i = 0; i < count; i++) {
      // Evenly spaced pane centres along the run.
      const t = (i + 1) / (count + 1);
      const zc = w.y1 + t * runLen;
      const z1 = zc - WINDOW_W / 2;
      const z2 = zc + WINDOW_W / 2;
      const paneRect: Rect = { x1: cx - halfX, y1: z1, x2: cx + halfX, y2: z2 };
      glassGeoms.push(rectToBox(paneRect, paneH, midY, COLORS.glass));

      // Frame: four bars hugging the pane, a touch prouder.
      const fx = halfX + 2;
      const top: Rect = { x1: cx - fx, y1: z1 - FRAME_BAND, x2: cx + fx, y2: z2 + FRAME_BAND };
      frameGeoms.push(rectToBox(top, FRAME_BAND, headY + FRAME_BAND / 2, frameColor)); // header
      frameGeoms.push(rectToBox(top, FRAME_BAND, sillY - FRAME_BAND / 2, frameColor)); // sill
      const left: Rect = { x1: cx - fx, y1: z1 - FRAME_BAND, x2: cx + fx, y2: z1 };
      const right: Rect = { x1: cx - fx, y1: z2, x2: cx + fx, y2: z2 + FRAME_BAND };
      frameGeoms.push(rectToBox(left, paneH, midY, frameColor));
      frameGeoms.push(rectToBox(right, paneH, midY, frameColor));
    }
  }

  return { frameGeoms, glassGeoms };
}
