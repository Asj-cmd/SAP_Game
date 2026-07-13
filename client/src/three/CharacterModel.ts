import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { COLORS, CHARACTER_SCALE } from "../constants";
import type { Team } from "../geometry/floorplan";

const MODEL_URL = "/models/character.glb";
// Pre-scale (Blender-unit) offset above the head-top (~1.85) for the carrying
// indicator; CHARACTER_SCALE is applied to `root`, which this is a child of.
const CARRY_INDICATOR_Y = 2.05;

// Loads the Blender-authored character (Milestone A2), plays its Idle/Walk
// clips blended by movement speed, and exposes a facing-angle rotation that's
// a direct axis-substitution port of the 2D game's Player.setFacing formula
// (dy -> dz, since world (x,y) maps to Three.js (x,z)).
export class CharacterModel {
  readonly root = new THREE.Group();
  private mixer: THREE.AnimationMixer;
  private idleAction: THREE.AnimationAction;
  private walkAction: THREE.AnimationAction;
  private bodyMaterial: THREE.MeshStandardMaterial | null = null;
  private facingAngle = 0;
  private carryIndicator: THREE.Mesh;
  private meshes: THREE.Mesh[] = [];

  private constructor(
    scene: THREE.Object3D,
    mixer: THREE.AnimationMixer,
    idleAction: THREE.AnimationAction,
    walkAction: THREE.AnimationAction,
    bodyMaterial: THREE.MeshStandardMaterial | null
  ) {
    this.root.add(scene);
    this.root.scale.setScalar(CHARACTER_SCALE);
    this.mixer = mixer;
    this.idleAction = idleAction;
    this.walkAction = walkAction;
    this.bodyMaterial = bodyMaterial;
    this.idleAction.play();
    this.walkAction.play();
    this.walkAction.setEffectiveWeight(0);

    scene.traverse((obj) => {
      if ((obj as THREE.Mesh).isMesh) this.meshes.push(obj as THREE.Mesh);
    });

    this.carryIndicator = new THREE.Mesh(
      new THREE.BoxGeometry(0.35, 0.22, 0.05),
      new THREE.MeshStandardMaterial({ color: COLORS.cash })
    );
    this.carryIndicator.position.set(0, CARRY_INDICATOR_Y, 0);
    this.carryIndicator.visible = false;
    this.root.add(this.carryIndicator);
  }

  static async load(team: Team): Promise<CharacterModel> {
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync(MODEL_URL);

    let bodyMaterial: THREE.MeshStandardMaterial | null = null;
    gltf.scene.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (mesh.isMesh) {
        mesh.castShadow = true;
        const mat = mesh.material as THREE.MeshStandardMaterial;
        if (mat?.name === "Body") bodyMaterial = mat;
      }
    });

    const mixer = new THREE.AnimationMixer(gltf.scene);
    const idleClip = THREE.AnimationClip.findByName(gltf.animations, "Idle");
    const walkClip = THREE.AnimationClip.findByName(gltf.animations, "Walk");
    if (!idleClip || !walkClip) {
      throw new Error("character.glb is missing the Idle or Walk animation clip");
    }

    const model = new CharacterModel(gltf.scene, mixer, mixer.clipAction(idleClip), mixer.clipAction(walkClip), bodyMaterial);
    model.setTeamColor(team);
    return model;
  }

  setTeamColor(team: Team) {
    this.bodyMaterial?.color.setHex(team === "B" ? COLORS.teamB : COLORS.teamA);
  }

  // dx/dz: normalized (or raw, only the direction matters) movement vector in
  // world space. No-op while stationary so the model keeps its last heading.
  setFacing(dx: number, dz: number) {
    if (dx === 0 && dz === 0) return;
    this.facingAngle = Math.atan2(dx, -dz);
    this.root.rotation.y = this.facingAngle;
  }

  getFacingAngle(): number {
    return this.facingAngle;
  }

  setCarrying(carrying: boolean) {
    this.carryIndicator.visible = carrying;
  }

  // 50% opacity while jailed, matching the 2D game's Player.setJailed dimming.
  setJailed(jailed: boolean) {
    const opacity = jailed ? 0.5 : 1;
    for (const mesh of this.meshes) {
      const mat = mesh.material as THREE.MeshStandardMaterial;
      if (!mat) continue;
      mat.transparent = jailed;
      mat.opacity = opacity;
    }
  }

  // speedFraction: 0 = fully idle, 1 = fully walking: blends the two clips'
  // weights directly rather than using a duration-based crossFadeTo, so the
  // blend continuously tracks acceleration/deceleration each frame.
  update(dt: number, speedFraction: number) {
    this.mixer.update(dt);
    const w = Math.max(0, Math.min(1, speedFraction));
    this.walkAction.setEffectiveWeight(w);
    this.idleAction.setEffectiveWeight(1 - w);
  }
}
