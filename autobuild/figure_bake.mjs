#!/usr/bin/env node
// Bakes a Quaternius Universal Base Character (CC0, D10) into a deadpan figure
// for Godot: godot/art/characters/figure_<body>.gltf + .bin.
//
//   node autobuild/figure_bake.mjs [--body=male|female] [--pose=Idle_Loop] [--frame=0]
//
// What it does to the source (STYLE.md §2):
//  - drops the eye and eyebrow meshes and every texture (blank, one material);
//  - keeps only the attributes the theme material can use (position, normal,
//    uv0, skin) plus a NEW COLOR_0: plain painted clothes by region of the bind
//    (T-)pose - shoes, trousers, shirt, bare putty above the collar and at the
//    hands. A theme material that ignores vertex colour shows a plain body; one
//    with `vertex_color_use_as_albedo` shows the clothes (P1-5 variant B);
//  - bakes one frame of an animation from the Universal Animation Library (same
//    rig) into the joints' rest transforms, so a still figure stands rather than
//    T-poses. Rotations are copied as they are; the pelvis/root translation is
//    applied as a change from the library's own rest (its bone lengths differ);
//  - scales the armature x100 (1 unit = 1 cm, godot/art/README.md).
//
// Reads the zips' contents from autobuild/Incoming/x/ (extract them there; the
// folder is gitignored, D10). Then (P2-1) welds the mesh, decimates it to the
// STYLE budget (--max-tris, default 5000) and takes shading normals from a
// smoothed copy (--normal-smooth passes, default 24). The family members (dad,
// mom, the kids) are NOT separate bakes: the ArtTheme draws them from these two
// bodies by height and bone scale (FamilyMember, default_theme.tres).

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC = path.join(ROOT, 'autobuild/Incoming/x');
const BODY_DIR = path.join(SRC, 'Universal Base Characters[Standard]/Base Characters/Godot - UE');
const ANIM_GLB = path.join(SRC, 'Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb');
const OUT_DIR = path.join(ROOT, 'godot/art/characters');

const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const bodyName = arg('body', 'male');
const poseName = arg('pose', 'Idle_Loop');
const poseFrame = Number(arg('frame', '0'));
const SOURCE = { male: 'Superhero_Male_FullBody', female: 'Superhero_Female_FullBody' }[bodyName];
if (!SOURCE) throw new Error(`unknown --body=${bodyName}`);

// Painted clothes, sRGB 0-255 (STYLE §2.3 / §3.3: muted, under ~35 % saturation).
// The bare parts are white, so the material's albedo (putty) shows through.
const PAINT = {
  bare: [255, 255, 255],
  // Multiplied by the figure albedo (putty), so these are lighter than they read.
  // First try (128/112/62) read as a dark wetsuit at chase distance (P1-5).
  // Tuned by frame (P1-5). Paints 2 and 3 never reached Godot at first (the
  // re-import bug, see bin_sha1 below); seen properly, 206/182 made the shirt as
  // light as the head and the trousers orange against the warm putty. The aim is
  // a shirt a step under the bare head and hands, trousers a step under that.
  shirt: [160, 174, 190], // muted blue-grey
  trousers: [128, 122, 116], // warm grey (x putty = grey-brown)
  shoes: [80, 76, 72], // dark brown-grey
};

const COMPONENTS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
const BYTES = { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 };

function readAccessor(doc, bin, index) {
  const acc = doc.accessors[index];
  const view = doc.bufferViews[acc.bufferView];
  const n = COMPONENTS[acc.type];
  const size = BYTES[acc.componentType];
  const stride = view.byteStride || n * size;
  const base = (view.byteOffset || 0) + (acc.byteOffset || 0);
  const out = [];
  for (let i = 0; i < acc.count; i++) {
    const row = [];
    for (let c = 0; c < n; c++) {
      const at = base + i * stride + c * size;
      row.push(acc.componentType === 5126 ? bin.readFloatLE(at) : bin.readUIntLE(at, size));
    }
    out.push(row);
  }
  return out;
}

function readGlb(file) {
  const b = fs.readFileSync(file);
  const jsonLength = b.readUInt32LE(12);
  const doc = JSON.parse(b.subarray(20, 20 + jsonLength).toString());
  const binStart = 20 + jsonLength + 8;
  const binLength = b.readUInt32LE(20 + jsonLength);
  return { doc, bin: b.subarray(binStart, binStart + binLength) };
}

