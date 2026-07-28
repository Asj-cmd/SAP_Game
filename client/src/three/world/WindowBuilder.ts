import * as THREE from "three";
import { WINDOW_SILL, WINDOW_HEAD, COLORS, teamSideAt, WORLD_SCALE, SURFACE_OVERLAP } from "../../constants";
import { WALLS, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";
import { floorY } from "./HeightField";

// Adds windows to the houses' exterior-facing SIDE walls so they read as homes,
// not blank boxes. Floor-aware: each window sits at WINDOW_SILL..WINDOW_HEAD
// above ITS wall's floor.
//
// These are REAL openings. The panes used to be a sheet of glass stuck onto an
// unbroken wall, so however translucent the material was you were still looking
// at solid plaster behind it. This module now reports each pane's z-range back
// to EnvironmentBuilder, which omits that stretch of wall between sill and head
// - so a window is a hole with a pane of glass in it and you can see through.

// A wall qualifies if it's a vertical side wall (runs along z, thin in x) sitting
// on a house<->garden or house<->backyard boundary - the faces you see from the
// garden/yard during play. Basement walls (floor -1) are below grade, so skipped.
const BOUNDARY_XS = [260, 720, 1180, 1640]; // pre-scale house side-wall lines
const BOUNDARY_EPS = 20; // scaled slack when matching a wall's centre x

const WINDOW_W = 55; // pane width along the wall (world units, unscaled like sills)
const WINDOW_GAP = 90; // min clear run between panes
const FRAME_BAND = 6;
const GLASS_HALF_T = 1.2; // half the pane thickness - glass, not a block of ice
const MIN_SEG = 140; // don't window a wall run shorter than this (scaled)

function isExteriorSideWall(w: Rect & { floor?: number }): boolean {
  if (w.floor === -1) return false; // basement is underground
  const thinInX = w.x2 - w.x1 < w.y2 - w.y1;
  if (!thinInX) return false;
  const cx = (w.x1 + w.x2) / 2;
  return BOUNDARY_XS.some((bx) => Math.abs(cx - bx * WORLD_SCALE) < BOUNDARY_EPS);
}

// One opening to cut out of a wall: a z-range along the run, between two
// absolute world heights.
export interface WindowOpening {
  z1: number;
  z2: number;
  sillY: number;
  headY: number;
}

export interface WindowBuildResult {
  frameGeoms: THREE.BufferGeometry[];
  glassGeoms: THREE.BufferGeometry[];
  // Keyed by the wall's index in WALLS, so the wall pass can look its own
  // openings up without re-deriving which walls got windows.
  openings: Map<number, WindowOpening[]>;
}

export function buildWindows(): WindowBuildResult {
  const frameGeoms: THREE.BufferGeometry[] = [];
  const glassGeoms: THREE.BufferGeometry[] = [];
  const openings = new Map<number, WindowOpening[]>();

  WALLS.forEach((w, wallIndex) => {
    if (!isExteriorSideWall(w)) return;
    const base = floorY(w.floor ?? 0);
    const cx = (w.x1 + w.x2) / 2;
    const halfX = (w.x2 - w.x1) / 2 + 4; // proud of the wall face on both sides
    const runLen = w.y2 - w.y1;
    if (runLen < MIN_SEG) return;

    const count = Math.max(1, Math.min(4, Math.floor(runLen / (WINDOW_W + WINDOW_GAP))));
    const frameColor = teamSideAt(cx) === "B" ? COLORS.doorFrameB : COLORS.doorFrameA;
    const sillY = base + WINDOW_SILL;
    const headY = base + WINDOW_HEAD;
    const paneH = headY - sillY;
    const midY = (sillY + headY) / 2;
    const wallOpenings: WindowOpening[] = [];

    for (let i = 0; i < count; i++) {
      // Evenly spaced pane centres along the run.
      const t = (i + 1) / (count + 1);
      const zc = w.y1 + t * runLen;
      const z1 = zc - WINDOW_W / 2;
      const z2 = zc + WINDOW_W / 2;
      wallOpenings.push({ z1, z2, sillY, headY });

      // A thin pane, not a block. It used to be built thicker than the wall it
      // sat in, which meant a slab of glass poking out of both faces.
      const paneRect: Rect = { x1: cx - GLASS_HALF_T, y1: z1, x2: cx + GLASS_HALF_T, y2: z2 };
      glassGeoms.push(rectToBox(paneRect, paneH, midY, COLORS.glass));

      // Frame: four bars LINING the opening.
      //
      // They used to stop exactly on the wall's own reveal faces - the sill the
      // opening is cut down to, the head it is cut up to, the jambs it is cut
      // between. Since the frames merge into the SAME mesh as the walls, that
      // put two identical same-facing surfaces on one plane at every one of
      // those four edges, and the depth buffer picked a different winner as the
      // camera moved: the shimmer around every window's inside surfaces.
      //
      // Each bar now runs SURFACE_OVERLAP past the reveal it meets, so the
      // wall's face is buried inside the frame instead of tying with it. The
      // bars are wider than the wall in both directions, so the buried face is
      // covered completely rather than just mostly.
      const fx = halfX + 2;
      const band = FRAME_BAND + SURFACE_OVERLAP;
      const across: Rect = { x1: cx - fx, y1: z1 - FRAME_BAND, x2: cx + fx, y2: z2 + FRAME_BAND };
      frameGeoms.push(rectToBox(across, band, headY - SURFACE_OVERLAP + band / 2, frameColor));
      frameGeoms.push(rectToBox(across, band, sillY + SURFACE_OVERLAP - band / 2, frameColor));
      const left: Rect = { x1: cx - fx, y1: z1 - FRAME_BAND, x2: cx + fx, y2: z1 + SURFACE_OVERLAP };
      const right: Rect = { x1: cx - fx, y1: z2 - SURFACE_OVERLAP, x2: cx + fx, y2: z2 + FRAME_BAND };
      // The jambs run only between sill and head; their own ends finish inside
      // those two bars, so they add no new junction of their own.
      frameGeoms.push(rectToBox(left, paneH, midY, frameColor));
      frameGeoms.push(rectToBox(right, paneH, midY, frameColor));
    }

    openings.set(wallIndex, wallOpenings);
  });

  return { frameGeoms, glassGeoms, openings };
}
