import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import {
  COLORS,
  WALL_HEIGHT,
  FLOOR_HEIGHT,
  DOOR_MAT_HEIGHT,
  WORLD_WIDTH,
  WORLD_HEIGHT,
} from "../constants";
import { ZONE_RECTS, WALLS, DOORS, CONNECTORS, type Rect, type Team } from "../geometry/floorplan";
import { floorY } from "./world/HeightField";
import { buildStaircaseGeoms } from "./world/StaircaseBuilder";

// Builds the 3D town-house from the same rect data the server validates against.
// Two merged meshes: a "walls" mesh (per-floor wall boxes + the local team's own
// sealed-connector panels so a staircase you can't use reads as a closed shaft)
// and a "floor" mesh (per-floor tinted slabs with connector holes punched
// through, connector ramps, ground-floor door mats, and a surrounding lawn).
// Colours are baked per-vertex so a single vertex-coloured material renders
// every rect. The roof lid over the top floor is added separately (RoofSystem).

function coloredBox(w: number, h: number, d: number, cx: number, cy: number, cz: number, colorHex: number) {
  const geo = new THREE.BoxGeometry(w, h, d);
  geo.translate(cx, cy, cz);
  const color = new THREE.Color(colorHex);
  const count = geo.attributes.position.count;
  const colors = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    colors[i * 3] = color.r;
    colors[i * 3 + 1] = color.g;
    colors[i * 3 + 2] = color.b;
  }
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  return geo;
}

// World (x, y) ground-plane rect -> Three.js (x, z) box, y is height/up.
export function rectToBox(r: Rect, height: number, yCenter: number, colorHex: number) {
  const w = r.x2 - r.x1;
  const d = r.y2 - r.y1;
  const cx = (r.x1 + r.x2) / 2;
  const cz = (r.y1 + r.y2) / 2;
  return coloredBox(w, height, d, cx, yCenter, cz, colorHex);
}

export interface Environment {
  wallsMesh: THREE.Mesh;
  floorMesh: THREE.Mesh;
}

// Rect `zone` minus every rect in `holes` - a plain grid decomposition (cut
// along every hole edge strictly inside the zone, keep cells whose centre isn't
// in a hole). Used to punch stairwell openings out of the slab above a ramp.
function rectMinusRects(zone: Rect, holes: Rect[]): Rect[] {
  const xs = new Set<number>([zone.x1, zone.x2]);
  const ys = new Set<number>([zone.y1, zone.y2]);
  for (const h of holes) {
    if (h.x1 > zone.x1 && h.x1 < zone.x2) xs.add(h.x1);
    if (h.x2 > zone.x1 && h.x2 < zone.x2) xs.add(h.x2);
    if (h.y1 > zone.y1 && h.y1 < zone.y2) ys.add(h.y1);
    if (h.y2 > zone.y1 && h.y2 < zone.y2) ys.add(h.y2);
  }
  const xArr = [...xs].sort((a, b) => a - b);
  const yArr = [...ys].sort((a, b) => a - b);
  const tiles: Rect[] = [];
  for (let i = 0; i < xArr.length - 1; i++) {
    for (let j = 0; j < yArr.length - 1; j++) {
      const cx = (xArr[i] + xArr[i + 1]) / 2;
      const cy = (yArr[j] + yArr[j + 1]) / 2;
      const inHole = holes.some((h) => cx > h.x1 && cx < h.x2 && cy > h.y1 && cy < h.y2);
      if (!inHole) tiles.push({ x1: xArr[i], y1: yArr[j], x2: xArr[i + 1], y2: yArr[j + 1] });
    }
  }
  return tiles;
}

function intersectRect(a: Rect, b: Rect): Rect | null {
  const x1 = Math.max(a.x1, b.x1);
  const y1 = Math.max(a.y1, b.y1);
  const x2 = Math.min(a.x2, b.x2);
  const y2 = Math.min(a.y2, b.y2);
  if (x2 <= x1 || y2 <= y1) return null;
  return { x1, y1, x2, y2 };
}

