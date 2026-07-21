import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import type { Room } from "colyseus.js";
import { BUNDLE_SCALE } from "../constants";
import { visualHeight } from "./world/HeightField";

const MODEL_URL = "/models/cashbundle.glb";

// Ports GameScene.syncCashBundles onto the Blender-authored cashbundle.glb
// prop (Milestone A2) instead of a 2D rectangle: spawns one clone per bundle
// id, positions it, and hides it while carried (location starts with
// "carried:") - identical logic to the 2D version, just a 3D mesh instead.
export class CashBundleView {
  private template: THREE.Object3D | null = null;
  private instances = new Map<string, THREE.Object3D>();

  private constructor(private scene: THREE.Scene) {}

  static async create(scene: THREE.Scene): Promise<CashBundleView> {
    const view = new CashBundleView(scene);
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync(MODEL_URL);
    view.template = gltf.scene;
    return view;
  }

  sync(room: Room) {
    if (!this.template) return;
    const seen = new Set<string>();

    room.state.cashBundles.forEach((b: any, id: string) => {
      seen.add(id);
      let inst = this.instances.get(id);
      if (!inst) {
        inst = this.template!.clone(true);
        inst.scale.setScalar(BUNDLE_SCALE);
        this.scene.add(inst);
        this.instances.set(id, inst);
      }
      const carried = typeof b.location === "string" && b.location.startsWith("carried:");
      inst.visible = !carried;
      if (!carried) inst.position.set(b.x, visualHeight(b.x, b.y, b.floor ?? 1), b.y);
    });

    for (const [id, inst] of this.instances) {
      if (!seen.has(id)) {
        this.scene.remove(inst);
        this.instances.delete(id);
      }
    }
  }
}
