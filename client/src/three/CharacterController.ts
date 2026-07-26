import { CharacterModel } from "./CharacterModel";
import { WALLS, CONNECTORS, connectorSealsOwner, resolveFloor, type Rect, type Team } from "../geometry/floorplan";
import { PROP_COLLIDERS } from "../../../shared/props";
import {
  MOVE_SPEED,
  WORLD_WIDTH,
  WORLD_HEIGHT,
  MOVE_ACCEL_RATE,
  MOVE_STOP_RATE,
  GRAVITY,
  STEP_UP_RATE,
  LANDING_IMPACT_MIN,
} from "../constants";
import { visualHeight } from "./world/HeightField";

// Body radius in world units - deliberately NOT scaled by WORLD_SCALE, so the
// character keeps a fixed size and every door gap (80+ units) stays passable.
export const CHAR_RADIUS = 20;

// Another character standing on the same floor is solid too. Supplied by the
// caller (GameController reads them off the remote-player sync) rather than
// imported, so this class keeps knowing only about geometry.
export interface BodyCollider {
  x: number;
  z: number;
  floor: number;
}
// A single frame's movement can exceed a wall's thickness (walls are 14 units
// thick; at the 1/20s dt cap the character covers ~11 at PLAYER_SPEED), so the
// move is applied in sub-steps no longer than this with a collision resolve
// after each. Without it a fast frame could tunnel clean THROUGH a wall - which
// is exactly what let characters walk through walls before.
const SUBSTEP = CHAR_RADIUS / 2;

// Moves the character along a caller-supplied world-space direction, resolving
// collision the same way the server resolves bots: axis-separated move-and-slide
// in sub-steps against the walls of the character's CURRENT floor plus its own
// team's sealed connectors. Floor is derived from position each sub-step, so
// walking onto a staircase/ladder changes floor (and therefore which walls are
// solid) exactly as it does server-side.
export class CharacterController {
  x: number;
  z: number;
  y = 0; // render height - eased over stairs, gravity-driven in the air
  floor = 0;
  vx = 0;
  vz = 0;
  vy = 0;
  airborne = false;
  private landingImpact = 0;
  // Other characters to treat as solid this frame. Re-supplied by the owner
  // each update, so it always reflects where everyone actually is.
  private bodies: readonly BodyCollider[] = [];

  constructor(
    readonly model: CharacterModel,
    private team: Team,
    startX: number,
    startZ: number,
    startFloor = 0
  ) {
    this.x = startX;
    this.z = startZ;
    this.floor = startFloor;
    this.y = visualHeight(this.x, this.z, this.floor, this.team);
    this.applyTransform();
  }

  setBodies(bodies: readonly BodyCollider[]) {
    this.bodies = bodies;
  }

  update(dt: number, moveX: number, moveZ: number) {
    // ---- horizontal: ease velocity toward the desired direction ----
    // Exponential approach, so identical feel at any frame rate. Accelerating
    // and stopping use different rates: you get up to speed with a little ramp
    // but pull up fairly sharply, which reads as controlled rather than icy.
    let desiredX = 0;
    let desiredZ = 0;
    if (moveX !== 0 || moveZ !== 0) {
      const len = Math.hypot(moveX, moveZ);
      desiredX = (moveX / len) * MOVE_SPEED;
      desiredZ = (moveZ / len) * MOVE_SPEED;
    }
    const rate = desiredX === 0 && desiredZ === 0 ? MOVE_STOP_RATE : MOVE_ACCEL_RATE;
    const t = 1 - Math.exp(-rate * dt);
    this.vx += (desiredX - this.vx) * t;
    this.vz += (desiredZ - this.vz) * t;
    if (Math.hypot(this.vx, this.vz) < 1) {
      this.vx = 0;
      this.vz = 0;
    }

    const beforeX = this.x;
    const beforeZ = this.z;
    this.moveWithCollision(this.vx * dt, this.vz * dt);

    // Velocity reported to the server is what ACTUALLY happened, not what was
    // asked for - so a character pressed into a wall reads as stopped (and its
    // walk animation settles) instead of jogging on the spot.
    const movedX = this.x - beforeX;
    const movedZ = this.z - beforeZ;
    if (dt > 0) {
      this.vx = movedX / dt;
      this.vz = movedZ / dt;
    }

    this.updateVertical(dt);

    // Continuous 0..1 blend instead of a binary on/off, so the walk cycle fades
    // in and out with the actual gait rather than popping.
    this.model.update(dt, Math.min(1, Math.hypot(this.vx, this.vz) / MOVE_SPEED));
  }

  // Ground height is a target, not an assignment: rising ground (stairs) is
  // eased so you walk up it, while ground BELOW you is a fall under gravity.
  // Previously the model's y was set straight from visualHeight, so walking off
  // a balcony teleported the character down a whole storey in one frame.
  private updateVertical(dt: number) {
    const groundY = visualHeight(this.x, this.z, this.floor, this.team);
    if (this.y > groundY + 0.5) {
      this.airborne = true;
      this.vy -= GRAVITY * dt;
      this.y += this.vy * dt;
      if (this.y <= groundY) {
        // Landed. Impact speed drives the thud + camera kick.
        this.landingImpact = Math.max(this.landingImpact, Math.abs(this.vy));
        this.y = groundY;
        this.vy = 0;
        this.airborne = false;
      }
    } else {
      this.y += (groundY - this.y) * Math.min(1, STEP_UP_RATE * dt);
      if (Math.abs(groundY - this.y) < 0.5) this.y = groundY;
      this.vy = 0;
      this.airborne = false;
    }
    this.model.root.position.set(this.x, this.y, this.z);
  }

