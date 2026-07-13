import * as THREE from "three";
import { FOLLOW_DISTANCE, FOLLOW_HEIGHT, LOOK_HEIGHT, MAX_YAW_SPEED } from "../constants";

// 3rd-person chase camera: position follows the character tightly every
// frame, but YAW is slew-rate limited toward the character's facing angle so
// a sharp direction reversal swings the camera over ~0.3-0.5s instead of
// snapping (per the plan: absolute-direction movement stays, only the camera
// auto-orients). A raycast against the environment's wall mesh pulls the
// camera in short of any wall between it and the character, since door gaps
// are narrow enough that an unclamped camera constantly clips through them.
export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private yaw = 0;
  private raycaster = new THREE.Raycaster();
  private initialized = false;

  constructor(
    camera: THREE.PerspectiveCamera,
    private obstacles: THREE.Object3D[]
  ) {
    this.camera = camera;
  }

  update(dt: number, targetX: number, targetZ: number, facingAngle: number) {
    if (!this.initialized) {
      this.yaw = facingAngle;
      this.initialized = true;
    } else {
      let diff = facingAngle - this.yaw;
      diff = Math.atan2(Math.sin(diff), Math.cos(diff)); // wrap to [-pi, pi]
      const maxStep = MAX_YAW_SPEED * dt;
      this.yaw += Math.max(-maxStep, Math.min(maxStep, diff));
    }

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
