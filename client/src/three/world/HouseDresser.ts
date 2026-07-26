import * as THREE from "three";
import { WORLD_SCALE, MAP_DEPTH_SCALE } from "../../constants";
import { createPropInstance } from "./PropLibrary";
import { ALL_PROPS, type PropPlacement } from "./propManifest";
import { floorY } from "./HeightField";

// Dresses both houses + the garden with props (beds mark the cash bedrooms, a
// jail cell in the basement, sofa/TV in the living room, garden trees/fountain,
// etc.). Placement data - including which props are SOLID and how big their
// footprints are - lives in shared/props.ts, so the server collides bots
// against exactly what is drawn here. This module only renders: it scales (x by
// WORLD_SCALE, depth by WORLD_SCALE*MAP_DEPTH_SCALE) and lifts each prop to its
// floor's height, using the same numbers the shared collider derivation does.
const S = WORLD_SCALE;
const YS = MAP_DEPTH_SCALE;

async function place(scene: THREE.Scene, p: PropPlacement): Promise<void> {
  const instance = await createPropInstance(p.prop);
  instance.position.set(p.x * S, floorY(p.floor), p.y * S * YS);
  instance.rotation.y = (p.rot * Math.PI) / 180;
  scene.add(instance);
}

// Loads and places every prop (both houses + the garden). Returns once all are
// in the scene.
export async function dressHouses(scene: THREE.Scene): Promise<void> {
  await Promise.all(ALL_PROPS.map((p) => place(scene, p)));
}
