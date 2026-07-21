import { CharacterModel } from "./CharacterModel";
import { WALLS, CONNECTORS, resolveFloor, type Rect, type Team } from "../geometry/floorplan";
import { PLAYER_SPEED, CARRY_SPEED, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";
import { visualHeight } from "./world/HeightField";

// World units; tuned relative to the narrowest door gaps so the character can
// pass through doors without clipping the frame.
const CHAR_RADIUS = 20;

// Moves the character along a caller-supplied world-space direction plus a
// circle-vs-AABB collision resolve. Now FLOOR-AWARE: the character's floor is
// derived from its position each frame (resolveFloor, mirroring the server), it
// collides only against walls on that floor plus its own team's sealed
// connectors, and its render height follows the floor / connector ramp.
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
    this.model.root.position.set(this.x, visualHeight(this.x, this.z, this.floor, this.team), this.z);
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
      this.x += this.vx * dt;
      this.z += this.vz * dt;
      speedFraction = 1;
    } else {
      this.vx = 0;
      this.vz = 0;
    }

    // Derive floor from the new position (a walked-onto staircase/ladder flips
    // it), then collide against that floor's walls, exactly like the server.
    this.floor = resolveFloor(this.x, this.z, this.floor, this.team);
    this.resolveCollisions();
    this.x = Math.max(0, Math.min(WORLD_WIDTH, this.x));
    this.z = Math.max(0, Math.min(WORLD_HEIGHT, this.z));
    // Re-resolve after collision in case the slide pushed us across a midline.
    this.floor = resolveFloor(this.x, this.z, this.floor, this.team);

    this.model.root.position.set(this.x, visualHeight(this.x, this.z, this.floor, this.team), this.z);
    this.model.update(dt, speedFraction);
  }

  // Server-authoritative snap (phase changes / jail). Floor comes from the
  // server so the character lands on the right level.
  freeze(x: number, z: number, floor: number) {
    this.x = x;
    this.z = z;
    this.floor = floor;
    this.vx = 0;
    this.vz = 0;
    this.model.root.position.set(this.x, visualHeight(this.x, this.z, this.floor, this.team), this.z);
  }

  // Colliders active on the character's current floor: every wall on that floor
  // (or a floor-less world-boundary wall) plus this team's own sealed connectors
  // (its bedroom/basement stairs & ladders - solid to the owner, like the old
  // sealed doors; the enemy walks through them).
  private activeColliders(): Rect[] {
    const rects: Rect[] = [];
    for (const w of WALLS) {
      if (w.floor === undefined || w.floor === this.floor) rects.push(w);
    }
    for (const c of CONNECTORS) {
      if (c.sealedFor === this.team) rects.push(c.rect);
    }
    return rects;
  }

  private resolveCollisions() {
    for (const r of this.activeColliders()) {
      const closestX = Math.max(r.x1, Math.min(this.x, r.x2));
      const closestZ = Math.max(r.y1, Math.min(this.z, r.y2));
      const dx = this.x - closestX;
      const dz = this.z - closestZ;
      const distSq = dx * dx + dz * dz;
      if (distSq < CHAR_RADIUS * CHAR_RADIUS) {
        const dist = Math.sqrt(distSq) || 0.001;
        const push = CHAR_RADIUS - dist;
        this.x += (dx / dist) * push;
        this.z += (dz / dist) * push;
      }
    }
  }
}
