import * as THREE from "three";

// Procedurally generated surface detail.
//
// The world is built from axis-aligned boxes, and no amount of lighting makes
// an untextured box look like anything but an untextured box: a flat surface
// with a single colour has no scale cue, so the eye reads it as a primitive
// rather than as plaster or floorboards. These generators draw tiling detail
// into a canvas at load time and derive a normal map from it, which gives every
// surface grain, a sense of size, and something for the key light to catch.
//
// Deliberately generated rather than downloaded: the project ships no image
// assets and this environment cannot fetch any, but more importantly a
// generated map is a handful of numbers to tune rather than a binary to manage,
// and it stays crisp at any world scale because the tiling rate is a parameter.
//
// The maps are GREYSCALE and are multiplied by the per-vertex colour that
// EnvironmentBuilder already bakes, so one shared texture serves every room and
// the palette stays in constants.ts. That is what keeps this to a few draw
// calls: same geometry, same merge, one extra texture lookup.

const SIZE = 256;

function makeCanvas(): { canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D } {
  const canvas = document.createElement("canvas");
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d")!;
  return { canvas, ctx };
}

// Cheap value noise: a lattice of random values, smoothly interpolated. Enough
// for surface grain, and far cheaper to write than a real Perlin.
function valueNoise(width: number, seed: number): number[] {
  const grid = width + 1;
  const rand: number[] = [];
  let s = seed;
  for (let i = 0; i < grid * grid; i++) {
    s = (s * 1664525 + 1013904223) >>> 0;
    rand.push(s / 4294967296);
  }
  const out: number[] = new Array(SIZE * SIZE);
  const step = SIZE / width;
  const smooth = (t: number) => t * t * (3 - 2 * t);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const gx = x / step;
      const gy = y / step;
      const x0 = Math.floor(gx) % width;
      const y0 = Math.floor(gy) % width;
      const x1 = (x0 + 1) % width;
      const y1 = (y0 + 1) % width;
      const fx = smooth(gx - Math.floor(gx));
      const fy = smooth(gy - Math.floor(gy));
      const a = rand[y0 * grid + x0];
      const b = rand[y0 * grid + x1];
      const c = rand[y1 * grid + x0];
      const d = rand[y1 * grid + x1];
      out[y * SIZE + x] = (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy;
    }
  }
  return out;
}

// Several octaves of the above, so the grain has both broad blotches and fine
// speckle rather than one uniform frequency.
function fbm(octaves: { width: number; weight: number; seed: number }[]): number[] {
  const out = new Array(SIZE * SIZE).fill(0);
  let total = 0;
  for (const o of octaves) {
    const n = valueNoise(o.width, o.seed);
    for (let i = 0; i < out.length; i++) out[i] += n[i] * o.weight;
    total += o.weight;
  }
  for (let i = 0; i < out.length; i++) out[i] /= total;
  return out;
}

function heightToCanvas(height: number[], lo: number, hi: number): HTMLCanvasElement {
  const { canvas, ctx } = makeCanvas();
  const img = ctx.createImageData(SIZE, SIZE);
  for (let i = 0; i < height.length; i++) {
    const v = Math.round((lo + (hi - lo) * height[i]) * 255);
    img.data[i * 4] = v;
    img.data[i * 4 + 1] = v;
    img.data[i * 4 + 2] = v;
    img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return canvas;
}

// Sobel the height field into a tangent-space normal map. `strength` is how
// pronounced the relief reads; too high and flat plaster looks like stucco.
function heightToNormal(height: number[], strength: number): HTMLCanvasElement {
  const { canvas, ctx } = makeCanvas();
  const img = ctx.createImageData(SIZE, SIZE);
  const at = (x: number, y: number) => height[((y + SIZE) % SIZE) * SIZE + ((x + SIZE) % SIZE)];
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const dx = at(x - 1, y) - at(x + 1, y);
      const dy = at(x, y - 1) - at(x, y + 1);
      const nx = dx * strength;
      const ny = dy * strength;
      const len = Math.hypot(nx, ny, 1);
      const i = (y * SIZE + x) * 4;
      img.data[i] = Math.round(((nx / len) * 0.5 + 0.5) * 255);
      img.data[i + 1] = Math.round(((ny / len) * 0.5 + 0.5) * 255);
      img.data[i + 2] = Math.round((1 / len) * 0.5 * 255 + 127);
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return canvas;
}

function toTexture(canvas: HTMLCanvasElement, srgb: boolean): THREE.Texture {
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = 8;
  if (srgb) tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

export interface SurfaceMaps {
  map: THREE.Texture; // greyscale detail, multiplied by the vertex colour
  normalMap: THREE.Texture;
  roughnessMap: THREE.Texture;
}

// ---- plaster: fine even grain, almost no relief. Reads as a painted wall.
function plaster(): SurfaceMaps {
  const h = fbm([
    { width: 8, weight: 0.5, seed: 11 },
    { width: 32, weight: 0.35, seed: 12 },
    { width: 128, weight: 0.15, seed: 13 },
  ]);
  return {
    map: toTexture(heightToCanvas(h, 0.86, 1.0), true),
    normalMap: toTexture(heightToNormal(h, 1.4), false),
    roughnessMap: toTexture(heightToCanvas(h, 0.82, 1.0), false),
  };
}

// ---- boards: long planks with dark seams and grain running along them. This
// is the one that most changes how a floor reads, because the plank width is a
// direct size cue - suddenly the room has a scale.
function boards(plankCount: number, seed: number): SurfaceMaps {
  const grain = fbm([
    { width: 4, weight: 0.4, seed },
    { width: 64, weight: 0.6, seed: seed + 1 },
  ]);
  const h = new Array(SIZE * SIZE);
  const plank = SIZE / plankCount;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const i = y * SIZE + x;
      // Stretch the grain along the plank direction so it reads as wood fibre.
      const stretched = grain[(y * SIZE + ((x * 4) % SIZE)) % (SIZE * SIZE)];
      const alongPlank = ((y % plank) + plank) % plank;
      const seam = alongPlank < 1.6 || alongPlank > plank - 1.6 ? 0.0 : 1.0;
      // Every plank gets its own slight tone, so the floor is not one flat sheet.
      const plankTone = 0.93 + 0.07 * (((Math.floor(y / plank) * 2654435761) >>> 0) / 4294967296);
      h[i] = Math.min(1, stretched * 0.18 + plankTone * 0.82) * (seam ? 1 : 0.74);
    }
  }
  return {
    map: toTexture(heightToCanvas(h, 0.82, 1.04), true),
    normalMap: toTexture(heightToNormal(h, 1.5), false),
    roughnessMap: toTexture(heightToCanvas(h, 0.5, 0.85), false),
  };
}

