import * as THREE from "three";
import { DEFAULT_PITCH, FOLLOW_DISTANCE, LOOK_HEIGHT } from "../constants";
import { heightAt, ceilingHeight } from "./world/HeightField";
import type { ZoneRect } from "../geometry/floorplan";

// Third-person spring-arm chase camera (PUBG / Meccha-Chameleon feel):
//
//  - The MOUSE owns yaw + pitch and they apply INSTANTLY. Rotation is never
//    smoothed - a shooter's aim must be 1:1 with the mouse or it feels laggy.
//  - The camera always sits directly behind the character on the boom line, so
//    the character stays centred no matter what (the old rig shoved the camera
//    sideways to stay in the room, which slid the character off-centre and read
//    as a snap).
//  - Only the boom LENGTH is constrained, and it is the single thing that gets
//    smoothed. Every limit - the room walls, the ceiling, exterior geometry -
//    is expressed as "how far along the boom can the camera go", then the boom
//    collapses INSTANTLY when a limit closes in (so the camera can never clip
//    through or see past a wall, and nothing has to be made transparent) and
//    EXTENDS SMOOTHLY when the limit opens back up (so there is no pop). That
//    asymmetry is what makes fast mouse flicks glide instead of jerk.

const GROUND_FOLLOW_RATE = 8; // 1/s; camera's vertical follow easing on stairs

// Pitch clamp, radians. PITCH_MIN dips slightly below horizontal so a player at
// the foot of a staircase can look up the flight; PITCH_MAX is just short of
// straight down.
const PITCH_MIN = -0.15;
const PITCH_MAX = 1.25;

