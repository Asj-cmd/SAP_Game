// Prop placement data + the SOLID footprints derived from it.
//
// This lives beside worldGeometry.ts, and for the same reason: props used to be
// purely decorative client-side dressing, but now that furniture is solid their
// footprints are part of the simulation - a bot must path around the sofa the
// human can't walk through. Keeping the placements here means there is exactly
// one copy of them, so the renderer and the authoritative server can never
// disagree about where the furniture is.
//
// Dependency-free and engine-agnostic (plain numbers, like worldGeometry.ts):
// the client re-exports the placement list to draw the models, the server reads
// only PROP_COLLIDERS.
import {
  MIRROR_X,
  WORLD_SCALE,
  MAP_DEPTH_SCALE,
  randomBedroomPoint,
  type FloorRect,
} from "./worldGeometry";

// Props are authored at true human proportion ("1 Blender unit ~= 1 metre") and
// deliberately do NOT scale with WORLD_SCALE - raising the map scale gives you
// more room, it does not inflate the furniture. Their POSITIONS scale; their
// SIZES do not.
export const PROP_SCALE = 45;

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

// Ground footprints in metres (w x d) for the props that are SOLID. Absence
// from this table is what makes a prop walk-through, and it is deliberate in
// every case:
//   rug / stone_path - flat floor dressing you walk over;
//   bush / pipes     - soft/thin set dressing, not worth a collider;
//   jail_bars        - the cell around the jail spot. A jailed player is
//                      TELEPORTED inside it and must be reachable to be
//                      rescued, so bars that stop a body would break the
//                      rescue mechanic outright.
export const FOOTPRINTS: Partial<Record<PropName, { w: number; d: number }>> = {
  bed: { w: 2.0, d: 1.1 },
  nightstand: { w: 0.45, d: 0.45 },
  dresser: { w: 1.5, d: 0.5 },
  sofa: { w: 1.8, d: 0.75 },
  tv: { w: 1.3, d: 0.5 },
  coffee_table: { w: 0.9, d: 0.55 },
  crate: { w: 0.75, d: 0.75 },
  shelf: { w: 1.8, d: 0.5 },
  shed: { w: 1.6, d: 1.2 },
  fountain: { w: 1.4, d: 1.4 },
  tree: { w: 0.35, d: 0.35 }, // trunk only - canopy overhangs without collision
  fence: { w: 2.0, d: 0.1 },
};