// --- the pose -------------------------------------------------------------
const lib = readGlb(ANIM_GLB);
const clip = lib.doc.animations.find((a) => a.name === poseName);
if (!clip) throw new Error(`no animation ${poseName}`);
const posed = {}; // bone name -> { rotation, translation }
for (const channel of clip.channels) {
  const name = lib.doc.nodes[channel.target.node].name;
  const sampler = clip.samplers[channel.sampler];
  const values = readAccessor(lib.doc, lib.bin, sampler.output);
  const key = Math.min(poseFrame, values.length - 1);
  (posed[name] ||= {})[channel.target.path] = values[key];
}
const libRest = Object.fromEntries(lib.doc.nodes.map((n) => [n.name, n]));

// --- the body -------------------------------------------------------------
const doc = JSON.parse(fs.readFileSync(path.join(BODY_DIR, `${SOURCE}.gltf`)));
const bin = fs.readFileSync(path.join(BODY_DIR, doc.buffers[0].uri));
const skin = doc.skins[0];
const joints = new Set(skin.joints);
// The body mesh is the one with the most vertices; the others are eyes/brows.
const bodyMesh = doc.meshes
  .map((m, i) => [i, doc.accessors[m.primitives[0].attributes.POSITION].count])
  .sort((a, b) => b[1] - a[1])[0][0];

for (const index of joints) {
  const node = doc.nodes[index];
  const pose = posed[node.name];
  if (!pose) continue;
  if (pose.rotation) node.rotation = pose.rotation;
  if (pose.translation && (node.name === 'pelvis' || node.name === 'root')) {
    const rest = libRest[node.name].translation || [0, 0, 0];
    const own = node.translation || [0, 0, 0];
    node.translation = own.map((v, i) => v + pose.translation[i] - rest[i]);
  }
}

// --- repack: only what the figure needs ------------------------------------
const chunks = [];
let offset = 0;
const views = [];
const accessors = [];
function addAccessor(rows, componentType, type, extra = {}) {
  const n = COMPONENTS[type];
  const size = BYTES[componentType];
  const buf = Buffer.alloc(rows.length * n * size);
  rows.forEach((row, i) => row.forEach((v, c) => {
    const at = (i * n + c) * size;
    if (componentType === 5126) buf.writeFloatLE(v, at);
    else buf.writeUIntLE(Math.round(v), at, size);
  }));
  const pad = (4 - (buf.length % 4)) % 4;
  views.push({ buffer: 0, byteOffset: offset, byteLength: buf.length });
  chunks.push(buf, Buffer.alloc(pad));
  offset += buf.length + pad;
  const acc = { bufferView: views.length - 1, componentType, count: rows.length, type, ...extra };
  if (type === 'VEC3' && componentType === 5126) {
    acc.min = [0, 1, 2].map((c) => Math.min(...rows.map((r) => r[c])));
    acc.max = [0, 1, 2].map((c) => Math.max(...rows.map((r) => r[c])));
  }
  accessors.push(acc);
  return accessors.length - 1;
}
function copyAccessor(index) {
  const src = doc.accessors[index];
  const extra = src.normalized ? { normalized: true } : {};
  return addAccessor(readAccessor(doc, bin, index), src.componentType, src.type, extra);
}

const prim = doc.meshes[bodyMesh].primitives[0];
const positions = readAccessor(doc, bin, prim.attributes.POSITION);
const normals = readAccessor(doc, bin, prim.attributes.NORMAL);
const triangles = readAccessor(doc, bin, prim.indices).map((r) => r[0]);
const top = Math.max(...positions.map((p) => p[1]));
const reach = Math.max(...positions.map((p) => Math.abs(p[0])));

