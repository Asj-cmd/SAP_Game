import { CharacterModel } from "./CharacterModel";
import { WALLS, CONNECTORS, resolveFloor, type Rect, type Team } from "../geometry/floorplan";
import { PLAYER_SPEED, CARRY_SPEED, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";
import { visualHeight } from "./world/HeightField";

// Body radius in world units - deliberately NOT scaled by WORLD_SCALE, so the
// character keeps a fixed size and every door gap (80+ units) stays passable.
const CHAR_RADIUS = 20;
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
  floor = 0;
  vx = 0;
  vz = 0;

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
    this.applyTransform();
  }

  update(dt: number, moveX: number, moveZ: number, carrying: boolean) {
    const speed = carrying ? CARRY_SPEED : PLAYER_SPEED;

    let speedFraction = 0;
    if (moveX !== 0 || moveZ !== 0) {
      const len = Math.hypot(moveX, moveZ);
      const ndx = moveX / len;
      const ndz = moveZ / len;
      this.vx = ndx * speed;
      this.vz = ndz * speed;
      this.moveWithCollision(this.vx * dt, this.vz * dt);
      speedFraction = 1;
    } else {
      this.vx = 0;
      this.vz = 0;
    }

    this.applyTransform();
    this.model.update(dt, speedFraction);
  }

  // Server-authoritative snap (phase changes / jail): position AND floor come
  // from the server, so the character lands on the right level.
  freeze(x: number, z: number, floor: number) {
    this.x = x;
    this.z = z;
    this.floor = floor;
    this.vx = 0;
    this.vz = 0;
    this.applyTransform();
  }

  private applyTransform() {
    this.model.root.position.set(this.x, visualHeight(this.x, this.z, this.floor, this.team), this.z);
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
  }

  // Colliders active right now: every wall on the current floor (or a
  // floor-less world-boundary wall) plus this team's own sealed connectors -
  // its bedroom/basement stairs and balcony ladders, which are solid to the
  // owner and open to raiders.
  private hitsWall(): boolean {
    const overlaps = (r: Rect) => {
      const cx = Math.max(r.x1, Math.min(this.x, r.x2));
      const cz = Math.max(r.y1, Math.min(this.z, r.y2));
      const dx = this.x - cx;
      const dz = this.z - cz;
      return dx * dx + dz * dz < CHAR_RADIUS * CHAR_RADIUS;
    };
    for (const w of WALLS) {
      if (w.floor !== undefined && w.floor !== this.floor) continue;
      if (overlaps(w)) return true;
    }
    for (const c of CONNECTORS) {
      if (c.sealedFor === this.team && overlaps(c.rect)) return true;
    }
    return false;
  }
}