export function buildEnvironment(localTeam: Team): Environment {
  // ---- walls: one box per per-floor wall rect (world-boundary walls, floor
  // undefined, sit at the ground floor as a map fence) + the local team's own
  // sealed connectors filled as a closed shaft panel so "stairs you can't use"
  // reads as a wall.
  const wallGeoms: THREE.BufferGeometry[] = [];
  for (const w of WALLS) {
    const base = floorY(w.floor ?? 0);
    wallGeoms.push(rectToBox(w, WALL_HEIGHT, base + WALL_HEIGHT / 2, COLORS.wall));
  }
  for (const c of CONNECTORS) {
    if (c.sealedFor !== localTeam) continue;
    // Panel on the owner's ground floor over the connector footprint.
    wallGeoms.push(rectToBox(c.rect, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.doorPanel));
  }
  const wallsMesh = new THREE.Mesh(mergeGeometries(wallGeoms, false), new THREE.MeshStandardMaterial({ vertexColors: true }));
  wallsMesh.castShadow = true;
  wallsMesh.receiveShadow = true;

  // ---- floor: per-zone slabs (carved where a connector ramp punches through
  // the slab above it) + connector ramps + ground door mats + lawn.
  const floorGeoms: THREE.BufferGeometry[] = [];
  // A connector cuts a hole in the slab of its HIGHER floor (the ceiling the
  // ramp rises through), wherever that slab overlaps the connector footprint.
  const holesForFloor = (zoneRect: Rect, floor: number): Rect[] =>
    CONNECTORS.filter((c) => Math.max(c.floorLow, c.floorHigh) === floor)
      .map((c) => intersectRect(c.rect, zoneRect))
      .filter((r): r is Rect => r !== null);

  for (const zone of ZONE_RECTS) {
    const base = floorY(zone.floor);
    const yc = base - FLOOR_HEIGHT / 2;
    if (zone.id === "garden") {
      const mid = (zone.xMin + zone.xMax) / 2;
      const left: Rect = { x1: zone.xMin, y1: zone.yMin, x2: mid, y2: zone.yMax };
      const right: Rect = { x1: mid, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
      floorGeoms.push(rectToBox(left, FLOOR_HEIGHT, yc, COLORS.garden));
      floorGeoms.push(rectToBox(right, FLOOR_HEIGHT, yc, COLORS.gardenAlt));
      continue;
    }
    const zoneRect: Rect = { x1: zone.xMin, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
    for (const tile of rectMinusRects(zoneRect, holesForFloor(zoneRect, zone.floor))) {
      floorGeoms.push(rectToBox(tile, FLOOR_HEIGHT, yc, zone.color));
    }
  }
  floorGeoms.push(...buildStaircaseGeoms());
  for (const door of DOORS) {
    floorGeoms.push(rectToBox(door, DOOR_MAT_HEIGHT, -FLOOR_HEIGHT + DOOR_MAT_HEIGHT / 2, COLORS.door));
  }
  // Lawn plane past the world bounds, just below the ground slabs.
  const LAWN_MARGIN = 600;
  const lawn: Rect = { x1: -LAWN_MARGIN, y1: -LAWN_MARGIN, x2: WORLD_WIDTH + LAWN_MARGIN, y2: WORLD_HEIGHT + LAWN_MARGIN };
  floorGeoms.push(rectToBox(lawn, FLOOR_HEIGHT, -FLOOR_HEIGHT - FLOOR_HEIGHT / 2, COLORS.ground));

  const floorMesh = new THREE.Mesh(mergeGeometries(floorGeoms, false), new THREE.MeshStandardMaterial({ vertexColors: true }));
  floorMesh.receiveShadow = true;

  return { wallsMesh, floorMesh };
}