// --- blank: an egg for a head (STYLE §2.1) ----------------------------------
// Smoothing could not remove the face: Taubin passes moved the head 0.4 cm on
// average, because nose, sockets and mouth are broad shapes at this density.
// So the head is PROJECTED onto an ellipsoid fitted to it (radially, in the
// ellipsoid's own scaled space) with the ellipsoid's own normals: no eyes, nose,
// mouth or ears can survive. From the chin down to the neck the projection
// fades out, then a few Laplacian passes blend the seam.
const HEAD_FROM = Number(arg('head-from', '0.845')); // fraction of height: mid neck
const HEAD_FULL = Number(arg('head-full', '0.885')); // about the chin
const BLEND_PASSES = Number(arg('blend-passes', '12'));
const weld = new Map();
const canon = positions.map((p) => {
  const key = p.map((v) => Math.round(v * 1e5)).join(',');
  if (!weld.has(key)) weld.set(key, weld.size);
  return weld.get(key);
});
const count = weld.size;
const point = Array.from({ length: count }, () => [0, 0, 0]);
positions.forEach((p, i) => { point[canon[i]] = [...p]; });
const ring = Array.from({ length: count }, () => new Set());
for (let t = 0; t < triangles.length; t += 3) {
  const [a, b, c] = [canon[triangles[t]], canon[triangles[t + 1]], canon[triangles[t + 2]]];
  ring[a].add(b).add(c); ring[b].add(a).add(c); ring[c].add(a).add(b);
}
const headWeight = point.map((p) => {
  const h = p[1] / top;
  return h <= HEAD_FROM ? 0 : Math.min(1, (h - HEAD_FROM) / (HEAD_FULL - HEAD_FROM));
});
// Fit: the head proper (above the chin). Radii from the 90th percentile so the
// ears and the nose tip do not inflate it.
const core = point.filter((p) => p[1] / top >= HEAD_FULL);
const pct = (xs, q) => { const s = [...xs].sort((x, y) => x - y); return s[Math.floor(q * (s.length - 1))]; };
const minY = Math.min(...core.map((p) => p[1]));
const cz = (pct(core.map((p) => p[2]), 0.05) + pct(core.map((p) => p[2]), 0.95)) / 2;
const centre = [0, (minY + top) / 2, cz];
const radii = [
  pct(core.map((p) => Math.abs(p[0])), 0.9),
  (top - minY) / 2 * 1.08, // reach a little under the chin so the jaw closes over the neck
  pct(core.map((p) => Math.abs(p[2] - cz)), 0.9),
];
const onEgg = (p) => {
  const s = p.map((v, c) => (v - centre[c]) / radii[c]);
  const len = Math.hypot(...s) || 1;
  return s.map((v, c) => centre[c] + (v / len) * radii[c]);
};
const eggNormal = (p) => {
  const g = p.map((v, c) => (v - centre[c]) / (radii[c] * radii[c]));
  const len = Math.hypot(...g) || 1;
  return g.map((v) => v / len);
};
for (let k = 0; k < count; k++) {
  const w = headWeight[k];
  if (w > 0) { const e = onEgg(point[k]); point[k] = point[k].map((v, c) => v + w * (e[c] - v)); }
}
// Blend the neck seam: plain Laplacian on the partly-projected band.
for (let pass = 0; pass < BLEND_PASSES; pass++) {
  const next = point.map((p, i) => {
    const w = headWeight[i];
    if (w <= 0 || w >= 1) return p;
    const mean = [0, 0, 0];
    for (const j of ring[i]) for (let c = 0; c < 3; c++) mean[c] += point[j][c] / ring[i].size;
    return p.map((v, c) => v + 0.5 * (mean[c] - v));
  });
  next.forEach((p, i) => { point[i] = p; });
}
console.log(`  head: egg centre ${centre.map((v) => (v * 100).toFixed(1)).join(', ')}, radii ${radii.map((v) => (v * 100).toFixed(1)).join(', ')} cm`);

// --- paint (by region of the bind T-pose) ------------------------------------
const PAINT_ORDER = ['bare', 'shirt', 'trousers', 'shoes'];
function paintClass([x, y]) {
  const h = y / top;
  const ax = Math.abs(x) / reach;
  if (h < 0.06) return 3;
  if (h < 0.555) return 2;
  // Sleeves to the wrist in the T-pose (hand is the outer ~22 % of the reach).
  // Collar at the base of the neck (P2-1: at 0.815 the front read as a low
  // scoop with bare upper chest once the mesh was decimated).
  // The shoulder tops rise above the collar in the T-pose: clothed too, out to
  // the sleeve, anywhere wider than the neck and head (egg x radius ~0.09 reach).
  if ((h < 0.832 || (h < 0.88 && ax > 0.12)) && ax < 0.78) return 1;
  return 0;
}

