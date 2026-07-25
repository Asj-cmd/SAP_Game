// Static placement data for the house/garden dressing - plain data, no Three.js
// imports, so it stays hand-comparable against the floor plan like
// geometry/floorplan.ts. Every coordinate is PRE-SCALE (original 1600x900
// layout); HouseDresser multiplies x by WORLD_SCALE and y by WORLD_SCALE *
// MAP_DEPTH_SCALE at placement time, and lifts each prop to its FLOOR's height.
//
// Props are purely DECORATIVE (never collidable) so they signal each room's
// purpose without eating the interior movement space. House A is mirrored from
// HOUSE_B_PROPS (x' = 1600 - x, rot' = (360 - rot) % 360); GARDEN_PROPS sits on
// the shared centre column and isn't mirrored.

export type PropName =
  | "bed"
  | "nightstand"
  | "dresser"
  | "rug"
  | "sofa"
  | "tv"
  | "coffee_table"
  | "jail_bars"
  | "crate"
  | "shelf"
  | "pipes"
  | "shed"
  | "bush"
  | "fence"
  | "tree"
  | "fountain"
  | "stone_path";

export type Rot = 0 | 90 | 180 | 270;

export interface PropPlacement {
  prop: PropName;
  x: number;
  y: number;
  floor: number; // -1 basement, 0 living/ground, +1 bedrooms
  rot: Rot;
}

// House B footprint x[260,720], y[0,700]. Stacked floors share it. Props hug
// the walls, clear of the stairwell openings (up: x[580,700] y[255,425]; down:
// x[300,420] y[430,600]), the living spawns (x 340/480, y 110/220) and every
// doorway.
export const HOUSE_B_PROPS: PropPlacement[] = [
  // ---- top floor, NORTH bedroom (floor +1, y[0,250]) ----
  { prop: "bed", x: 430, y: 70, floor: 1, rot: 0 },
  { prop: "nightstand", x: 520, y: 60, floor: 1, rot: 0 },
  { prop: "dresser", x: 660, y: 70, floor: 1, rot: 0 },
  { prop: "rug", x: 480, y: 190, floor: 1, rot: 0 },
  // ---- top floor, SOUTH bedroom (floor +1, y[430,700]) ----
  { prop: "bed", x: 430, y: 660, floor: 1, rot: 0 },
  { prop: "dresser", x: 660, y: 660, floor: 1, rot: 0 },
  { prop: "rug", x: 480, y: 500, floor: 1, rot: 0 },
  // ---- living room (floor 0) ----
  { prop: "sofa", x: 300, y: 160, floor: 0, rot: 90 },
  { prop: "coffee_table", x: 375, y: 160, floor: 0, rot: 0 },
  { prop: "tv", x: 695, y: 160, floor: 0, rot: 270 },
  { prop: "rug", x: 620, y: 330, floor: 0, rot: 0 },
  // ---- basement (floor -1): a cell around the jail spot (560,560) ----
  { prop: "jail_bars", x: 500, y: 500, floor: -1, rot: 90 },
  { prop: "jail_bars", x: 620, y: 500, floor: -1, rot: 90 },
  { prop: "jail_bars", x: 560, y: 640, floor: -1, rot: 0 },
  { prop: "crate", x: 330, y: 120, floor: -1, rot: 0 },
  { prop: "shelf", x: 695, y: 250, floor: -1, rot: 90 },
  { prop: "pipes", x: 470, y: 50, floor: -1, rot: 0 },
  // ---- backyard (floor 0, x[0,260]) ----
  { prop: "shed", x: 65, y: 250, floor: 0, rot: 0 },
  { prop: "bush", x: 55, y: 430, floor: 0, rot: 0 },
  { prop: "bush", x: 60, y: 660, floor: 0, rot: 0 },
  { prop: "fence", x: 22, y: 170, floor: 0, rot: 90 },
  { prop: "fence", x: 22, y: 530, floor: 0, rot: 90 },
];

const STONE_PATH_Y = 350;
const stonePathTiles: PropPlacement[] = [];
for (let x = 780; x <= 1120; x += 60) {
  stonePathTiles.push({ prop: "stone_path", x, y: STONE_PATH_Y, floor: 0, rot: 0 });
}

// Garden (floor 0, x[720,1180]) - shared, not mirrored.
export const GARDEN_PROPS: PropPlacement[] = [
  { prop: "tree", x: 790, y: 90, floor: 0, rot: 0 },
  { prop: "tree", x: 1110, y: 110, floor: 0, rot: 0 },
  { prop: "tree", x: 790, y: 620, floor: 0, rot: 0 },
  { prop: "tree", x: 1110, y: 600, floor: 0, rot: 0 },
  { prop: "fountain", x: 950, y: 180, floor: 0, rot: 0 },
  { prop: "bush", x: 850, y: 470, floor: 0, rot: 0 },
  { prop: "bush", x: 1050, y: 500, floor: 0, rot: 0 },
  ...stonePathTiles,
];
