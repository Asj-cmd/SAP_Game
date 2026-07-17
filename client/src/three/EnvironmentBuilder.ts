import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import {
  COLORS,
  WALL_HEIGHT,
  FLOOR_HEIGHT,
  FLOOR_RISE,
  DOOR_MAT_HEIGHT,
  DOOR_HEIGHT,
  DOOR_JAMB,
  WORLD_WIDTH,
  WORLD_HEIGHT,
  teamSideAt,
} from "../constants";
import { ZONE_RECTS, WALLS, DOORS, getZoneAt, type Door, type Rect, type Team } from "../geometry/floorplan";
import { buildWindows } from "./world/WindowBuilder";
import { zoneBaseHeight, heightAt, STAIR_CORRIDORS, corridorBBox } from "./world/HeightField";
import { buildWallBoxes } from "./world/WallHeightBuilder";
import { buildStaircaseGeoms } from "./world/StaircaseBuilder";

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
// Exported for WindowBuilder, which needs the same rect->box conversion to
// split a wall rect around an opening.
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
  // Real see-through window panes (Phase 3) - a separate mesh since it needs
  // its own translucent material, not the walls' opaque vertex-colored one.
  windowGlassMesh: THREE.Mesh;
  // Collider rects for movement collision (Milestone B): every solid wall plus
  // whichever doors are sealed for the local team. Deliberately the ORIGINAL
  // WALLS rects, not WindowBuilder's split replacements - a window changes
  // what you can see, never what you can walk through.
  colliderRects: Rect[];
}

// Ground height the CLOSED DOOR PANEL sits on: the local height right at the
// door line's center. For flat doors this is always 0 (unchanged from
// before); for a sealed stair door it's the ramp's mid-height at that exact
// line, which is where the door literally sits along the stairs.
function doorBase(door: Door): number {
  const cx = (door.x1 + door.x2) / 2;
  const cy = (door.y1 + door.y2) / 2;
  return heightAt(cx, cy);
}

// Ground height the door's FRAME (lintel + jambs) sits on: the HIGHER of the
// two zones the door connects. A flat door's two sides are the same height,
// so this is identical to doorBase there. A stair door's frame, unlike the
// panel, spans the *entire* corridor width as one fixed-height opening - if
// it sat at the door line's mid-ramp height (doorBase), the lintel would
// pinch a climbing character's headroom on the raised side of the ramp
// (verified: the chase camera's sightline clips through it there). Framing
// at the taller side's height guarantees DOOR_HEIGHT of clearance everywhere
// along the ramp, at the cost of the jambs looking a little deep on the
// lower side - not a hand-authored exception, just probing outward past
// RAMP_EXTENT so the samples land in the two flat zones on either side.
function doorFrameBase(door: Door): number {
  const cx = (door.x1 + door.x2) / 2;
  const cy = (door.y1 + door.y2) / 2;
  const PROBE = 150; // scaled units, past any corridor's RAMP_EXTENT (105)
  const heights = [
    zoneBaseHeight(getZoneAt(cx - PROBE, cy)),
    zoneBaseHeight(getZoneAt(cx + PROBE, cy)),
    zoneBaseHeight(getZoneAt(cx, cy - PROBE)),
    zoneBaseHeight(getZoneAt(cx, cy + PROBE)),
  ];
  return Math.max(...heights);
}

// Wooden trim around a door opening: a lintel filling the gap from DOOR_HEIGHT
// up to the wall top, plus a full-height jamb post just past each end of the
// gap. The door rect is slightly "proud" of the wall's thickness on purpose
// (it always was, for the 2D door mats), so the trim visibly wraps the wall.
// `base` offsets every piece vertically - 0 for a flat door, the door line's
// local ground height for a stair door.
function doorFrameGeoms(door: Door, base: number): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];
  const lintelHeight = WALL_HEIGHT - DOOR_HEIGHT;
  // Trim picks up the owning house's team hue (west half = B, east = A) so
  // each house reads as its family's from a distance.
  const frameColor = teamSideAt((door.x1 + door.x2) / 2) === "B" ? COLORS.doorFrameB : COLORS.doorFrameA;
  geoms.push(rectToBox(door, lintelHeight, base + DOOR_HEIGHT + lintelHeight / 2, frameColor));

  const gapRunsAlongY = door.x2 - door.x1 < door.y2 - door.y1;
  const jambA: Rect = gapRunsAlongY
    ? { x1: door.x1, y1: door.y1 - DOOR_JAMB, x2: door.x2, y2: door.y1 }
    : { x1: door.x1 - DOOR_JAMB, y1: door.y1, x2: door.x1, y2: door.y2 };
  const jambB: Rect = gapRunsAlongY
    ? { x1: door.x1, y1: door.y2, x2: door.x2, y2: door.y2 + DOOR_JAMB }
    : { x1: door.x2, y1: door.y1, x2: door.x2 + DOOR_JAMB, y2: door.y2 };
  geoms.push(rectToBox(jambA, WALL_HEIGHT, base + WALL_HEIGHT / 2, frameColor));
  geoms.push(rectToBox(jambB, WALL_HEIGHT, base + WALL_HEIGHT / 2, frameColor));
  return geoms;
}

// Rect `zone` minus every rect in `holes` (only the parts of a hole that
// actually overlap zone matter) - a plain grid decomposition: cut along every
// hole edge that falls strictly inside the zone, then keep every resulting
// cell whose center isn't inside any hole. Small numbers of rects (a
// bedroom's 2 stair holes), so the O(cells * holes) cost is negligible.
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