// --- weld: one vertex per position ------------------------------------------
// The figure has no texture, so UV seams (where the source splits vertices) buy
// nothing and stop a simplifier. Every attribute is taken from the first source
// vertex at a position; seam twins share skin weights.
const firstOf = new Array(count).fill(-1);
canon.forEach((k, i) => { if (firstOf[k] < 0) firstOf[k] = i; });
const srcUvs = readAccessor(doc, bin, prim.attributes.TEXCOORD_0);
const srcJoints = readAccessor(doc, bin, prim.attributes.JOINTS_0);
const srcWeights = readAccessor(doc, bin, prim.attributes.WEIGHTS_0);
let faces = [];
for (let t = 0; t < triangles.length; t += 3) {
  const f = [canon[triangles[t]], canon[triangles[t + 1]], canon[triangles[t + 2]]];
  if (f[0] !== f[1] && f[1] !== f[2] && f[0] !== f[2]) faces.push(f);
}
const paints = point.map(paintClass);

// --- decimate to the STYLE budget (P2-1: family member <= 6k triangles) -------
// Quadric error, half-edge collapse (a vertex moves onto a neighbour, so every
// kept vertex keeps its own skin weights exactly). Never across a paint border
// (the clothes keep their edges), never moves an open boundary inward, never
// flips a face, keeps the mesh manifold (link condition).
const MAX_TRIS = Number(arg('max-tris', '5000'));
const sourceTris = faces.length;
if (faces.length > MAX_TRIS) faces = decimate(point, faces, paints, MAX_TRIS);

