import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { PROP_SCALE } from "../../constants";
import type { PropName } from "./propManifest";

const loader = new GLTFLoader();
// Cached load-once promise per prop name, cloned per instance - same pattern
// as CashBundleView/CharacterModel's shared bundle template.
const templates = new Map<PropName, Promise<THREE.Object3D>>();

// Named material roles from the bpy prop scripts (assets/blender/
// build_furniture.py / build_nature.py name every material - "Wood",
// "JailMetal", "SofaFabric", "FountainWater", etc.) - every one of them was
// exported with the same flat 0.75 roughness / 0 metalness, so every prop
// currently reads as identical semi-matte plastic regardless of what it's
// supposed to be. This reuses those names (no GLB regeneration needed) to
// assign a small shared material-role kit at load time, same technical-art
// pattern as the material roles in threejs-aaa-graphics-builder's kit: one
// role per surface type, applied everywhere that type appears.
const MATERIAL_ROLES: { test: RegExp; roughness: number; metalness: number }[] = [
  { test: /metal|handle|joint/i, roughness: 0.35, metalness: 0.75 }, // handles, pipes, jail bars
  { test: /screen/i, roughness: 0.2, metalness: 0.15 }, // TV screen - glossier than the console around it
  { test: /water/i, roughness: 0.12, metalness: 0.05 }, // fountain basin water
  { test: /wood/i, roughness: 0.82, metalness: 0 }, // furniture wood, fences
  { test: /fabric|rug|sheet|pillow/i, roughness: 0.92, metalness: 0 }, // sofa, bed, rug
  { test: /leaf|trunk/i, roughness: 0.85, metalness: 0 }, // tree/bush foliage + bark
  { test: /stone/i, roughness: 0.88, metalness: 0 }, // stone path, fountain basin
];

function applyMaterialRoles(root: THREE.Object3D) {
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (!mesh.isMesh) return;
    const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    for (const material of materials) {
      const std = material as THREE.MeshStandardMaterial;
      if (!std || !std.isMeshStandardMaterial) continue;
      const role = MATERIAL_ROLES.find((r) => r.test.test(std.name));
      if (!role) continue;
      std.roughness = role.roughness;
      std.metalness = role.metalness;
    }
  });
}

function loadTemplate(prop: PropName): Promise<THREE.Object3D> {
  let template = templates.get(prop);
  if (!template) {
    template = loader.loadAsync(`/models/props/${prop}.glb`).then((gltf) => {
      applyMaterialRoles(gltf.scene);
      return gltf.scene;
    });
    templates.set(prop, template);
  }
  return template;
}

// Exposed so InstancedPropBuilder can read geometry/material straight off the
// shared (never-added-to-scene, never-mutated-in-place) template instead of
// cloning per placement - the whole point of instancing is one GPU draw call
// per mesh primitive covering every placement of that prop.
export const loadPropTemplate = loadTemplate;

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

// Exposed so InstancedPropBuilder applies the same cast/receive policy to
// instanced props as createPropInstance applies to individually-placed ones.
export function isReceiveOnly(prop: PropName): boolean {
  return RECEIVE_ONLY.has(prop);
}

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
