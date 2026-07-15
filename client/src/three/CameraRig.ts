import * as THREE from "three";
import { FOLLOW_DISTANCE, FOLLOW_HEIGHT, LOOK_HEIGHT } from "../constants";
import { heightAt } from "./world/HeightField";

// Ground height tracks toward heightAt(target) at this rate (units/sec of
// lerp-fraction, i.e. 1 - e^-RATE*dt), not snapped instantly, so climbing a
// staircase eases the camera's vertical follow instead of juddering a frame
// behind the character on every step.
const GROUND_FOLLOW_RATE = 8;

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
  // Smoothed ground height under the followed target - see GROUND_FOLLOW_RATE.
  private groundY = 0;
  private groundInitialized = false;
  // Scratch vectors reused every frame in update() instead of allocated fresh -
  // this runs once per rendered frame, so `new THREE.Vector3()`/`.clone()`
  // here would be a steady stream of small GC garbage at 60+ fps.
  private readonly lookAt = new THREE.Vector3();
  private readonly forward = new THREE.Vector3();
  private readonly desired = new THREE.Vector3();
  private readonly toDesired = new THREE.Vector3();
  private readonly dir = new THREE.Vector3();

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
    const targetGroundY = heightAt(targetX, targetZ);
    if (!this.groundInitialized) {
      // Snap on the very first frame instead of easing up from 0, in case a
      // future spawn point ever lands somewhere other than grade.
      this.groundY = targetGroundY;
      this.groundInitialized = true;
    } else {
      this.groundY += (targetGroundY - this.groundY) * Math.min(1, GROUND_FOLLOW_RATE * dt);
    }

    this.lookAt.set(targetX, LOOK_HEIGHT + this.groundY, targetZ);
    // forward direction implied by CharacterModel.setFacing's atan2(dx,-dz):
    // theta -> forward = (sin(theta), -cos(theta)); camera sits behind it.
    this.forward.set(Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    this.desired.copy(this.lookAt).addScaledVector(this.forward, -FOLLOW_DISTANCE);
    this.desired.y = LOOK_HEIGHT + FOLLOW_HEIGHT + this.groundY;

    this.toDesired.subVectors(this.desired, this.lookAt);
    const dist = this.toDesired.length();
    if (dist > 1e-4) {
      this.dir.copy(this.toDesired).normalize();
      this.raycaster.set(this.lookAt, this.dir);
      this.raycaster.far = dist;
      const hits = this.raycaster.intersectObjects(this.obstacles, false);
      if (hits.length > 0 && hits[0].distance < dist) {
        const pulled = Math.max(hits[0].distance - 10, 20);
        this.desired.copy(this.lookAt).addScaledVector(this.dir, pulled);
      }
    }

    this.camera.position.copy(this.desired);
    this.camera.lookAt(this.lookAt);
  }
}