function decimate(P, F, cls, target) {
  const n = P.length;
  const alive = new Uint8Array(F.length).fill(1);
  const vf = Array.from({ length: n }, () => new Set());
  F.forEach((f, i) => f.forEach((v) => vf[v].add(i)));
  const Q = Array.from({ length: n }, () => new Float64Array(10));
  const addPlane = (q, nx, ny, nz, d, w) => {
    q[0] += w * nx * nx; q[1] += w * nx * ny; q[2] += w * nx * nz; q[3] += w * nx * d;
    q[4] += w * ny * ny; q[5] += w * ny * nz; q[6] += w * ny * d;
    q[7] += w * nz * nz; q[8] += w * nz * d; q[9] += w * d * d;
  };
  const evalQ = (a, b, [x, y, z]) => {
    let s = 0;
    const q = (i) => a[i] + b[i];
    s += q(0) * x * x + 2 * q(1) * x * y + 2 * q(2) * x * z + 2 * q(3) * x;
    s += q(4) * y * y + 2 * q(5) * y * z + 2 * q(6) * y;
    s += q(7) * z * z + 2 * q(8) * z + q(9);
    return s;
  };
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const faceNormal = (f) => cross(sub(P[f[1]], P[f[0]]), sub(P[f[2]], P[f[0]]));
  const edgeFaces = new Map();
  const ekey = (a, b) => (a < b ? a * n + b : b * n + a);
  F.forEach((f, i) => {
    const raw = faceNormal(f);
    const len = Math.hypot(...raw) || 1e-12;
    const nn = raw.map((v) => v / len);
    const d = -dot(nn, P[f[0]]);
    for (const v of f) addPlane(Q[v], nn[0], nn[1], nn[2], d, len / 2);
    for (let k = 0; k < 3; k++) {
      const key = ekey(f[k], f[(k + 1) % 3]);
      edgeFaces.set(key, (edgeFaces.get(key) || 0) + 1);
    }
  });
  // Open boundaries: a stiff plane through the edge, perpendicular to its face.
  const onBoundary = new Uint8Array(n);
  F.forEach((f) => {
    for (let k = 0; k < 3; k++) {
      const a = f[k];
      const b = f[(k + 1) % 3];
      if (edgeFaces.get(ekey(a, b)) !== 1) continue;
      onBoundary[a] = onBoundary[b] = 1;
      const e = sub(P[b], P[a]);
      const side = cross(e, faceNormal(f));
      const len = Math.hypot(...side) || 1e-12;
      const nn = side.map((v) => v / len);
      addPlane(Q[a], ...nn, -dot(nn, P[a]), 100 * dot(e, e));
      addPlane(Q[b], ...nn, -dot(nn, P[a]), 100 * dot(e, e));
    }
  });
  const neighbours = (v) => {
    const out = new Set();
    for (const fi of vf[v]) for (const w of F[fi]) if (w !== v) out.add(w);
    return out;
  };
  const version = new Int32Array(n);
  const dead = new Uint8Array(n);
  // Binary min-heap of [cost, from, to, version(from), version(to)].
  const heap = [];
  const push = (item) => {
    heap.push(item);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heap[p][0] <= heap[i][0]) break;
      [heap[p], heap[i]] = [heap[i], heap[p]];
      i = p;
    }
  };
  const pop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length > 0) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === i) break;
        [heap[m], heap[i]] = [heap[i], heap[m]];
        i = m;
      }
    }
    return top;
  };
  const offer = (u, v) => {
    if (cls[u] !== cls[v]) return;
    push([evalQ(Q[u], Q[v], P[v]), u, v, version[u], version[v]]);
  };
  for (let v = 0; v < n; v++) for (const w of neighbours(v)) offer(v, w);
  let live = F.length;
  while (live > target && heap.length > 0) {
    const [, u, v, vu, vv] = pop();
    if (dead[u] || dead[v] || version[u] !== vu || version[v] !== vv) continue;
    const nu = neighbours(u);
    if (!nu.has(v)) continue;
    // A boundary vertex may only slide along its boundary.
    if (onBoundary[u] && !(onBoundary[v] && edgeFaces.get(ekey(u, v)) === 1)) continue;
    // Link condition: the shared neighbours are exactly the shared faces' third corners.
    const nv = neighbours(v);
    let common = 0;
    for (const w of nu) if (nv.has(w)) common++;
    let shared = 0;
    for (const fi of vf[u]) if (F[fi].includes(v)) shared++;
    if (common !== shared) continue;
    // No face may flip or collapse to a sliver.
    let ok = true;
    for (const fi of vf[u]) {
      const f = F[fi];
      if (f.includes(v)) continue;
      const before = faceNormal(f);
      const after = faceNormal(f.map((w) => (w === u ? v : w)));
      const lb = Math.hypot(...before);
      const la = Math.hypot(...after);
      if (la < 1e-12 || dot(before, after) < 0.3 * lb * la) { ok = false; break; }
    }
    if (!ok) continue;
    for (const fi of [...vf[u]]) {
      const f = F[fi];
      if (f.includes(v)) {
        alive[fi] = 0;
        live--;
        for (const w of f) vf[w].delete(fi);
      } else {
        F[fi] = f.map((w) => (w === u ? v : w));
        vf[v].add(fi);
      }
    }
    vf[u].clear();
    dead[u] = 1;
    for (let k = 0; k < 10; k++) Q[v][k] += Q[u][k];
    if (onBoundary[u]) onBoundary[v] = 1;
    version[v]++;
    for (const w of neighbours(v)) {
      version[w]++;
      for (const x of neighbours(w)) offer(w, x), offer(x, w);
    }
  }
  return F.filter((_, i) => alive[i]);
}

