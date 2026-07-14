import * as THREE from "three";
import { WALLS, type Rect } from "../../geometry/floorplan";
import { WALL_HEIGHT, WINDOW_SILL, WINDOW_HEAD, WORLD_SCALE, COLORS } from "../../constants";
import { rectToBox } from "../EnvironmentBuilder";
import { WINDOWS, type WindowSpec } from "./propManifest";

// Real see-through openings punched into the WALLS rects: for every window,
// EnvironmentBuilder skips emitting that wall's rect as one solid box and
// splices in this module's replacement boxes (solid above/below/either side
// of the opening) plus a wooden frame, instead. Collision is untouched -
// GameController/EnvironmentBuilder keep colliding against the ORIGINAL WALLS
// rects, so a window never changes what you can walk through.

// A small reveal beyond the wall's own thickness so the frame visibly wraps
// the opening, matching how the door jambs sit "proud" of the wall face.
const FRAME_PROUD = 4 * WORLD_SCALE;
// Thickness of the sill/head trim bands, and the width of each side jamb,
// measured along the wall's run direction.
const FRAME_BAND = 8 * WORLD_SCALE;
// Thinner cross-bar splitting each pane into 4 lights (like the sill/head/
// jamb trim, but thin enough to read as glazing bars rather than structural
// frame) - a plain glass rectangle reads as a hole in the wall from outside;
// a 4-light window reads as an authored window.
const MULLION_THICKNESS = 3 * WORLD_SCALE;

interface ScaledWindow {
  axis: "x" | "y";
  plane: number;
  start: number;
  end: number;
}

function scaleWindow(w: WindowSpec): ScaledWindow {
  const plane = w.plane * WORLD_SCALE;
  const center = w.center * WORLD_SCALE;
  const half = (w.width * WORLD_SCALE) / 2;
  return { axis: w.axis, plane, start: center - half, end: center + half };
}

// The WALLS rect a window pierces: axis "x" windows sit in vertical walls
// (thinner in x than y), axis "y" windows sit in horizontal walls (thinner in
// y than x) - the window's plane must fall inside the wall's thickness, and
// its span must fall strictly inside the wall's run, so it never straddles a
// door gap.
function findWallIndex(win: ScaledWindow): number {
  return WALLS.findIndex((r) => {
    if (win.axis === "x") {
      const vertical = r.x2 - r.x1 < r.y2 - r.y1;
      return vertical && win.plane >= r.x1 && win.plane <= r.x2 && win.start > r.y1 && win.end < r.y2;
    }
    const horizontal = r.y2 - r.y1 < r.x2 - r.x1;
    return horizontal && win.plane >= r.y1 && win.plane <= r.y2 && win.start > r.x1 && win.end < r.x2;
  });
}

// Sub-rect of the containing wall `r`: keeps the wall's own thickness, swaps
// in [start, end] along whichever ground-plane axis the wall runs.
function runRect(r: Rect, axis: "x" | "y", start: number, end: number): Rect {
  return axis === "x" ? { x1: r.x1, x2: r.x2, y1: start, y2: end } : { x1: start, x2: end, y1: r.y1, y2: r.y2 };
}

// Same, but proud of the wall's thickness by FRAME_PROUD on both faces - used
// for the wooden frame trim so it visibly pokes past the wall surface.
function proudRunRect(r: Rect, axis: "x" | "y", start: number, end: number): Rect {
  return axis === "x"
    ? { x1: r.x1 - FRAME_PROUD, x2: r.x2 + FRAME_PROUD, y1: start, y2: end }
    : { x1: start, x2: end, y1: r.y1 - FRAME_PROUD, y2: r.y2 + FRAME_PROUD };
}

function plainBox(r: Rect, height: number, yCenter: number): THREE.BufferGeometry {
  const geo = new THREE.BoxGeometry(r.x2 - r.x1, height, r.y2 - r.y1);
  geo.translate((r.x1 + r.x2) / 2, yCenter, (r.y1 + r.y2) / 2);
  return geo;
}

export interface WindowBuildResult {
  // Indices into WALLS that were split - EnvironmentBuilder must skip these
  // when it emits the plain per-wall boxes, since wallReplacementGeoms
  // already covers them (minus the opening).
  splitWallIndices: Set<number>;
  // Vertex-colored (COLORS.wall) boxes to merge alongside the plain wall
  // boxes, replacing every split wall rect.
  wallReplacementGeoms: THREE.BufferGeometry[];
  // Vertex-colored (COLORS.doorFrame) wooden trim, merged into the same walls
  // mesh as the door frames.
  frameGeoms: THREE.BufferGeometry[];
  // Plain (uncolored) boxes for the separate translucent glass mesh.
  glassGeoms: THREE.BufferGeometry[];
}