// ---- concrete: broad blotches plus fine pitting. The basement floor.
function concrete(): SurfaceMaps {
  const h = fbm([
    { width: 4, weight: 0.45, seed: 41 },
    { width: 16, weight: 0.3, seed: 42 },
    { width: 96, weight: 0.25, seed: 43 },
  ]);
  return {
    map: toTexture(heightToCanvas(h, 0.84, 1.06), true),
    normalMap: toTexture(heightToNormal(h, 1.5), false),
    roughnessMap: toTexture(heightToCanvas(h, 0.78, 1.0), false),
  };
}

// ---- turf: dense high-frequency clumping, no seams. Reads as mown grass from
// a standing camera without needing a single blade of geometry.
function turf(): SurfaceMaps {
  const h = fbm([
    { width: 16, weight: 0.3, seed: 71 },
    { width: 64, weight: 0.3, seed: 72 },
    { width: 128, weight: 0.4, seed: 73 },
  ]);
  return {
    map: toTexture(heightToCanvas(h, 0.78, 1.10), true),
    normalMap: toTexture(heightToNormal(h, 2.2), false),
    roughnessMap: toTexture(heightToCanvas(h, 0.85, 1.0), false),
  };
}

// Built once and shared by every mesh that wants them.
let cache: Record<string, SurfaceMaps> | null = null;

export function surfaces(): Record<"plaster" | "floorboards" | "concrete" | "turf" | "painted" | "shingle", SurfaceMaps> {
  if (!cache) {
    cache = {
      plaster: plaster(),
      floorboards: boards(7, 21),
      concrete: concrete(),
      turf: turf(),
      // Painted timber - the same board layout, much finer grain and tighter
      // tone variation, so stairs and trim read as painted rather than raw.
      painted: boards(4, 31),
      // Roof tiles: many narrow courses. A roof is the largest single plane in
      // the game and the first thing seen from outside, so leaving it flat
      // undoes the rest of the surface work on its own.
      shingle: boards(14, 51),
    };
  }
  return cache as Record<"plaster" | "floorboards" | "concrete" | "turf" | "painted" | "shingle", SurfaceMaps>;
}

// ---------------------------------------------------------------------------
// World-space UVs.
//
// Box UVs run 0..1 per face, so a tiling texture stretches to fit whatever the
// box happens to be: a 900-unit wall and a 30-unit step would get the same
// number of plaster grains, which destroys the size cue the texture exists to
// provide. This reprojects UVs from WORLD POSITION after merging, picking the
// axis pair the triangle actually faces, so texel density is constant
// everywhere and every surface agrees about how big a plank is.
// ---------------------------------------------------------------------------
export function applyWorldUVs(geometry: THREE.BufferGeometry, tileSize: number): void {
  const pos = geometry.attributes.position;
  const nrm = geometry.attributes.normal;
  const uv = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const y = pos.getY(i);
    const z = pos.getZ(i);
    const nx = Math.abs(nrm.getX(i));
    const ny = Math.abs(nrm.getY(i));
    const nz = Math.abs(nrm.getZ(i));
    let u: number;
    let v: number;
    if (ny >= nx && ny >= nz) {
      u = x; // floor/ceiling: project down
      v = z;
    } else if (nx >= nz) {
      u = z; // wall facing along x
      v = y;
    } else {
      u = x; // wall facing along z
      v = y;
    }
    uv[i * 2] = u / tileSize;
    uv[i * 2 + 1] = v / tileSize;
  }
  geometry.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
}
