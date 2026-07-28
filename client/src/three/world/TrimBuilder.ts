import * as THREE from "three";
import { COLORS, WALL_HEIGHT, DOOR_HEIGHT, SURFACE_OVERLAP, teamSideAt, STORY_HEIGHT } from "../../constants";
import { WALLS, DOORS, type FloorRect, type Rect } from "../../geometry/floorplan";
import { rectToBox } from "../EnvironmentBuilder";
import { floorY } from "./HeightField";

// Architectural trim: skirting boards, door architraves and ceiling cornices.
//
// This is the cheapest thing that stops a room reading as a box. A real room is
// never a bare plane meeting another bare plane - there is always a moulding at
// the junction, and the eye uses those horizontal lines to judge the height of
// the space and the distance to the wall. Without them a wall/floor junction is
// a single hard edge with no thickness, which is exactly what "untextured
// primitive" looks like.
//
// Every piece is derived from the SAME wall and doorway rects the simulation
// uses, so this adds nothing the player can collide with and cannot drift out
// of step with the floor plan. It is drawn as one more merged mesh.

const SKIRT_HEIGHT = 13; // tall enough to read across a room, short enough to be trim
const SKIRT_PROUD = 2.4; // how far it stands off the wall face
const CORNICE_HEIGHT = 8;
const CORNICE_PROUD = 3.2;
const ARCH_WIDTH = 7; // architrave band around a doorway
const ARCH_PROUD = 2.8;

// Grow a rect outward on its THIN axis only - a wall run stays the same length
// but gains a lip standing proud of its face.
function proudOfWall(w: Rect, by: number): Rect {
  const thinInX = w.x2 - w.x1 < w.y2 - w.y1;
  return thinInX
    ? { x1: w.x1 - by, y1: w.y1, x2: w.x2 + by, y2: w.y2 }
    : { x1: w.x1, y1: w.y1 - by, x2: w.x2, y2: w.y2 + by };
}

function trimColor(x: number): number {
  return teamSideAt(x) === "B" ? COLORS.doorFrameB : COLORS.doorFrameA;
}

// Interior walls only. The world-boundary fence has no rooms behind it, and
// basement walls are below grade where trim would never have been fitted.
function isRoomWall(w: FloorRect): boolean {
  return w.floor !== undefined;
}

export function buildTrimGeoms(): THREE.BufferGeometry[] {
  const geoms: THREE.BufferGeometry[] = [];

  for (const w of WALLS) {
    if (!isRoomWall(w)) continue;
    const base = floorY(w.floor!);
    const colour = trimColor((w.x1 + w.x2) / 2);

    // Skirting: sits ON the floor, running the full length of the wall, and is
    // sunk slightly INTO the wall so the two never share a plane.
    geoms.push(
      rectToBox(
        proudOfWall(w, SKIRT_PROUD),
        SKIRT_HEIGHT,
        base + SKIRT_HEIGHT / 2 - SURFACE_OVERLAP,
        colour
      )
    );

    // Cornice: the same idea at the ceiling line. It reads as the room having a
    // finished top rather than the wall simply stopping.
    //
    // It stops SHORT of the wall top rather than level with it. Both used to end
    // on exactly the same plane, which put two up-facing surfaces at one depth
    // across the entire wall network on every floor - the single largest
    // depth-buffer tie in the world, and the shimmer seen down into the basement
    // and along every ceiling line. The wall now ends SURFACE_OVERLAP below the
    // floor above, and the cornice another SURFACE_OVERLAP below that, so no two
    // horizontal surfaces here share a height. It reads as a moulding with a
    // reveal above it.
    const corniceTop = base + WALL_HEIGHT - 2 * SURFACE_OVERLAP;
    geoms.push(
      rectToBox(
        proudOfWall(w, CORNICE_PROUD),
        CORNICE_HEIGHT,
        corniceTop - CORNICE_HEIGHT / 2,
        COLORS.wallShade
      )
    );
  }

  // Architraves: a band up each jamb of a doorway and across its head, so an
  // opening reads as a cased door rather than as a hole in a wall.
  for (const door of DOORS) {
    const base = floorY(door.floor ?? 0);
    const colour = trimColor((door.x1 + door.x2) / 2);
    const cased = proudOfWall(door, ARCH_PROUD);
    const thinInX = door.x2 - door.x1 < door.y2 - door.y1;

    // Head band, sitting just under the lintel.
    geoms.push(rectToBox(cased, ARCH_WIDTH, base + DOOR_HEIGHT - ARCH_WIDTH / 2, colour));

    // The two jambs, running from floor to head. `cased` is the full opening;
    // each jamb is a slice of it at one end of the RUN direction.
    const jambA: Rect = thinInX
      ? { ...cased, y2: cased.y1 + ARCH_WIDTH }
      : { ...cased, x2: cased.x1 + ARCH_WIDTH };
    const jambB: Rect = thinInX
      ? { ...cased, y1: cased.y2 - ARCH_WIDTH }
      : { ...cased, x1: cased.x2 - ARCH_WIDTH };
    const jambHeight = DOOR_HEIGHT - ARCH_WIDTH;
    for (const jamb of [jambA, jambB]) {
      geoms.push(rectToBox(jamb, jambHeight, base + jambHeight / 2, colour));
    }
  }

  return geoms;
}

