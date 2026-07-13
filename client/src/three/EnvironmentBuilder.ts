import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import {
  COLORS,
  WALL_HEIGHT,
  FLOOR_HEIGHT,
  DOOR_MAT_HEIGHT,
  DOOR_HEIGHT,
  DOOR_JAMB,
  WORLD_WIDTH,
  WORLD_HEIGHT,
} from "../constants";
import { ZONE_RECTS, WALLS, DOORS, type Door, type Rect, type Team } from "../geometry/floorplan";

// Builds the 3D floor plan from the same rect data the server validates against.
// Two draw calls total: one merged "walls" mesh (extruded wall boxes, wooden
// door frames around every opening, and the current team's own sealed doors
// rendered as closed door panels - what you see must match what you can walk
// through) and one merged "floor" mesh (per-zone tinted floor slabs, door mats
// for every door NOT sealed to you, and a lawn plane surrounding the whole
// map). Colors are baked per-vertex so a single vertex-colored material can
// render every rect.

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

// Wooden trim around a door opening: a lintel filling the gap from DOOR_HEIGHT
// up to the wall top, plus a full-height jamb post just past each end of the
// gap. The door rect is slightly "proud" of the wall's thickness on purpose
// (it always was, for the 2D door mats), so the trim visibly wraps the wall.
function doorFrameGeoms(door: Door): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];
  const lintelHeight = WALL_HEIGHT - DOOR_HEIGHT;
  geoms.push(rectToBox(door, lintelHeight, DOOR_HEIGHT + lintelHeight / 2, COLORS.doorFrame));

  const gapRunsAlongY = door.x2 - door.x1 < door.y2 - door.y1;
  const jambA: Rect = gapRunsAlongY
    ? { x1: door.x1, y1: door.y1 - DOOR_JAMB, x2: door.x2, y2: door.y1 }
    : { x1: door.x1 - DOOR_JAMB, y1: door.y1, x2: door.x1, y2: door.y2 };
  const jambB: Rect = gapRunsAlongY
    ? { x1: door.x1, y1: door.y2, x2: door.x2, y2: door.y2 + DOOR_JAMB }
    : { x1: door.x2, y1: door.y1, x2: door.x2 + DOOR_JAMB, y2: door.y2 };
  geoms.push(rectToBox(jambA, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.doorFrame));
  geoms.push(rectToBox(jambB, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.doorFrame));
  return geoms;
}

export function buildEnvironment(localTeam: Team): Environment {
  const sealedDoors = DOORS.filter((d) => d.sealedFor === localTeam);
  const openDoors = DOORS.filter((d) => d.sealedFor !== localTeam);

  // ---- walls: WALLS + a wooden frame around every opening + this team's own
  // sealed doors filled with a closed door panel (instead of blank wall, so a
  // "door that won't open for you" reads as exactly that) ----
  const wallGeoms = WALLS.map((r) => rectToBox(r, WALL_HEIGHT, WALL_HEIGHT / 2, COLORS.wall));
  const frameGeoms = DOORS.flatMap((d) => doorFrameGeoms(d));
  const sealedGeoms = sealedDoors.map((r) => rectToBox(r, DOOR_HEIGHT, DOOR_HEIGHT / 2, COLORS.doorPanel));
  const wallsMerged = mergeGeometries([...wallGeoms, ...frameGeoms, ...sealedGeoms], false);
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
  // Lawn plane extending past the world bounds on every side, sitting just
  // below the zone slabs, so the map edge isn't a cliff into black void.
  const LAWN_MARGIN = 600;
  floorGeoms.push(
    rectToBox(
      { x1: -LAWN_MARGIN, y1: -LAWN_MARGIN, x2: WORLD_WIDTH + LAWN_MARGIN, y2: WORLD_HEIGHT + LAWN_MARGIN },
      FLOOR_HEIGHT,
      -FLOOR_HEIGHT - FLOOR_HEIGHT / 2,
      COLORS.ground
    )
  );
  const floorMerged = mergeGeometries(floorGeoms, false);
  const floorMesh = new THREE.Mesh(floorMerged, new THREE.MeshStandardMaterial({ vertexColors: true }));
  floorMesh.receiveShadow = true;

  return {
    wallsMesh,
    floorMesh,
    colliderRects: [...WALLS, ...sealedDoors],
  };
}
