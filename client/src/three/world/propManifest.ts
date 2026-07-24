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

// House B footprint x[240,620]. Stacked floors share it. Props hug the walls,
// clear of the stair footprints (x[380,540]), the ladder/cellar landings
// (x[240,320]), the living spawns (x[300,460] y[420,520]) and the partition
// door (x[400,480] y=450).
export const HOUSE_B_PROPS: PropPlacement[] = [
  // ---- top floor, north bedroom (floor +1, y < 450) ----
  { prop: "bed", x: 300, y: 90, floor: 1, rot: 0 },
  { prop: "nightstand", x: 360, y: 70, floor: 1, rot: 0 },
  { prop: "dresser", x: 570, y: 90, floor: 1, rot: 0 },
  { prop: "rug", x: 430, y: 330, floor: 1, rot: 0 },
  // ---- top floor, south bedroom (floor +1, y > 450) ----
  { prop: "bed", x: 300, y: 830, floor: 1, rot: 0 },
  { prop: "dresser", x: 570, y: 830, floor: 1, rot: 0 },
  { prop: "rug", x: 430, y: 600, floor: 1, rot: 0 },
  // ---- living room (floor 0) ----
  { prop: "sofa", x: 300, y: 200, floor: 0, rot: 90 },
  { prop: "tv", x: 575, y: 200, floor: 0, rot: 270 },
  { prop: "coffee_table", x: 320, y: 260, floor: 0, rot: 0 },
  { prop: "rug", x: 430, y: 470, floor: 0, rot: 0 },
  // ---- basement (floor -1): a jail cell around the jail spot (430,830) ----
  { prop: "jail_bars", x: 380, y: 800, floor: -1, rot: 90 },
  { prop: "jail_bars", x: 490, y: 800, floor: -1, rot: 90 },
  { prop: "jail_bars", x: 435, y: 885, floor: -1, rot: 0 },
  { prop: "crate", x: 290, y: 820, floor: -1, rot: 0 },
  { prop: "shelf", x: 575, y: 700, floor: -1, rot: 90 },
  { prop: "pipes", x: 430, y: 90, floor: -1, rot: 0 },
  // ---- backyard (floor 0, x[0,240]) ----
  { prop: "shed", x: 60, y: 80, floor: 0, rot: 0 },
  { prop: "bush", x: 70, y: 360, floor: 0, rot: 0 },
  { prop: "bush", x: 50, y: 560, floor: 0, rot: 0 },
  { prop: "bush", x: 90, y: 820, floor: 0, rot: 0 },
  { prop: "fence", x: 16, y: 200, floor: 0, rot: 90 },
  { prop: "fence", x: 16, y: 520, floor: 0, rot: 90 },
];

const STONE_PATH_Y = 450;
const stonePathTiles: PropPlacement[] = [];
for (let x = 660; x <= 940; x += 60) {
  stonePathTiles.push({ prop: "stone_path", x, y: STONE_PATH_Y, floor: 0, rot: 0 });
}

// Garden (floor 0, x[620,980]) - shared, not mirrored.
export const GARDEN_PROPS: PropPlacement[] = [
  { prop: "tree", x: 660, y: 140, floor: 0, rot: 0 },
  { prop: "tree", x: 940, y: 170, floor: 0, rot: 0 },
  { prop: "tree", x: 660, y: 780, floor: 0, rot: 0 },
  { prop: "tree", x: 940, y: 760, floor: 0, rot: 0 },
  { prop: "fountain", x: 800, y: 250, floor: 0, rot: 0 },
  { prop: "bush", x: 720, y: 560, floor: 0, rot: 0 },
  { prop: "bush", x: 880, y: 640, floor: 0, rot: 0 },
  ...stonePathTiles,
];