export function buildWindows(): WindowBuildResult {
  const splitWallIndices = new Set<number>();
  const byWall = new Map<number, ScaledWindow[]>();

  for (const spec of WINDOWS) {
    const win = scaleWindow(spec);
    const idx = findWallIndex(win);
    if (idx < 0) continue; // validated data shouldn't miss, but don't break the build if it ever does
    splitWallIndices.add(idx);
    const list = byWall.get(idx) ?? [];
    list.push(win);
    byWall.set(idx, list);
  }

  const wallReplacementGeoms: THREE.BufferGeometry[] = [];
  const frameGeoms: THREE.BufferGeometry[] = [];
  const glassGeoms: THREE.BufferGeometry[] = [];
  const glassHeight = WINDOW_HEAD - WINDOW_SILL;
  const headHeight = WALL_HEIGHT - WINDOW_HEAD;

  for (const [idx, windows] of byWall) {
    const r = WALLS[idx];
    const axis = windows[0].axis;
    const [runMin, runMax] = axis === "x" ? [r.y1, r.y2] : [r.x1, r.x2];
    const sorted = [...windows].sort((a, b) => a.start - b.start);

    let cursor = runMin;
    for (const win of sorted) {
      // Solid wall between the previous opening (or the wall's start) and
      // this one.
      if (win.start > cursor) {
        wallReplacementGeoms.push(rectToBox(runRect(r, axis, cursor, win.start), WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.wall));
      }

      // Solid wall below the sill and above the head, spanning just the
      // opening - what's left of the wall once the window pane is cut out.
      wallReplacementGeoms.push(
        rectToBox(runRect(r, axis, win.start, win.end), WINDOW_SILL, WINDOW_SILL / 2, COLORS.wall)
      );
      wallReplacementGeoms.push(
        rectToBox(runRect(r, axis, win.start, win.end), headHeight, WINDOW_HEAD + headHeight / 2, COLORS.wall)
      );

      // Wooden frame: sill + head trim bands across the opening, plus a jamb
      // post just past each side.
      frameGeoms.push(
        rectToBox(proudRunRect(r, axis, win.start, win.end), FRAME_BAND, WINDOW_SILL + FRAME_BAND / 2, COLORS.doorFrame)
      );
      frameGeoms.push(
        rectToBox(proudRunRect(r, axis, win.start, win.end), FRAME_BAND, WINDOW_HEAD - FRAME_BAND / 2, COLORS.doorFrame)
      );
      frameGeoms.push(
        rectToBox(
          proudRunRect(r, axis, win.start - FRAME_BAND, win.start),
          glassHeight,
          WINDOW_SILL + glassHeight / 2,
          COLORS.doorFrame
        )
      );
      frameGeoms.push(
        rectToBox(
          proudRunRect(r, axis, win.end, win.end + FRAME_BAND),
          glassHeight,
          WINDOW_SILL + glassHeight / 2,
          COLORS.doorFrame
        )
      );

      // Mullions: one vertical bar (full pane height, centered on the run)
      // and one horizontal bar (full pane width, centered on the sill/head
      // midpoint), splitting the pane into 4 lights.
      const mid = (win.start + win.end) / 2;
      frameGeoms.push(
        rectToBox(
          proudRunRect(r, axis, mid - MULLION_THICKNESS / 2, mid + MULLION_THICKNESS / 2),
          glassHeight,
          WINDOW_SILL + glassHeight / 2,
          COLORS.doorFrame
        )
      );
      frameGeoms.push(
        rectToBox(proudRunRect(r, axis, win.start, win.end), MULLION_THICKNESS, WINDOW_SILL + glassHeight / 2, COLORS.doorFrame)
      );

      // The pane itself: a separate translucent mesh, not merged with the
      // opaque walls material.
      glassGeoms.push(plainBox(runRect(r, axis, win.start, win.end), glassHeight, WINDOW_SILL + glassHeight / 2));

      cursor = win.end;
    }
    if (cursor < runMax) {
      wallReplacementGeoms.push(rectToBox(runRect(r, axis, cursor, runMax), WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.wall));
    }
  }

  return { splitWallIndices, wallReplacementGeoms, frameGeoms, glassGeoms };
}
