import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import {
  COLORS,
  WALL_HEIGHT,
  FLOOR_HEIGHT,
  DOOR_MAT_HEIGHT,
  DOOR_HEIGHT,
  WORLD_WIDTH,
  WORLD_HEIGHT,
  SURFACE_OVERLAP,
  teamSideAt,
} from "../constants";
import {
  ZONE_RECTS,
  WALLS,
  DOORS,
  CONNECTORS,
  BALCONIES,
  connectorSealsOwner,
  type Rect,
  type Team,
  type ZoneRect,
} from "../geometry/floorplan";
import { floorY } from "./world/HeightField";
import { buildStaircaseGeoms } from "./world/StaircaseBuilder";
import { buildWindows, type WindowOpening } from "./world/WindowBuilder";
import { surfaces, applyWorldUVs, type SurfaceMaps } from "./world/Textures";
import { buildTrimGeoms, buildPlinthGeoms, buildBalconyRails, buildFasciaGeoms } from "./world/TrimBuilder";
import { buildExteriorGeoms } from "./world/ExteriorBuilder";
import { TILE } from "../constants";

// Builds the 3D town-house from the same rect data the server validates against.
// Two merged meshes: a "walls" mesh (per-floor wall boxes, cut open where the
// windows are) and a "floor" mesh (per-floor tinted slabs with connector holes
// punched through, connector ramps/ladders, door mats, and a surrounding lawn).
// Colours are baked per-vertex so a single vertex-coloured material renders
// every rect. The roof over the top floor is added separately (RoofSystem).
//
// SURFACE RULE (see SURFACE_OVERLAP). Two faces that are coplanar AND overlap
// in area tie in the depth buffer, and the tie resolves differently as the
// camera moves - the shimmering the world showed at stair ends, doorway
// borders and the cellar mouth. Where that happens, one piece is pushed a
// little PAST the other so the losing face ends up buried inside solid
// geometry (stair treads into their neighbours, cellar treads into the pit
// walls, wall bases under the slab). Pieces that merely TILE - two floor slabs
// sharing an edge, a lintel sitting on its doorway - are left butted: their
// touching faces point opposite ways, so only one is ever rasterised and
// inflating them would create the very overlap being avoided.

// BoxGeometry lays its faces out in a fixed order, 4 vertices each: +x, -x, +y,
// -y, +z, -z. So the DOWN-facing face - a room's ceiling, seen from the storey
// below - is vertices 12..15, and can be painted separately from the rest.
const BOTTOM_FACE_VERTS = [12, 13, 14, 15];

function coloredBox(
  w: number,
  h: number,
  d: number,
  cx: number,
  cy: number,
  cz: number,
  colorHex: number,
  bottomColorHex?: number
) {
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
  if (bottomColorHex !== undefined) {
    const under = new THREE.Color(bottomColorHex);
    for (const i of BOTTOM_FACE_VERTS) {
      colors[i * 3] = under.r;
      colors[i * 3 + 1] = under.g;
      colors[i * 3 + 2] = under.b;
    }
  }
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  return geo;
}

// World (x, y) ground-plane rect -> Three.js (x, z) box, y is height/up.
export function rectToBox(
  r: Rect,
  height: number,
  yCenter: number,
  colorHex: number,
  bottomColorHex?: number
) {
  const w = r.x2 - r.x1;
  const d = r.y2 - r.y1;
  const cx = (r.x1 + r.x2) / 2;
  const cz = (r.y1 + r.y2) / 2;
  return coloredBox(w, height, d, cx, yCenter, cz, colorHex, bottomColorHex);
}

export interface Environment {
  meshes: THREE.Mesh[]; // everything to add to the scene
  occluders: THREE.Mesh[]; // what the chase camera pulls in against
}

