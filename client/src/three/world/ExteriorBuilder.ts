import * as THREE from "three";
import { mergeVertices } from "three/addons/utils/BufferGeometryUtils.js";
import { COLORS, WALL_HEIGHT, FLOOR_HEIGHT, WORLD_WIDTH, WORLD_HEIGHT, SURFACE_OVERLAP } from "../../constants";
import { WALLS, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";
import { floorY } from "./HeightField";

// Everything OUTSIDE the play area.
//
// The interior got trim, generated surfaces and a real light rig, and that
// made the outside worse by comparison: the map ended at a bare plaster
// boundary wall with a flat green sheet behind it running to the horizon. From
// the garden - which is where the whole match is fought - that flat sheet is
// most of the upper half of the screen, so it was the largest untreated
// surface left in the game.
//
// Three things fix it, in descending order of how much they matter:
//   1. the boundary wall gets a coping course and piers, so the map edge has a
//      silhouette instead of being a cut-off slab;
//   2. hedging runs outside it, which is what gives the wall a base and stops
//      it reading as a wall standing on nothing;
//   3. trees and mown patches break up the outer lawn, which is what puts a
//      sense of DISTANCE behind the houses.
//
// None of it is collidable and none of it is inside the world bounds - the
// boundary wall is already solid, so nothing here can change where a player or
// a bot may walk. It is emitted as plain geometry lists which
// EnvironmentBuilder merges into the meshes it already builds, so the whole
// exterior costs zero extra draw calls.

export interface ExteriorGeoms {
  painted: THREE.BufferGeometry[]; // coping, piers, trunks - timber/masonry roles
  turf: THREE.BufferGeometry[]; // hedging, canopies, ground patches
}

// Deterministic scatter. A seeded LCG rather than Math.random so the treeline
// is identical in every client and on every reload - two players describing
// "the tree by the corner" have to be looking at the same tree.
function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

// Bake a flat colour in, and hand back an INDEXED geometry. The second part
// matters: everything here is merged into meshes built from BoxGeometry, and
// mergeGeometries refuses a batch that mixes indexed and non-indexed inputs -
// which the polyhedra used for foliage are. mergeVertices only welds vertices
// agreeing on every attribute INCLUDING the normal, so a faceted blob keeps its
// facets and simply gains an index buffer.
function colored(geo: THREE.BufferGeometry, colorHex: number): THREE.BufferGeometry {
  const color = new THREE.Color(colorHex);
  const count = geo.attributes.position.count;
  const colors = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    colors[i * 3] = color.r;
    colors[i * 3 + 1] = color.g;
    colors[i * 3 + 2] = color.b;
  }
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  return geo.index ? geo : mergeVertices(geo);
}

// Grow a rect outward on its THIN axis only, leaving the run length alone.
function proud(r: Rect, by: number): Rect {
  return r.x2 - r.x1 < r.y2 - r.y1
    ? { x1: r.x1 - by, y1: r.y1, x2: r.x2 + by, y2: r.y2 }
    : { x1: r.x1, y1: r.y1 - by, x2: r.x2, y2: r.y2 + by };
}

// The four world-boundary walls are the only WALLS entries with no floor: they
// stand at ground level and span the whole map edge.
function boundaryWalls(): Rect[] {
  return WALLS.filter((w) => w.floor === undefined);
}

const COPING_H = 11;
const COPING_PROUD = 6;
const PIER_PROUD = 13;
const PIER_W = 34;
const PIER_RISE = 26; // how far a pier stands above the coping
const PIER_SPACING = 230;

// A capped wall reads as built; an uncapped one reads as cut. The cap is butted
// onto the wall top rather than overlapped - the two touching faces point in
// opposite directions, so only one is ever rasterised (see SURFACE_OVERLAP).
function wallDressing(): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];
  const base = floorY(0);
  const top = base + WALL_HEIGHT;

  for (const w of boundaryWalls()) {
    geoms.push(rectToBox(proud(w, COPING_PROUD), COPING_H, top + COPING_H / 2, COLORS.coping));

    // Piers march along the wall's LONG axis at a fixed spacing, so the corner
    // pier of one run and of the next are two separate boxes that happen to
    // overlap - which is fine, they are solid and the buried faces never draw.
    const runInX = w.x2 - w.x1 > w.y2 - w.y1;
    const from = runInX ? w.x1 : w.y1;
    const to = runInX ? w.x2 : w.y2;
    const count = Math.max(2, Math.round((to - from) / PIER_SPACING));
    for (let i = 0; i <= count; i++) {
      const at = from + ((to - from) * i) / count;
      const a = Math.max(from, at - PIER_W / 2);
      const b = Math.min(to, at + PIER_W / 2);
      const slice: Rect = runInX
        ? { x1: a, y1: w.y1, x2: b, y2: w.y2 }
        : { x1: w.x1, y1: a, x2: w.x2, y2: b };
      const pier = proud(slice, PIER_PROUD);
      const h = WALL_HEIGHT + COPING_H + PIER_RISE;
      geoms.push(rectToBox(pier, h, base + h / 2, COLORS.foundation));
      // A little cap on each pier, the same idea one storey up.
      geoms.push(rectToBox(proud(pier, 4), 7, base + h + 3.5, COLORS.coping));
    }
  }
  return geoms;
}

const HEDGE_GAP = 26; // clear of the wall, so the two never share a face
const HEDGE_DEPTH = 62;
const HEDGE_H = 74;

