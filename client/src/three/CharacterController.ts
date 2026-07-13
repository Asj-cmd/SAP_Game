import { CharacterModel } from "./CharacterModel";
import type { Rect } from "../geometry/floorplan";
import { PLAYER_SPEED, CARRY_SPEED, WORLD_WIDTH, WORLD_HEIGHT } from "../constants";

// World units; tuned relative to the narrowest door gaps (90+ units at the
// current WORLD_SCALE) so the character can pass through doors without
// clipping the frame.
const CHAR_RADIUS = 20;

// Moves the character along a caller-supplied world-space direction (the
// GameController rotates raw WASD by the camera's yaw first, so controls are
// camera-relative) plus a circle-vs-AABB collision resolve against the same
// wall rects Arcade Physics used to collide against in the 2D build.
export class CharacterController {
  x: number;
  z: number;
  // Last-applied velocity (world units/sec), mirroring what the 2D build read
  // off Arcade Physics' body.velocity for the "move" network message.
  vx = 0;
  vz = 0;

  constructor(
    readonly model: CharacterModel,
    private colliderRects: Rect[],
    startX: number,
    startZ: number
  ) {
    this.x = startX;
    this.z = startZ;
    this.model.root.position.set(this.x, 0, this.z);
  }

  // (moveX, moveZ): desired world-space direction, any length (normalized
  // here). faceMovement=false keeps the current heading while moving - used
  // for FPS-style backpedaling, where turning around would spin the camera.
  update(dt: number, moveX: number, moveZ: number, faceMovement: boolean, carrying: boolean) {
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
      if (faceMovement) this.model.setFacing(ndx, ndz);
      speedFraction = 1;
    } else {
      this.vx = 0;
      this.vz = 0;
    }

    this.resolveCollisions();
    this.x = Math.max(0, Math.min(WORLD_WIDTH, this.x));
    this.z = Math.max(0, Math.min(WORLD_HEIGHT, this.z));

    this.model.root.position.set(this.x, 0, this.z);
    this.model.update(dt, speedFraction);
  }

  // Server-authoritative snap for phases outside "playing" or while jailed -
  // mirrors the 2D build's body.reset(x, y): hard-set position, zero velocity.
  freeze(x: number, z: number) {
    this.x = x;
    this.z = z;
    this.vx = 0;
    this.vz = 0;
    this.model.root.position.set(this.x, 0, this.z);
  }

  private resolveCollisions() {
    for (const r of this.colliderRects) {
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
