import * as THREE from "three";
import { WORLD_SCALE, PROP_SCALE } from "../../constants";
import type { PropName, PropPlacement } from "./propManifest";
import { loadPropTemplate, isReceiveOnly } from "./PropLibrary";
import { heightAt } from "./HeightField";

// Renders every placement of one repeated PropName as InstancedMesh(es) -
// one per mesh primitive in the source GLB (a tree's trunk + 2 canopy
// primitives stay 3 separate InstancedMeshes, each covering every tree
// placement) - instead of HouseDresser's one Object3D.clone() per placement.
// Three.js does not batch separate mesh nodes into a single draw call just
// because they share geometry/material, so cloning is still N draw calls for
// N placements; this is a real draw-call win for props placed many times
// (trees, bushes, fences, crates, jail bars, stone path tiles, rugs).
//
// Collision is untouched by this module on purpose: HouseDresser computes
// every solid rect straight from PropPlacement data (see solidRect there),
// never from the Object3D graph, so switching a prop's render path between
// "one clone per placement" and "one InstancedMesh per mesh primitive"
// changes nothing about what the character can walk through.
const dummy = new THREE.Object3D();

export async function buildInstancedProps(
  scene: THREE.Scene,
  prop: PropName,
  placements: PropPlacement[]
): Promise<void> {
  if (placements.length === 0) return;

  // The shared, never-added-to-scene template: read its meshes' geometry/
  // material and local (template-relative) transform directly, never clone.
  const template = await loadPropTemplate(prop);
  template.updateMatrixWorld(true);

  const meshes: THREE.Mesh[] = [];
  template.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (mesh.isMesh) meshes.push(mesh);
  });

  const receiveOnly = isReceiveOnly(prop);
  const count = placements.length;

  for (const mesh of meshes) {
    const instanced = new THREE.InstancedMesh(mesh.geometry, mesh.material, count);
    instanced.castShadow = !receiveOnly;
    instanced.receiveShadow = true;

    placements.forEach((p, i) => {
      const sx = p.x * WORLD_SCALE;
      const sz = p.y * WORLD_SCALE;
      dummy.position.set(sx, heightAt(sx, sz), sz);
      dummy.rotation.set(0, (p.rot * Math.PI) / 180, 0);
      dummy.scale.setScalar(PROP_SCALE);
      dummy.updateMatrix();
      // Root placement transform, composed with this mesh's own transform
      // relative to the template root (identical composition order to what
      // Three's scene graph would do if this mesh were still nested under a
      // per-placement clone: worldMatrix = placementMatrix * localMatrix).
      const instanceMatrix = dummy.matrix.clone().multiply(mesh.matrixWorld);
      instanced.setMatrixAt(i, instanceMatrix);
    });
    instanced.instanceMatrix.needsUpdate = true;
    instanced.computeBoundingSphere();

    scene.add(instanced);
  }
}