// --- compact, normals ---------------------------------------------------------
const used = new Map();
const order = [];
for (const f of faces) for (const v of f) if (!used.has(v)) { used.set(v, order.length); order.push(v); }
// Shading normals come from a SMOOTHED copy of the body (plain Laplacian, the
// positions themselves stay put): the silhouette is the source's, but the
// superhero pecs, abs and biceps stop catching the light (STYLE §2.1, P2-1).
const NORMAL_SMOOTH = Number(arg('normal-smooth', '24'));
let shade = order.map((k) => [...point[k]]);
const near = order.map(() => new Set());
for (const f of faces) {
  const [a, b, c] = f.map((v) => used.get(v));
  near[a].add(b).add(c); near[b].add(a).add(c); near[c].add(a).add(b);
}
for (let pass = 0; pass < NORMAL_SMOOTH; pass++) {
  shade = shade.map((p, i) => {
    const mean = [0, 0, 0];
    for (const j of near[i]) for (let c = 0; c < 3; c++) mean[c] += shade[j][c] / near[i].size;
    return p.map((v, c) => v + 0.5 * (mean[c] - v));
  });
}
const fresh = order.map(() => [0, 0, 0]);
for (const f of faces) {
  const [a, b, c] = f.map((v) => used.get(v));
  const u = shade[b].map((x, k) => x - shade[a][k]);
  const w = shade[c].map((x, k) => x - shade[a][k]);
  const nn = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]];
  for (const k of [a, b, c]) for (let d = 0; d < 3; d++) fresh[k][d] += nn[d];
}
// Normals: the egg's own on the head, area-weighted face normals elsewhere.
const outPositions = order.map((k) => [...point[k]]);
const outNormals = order.map((k, i) => {
  if (headWeight[k] >= 1) return eggNormal(point[k]);
  const nn = fresh[i];
  const len = Math.hypot(...nn) || 1;
  return nn.map((v) => v / len);
});
const uvs = order.map((k) => srcUvs[firstOf[k]]);
const skinJoints = order.map((k) => srcJoints[firstOf[k]]);
const skinWeights = order.map((k) => srcWeights[firstOf[k]]);
const indexRows = faces.flatMap((f) => f.map((v) => [used.get(v)]));
const colours = order.map((k) => [...PAINT[PAINT_ORDER[paints[k]]], 255]);
positions.length = 0;
positions.push(...outPositions);
normals.length = 0;
normals.push(...outNormals);
console.log(`  welded ${count} vertices; ${sourceTris} -> ${faces.length} triangles (max ${MAX_TRIS})`);

const attributes = {
  POSITION: addAccessor(positions, 5126, 'VEC3'),
  NORMAL: addAccessor(normals, 5126, 'VEC3'),
  TEXCOORD_0: addAccessor(uvs, 5126, 'VEC2'),
  COLOR_0: addAccessor(colours, 5121, 'VEC4', { normalized: true }),
  JOINTS_0: addAccessor(skinJoints, doc.accessors[prim.attributes.JOINTS_0].componentType, 'VEC4'),
  WEIGHTS_0: addAccessor(skinWeights, doc.accessors[prim.attributes.WEIGHTS_0].componentType, 'VEC4',
    doc.accessors[prim.attributes.WEIGHTS_0].normalized ? { normalized: true } : {}),
};
const indices = addAccessor(indexRows, 5125, 'SCALAR');
const inverseBind = copyAccessor(skin.inverseBindMatrices);

for (const node of doc.nodes) {
  if (node.mesh === undefined) continue;
  if (node.mesh === bodyMesh) {
    node.mesh = 0;
    node.name = 'Figure';
  } else {
    delete node.mesh; // eyes, eyebrows: blank face (D2)
    delete node.skin;
    node.name = `${node.name}_removed`;
  }
}
const armature = doc.nodes.find((n) => n.name === 'Armature');
armature.scale = [100, 100, 100];

const out = {
  asset: { version: '2.0', generator: 'cashgrab figure_bake.mjs' },
  scene: 0,
  scenes: doc.scenes,
  nodes: doc.nodes,
  meshes: [{ name: 'Figure', primitives: [{ attributes, indices, material: 0 }] }],
  materials: [{ name: 'figure', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 0.55 } }],
  skins: [{ ...skin, inverseBindMatrices: inverseBind }],
  accessors,
  bufferViews: views,
  buffers: [{ byteLength: offset, uri: `figure_${bodyName}.bin` }],
};

fs.mkdirSync(OUT_DIR, { recursive: true });
const binary = Buffer.concat(chunks);
// Godot re-imports a .gltf only when the .gltf itself changes, not its .bin: carry
// the binary's hash in the JSON so a re-bake always reaches the game.
out.asset.extras = { bin_sha1: crypto.createHash('sha1').update(binary).digest('hex') };
fs.writeFileSync(path.join(OUT_DIR, `figure_${bodyName}.bin`), binary);
fs.writeFileSync(path.join(OUT_DIR, `figure_${bodyName}.gltf`), JSON.stringify(out));
const tris = indexRows.length / 3;
console.log(`figure_${bodyName}: ${positions.length} vertices, ${tris} triangles, ` +
  `height ${(top * 100).toFixed(1)}, pose ${poseName}[${poseFrame}], ${(offset / 1024).toFixed(0)} KB`);