  // Landing speed in world units/sec, or 0 if nothing worth reacting to.
  consumeLandingImpact(): number {
    const impact = this.landingImpact;
    this.landingImpact = 0;
    return impact < LANDING_IMPACT_MIN ? 0 : impact;
  }

  // Server-authoritative snap (phase changes / jail): position AND floor come
  // from the server, so the character lands on the right level.
  freeze(x: number, z: number, floor: number) {
    this.x = x;
    this.z = z;
    this.floor = floor;
    this.vx = 0;
    this.vz = 0;
    this.vy = 0;
    this.airborne = false;
    this.landingImpact = 0;
    this.y = visualHeight(this.x, this.z, this.floor, this.team);
    this.applyTransform();
  }

  private applyTransform() {
    this.model.root.position.set(this.x, this.y, this.z);
  }

  // Axis-separated move-and-slide: each axis is attempted alone and reverted if
  // it would put the body inside a wall, so pressing diagonally into a wall
  // beside a doorway keeps the unblocked axis and slides into the gap instead
  // of sticking. A blocked axis is simply not taken, so the body never ends up
  // inside geometry and no push-out pass is needed.
  private moveWithCollision(dx: number, dz: number) {
    const total = Math.hypot(dx, dz);
    const steps = Math.max(1, Math.ceil(total / SUBSTEP));
    const sx = dx / steps;
    const sz = dz / steps;
    for (let i = 0; i < steps; i++) {
      // Escape first if we are ALREADY inside geometry. Crossing a connector's
      // midline flips the floor, which changes WHICH walls are solid - so a body
      // can be left standing inside a wall that only exists on the floor it just
      // arrived on. Move-and-slide alone can never free it (every axis ends in a
      // wall, so both get reverted) and the player is stuck for good.
      this.unstick();
      const ox = this.x;
      this.x = Math.max(0, Math.min(WORLD_WIDTH, this.x + sx));
      if (this.hitsWall()) this.x = ox;
      const oz = this.z;
      this.z = Math.max(0, Math.min(WORLD_HEIGHT, this.z + sz));
      if (this.hitsWall()) this.z = oz;
      // Crossing a staircase/ladder mid-step flips the floor, so collision
      // switches to the destination floor's walls exactly as we arrive.
      this.floor = resolveFloor(this.x, this.z, this.floor, this.team);
    }
    this.unstick();
  }

  // Push the body out of anything it overlaps, shallowest penetration first.
  // A no-op in the normal case (nothing overlapping), so it costs nothing.
  private unstick() {
    for (let pass = 0; pass < 4; pass++) {
      let corrected = false;
      // Bodies first - two circles separate along the line between centres.
      for (const b of this.bodies) {
        if (b.floor !== this.floor) continue;
        const dx = this.x - b.x;
        const dz = this.z - b.z;
        const distSq = dx * dx + dz * dz;
        const minDist = CHAR_RADIUS * 2;
        if (distSq >= minDist * minDist) continue;
        const dist = Math.sqrt(distSq);
        const nx = dist > 1e-6 ? dx / dist : 1;
        const nz = dist > 1e-6 ? dz / dist : 0;
        this.x = b.x + nx * minDist;
        this.z = b.z + nz * minDist;
        corrected = true;
      }
      for (const r of this.activeColliders()) {
        const cx = Math.max(r.x1, Math.min(this.x, r.x2));
        const cz = Math.max(r.y1, Math.min(this.z, r.y2));
        const dx = this.x - cx;
        const dz = this.z - cz;
        const distSq = dx * dx + dz * dz;
        if (distSq >= CHAR_RADIUS * CHAR_RADIUS) continue;
        const dist = Math.sqrt(distSq);
        if (dist > 1e-6) {
          const push = (CHAR_RADIUS - dist) / dist;
          this.x += dx * push;
          this.z += dz * push;
        } else {
          // Dead centre inside the rect - leave by the nearest face.
          const west = this.x - r.x1;
          const east = r.x2 - this.x;
          const north = this.z - r.y1;
          const south = r.y2 - this.z;
          const min = Math.min(west, east, north, south);
          if (min === west) this.x = r.x1 - CHAR_RADIUS;
          else if (min === east) this.x = r.x2 + CHAR_RADIUS;
          else if (min === north) this.z = r.y1 - CHAR_RADIUS;
          else this.z = r.y2 + CHAR_RADIUS;
        }
        corrected = true;
      }
      if (!corrected) break;
    }
  }

  // Static colliders active right now: every wall on the current floor (or a
  // floor-less world-boundary wall), the solid furniture on it, plus this
  // team's own sealed connectors that actually block - its bedroom stairs and
  // balcony ladders. A sealed route DOWN is a walk-over lid, not a block
  // (connectorSealsOwner), which is what the server enforces too.
  private *activeColliders(): Generator<Rect> {
    for (const w of WALLS) {
      if (w.floor === undefined || w.floor === this.floor) yield w;
    }
    for (const p of PROP_COLLIDERS) {
      if (p.floor === this.floor) yield p;
    }
    for (const c of CONNECTORS) {
      if (c.sealedFor === this.team && connectorSealsOwner(c)) yield c.rect;
    }
  }

  private hitsWall(): boolean {
    for (const r of this.activeColliders()) {
      const cx = Math.max(r.x1, Math.min(this.x, r.x2));
      const cz = Math.max(r.y1, Math.min(this.z, r.y2));
      const dx = this.x - cx;
      const dz = this.z - cz;
      if (dx * dx + dz * dz < CHAR_RADIUS * CHAR_RADIUS) return true;
    }
    // Bodies are deliberately NOT tested here - see unstick(). Blocking a move
    // on another character deadlocks two bodies that touch (every axis of every
    // move ends inside the other), so characters are made solid by separation
    // instead: you shove past each other rather than stopping dead.
    return false;
  }
}
