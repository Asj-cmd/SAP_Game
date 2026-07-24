import * as THREE from "three";
import { WORLD_SCALE, MAP_DEPTH_SCALE } from "../../constants";
import { createPropInstance } from "./PropLibrary";
import { HOUSE_B_PROPS, GARDEN_PROPS, type PropPlacement } from "./propManifest";
import { floorY } from "./HeightField";

// Dresses both houses + the garden with DECORATIVE props (beds mark the cash
// bedrooms, a jail cell in the basement, sofa/TV in the living room, garden
// trees/fountain, etc.). Every prop is non-collidable, so it signals a room's
// purpose without eating the interior movement space. Pre-scale placement data
// lives in propManifest.ts; here we scale (x by WORLD_SCALE, depth by
// WORLD_SCALE*MAP_DEPTH_SCALE) and lift each prop to its floor's height.
const S = WORLD_SCALE;
const YS = MAP_DEPTH_SCALE;

// House A mirrors house B across the map centre: x' = 1600 - x, rot' flips.
function mirror(p: PropPlacement): PropPlacement {
  return { ...p, x: 1600 - p.x, rot: (((360 - p.rot) % 360) as PropPlacement["rot"]) };
}

async function place(scene: THREE.Scene, p: PropPlacement): Promise<void> {
  const instance = await createPropInstance(p.prop);
  instance.position.set(p.x * S, floorY(p.floor), p.y * S * YS);
  instance.rotation.y = (p.rot * Math.PI) / 180;
  scene.add(instance);
}

// Loads and places every prop. Returns once all are in the scene. Purely
// visual - no colliders are produced, so movement/collision is untouched.
export async function dressHouses(scene: THREE.Scene): Promise<void> {
  const placements: PropPlacement[] = [
    ...HOUSE_B_PROPS,
    ...HOUSE_B_PROPS.map(mirror), // house A
    ...GARDEN_PROPS,
  ];
  await Promise.all(placements.map((p) => place(scene, p)));
}