// A merged, textured, world-UV'd mesh for one surface ROLE. Splitting by role
// is what lets plaster, floorboards, concrete and turf each have their own
// grain and tiling rate while the whole world still costs a handful of draw
// calls - one per role, not one per rect.
function roleMesh(
  geoms: THREE.BufferGeometry[],
  maps: SurfaceMaps,
  tileSize: number,
  extra: THREE.MeshStandardMaterialParameters
): THREE.Mesh | null {
  if (geoms.length === 0) return null;
  const merged = mergeGeometries(geoms, false);
  applyWorldUVs(merged, tileSize);
  const mesh = new THREE.Mesh(
    merged,
    new THREE.MeshStandardMaterial({
      vertexColors: true,
      map: maps.map,
      normalMap: maps.normalMap,
      roughnessMap: maps.roughnessMap,
      ...extra,
    })
  );
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
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

// The colour a room's CEILING should be - i.e. the underside of the slab that
// forms it. Keyed by the zone UNDER the slab, so the blue house looks up at
// blue and the orange house at orange; before this, every ceiling was painted
// in the colour of the ROOM ABOVE, which made house A's living room red.
// Outdoor zones have nothing underneath them and keep the default.
function ceilingColorBelow(zone: ZoneRect): number | undefined {
  const below = ZONE_RECTS.find(
    (z) => z.floor === zone.floor - 1 && z.xMin === zone.xMin && z.xMax === zone.xMax
  );
  if (!below) return undefined;
  return teamSideAt((below.xMin + below.xMax) / 2) === "B" ? COLORS.ceilingB : COLORS.ceilingA;
}

// A wall run cut into the pieces left once its window openings are removed:
// the full-height stretches between panes, plus the bands under the sill and
// over the head of each pane. Openings are z-ranges along a wall that runs in z
// (every windowed wall is a house side wall, thin in x - see WindowBuilder).
function wallPiecesWithOpenings(
  wall: Rect,
  base: number,
  height: number,
  openings: WindowOpening[]
): { rect: Rect; height: number; yCenter: number }[] {
  const top = base + height;
  if (openings.length === 0) return [{ rect: wall, height, yCenter: base + height / 2 }];

  // Every piece shares the wall's x extent, so the pieces are BUTTED, never
  // overlapped: overlapping them would put two identical outward faces on the
  // same plane and stripe the wall with shimmer at each seam.
  const sorted = [...openings].sort((a, b) => a.z1 - b.z1);
  const pieces: { rect: Rect; height: number; yCenter: number }[] = [];
  let cursor = wall.y1;
  for (const o of sorted) {
    if (o.z1 > cursor) {
      pieces.push({ rect: { x1: wall.x1, y1: cursor, x2: wall.x2, y2: o.z1 }, height, yCenter: base + height / 2 });
    }
    const band = { x1: wall.x1, y1: o.z1, x2: wall.x2, y2: o.z2 };
    const sillH = o.sillY - base;
    if (sillH > 0) pieces.push({ rect: band, height: sillH, yCenter: base + sillH / 2 });
    const headH = top - o.headY;
    if (headH > 0) pieces.push({ rect: band, height: headH, yCenter: top - headH / 2 });
    cursor = o.z2;
  }
  if (cursor < wall.y2) {
    pieces.push({
      rect: { x1: wall.x1, y1: cursor, x2: wall.x2, y2: wall.y2 },
      height,
      yCenter: base + height / 2,
    });
  }
  return pieces;
}

export function buildEnvironment(localTeam: Team): Environment {
  // Windows are resolved first: they tell the wall pass which stretches of
  // which walls to leave OUT, so the panes look through a real opening instead
  // of being glued onto solid plaster.
  const windows = buildWindows();

  // ---- walls: one box per per-floor wall rect (world-boundary walls, floor
  // undefined, sit at the ground floor as a map fence), minus window openings.
  //
  // NOTE: a sealed connector is deliberately NOT filled with a floor-to-ceiling
  // panel. Doing that put two huge dark columns in the middle of your own living
  // room, which read as unfinished and made the space confusing. Instead:
  //   - a sealed route UP keeps its visible staircase/ladder, which is itself
  //     the obstacle (see connectorSealsOwner), so nothing extra is drawn;
  //   - a sealed route DOWN gets its floor opening left SOLID below, so it reads
  //     as a closed hatch you simply walk over.
  const wallGeoms: THREE.BufferGeometry[] = [];
  WALLS.forEach((w, i) => {
    const base = floorY(w.floor ?? 0);
    // A wall stands ON its own slab (its underside is hidden by the slab, so
    // that end needs nothing) but runs a hair PAST the slab above: the two used
    // to end on exactly the same plane, both facing up, which shimmered in
    // every doorway threshold where the storey above has a gap rather than a
    // wall of its own.
    const bottom = base;
    const height = WALL_HEIGHT + SURFACE_OVERLAP;
    for (const piece of wallPiecesWithOpenings(w, bottom, height, windows.openings.get(i) ?? [])) {
      wallGeoms.push(rectToBox(piece.rect, piece.height, piece.yCenter, COLORS.wall));
    }
  });
  // LINTELS. A doorway is simply an absent stretch of wall, so until now every
  // door was a floor-to-ceiling slot - and because the slab above stops on the
  // wall's centre line, that slot ran right past the ceiling and showed open
  // sky in a band over each doorway. Filling from DOOR_HEIGHT up to the wall
  // top closes it and makes an opening read as a door rather than a missing
  // panel. Render-only: the gap in WALLS is what the simulation walks through,
  // and that is untouched.
  for (const door of DOORS) {
    const base = floorY(door.floor ?? 0);
    const lintelBottom = base + DOOR_HEIGHT;
    const lintelHeight = WALL_HEIGHT + SURFACE_OVERLAP - DOOR_HEIGHT;
    wallGeoms.push(
      rectToBox(door, lintelHeight, lintelBottom + lintelHeight / 2, COLORS.wall, COLORS.wallShade)
    );
  }
  // Window frames merge into the walls mesh; glass panes get their own mesh.
  wallGeoms.push(...windows.frameGeoms);
  const skin = surfaces();
  // Plaster: rough, barely reflective, but it still samples the environment map
  // so a wall facing the sky is cooler than one facing the ground.
  const wallsMesh = roleMesh(wallGeoms, skin.plaster, TILE.plaster, {
    roughness: 0.95,
    metalness: 0.0,
    envMapIntensity: 0.4,
    normalScale: new THREE.Vector2(0.6, 0.6),
  })!;

  // Real glass now that the wall behind it is actually open: barely tinted, lit
  // from both sides (you see it from inside and out), and never writing depth
  // so whatever is behind it draws normally.
  const glassMesh = new THREE.Mesh(
    mergeGeometries(windows.glassGeoms, false),
    new THREE.MeshStandardMaterial({
      color: COLORS.glass,
      transparent: true,
      opacity: 0.18,
      roughness: 0.04,
      metalness: 0.1,
      envMapIntensity: 2.2, // the sky reflection IS the window
      depthWrite: false,
      // FrontSide, not DoubleSide. A pane is a closed box, so back-face culling
      // leaves exactly ONE visible surface whichever side you view it from -
      // the near one. DoubleSide drew the far face too, blending the tint twice
      // and leaving two coincident translucent surfaces to sort against each
      // other every frame.
      side: THREE.FrontSide,
    })
  );

  // ---- floors, split by SURFACE ROLE. Which material a slab gets is decided
  // by what the room is, so a living room reads as boards, a basement as poured
  // concrete and the garden as turf - three different grains and three
  // different tiling rates, which is most of what tells the eye these are
  // different places rather than differently-coloured rectangles.
  const boardGeoms: THREE.BufferGeometry[] = []; // living rooms + bedrooms
  const concreteGeoms: THREE.BufferGeometry[] = []; // basements + foundations
  const turfGeoms: THREE.BufferGeometry[] = []; // garden, yards, lawn
  const paintedGeoms: THREE.BufferGeometry[] = []; // stairs, ladders, door mats

  // A connector cuts a hole in the slab of its HIGHER floor (the ceiling the
  // ramp rises through), wherever that slab overlaps the connector footprint.
  const holesForFloor = (zoneRect: Rect, floor: number): Rect[] =>
    CONNECTORS.filter((c) => Math.max(c.floorLow, c.floorHigh) === floor)
      // Your OWN basement openings stay closed: leaving the slab intact is the
      // lid you walk over, instead of a hole you can neither cross nor enter.
      .filter((c) => !(c.sealedFor === localTeam && !connectorSealsOwner(c)))
      .map((c) => intersectRect(c.rect, zoneRect))
      .filter((r): r is Rect => r !== null);

  const OUTDOOR = new Set(["garden", "backyardA", "backyardB"]);
  const bucketFor = (zoneId: string): THREE.BufferGeometry[] => {
    if (OUTDOOR.has(zoneId)) return turfGeoms;
    if (zoneId.startsWith("basement")) return concreteGeoms;
    return boardGeoms;
  };

  for (const zone of ZONE_RECTS) {
    const base = floorY(zone.floor);
    const yc = base - FLOOR_HEIGHT / 2;
    const ceiling = ceilingColorBelow(zone);
    const bucket = bucketFor(zone.id);
    if (zone.id === "garden") {
      // Two mown tones, so the lawn has a groundskeeper's stripe through it.
      const mid = (zone.xMin + zone.xMax) / 2;
      const left: Rect = { x1: zone.xMin, y1: zone.yMin, x2: mid, y2: zone.yMax };
      const right: Rect = { x1: mid, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
      bucket.push(rectToBox(left, FLOOR_HEIGHT, yc, COLORS.garden));
      bucket.push(rectToBox(right, FLOOR_HEIGHT, yc, COLORS.gardenAlt));
      continue;
    }
    const zoneRect: Rect = { x1: zone.xMin, y1: zone.yMin, x2: zone.xMax, y2: zone.yMax };
    for (const tile of rectMinusRects(zoneRect, holesForFloor(zoneRect, zone.floor))) {
      bucket.push(rectToBox(tile, FLOOR_HEIGHT, yc, zone.color, ceiling));
    }
  }

  // Flights, ladders and balconies are painted timber.
  paintedGeoms.push(...buildStaircaseGeoms());
  for (const b of BALCONIES) {
    paintedGeoms.push(rectToBox(b, FLOOR_HEIGHT, floorY(1) - FLOOR_HEIGHT / 2, COLORS.foundation));
  }
  // Door mats sit ON TOP of their own floor's slab. (They used to be placed at
  // the slab's UNDERSIDE, where they were invisible from the room AND exactly
  // coplanar with the slab's bottom face - the flickering "borders" seen around
  // the basement and backyard doorways.)
  for (const door of DOORS) {
    const base = floorY(door.floor ?? 0);
    paintedGeoms.push(rectToBox(door, DOOR_MAT_HEIGHT + SURFACE_OVERLAP, base + DOOR_MAT_HEIGHT / 2, COLORS.door));
  }

  // Lawn skirt AROUND the map, so its edge isn't a cliff into black void. It is
  // carved to the region OUTSIDE the world bounds on purpose: every in-bounds
  // zone already has its own floor slab, and a lawn sheet running under the
  // houses would slice through the basements (which sit a storey below it) and
  // show up as a false ceiling from inside.
  const LAWN_MARGIN = 2600;
  const lawn: Rect = { x1: -LAWN_MARGIN, y1: -LAWN_MARGIN, x2: WORLD_WIDTH + LAWN_MARGIN, y2: WORLD_HEIGHT + LAWN_MARGIN };
  const worldRect: Rect = { x1: 0, y1: 0, x2: WORLD_WIDTH, y2: WORLD_HEIGHT };
  for (const tile of rectMinusRects(lawn, [worldRect])) {
    turfGeoms.push(rectToBox(tile, FLOOR_HEIGHT, -FLOOR_HEIGHT - FLOOR_HEIGHT / 2, COLORS.ground));
  }

  // ---- everything beyond the boundary wall: coping and piers on the wall
  // itself, hedging outside it, then a treeline and mown patches across the
  // skirt. It rides in the SAME two buckets as the rest of the world, so all of
  // it merges into meshes that already exist and adds no draw calls.
  const exterior = buildExteriorGeoms();
  paintedGeoms.push(...exterior.painted);
  turfGeoms.push(...exterior.turf);

  const boardsMesh = roleMesh(boardGeoms, skin.floorboards, TILE.floorboards, {
    roughness: 0.55,
    metalness: 0.02,
    envMapIntensity: 0.45,
    normalScale: new THREE.Vector2(0.85, 0.85),
  });
  const concreteMesh = roleMesh(concreteGeoms, skin.concrete, TILE.concrete, {
    roughness: 0.92,
    metalness: 0.0,
    envMapIntensity: 0.35,
    normalScale: new THREE.Vector2(0.7, 0.7),
  });
  const turfMesh = roleMesh(turfGeoms, skin.turf, TILE.turf, {
    roughness: 0.98,
    metalness: 0.0,
    envMapIntensity: 0.5,
    normalScale: new THREE.Vector2(1.1, 1.1),
  });
  // ---- architectural trim. Skirting, cornices and architraves are what make a
  // room read as a room; the plinth, fascia and balcony rails do the same for
  // the exterior. All derived from the same rects the simulation uses, so none
  // of it can drift from the floor plan or be collided with.
  const footprints: Rect[] = (["bedroomB", "bedroomA"] as const)
    .map((id) => ZONE_RECTS.find((z) => z.id === id))
    .filter((z): z is ZoneRect => z !== undefined)
    .map((z) => ({ x1: z.xMin, y1: z.yMin, x2: z.xMax, y2: z.yMax }));
  paintedGeoms.push(...buildTrimGeoms());
  paintedGeoms.push(...buildBalconyRails([...BALCONIES]));
  concreteGeoms.push(...buildPlinthGeoms(footprints));
  paintedGeoms.push(...buildFasciaGeoms(footprints));

  const paintedMesh = roleMesh(paintedGeoms, skin.painted, TILE.painted, {
    roughness: 0.48,
    metalness: 0.03,
    envMapIntensity: 0.55,
    normalScale: new THREE.Vector2(0.5, 0.5),
  });

  const solids = [wallsMesh, boardsMesh, concreteMesh, turfMesh, paintedMesh].filter(
    (m): m is THREE.Mesh => m !== null
  );
  // Glass is left OUT of the occluder list: it is translucent, so pulling the
  // chase camera in against a window would be wrong.
  return { meshes: [...solids, glassMesh], occluders: solids };
}
