import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import { COLORS, WALL_HEIGHT, FLOOR_HEIGHT, DOOR_MAT_HEIGHT } from "../constants";
import { ZONE_RECTS, WALLS, DOORS, type Rect, type Team } from "../geometry/floorplan";

// Builds the 3D floor plan from the same rect data the server validates against.
// Two draw calls total: one merged "walls" mesh (extruded boxes, plus the
// current team's own sealed doors rendered as solid wall - what you see must
// match what you can walk through) and one merged "floor" mesh (per-zone tinted
// floor slabs + door mats for every door NOT sealed to you). Colors are baked
// per-vertex so a single vertex-colored material can render every rect.

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
function rectToBox(r: Rect, height: number, yCenter: number, colorHex: number) {
  const w = r.x2 - r.x1;
  const d = r.y2 - r.y1;
  const cx = (r.x1 + r.x2) / 2;
  const cz = (r.y1 + r.y2) / 2;
  return coloredBox(w, height, d, cx, yCenter, cz, colorHex);
}

export interface Environment {
  wallsMesh: THREE.Mesh;
  floorMesh: THREE.Mesh;
  // Collider rects for movement collision (Milestone B): every solid wall plus
  // whichever doors are sealed for the local team.
  colliderRects: Rect[];
}

export function buildEnvironment(localTeam: Team): Environment {
  const sealedDoors = DOORS.filter((d) => d.sealedFor === localTeam);
  const openDoors = DOORS.filter((d) => d.sealedFor !== localTeam);

  // ---- walls: WALLS + this team's own sealed doors ----
  const wallGeoms = WALLS.map((r) => rectToBox(r, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.wall));
  const sealedGeoms = sealedDoors.map((r) => rectToBox(r, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.wall));
  const wallsMerged = mergeGeometries([...wallGeoms, ...sealedGeoms], false);
  const wallsMesh = new THREE.Mesh(wallsMerged, new THREE.MeshStandardMaterial({ vertexColors: true }));

  // ---- floor: per-zone tinted slabs (garden split into its two cosmetic
  // halves) + door mats for every door open to this team ----
  const floorGeoms: THREE.BufferGeometry[] = [];
  for (const zone of ZONE_RECTS) {
    if (zone.id === "garden") {
      const mid = (zone.xMin + zone.xMax) / 2;
      floorGeoms.push(
        rectToBox({ x1: zone.xMin, y1: zone.yMin, x2: mid, y2: zone.yMax }, FLOOR_HEIGHT, -FLOOR_HEIGHT / 2, COLORS.garden)
      );
      floorGeoms.push(
        rectToBox(
          { x1: mid, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax },
          FLOOR_HEIGHT,
          -FLOOR_HEIGHT / 2,
          COLORS.gardenAlt
        )
      );
    } else {
      floorGeoms.push(
        rectToBox({ x1: zone.xMin, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax }, FLOOR_HEIGHT, -FLOOR_HEIGHT / 2, zone.color)
      );
    }
  }
  for (const door of openDoors) {
    floorGeoms.push(rectToBox(door, DOOR_MAT_HEIGHT, -FLOOR_HEIGHT + DOOR_MAT_HEIGHT / 2, COLORS.door));
  }
  const floorMerged = mergeGeometries(floorGeoms, false);
  const floorMesh = new THREE.Mesh(floorMerged, new THREE.MeshStandardMaterial({ vertexColors: true }));
  floorMesh.receiveShadow = true;

  return {
    wallsMesh,
    floorMesh,
    colliderRects: [...WALLS, ...sealedDoors],
  };
}