// House B footprint x[260,720], y[0,700]. Stacked floors share it. Props hug
// the walls, clear of the stairwell openings (up: x[450,570] y[268,422]; down:
// x[290,410] y[520,675]), the living spawns (x 330/470, y 120/240), every
// doorway, and - now that they are solid - every leg of the bot waypoint graph.
export const HOUSE_B_PROPS: PropPlacement[] = [
  // ---- top floor, NORTH bedroom (floor +1, y[0,240]) ----
  { prop: "bed", x: 430, y: 70, floor: 1, rot: 0 },
  { prop: "nightstand", x: 520, y: 60, floor: 1, rot: 0 },
  { prop: "dresser", x: 660, y: 70, floor: 1, rot: 0 },
  { prop: "rug", x: 480, y: 190, floor: 1, rot: 0 },
  // ---- top floor, SOUTH bedroom (floor +1, y[450,700]) ----
  { prop: "bed", x: 430, y: 660, floor: 1, rot: 0 },
  { prop: "dresser", x: 660, y: 660, floor: 1, rot: 0 },
  { prop: "rug", x: 480, y: 500, floor: 1, rot: 0 },
  // ---- living room (floor 0) ----
  { prop: "sofa", x: 300, y: 160, floor: 0, rot: 90 },
  { prop: "coffee_table", x: 375, y: 160, floor: 0, rot: 0 },
  // Against the east wall in the run BETWEEN the first two garden doors
  // (y[120,200] and y[320,400]). It used to sit at y=160, dead centre of the
  // first doorway, blocking it in both houses.
  { prop: "tv", x: 695, y: 260, floor: 0, rot: 270 },
  { prop: "rug", x: 620, y: 330, floor: 0, rot: 0 },
  // ---- basement (floor -1) ----
  // The cell reads as an L around the jail spot (560,560) rather than a closed
  // box: the approaches from the cellar steps and the down-staircase both come
  // from the WEST, so the open sides face them and a rescuer can always walk in.
  { prop: "jail_bars", x: 650, y: 560, floor: -1, rot: 90 },
  { prop: "jail_bars", x: 560, y: 650, floor: -1, rot: 0 },
  { prop: "crate", x: 330, y: 120, floor: -1, rot: 0 },
  { prop: "shelf", x: 695, y: 250, floor: -1, rot: 90 },
  { prop: "pipes", x: 470, y: 50, floor: -1, rot: 0 },
  // ---- backyard (floor 0, x[0,260]) ----
  // The shed hugs the west boundary so the yard's north-south run past it stays
  // wider than a body - it is on the route from the yard to the north ladder.
  { prop: "shed", x: 48, y: 250, floor: 0, rot: 0 },
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

// House A mirrors house B across the map centre: x' = MIRROR_X - x, rot flips.
export function mirrorPlacement(p: PropPlacement): PropPlacement {
  return { ...p, x: MIRROR_X - p.x, rot: (((360 - p.rot) % 360) as Rot) };
}

export const ALL_PROPS: PropPlacement[] = [
  ...HOUSE_B_PROPS,
  ...HOUSE_B_PROPS.map(mirrorPlacement),
  ...GARDEN_PROPS,
];

// Solid props as per-floor world-space rects, ready to be collided against
// exactly like a wall. Positions scale with the map; sizes do not (see
// PROP_SCALE). A quarter-turn swaps the footprint's width and depth.
export const PROP_COLLIDERS: FloorRect[] = ALL_PROPS.flatMap((p) => {
  const size = FOOTPRINTS[p.prop];
  if (!size) return [];
  const turned = p.rot === 90 || p.rot === 270;
  const halfX = ((turned ? size.d : size.w) * PROP_SCALE) / 2;
  const halfY = ((turned ? size.w : size.d) * PROP_SCALE) / 2;
  const cx = p.x * WORLD_SCALE;
  const cy = p.y * WORLD_SCALE * MAP_DEPTH_SCALE;
  return [{ x1: cx - halfX, y1: cy - halfY, x2: cx + halfX, y2: cy + halfY, floor: p.floor }];
});

// Clearance a cash bundle keeps from any solid prop, so it is never left
// floating inside a bed and is always reachable from open floor.
const CASH_PROP_CLEARANCE = 30;

function insideSolidProp(x: number, y: number, floor: number, margin: number): boolean {
  for (const p of PROP_COLLIDERS) {
    if (p.floor !== floor) continue;
    if (x > p.x1 - margin && x < p.x2 + margin && y > p.y1 - margin && y < p.y2 + margin) return true;
  }
  return false;
}

// A random cash spot in `house`'s two bedrooms, clear of the furniture. Plain
// rejection sampling over worldGeometry's geometric sampler: the bedrooms are
// mostly open floor, so this lands on the first or second try in practice, and
// the bounded retry means it can never hang. Roughly one spot in nine used to
// come out inside a bed or dresser, which is only a problem now that furniture
// is solid.
export function randomCashSpot(house: "B" | "A"): { x: number; y: number } {
  let spot = randomBedroomPoint(house);
  for (let tries = 0; tries < 24 && insideSolidProp(spot.x, spot.y, 1, CASH_PROP_CLEARANCE); tries++) {
    spot = randomBedroomPoint(house);
  }
  return spot;
}

export function randomCashSpots(house: "B" | "A", count: number): { x: number; y: number }[] {
  const out: { x: number; y: number }[] = [];
  for (let i = 0; i < count; i++) out.push(randomCashSpot(house));
  return out;
}
