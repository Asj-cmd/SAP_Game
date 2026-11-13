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
// folder is gitignored, D10). Decimation to the STYLE budget is P2-1's job.

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
// Normals: the egg's own on the head, area-weighted face normals on the seam.
const fresh = point.map(() => [0, 0, 0]);
for (let t = 0; t < triangles.length; t += 3) {
  const [a, b, c] = [canon[triangles[t]], canon[triangles[t + 1]], canon[triangles[t + 2]]];
  const u = point[b].map((v, k) => v - point[a][k]);
  const v = point[c].map((x, k) => x - point[a][k]);
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  for (const k of [a, b, c]) for (let d = 0; d < 3; d++) fresh[k][d] += n[d];
}
positions.forEach((_, i) => {
  const k = canon[i];
  positions[i] = [...point[k]];
  if (headWeight[k] >= 1) normals[i] = eggNormal(point[k]);
  else if (headWeight[k] > 0) { const n = fresh[k]; const len = Math.hypot(...n) || 1; normals[i] = n.map((v) => v / len); }
});
console.log(`  head: egg centre ${centre.map((v) => (v * 100).toFixed(1)).join(', ')}, radii ${radii.map((v) => (v * 100).toFixed(1)).join(', ')} cm`);
const uvs = readAccessor(doc, bin, prim.attributes.TEXCOORD_0);
const skinJoints = readAccessor(doc, bin, prim.attributes.JOINTS_0);
const skinWeights = readAccessor(doc, bin, prim.attributes.WEIGHTS_0);
const indexRows = triangles.map((v) => [v]);
function paint([x, y]) {
  const h = y / top;
  const ax = Math.abs(x) / reach;
  if (h < 0.06) return PAINT.shoes;
  if (h < 0.555) return PAINT.trousers;
  // Sleeves to the wrist in the T-pose (hand is the outer ~22 % of the reach).
  if (h < 0.815 && ax < 0.78) return PAINT.shirt;
  return PAINT.bare;
}
const colours = positions.map((p) => [...paint(p), 255]);

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