// Bedroom footprints (house B + mirrored house A) need a solid fill from
// grade up to FLOOR_RISE underneath their floor slab, or the raised wing
// would read as floating on stilts - the retaining walls close the sides,
// this closes the underside. Not hand-authored per house: derived from
// ZONE_RECTS' own bedroomB/bedroomA rects, the same data the floor slabs
// use - MINUS whichever stair corridors cut through that same footprint (the
// bedroom's own interior + exterior stair openings), or the "solid fill"
// would literally wall off the stairwell it's supposed to leave open.
function foundationGeoms(): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];
  for (const zone of ZONE_RECTS) {
    if (zone.id !== "bedroomB" && zone.id !== "bedroomA") continue;
    const zoneRect: Rect = { x1: zone.xMin, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
    const holes = STAIR_CORRIDORS.map((c) => intersectRect(corridorBBox(c), zoneRect)).filter(
      (r): r is Rect => r !== null
    );
    for (const tile of rectMinusRects(zoneRect, holes)) {
      geoms.push(rectToBox(tile, FLOOR_RISE, FLOOR_RISE / 2, COLORS.foundation));
    }
  }
  return geoms;
}

// A door counts as a "stair door" (ramped, no floor mat, furniture positioned
// at the ramp's local height) exactly when it's sealed for someone -
// geometry/floorplan.ts's DOORS table marks precisely the 4-per-house
// bedroom/basement doors this way; every other door (living<->garden,
// living<->backyard) is flat and unsealed for both teams.
function isStairDoor(d: Door): boolean {
  return d.sealedFor !== undefined;
}

export function buildEnvironment(localTeam: Team): Environment {
  const sealedDoors = DOORS.filter((d) => d.sealedFor === localTeam);
  const flatDoors = DOORS.filter((d) => !isStairDoor(d));

  // ---- walls: WALLS (minus whichever rects have a window punched into them)
  // + a wooden frame around every door AND window opening + this team's own
  // sealed doors filled with a closed door panel (instead of blank wall, so a
  // "door that won't open for you" reads as exactly that) ----
  const windows = buildWindows();
  const wallGeoms = WALLS.filter((_, i) => !windows.splitWallIndices.has(i)).flatMap((r) =>
    buildWallBoxes(r, COLORS.wall)
  );
  const frameGeoms = [...DOORS.flatMap((d) => doorFrameGeoms(d, doorFrameBase(d))), ...windows.frameGeoms];
  const sealedGeoms = sealedDoors.map((r) => rectToBox(r, DOOR_HEIGHT, doorBase(r) + DOOR_HEIGHT / 2, COLORS.doorPanel));
  const wallsMerged = mergeGeometries(
    [...wallGeoms, ...windows.wallReplacementGeoms, ...frameGeoms, ...sealedGeoms, ...foundationGeoms()],
    false
  );
  const wallsMesh = new THREE.Mesh(wallsMerged, new THREE.MeshStandardMaterial({ vertexColors: true }));
  wallsMesh.castShadow = true;
  wallsMesh.receiveShadow = true;

  const glassMerged = mergeGeometries(windows.glassGeoms, false);
  const windowGlassMesh = new THREE.Mesh(
    glassMerged,
    new THREE.MeshStandardMaterial({
      color: COLORS.glass,
      transparent: true,
      opacity: 0.35,
      roughness: 0.1,
      metalness: 0,
      depthWrite: false,
    })
  );

  // ---- floor: per-zone tinted slabs (garden split into its two cosmetic
  // halves, each at its zone's base height) + door mats for every FLAT door
  // open to this team + rendered staircases inside every stair corridor ----
  //
  // Every zone slab is carved (rectMinusRects) wherever a stair corridor's
  // footprint overlaps it: the corridor's own step geometry already covers
  // that exact footprint end-to-end (see buildStaircaseGeoms), so leaving the
  // flat slab underneath would coincide with the corridor's own end steps -
  // same top face, same height, a textbook z-fight.
  const floorGeoms: THREE.BufferGeometry[] = [];
  const zoneHoles = (zoneRect: Rect) =>
    STAIR_CORRIDORS.map((c) => intersectRect(corridorBBox(c), zoneRect)).filter((r): r is Rect => r !== null);
  for (const zone of ZONE_RECTS) {
    const base = zoneBaseHeight(zone.id);
    if (zone.id === "garden") {
      const mid = (zone.xMin + zone.xMax) / 2;
      const left: Rect = { x1: zone.xMin, y1: zone.yMin, x2: mid, y2: zone.yMax };
      const right: Rect = { x1: mid, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
      for (const tile of rectMinusRects(left, zoneHoles(left))) {
        floorGeoms.push(rectToBox(tile, FLOOR_HEIGHT, base - FLOOR_HEIGHT / 2, COLORS.garden));
      }
      for (const tile of rectMinusRects(right, zoneHoles(right))) {
        floorGeoms.push(rectToBox(tile, FLOOR_HEIGHT, base - FLOOR_HEIGHT / 2, COLORS.gardenAlt));
      }
    } else {
      const zoneRect: Rect = { x1: zone.xMin, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
      for (const tile of rectMinusRects(zoneRect, zoneHoles(zoneRect))) {
        floorGeoms.push(rectToBox(tile, FLOOR_HEIGHT, base - FLOOR_HEIGHT / 2, zone.color));
      }
    }
  }
  for (const door of flatDoors) {
    floorGeoms.push(rectToBox(door, DOOR_MAT_HEIGHT, -FLOOR_HEIGHT + DOOR_MAT_HEIGHT / 2, COLORS.door));
  }
  floorGeoms.push(...buildStaircaseGeoms());
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
    windowGlassMesh,
    colliderRects: [...WALLS, ...sealedDoors],
  };
}