// Clipped hedging outside the boundary, in segments of slightly varying height
// so the top line is not a ruler edge. Placed OUTSIDE the map on purpose: this
// is scenery seen over the wall, and putting it inside would change where the
// chase camera can sit.
function hedging(): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];
  const base = floorY(0) - FLOOR_HEIGHT;
  const rand = rng(90210);

  // One band per map side, laid just beyond the boundary wall and run long
  // enough at the corners to close the ring.
  const outer = HEDGE_GAP + HEDGE_DEPTH;
  const bands: { rect: Rect; runInX: boolean }[] = [
    { rect: { x1: -outer, y1: -outer, x2: WORLD_WIDTH + outer, y2: -HEDGE_GAP }, runInX: true },
    { rect: { x1: -outer, y1: WORLD_HEIGHT + HEDGE_GAP, x2: WORLD_WIDTH + outer, y2: WORLD_HEIGHT + outer }, runInX: true },
    { rect: { x1: -outer, y1: -outer, x2: -HEDGE_GAP, y2: WORLD_HEIGHT + outer }, runInX: false },
    { rect: { x1: WORLD_WIDTH + HEDGE_GAP, y1: -outer, x2: WORLD_WIDTH + outer, y2: WORLD_HEIGHT + outer }, runInX: false },
  ];

  const SEG = 130;
  for (const band of bands) {
    const from = band.runInX ? band.rect.x1 : band.rect.y1;
    const to = band.runInX ? band.rect.x2 : band.rect.y2;
    const steps = Math.ceil((to - from) / SEG);
    for (let i = 0; i < steps; i++) {
      const a = from + (i * (to - from)) / steps;
      const b = from + ((i + 1) * (to - from)) / steps;
      const seg: Rect = band.runInX
        ? { x1: a, y1: band.rect.y1, x2: b, y2: band.rect.y2 }
        : { x1: band.rect.x1, y1: a, x2: band.rect.x2, y2: b };
      const h = HEDGE_H * (0.86 + rand() * 0.3);
      geoms.push(rectToBox(seg, h, base + h / 2, rand() < 0.5 ? COLORS.hedge : COLORS.hedgeAlt));
    }
  }
  return geoms;
}

// A tree: tapered trunk plus three overlapping low-poly canopy blobs at
// different heights and tones. Three blobs rather than one is what stops it
// reading as a lollipop - the silhouette gets a notch, and the tones separate
// the lit side from the shaded one without needing a second light.
function tree(x: number, z: number, scale: number, rand: () => number, out: ExteriorGeoms): void {
  const base = floorY(0) - FLOOR_HEIGHT;
  const trunkH = 150 * scale;
  const trunkR = 12 * scale;

  const trunk = new THREE.CylinderGeometry(trunkR * 0.72, trunkR, trunkH, 6);
  trunk.translate(x, base + trunkH / 2, z);
  out.painted.push(colored(trunk, COLORS.trunk));

  const tones = [COLORS.canopy, COLORS.canopyAlt, COLORS.canopyDeep];
  for (let i = 0; i < 3; i++) {
    const r = (62 - i * 9) * scale * (0.85 + rand() * 0.3);
    const blob = new THREE.IcosahedronGeometry(r, 0);
    blob.translate(
      x + (rand() - 0.5) * 46 * scale,
      base + trunkH + (18 + i * 30) * scale,
      z + (rand() - 0.5) * 46 * scale
    );
    out.turf.push(colored(blob, tones[i]));
  }
}

// Trees and mown patches across the outer lawn. Both are rejection-sampled to
// stay clear of the map: anything overlapping the play area would poke through
// a wall or float over a garden.
function outerScatter(out: ExteriorGeoms): void {
  const rand = rng(4242);
  const MARGIN = 1500; // a deep band of country, inside the lawn skirt
  const CLEAR = 150; // how far a tree must stay off the hedging
  const base = floorY(0) - FLOOR_HEIGHT;

  const outside = (x: number, z: number, pad: number) =>
    x < -pad || x > WORLD_WIDTH + pad || z < -pad || z > WORLD_HEIGHT + pad;

  // Uniform sampling alone clumps: three trunks land on top of each other and
  // read as one bush with a fence of legs. A minimum separation costs one loop
  // and is the difference between a treeline and a pile.
  const SPACING = 200;
  const placed: { x: number; z: number }[] = [];
  for (let i = 0; i < 260; i++) {
    if (placed.length >= 90) break;
    const x = -MARGIN + rand() * (WORLD_WIDTH + MARGIN * 2);
    const z = -MARGIN + rand() * (WORLD_HEIGHT + MARGIN * 2);
    if (!outside(x, z, CLEAR)) continue;
    if (placed.some((p) => Math.hypot(p.x - x, p.z - z) < SPACING)) continue;
    placed.push({ x, z });
    tree(x, z, 0.8 + rand() * 0.7, rand, out);
  }

  // Flat mown patches: a hair above the lawn slab, never overlapping each
  // other's plane enough to matter, and only two tones so it reads as mowing
  // rather than as noise.
  for (let i = 0; i < 60; i++) {
    const x = -MARGIN + rand() * (WORLD_WIDTH + MARGIN * 2);
    const z = -MARGIN + rand() * (WORLD_HEIGHT + MARGIN * 2);
    if (!outside(x, z, 40)) continue;
    const w = 160 + rand() * 380;
    const d = 120 + rand() * 260;
    const patch: Rect = { x1: x - w / 2, y1: z - d / 2, x2: x + w / 2, y2: z + d / 2 };
    out.turf.push(
      rectToBox(patch, FLOOR_HEIGHT, base - FLOOR_HEIGHT / 2 + SURFACE_OVERLAP, rand() < 0.5 ? COLORS.meadow : COLORS.meadowAlt)
    );
  }
}

export function buildExteriorGeoms(): ExteriorGeoms {
  const out: ExteriorGeoms = { painted: [], turf: [] };
  out.painted.push(...wallDressing());
  out.turf.push(...hedging());
  outerScatter(out);
  return out;
}