// A shallow plinth around each house's footprint, at ground level. Buildings
// that meet the ground on a bare edge look like they were dropped on it; a
// plinth reads as a foundation the house was built up from, and it gives the
// exterior a strong horizontal that catches the low sun.
export function buildPlinthGeoms(houseFootprints: Rect[]): THREE.BufferGeometry[] {
  const PLINTH_HEIGHT = 22;
  const PLINTH_PROUD = 9;
  return houseFootprints.map((f) =>
    rectToBox(
      { x1: f.x1 - PLINTH_PROUD, y1: f.y1 - PLINTH_PROUD, x2: f.x2 + PLINTH_PROUD, y2: f.y2 + PLINTH_PROUD },
      PLINTH_HEIGHT,
      floorY(0) - PLINTH_HEIGHT / 2 + SURFACE_OVERLAP,
      COLORS.foundation
    )
  );
}

// Window sills, proud of the wall under each opening. Same reasoning as the
// skirting: a sill is a strong horizontal that says "this is a real window in a
// real wall" rather than a rectangle painted on it.
export function buildSillGeoms(sills: { rect: Rect; y: number; x: number }[]): THREE.BufferGeometry[] {
  const SILL_HEIGHT = 6;
  const SILL_PROUD = 5;
  return sills.map((s) =>
    rectToBox(proudOfWall(s.rect, SILL_PROUD), SILL_HEIGHT, s.y - SILL_HEIGHT / 2, trimColor(s.x))
  );
}

// Guard rail along each balcony's open edge. A first-floor platform with no
// railing reads as unfinished, and this is the one place the player stands at
// height with nothing around them.
export function buildBalconyRails(balconies: Rect[]): THREE.BufferGeometry[] {
  const POST = 6;
  const RAIL_H = 46;
  const geoms: THREE.BufferGeometry[] = [];
  const y = floorY(1);
  for (const b of balconies) {
    // The OUTER edge is the one away from the house - west for house B, east
    // for house A - plus both short returns.
    const outerWest = teamSideAt((b.x1 + b.x2) / 2) === "B";
    const outer: Rect = outerWest
      ? { x1: b.x1, y1: b.y1, x2: b.x1 + POST, y2: b.y2 }
      : { x1: b.x2 - POST, y1: b.y1, x2: b.x2, y2: b.y2 };
    const north: Rect = { x1: b.x1, y1: b.y1, x2: b.x2, y2: b.y1 + POST };
    const south: Rect = { x1: b.x1, y1: b.y2 - POST, x2: b.x2, y2: b.y2 };
    for (const r of [outer, north, south]) {
      geoms.push(rectToBox(r, RAIL_H, y + RAIL_H / 2, COLORS.foundation));
    }
  }
  return geoms;
}

// The roof's fascia board - a band around the eave line. Without it the roof
// planes end in a knife edge, which is the single most "untextured primitive"
// silhouette a building can have.
export function buildFasciaGeoms(footprints: Rect[]): THREE.BufferGeometry[] {
  const FASCIA_H = 14;
  const OVERHANG = 20;
  const y = floorY(1) + WALL_HEIGHT;
  return footprints.flatMap((f) => {
    const o: Rect = { x1: f.x1 - OVERHANG, y1: f.y1 - OVERHANG, x2: f.x2 + OVERHANG, y2: f.y2 + OVERHANG };
    const colour = teamSideAt((f.x1 + f.x2) / 2) === "B" ? COLORS.roofB : COLORS.roofA;
    const bands: Rect[] = [
      { x1: o.x1, y1: o.y1, x2: o.x2, y2: o.y1 + FASCIA_H },
      { x1: o.x1, y1: o.y2 - FASCIA_H, x2: o.x2, y2: o.y2 },
      { x1: o.x1, y1: o.y1, x2: o.x1 + FASCIA_H, y2: o.y2 },
      { x1: o.x2 - FASCIA_H, y1: o.y1, x2: o.x2, y2: o.y2 },
    ];
    return bands.map((b) => rectToBox(b, FASCIA_H, y - FASCIA_H / 2 + STORY_HEIGHT * 0, colour));
  });
}
