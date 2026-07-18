// Static placement data for Phase 3's house/garden dressing - plain data, no
// Three.js imports, so it stays hand-comparable against the floor plan like
// geometry/floorplan.ts's own tables. Every coordinate here is PRE-SCALE
// (original 1600x900 layout); HouseDresser multiplies by WORLD_SCALE at
// placement time, exactly like floorplan.ts's scaleRect pattern.
//
// House A is never listed directly: HouseDresser mirrors HOUSE_B_PROPS with
// x' = 1600 - x, rot' = (360 - rot) % 360. GARDEN_PROPS sits on the shared
// center column, so it's listed once and not mirrored.

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
  rot: Rot;
  solid: boolean;
}

export const HOUSE_B_PROPS: PropPlacement[] = [
  // bedroom B (cash room): bundle row centers y=70, score rows y=125/165 -
  // furniture stays in the y<55 north band, clear of both.
  { prop: "bed", x: 265, y: 22, rot: 0, solid: true },
  { prop: "nightstand", x: 310, y: 15, rot: 0, solid: true },
  { prop: "dresser", x: 440, y: 14, rot: 0, solid: true },
  { prop: "rug", x: 340, y: 110, rot: 0, solid: false },
  // living B: spawns at (280,330),(400,330),(280,450),(400,450) - center stays clear.
  { prop: "sofa", x: 163, y: 280, rot: 90, solid: true },
  { prop: "tv", x: 521, y: 325, rot: 270, solid: true },
  { prop: "coffee_table", x: 215, y: 275, rot: 0, solid: true },
  { prop: "rug", x: 340, y: 390, rot: 0, solid: false },
  // basement B: jail spot (340,760); cell = 3 bar panels open to the north.
  { prop: "jail_bars", x: 335, y: 822, rot: 0, solid: true },
  { prop: "jail_bars", x: 295, y: 785, rot: 90, solid: true },
  { prop: "jail_bars", x: 385, y: 785, rot: 90, solid: true },
  { prop: "crate", x: 170, y: 835, rot: 0, solid: true },
  { prop: "crate", x: 205, y: 855, rot: 0, solid: true },
  { prop: "crate", x: 180, y: 800, rot: 90, solid: true },
  { prop: "shelf", x: 524, y: 700, rot: 90, solid: true },
  { prop: "pipes", x: 460, y: 890, rot: 0, solid: false },
  // backyard B
  { prop: "shed", x: 55, y: 48, rot: 0, solid: true },
  { prop: "bush", x: 70, y: 250, rot: 0, solid: false },
  { prop: "bush", x: 40, y: 550, rot: 0, solid: false },
  { prop: "bush", x: 90, y: 640, rot: 0, solid: false },
  { prop: "fence", x: 16, y: 180, rot: 90, solid: false },
  { prop: "fence", x: 16, y: 520, rot: 90, solid: false },
  { prop: "fence", x: 16, y: 840, rot: 90, solid: false },
  // Decorative-only density pass (graphics quality gate): clear open lawn
  // between the door gaps, away from the shed/existing bushes/fences and
  // every solid rect above - purely visual, not solid, doesn't touch any
  // existing entry.
  { prop: "bush", x: 110, y: 200, rot: 0, solid: false },
  { prop: "bush", x: 100, y: 850, rot: 0, solid: false },
];

const STONE_PATH_Y = 430;
const STONE_PATH_X_START = 600;
const STONE_PATH_X_END = 1020;
const STONE_PATH_STEP = 60;
const stonePathTiles: PropPlacement[] = [];
for (let x = STONE_PATH_X_START; x <= STONE_PATH_X_END; x += STONE_PATH_STEP) {
  stonePathTiles.push({ prop: "stone_path", x, y: STONE_PATH_Y, rot: 0, solid: false });
}

export const GARDEN_PROPS: PropPlacement[] = [
  { prop: "tree", x: 620, y: 120, rot: 0, solid: true },
  { prop: "tree", x: 980, y: 150, rot: 0, solid: true },
  { prop: "tree", x: 600, y: 800, rot: 0, solid: true },
  { prop: "tree", x: 1000, y: 780, rot: 0, solid: true },
  { prop: "bush", x: 700, y: 300, rot: 0, solid: false },
  { prop: "bush", x: 900, y: 620, rot: 0, solid: false },
  { prop: "bush", x: 760, y: 700, rot: 0, solid: false },
  { prop: "fountain", x: 800, y: 180, rot: 0, solid: true },
  // Decorative-only density pass: open lawn away from the path/trees/
  // fountain/existing bushes above.
  { prop: "bush", x: 650, y: 250, rot: 0, solid: false },
  { prop: "bush", x: 900, y: 800, rot: 0, solid: false },
  ...stonePathTiles,
];

// ---- windows ----
//
// Pre-scale center-along-wall + a 60-unit PRE-SCALE width (WindowBuilder
// multiplies it by WORLD_SCALE like every other run-axis dimension, so
// windows stay proportional to their walls at any map scale), vertical extent
// WINDOW_SILL..WINDOW_HEAD (see constants.ts). `axis` names which coordinate
// of the wall is FIXED (the wall's own plane): "x" for the vertical walls
// dividing backyard|house|garden (garden-side / backyard-side windows), "y"
// for the horizontal world-boundary wall (the north-facing bedroom windows).
// House B only; WindowBuilder finds the containing WALLS rect and mirrors
// nothing here - the WINDOWS export below already includes both houses.
export interface WindowSpec {
  axis: "x" | "y";
  plane: number;
  center: number;
  width: number;
}

const WINDOW_WIDTH = 60;

const HOUSE_B_WINDOWS: WindowSpec[] = [
  // east wall (garden side), plane x=540
  { axis: "x", plane: 540, center: 100, width: WINDOW_WIDTH },
  { axis: "x", plane: 540, center: 335, width: WINDOW_WIDTH },
  { axis: "x", plane: 540, center: 485, width: WINDOW_WIDTH },
  // west wall (backyard side), plane x=140
  { axis: "x", plane: 140, center: 250, width: WINDOW_WIDTH },
  { axis: "x", plane: 140, center: 320, width: WINDOW_WIDTH },
  // north boundary wall, plane y=5
  { axis: "y", plane: 5, center: 250, width: WINDOW_WIDTH },
  { axis: "y", plane: 5, center: 430, width: WINDOW_WIDTH },
];

// House A mirror: vertical walls (axis "x") flip the wall's plane (x' = 1600
// - x) and keep the run-direction center as-is; the shared north boundary
// wall (axis "y") keeps its plane and flips the run-direction center instead
// - exactly matching how WALLS/DOORS mirror across the map's centerline.
function mirrorWindow(w: WindowSpec): WindowSpec {
  return w.axis === "x" ? { ...w, plane: 1600 - w.plane } : { ...w, center: 1600 - w.center };
}

export const WINDOWS: WindowSpec[] = [...HOUSE_B_WINDOWS, ...HOUSE_B_WINDOWS.map(mirrorWindow)];
