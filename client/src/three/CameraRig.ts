import * as THREE from "three";
import { DEFAULT_PITCH, FOLLOW_DISTANCE, LOOK_HEIGHT } from "../constants";
import { heightAt, ceilingHeight } from "./world/HeightField";
import type { ZoneRect } from "../geometry/floorplan";

// Ground height tracks toward heightAt(target) at this rate (units/sec of
// lerp-fraction, i.e. 1 - e^-RATE*dt), not snapped instantly, so climbing a
// staircase eases the camera's vertical follow instead of juddering a frame
// behind the character on every step.
const GROUND_FOLLOW_RATE = 8;

// Pitch clamp, radians. PITCH_MIN sits slightly below horizontal (not all the
// way to it) so a player at the foot of the basement/bedroom split-level
// staircases can look up toward the floor above without the camera crashing
// into the stairwell ceiling. PITCH_MAX is just short of straight down.
const PITCH_MIN = -0.15;
const PITCH_MAX = 1.25;

// Indoor horizontal clamp (see update()'s bounds parameter). The inset keeps
// the camera off the walls' inner faces (boundary walls are ~10 scaled units
// thick, centered on the zone edge). Applied as a HARD clamp every frame, not
// eased: an earlier eased version lagged the correction on a fast mouse flick,
// so the camera pinned to the wall for several frames then sprang free - a
// visible flash/switch. A pure per-frame clamp makes the camera position a
// deterministic function of yaw/pitch/target, so fast and slow mouse look
// identical and the camera simply slides along the wall when the orbit would
// exceed the room.
const CLAMP_INSET = 30;
// Indoors the camera also can't rise above the room's own (solid, opaque)
// ceiling - ceilingHeight() is the exact plane RoofSystem draws the slab at,
// and this margin keeps the camera clearly under it rather than grazing it.
// Pitch past the cap still steepens the view - the orbit's horizontal
// component keeps shrinking with cos(pitch) while height holds - it just
// tops out shy of straight-down indoors instead of outdoor's full range.
const CEILING_MARGIN = 16;

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

// 3rd-person chase camera with FPS-style mouse look: the mouse owns yaw AND
// pitch (GameController feeds pointer-lock movementX/movementY into
// addYaw/addPitch), and the camera orbits the look-at point at that
// yaw/pitch - it never rotates on its own, so the view only ever moves when
// the player moves the mouse. Movement input is rotated by getYaw() so W
// always walks into the screen. A raycast against the environment's wall +
// floor meshes pulls the camera in short of any geometry between it and the
// character, since door gaps (and, looking down in the basement, the slab)
// are narrow/close enough that an unclamped camera constantly clips through.
export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private yaw = 0;
  // Elevation angle above horizontal; see DEFAULT_PITCH's provenance comment
  // in constants.ts for why this starting value reproduces the old fixed
  // camera's look with the mouse untouched.
  private pitch = DEFAULT_PITCH;
  private raycaster = new THREE.Raycaster();
  // Smoothed ground height under the followed target - see GROUND_FOLLOW_RATE.
  private groundY = 0;
  private groundInitialized = false;
  // Scratch vectors reused every frame in update() instead of allocated fresh -
  // this runs once per rendered frame, so `new THREE.Vector3()`/`.clone()`
  // here would be a steady stream of small GC garbage at 60+ fps.
  private readonly lookAt = new THREE.Vector3();
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

  // Mouse-look input: positive delta pitches the camera down toward
  // top-down (see PITCH_MAX); GameController is responsible for sign/invert.
  addPitch(delta: number) {
    this.pitch = clamp(this.pitch + delta, PITCH_MIN, PITCH_MAX);
  }

  // `bounds`: the enclosed interior zone the character is standing in (its
  // ZONE_RECTS entry), or null outdoors. Indoors the camera's final X/Z is
  // clamped inside that rect: FOLLOW_DISTANCE fits inside the scaled-up rooms
  // without the raycast ever firing (it only sees geometry ON the ray), so an
  // unclamped orbit can drift past the room's footprint and show sky around
  // the building or over a wall's top edge. Y is deliberately never clamped -
  // the near-top-down pitch must keep working.
  update(dt: number, targetX: number, targetZ: number, bounds: ZoneRect | null = null) {
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

    // True yaw+pitch spherical orbit: desired = lookAt - dir(yaw, pitch) *
    // FOLLOW_DISTANCE. Horizontal component matches the old forward direction
    // (sin(yaw), -cos(yaw)) implied by CharacterModel.setFacing's
    // atan2(dx,-dz); pitch tilts the camera up/down off that horizontal plane.
    const cosPitch = Math.cos(this.pitch);
    this.desired.set(
      this.lookAt.x - Math.sin(this.yaw) * cosPitch * FOLLOW_DISTANCE,
      this.lookAt.y + Math.sin(this.pitch) * FOLLOW_DISTANCE,
      this.lookAt.z + Math.cos(this.yaw) * cosPitch * FOLLOW_DISTANCE
    );

    this.toDesired.subVectors(this.desired, this.lookAt);
    const dist = this.toDesired.length();
    if (dist > 1e-4) {
      this.dir.copy(this.toDesired).normalize();
      this.raycaster.set(this.lookAt, this.dir);
      this.raycaster.far = dist;
      const hits = this.raycaster.intersectObjects(this.obstacles, false);
      if (hits.length > 0 && hits[0].distance < dist) {
        // Pull in short of the hit, never forced past it into geometry; floor
        // of 1 (not 0) guards camera.lookAt below, since camera == lookAt
        // makes the look direction degenerate. Near-1 is a brief
        // almost-first-person moment, which is acceptable and rare (it only
        // happens when there's genuinely no room behind the character).
        const pulled = Math.max(hits[0].distance - 10, 1);
        this.desired.copy(this.lookAt).addScaledVector(this.dir, pulled);
      }
    }

    // Indoor clamp, applied AFTER the pull-in (which still owns door gaps and
    // the basement slab). Hard, every frame - the camera can never render
    // outside the room even for one frame, so a fast mouse flick can't flash
    // the exterior; the camera just slides along the wall when the orbit would
    // exceed the room. Floorplan (x, y) maps to three (x, z), hence yMin/yMax
    // against desired.z. Y only ever pushes DOWN, under the ceiling plane
    // (CEILING_MARGIN below RoofSystem's slab); outdoor pitch is untouched.
    if (bounds) {
      this.desired.x = clamp(this.desired.x, bounds.xMin + CLAMP_INSET, bounds.xMax - CLAMP_INSET);
      this.desired.z = clamp(this.desired.z, bounds.yMin + CLAMP_INSET, bounds.yMax - CLAMP_INSET);
      this.desired.y = Math.min(this.desired.y, ceilingHeight(bounds.id) - CEILING_MARGIN);
    }

    this.camera.position.copy(this.desired);
    this.camera.lookAt(this.lookAt);
  }
}
