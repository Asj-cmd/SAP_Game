import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { COLORS, CHARACTER_SCALE, BUNDLE_SCALE } from "../constants";
import type { Team } from "../geometry/floorplan";

import { MODEL_PATHS } from "../assets";
const BUNDLE_URL = MODEL_PATHS.cashBundle;

// The four family members (assets/blender/build_family.py). Every client
// derives the same member for the same player (see pickFamilyVariant), so the
// cast is consistent across all screens without any server involvement.
export type FamilyVariant = "father" | "mother" | "son" | "daughter";
const FAMILY_ORDER: FamilyVariant[] = ["father", "mother", "son", "daughter"];
const VARIANT_URL = (v: FamilyVariant) => MODEL_PATHS.character(v);

// Head-top height per member in Blender units (from build_family.py's report,
// hair included) - the carried bundle floats a fixed margin above whoever is
// carrying, so the son doesn't wear it at his eye line or the father clip it.
const VARIANT_TOP: Record<FamilyVariant, number> = {
  father: 1.97,
  mother: 1.8,
  son: 1.48,
  daughter: 1.29,
};
const CARRY_BUNDLE_MARGIN = 0.28;

// Deterministic per-player family member: players of a team get
// father/mother/son/daughter in the order they appear in the state's players
// map (Colyseus preserves insertion order in sync, so every client iterates
// identically). No randomness, no server field needed.
export function pickFamilyVariant(players: { forEach(cb: (p: any, id: string) => void): void }, playerId: string): FamilyVariant {
  let indexInTeam = 0;
  let team = "";
  players.forEach((p: any, id: string) => {
    if (id === playerId) team = p.team;
  });
  let counted = 0;
  players.forEach((p: any, id: string) => {
    if (p.team !== team) return;
    if (id === playerId) indexInTeam = counted;
    counted++;
  });
  return FAMILY_ORDER[indexInTeam % FAMILY_ORDER.length];
}
// World-size fraction of a ground bundle: big enough to read at a glance,
// small enough not to look like a hat from across the map.
const CARRY_BUNDLE_WORLD_SCALE = (BUNDLE_SCALE / CHARACTER_SCALE) * 0.75;

// The bundle template is shared by every character instance (local + remotes);
// loaded once, cloned per character.
let bundleTemplatePromise: Promise<THREE.Object3D> | null = null;
function loadBundleTemplate(): Promise<THREE.Object3D> {
  if (!bundleTemplatePromise) {
    bundleTemplatePromise = new GLTFLoader().loadAsync(BUNDLE_URL).then((gltf) => gltf.scene);
  }
  return bundleTemplatePromise;
}

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
  private carryIndicator: THREE.Object3D;
  private meshes: THREE.Mesh[] = [];

  private constructor(
    scene: THREE.Object3D,
    mixer: THREE.AnimationMixer,
    idleAction: THREE.AnimationAction,
    walkAction: THREE.AnimationAction,
    bodyMaterial: THREE.MeshStandardMaterial | null,
    carriedBundle: THREE.Object3D,
    variant: FamilyVariant
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

    this.carryIndicator = carriedBundle;
    this.carryIndicator.scale.setScalar(CARRY_BUNDLE_WORLD_SCALE);
    this.carryIndicator.position.set(0, VARIANT_TOP[variant] + CARRY_BUNDLE_MARGIN, 0);
    this.carryIndicator.visible = false;
    this.root.add(this.carryIndicator);
  }

  static async load(team: Team, variant: FamilyVariant): Promise<CharacterModel> {
    const loader = new GLTFLoader();
    const [gltf, bundleTemplate] = await Promise.all([loader.loadAsync(VARIANT_URL(variant)), loadBundleTemplate()]);

    // Team identity lives in the shirt: build_family.py names each member's
    // shirt material exactly "Team" (neutral gray in the GLB) for the runtime
    // tint below. Skin/hair/pants keep their authored colors.
    let bodyMaterial: THREE.MeshStandardMaterial | null = null;
    gltf.scene.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (mesh.isMesh) {
        mesh.castShadow = true;
        const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
        for (const mat of mats as THREE.MeshStandardMaterial[]) {
          if (mat?.name === "Team") bodyMaterial = mat;
        }
      }
    });

    const mixer = new THREE.AnimationMixer(gltf.scene);
    const idleClip = THREE.AnimationClip.findByName(gltf.animations, "Idle");
    const walkClip = THREE.AnimationClip.findByName(gltf.animations, "Walk");
    if (!idleClip || !walkClip) {
      throw new Error(`${variant}.glb is missing the Idle or Walk animation clip`);
    }

    const model = new CharacterModel(
      gltf.scene,
      mixer,
      mixer.clipAction(idleClip),
      mixer.clipAction(walkClip),
      bodyMaterial,
      bundleTemplate.clone(true),
      variant
    );
    model.setTeamColor(team);
    return model;
  }

  setTeamColor(team: Team) {
    this.bodyMaterial?.color.setHex(team === "B" ? COLORS.teamB : COLORS.teamA);
  }

  // Heading in radians, in the game's world convention: angle 0 means the
  // character faces -z, and heading `a` means it faces (sin a, -cos a) - the
  // SAME direction W-forward moves and the camera looks, so at any camera yaw
  // the local player faces exactly where they walk (away from the camera, like
  // any TPS).
  //
  // The rig sets root.rotation.y = -angle, NOT +angle. The GLB's authored
  // forward is -Z (the family faces +Y in Blender, which the glTF export maps
  // to -Z; verified by render), and for a -Z-forward model Three.js's
  // right-handed Y-rotation only reaches (sin a, -cos a) at rotation.y = -a.
  // The previous +angle faced (-sin a, -cos a): correct walking N/S but
  // BACKWARDS walking E/W, so the character showed its face to the camera
  // "more than half the time". Both the local player (this method, fed
  // CameraRig.getYaw) and remotes (RemoteCharacterSync, fed the velocity
  // heading) go through here so the mapping can't drift between them.
  setFacingAngle(angle: number) {
    this.facingAngle = angle;
    this.root.rotation.y = -angle;
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
