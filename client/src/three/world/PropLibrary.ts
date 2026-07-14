import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { PROP_SCALE } from "../../constants";
import type { PropName } from "./propManifest";

const loader = new GLTFLoader();
// Cached load-once promise per prop name, cloned per instance - same pattern
// as CashBundleView/CharacterModel's shared bundle template.
const templates = new Map<PropName, Promise<THREE.Object3D>>();

function loadTemplate(prop: PropName): Promise<THREE.Object3D> {
  let template = templates.get(prop);
  if (!template) {
    template = loader.loadAsync(`/models/props/${prop}.glb`).then((gltf) => gltf.scene);
    templates.set(prop, template);
  }
  return template;
}

// Ground footprints in meters (w x d), matching the "1 Blender unit ~= 1
// meter" convention the character/bundle rigs already use; HouseDresser
// multiplies these by PROP_SCALE to get world-unit AABB colliders. Only the
// props that are ever placed `solid: true` need an entry - rug/bush/pipes/
// stone_path are purely decorative and never solid, so they're intentionally
// absent here.
export const FOOTPRINTS: Partial<Record<PropName, { w: number; d: number }>> = {
  bed: { w: 2.0, d: 1.1 },
  nightstand: { w: 0.45, d: 0.45 },
  dresser: { w: 1.5, d: 0.5 },
  sofa: { w: 1.8, d: 0.75 },
  tv: { w: 1.3, d: 0.5 },
  coffee_table: { w: 0.9, d: 0.55 },
  crate: { w: 0.75, d: 0.75 },
  shelf: { w: 1.8, d: 0.5 },
  jail_bars: { w: 2.0, d: 0.12 },
  shed: { w: 1.6, d: 1.2 },
  fountain: { w: 1.4, d: 1.4 },
  tree: { w: 0.35, d: 0.35 }, // trunk only - canopy overhangs without collision
  fence: { w: 2.0, d: 0.1 },
};

// Decorative floor dressing the character is meant to walk over freely -
// receiveShadow only, never casts one (a flat rug/path casting a shadow onto
// itself/its neighbors would just look wrong).
const RECEIVE_ONLY: ReadonlySet<PropName> = new Set(["rug", "stone_path"]);

// Loads (once) and clones a prop instance, pre-scaled and shadow-configured -
// mirrors CashBundleView's load-once-clone pattern.
export async function createPropInstance(prop: PropName): Promise<THREE.Object3D> {
  const template = await loadTemplate(prop);
  const instance = template.clone(true);
  instance.scale.setScalar(PROP_SCALE);

  const receiveOnly = RECEIVE_ONLY.has(prop);
  instance.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (!mesh.isMesh) return;
    mesh.castShadow = !receiveOnly;
    mesh.receiveShadow = true;
  });

  return instance;
}
