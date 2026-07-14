import * as THREE from "three";
import { FOLLOW_DISTANCE, FOLLOW_HEIGHT, LOOK_HEIGHT } from "../constants";

// 3rd-person chase camera with FPS-style mouse look: the mouse owns the yaw
// (GameController feeds pointer-lock movementX deltas into addYaw), and the
// camera just orbits behind the character at that heading - it never rotates
// on its own, so the view only ever moves when the player moves the mouse.
// Movement input is rotated by getYaw() so W always walks into the screen.
// A raycast against the environment's wall mesh pulls the camera in short of
// any wall between it and the character, since door gaps are narrow enough
// that an unclamped camera constantly clips through them.
export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private yaw = 0;
  private raycaster = new THREE.Raycaster();

  constructor(
    camera: THREE.PerspectiveCamera,
    private obstacles: THREE.Object3D[]
  ) {
    this.camera = camera;
  }

  // Current camera heading; the ground-plane forward it implies is
  // (sin(yaw), -cos(yaw)), matching CharacterModel.setFacing's convention.
  getYaw(): number {
    return this.yaw;
  }

  // Mouse-look input: positive delta (mouse moved right) turns the view right.
  addYaw(delta: number) {
    this.yaw += delta;
  }

  update(dt: number, targetX: number, targetZ: number) {
    const lookAt = new THREE.Vector3(targetX, LOOK_HEIGHT, targetZ);
    // forward direction implied by CharacterModel.setFacing's atan2(dx,-dz):
    // theta -> forward = (sin(theta), -cos(theta)); camera sits behind it.
    const forward = new THREE.Vector3(Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    let desired = lookAt.clone().addScaledVector(forward, -FOLLOW_DISTANCE);
    desired.y = LOOK_HEIGHT + FOLLOW_HEIGHT;

    const toDesired = desired.clone().sub(lookAt);
    const dist = toDesired.length();
    if (dist > 1e-4) {
      const dir = toDesired.clone().normalize();
      this.raycaster.set(lookAt, dir);
      this.raycaster.far = dist;
      const hits = this.raycaster.intersectObjects(this.obstacles, false);
      if (hits.length > 0 && hits[0].distance < dist) {
        const pulled = Math.max(hits[0].distance - 10, 20);
        desired = lookAt.clone().addScaledVector(dir, pulled);
      }
    }

    this.camera.position.copy(desired);
    this.camera.lookAt(lookAt);
  }
}