// Keep the camera this far inside a room's walls / below its ceiling, so the
// body never grazes the surface. Boundary walls are ~20 scaled units thick,
// centred on the zone edge (inner face ~10 in), so 30 leaves clear air.
const CLAMP_INSET = 30;
const CEILING_MARGIN = 20;
// Pull the boom this far short of a raycast hit (a stand-in for the camera's
// body radius, since the collision ray is infinitely thin).
const COLLISION_SKIN = 14;
// Never collapse nearer than this (avoids a degenerate look-at). Kept below the
// character's own wall gap (CHAR_RADIUS 20 + half-wall 10 = 30, the same as
// CLAMP_INSET) so that even fully boxed in, the collapsed camera stays on the
// interior side of the wall rather than poking through it.
const MIN_DISTANCE = 16;
// Boom EXTEND easing (1/s). Collapse is instant (see update) to prevent any
// clip; only lengthening is eased, and this rate is the whole "smoothness".
const BOOM_EXTEND_RATE = 7;

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private yaw = 0;
  private pitch = DEFAULT_PITCH;
  private raycaster = new THREE.Raycaster();
  // Smoothed ground height under the followed target (see GROUND_FOLLOW_RATE).
  private groundY = 0;
  private groundInitialized = false;
  // Smoothed boom length - the only damped quantity in the whole rig.
  private boomLength = FOLLOW_DISTANCE;
  // Scratch vectors reused each frame (this runs every rendered frame; fresh
  // allocations here would be steady GC pressure at 60+ fps).
  private readonly pivot = new THREE.Vector3();
  private readonly dir = new THREE.Vector3();
  private readonly camPos = new THREE.Vector3();

  constructor(
    camera: THREE.PerspectiveCamera,
    private obstacles: THREE.Object3D[]
  ) {
    this.camera = camera;
  }

  getYaw(): number {
    return this.yaw;
  }

  // Mouse-look: applied instantly (positive delta turns the view right).
  addYaw(delta: number) {
    this.yaw += delta;
  }

  // Mouse-look: positive delta pitches toward top-down (GameController owns
  // the sign / invert-Y). Clamped instantly.
  addPitch(delta: number) {
    this.pitch = clamp(this.pitch + delta, PITCH_MIN, PITCH_MAX);
  }

  // `bounds`: the enclosed interior zone the character stands in (its
  // ZONE_RECTS entry), or null outdoors. Indoors it caps the boom so the
  // camera stays inside the room and under its ceiling; outdoors only the
  // raycast against world geometry constrains it.
  update(dt: number, targetX: number, targetZ: number, bounds: ZoneRect | null = null) {
    // ---- pivot (look-at point), with eased vertical follow so stairs glide.
    const targetGroundY = heightAt(targetX, targetZ);
    if (!this.groundInitialized) {
      this.groundY = targetGroundY;
      this.groundInitialized = true;
    } else {
      this.groundY += (targetGroundY - this.groundY) * Math.min(1, GROUND_FOLLOW_RATE * dt);
    }
    this.pivot.set(targetX, LOOK_HEIGHT + this.groundY, targetZ);

    // ---- boom direction from yaw/pitch (instant). Points pivot -> camera.
    // Horizontal component (sin yaw, cos yaw) matches CharacterModel facing.
    const cosPitch = Math.cos(this.pitch);
    this.dir.set(-Math.sin(this.yaw) * cosPitch, Math.sin(this.pitch), Math.cos(this.yaw) * cosPitch);

    // ---- how far the camera may sit along the boom this frame ----
    let limit = FOLLOW_DISTANCE;
    // Room box + ceiling: distance along the boom before it would leave the
    // room (keeps the camera inside without shoving it sideways).
    if (bounds) limit = Math.min(limit, this.boundsDistance(bounds));
    // World geometry between pivot and camera (exterior walls, floor/slab).
    this.raycaster.set(this.pivot, this.dir);
    this.raycaster.far = limit;
    const hits = this.raycaster.intersectObjects(this.obstacles, false);
    if (hits.length > 0 && hits[0].distance < limit) limit = hits[0].distance - COLLISION_SKIN;
    limit = Math.max(MIN_DISTANCE, limit);

    // ---- asymmetric boom smoothing: collapse instantly (never clip / see
    // past a wall), extend smoothly (no pop when a wall clears).
    if (limit <= this.boomLength) {
      this.boomLength = limit;
    } else {
      this.boomLength += (limit - this.boomLength) * Math.min(1, BOOM_EXTEND_RATE * dt);
    }

    // ---- place the camera on the boom, always looking at the pivot (so the
    // character is always centred - no sideways displacement).
    this.camPos.copy(this.pivot).addScaledVector(this.dir, this.boomLength);
    this.camera.position.copy(this.camPos);
    this.camera.lookAt(this.pivot);
  }

  // Largest distance t >= 0 such that pivot + dir*t stays inside the room's
  // inset AABB and below its ceiling - a ray-vs-box exit distance. Because the
  // camera rides the boom, this is a pure length limit (never a sideways move),
  // so it can't decentre the character or snap it between zones.
  private boundsDistance(bounds: ZoneRect): number {
    const EPS = 1e-4;
    let t = FOLLOW_DISTANCE;
    // Floorplan (x, y) maps to three (x, z); yMin/yMax bound desired.z.
    const x1 = bounds.xMin + CLAMP_INSET;
    const x2 = bounds.xMax - CLAMP_INSET;
    const z1 = bounds.yMin + CLAMP_INSET;
    const z2 = bounds.yMax - CLAMP_INSET;
    if (this.dir.x > EPS) t = Math.min(t, (x2 - this.pivot.x) / this.dir.x);
    else if (this.dir.x < -EPS) t = Math.min(t, (x1 - this.pivot.x) / this.dir.x);
    if (this.dir.z > EPS) t = Math.min(t, (z2 - this.pivot.z) / this.dir.z);
    else if (this.dir.z < -EPS) t = Math.min(t, (z1 - this.pivot.z) / this.dir.z);
    // Ceiling (camera is above the pivot whenever pitch > 0, i.e. dir.y > 0).
    if (this.dir.y > EPS) {
      const cy = ceilingHeight(bounds.id) - CEILING_MARGIN;
      t = Math.min(t, (cy - this.pivot.y) / this.dir.y);
    }
    return Math.max(0, t);
  }
}
