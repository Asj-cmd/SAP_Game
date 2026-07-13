import * as THREE from "three";
import type { Room } from "colyseus.js";
import { CharacterModel } from "./CharacterModel";
import { REMOTE_LERP, ROTATION_LERP } from "../constants";
import type { Team } from "../geometry/floorplan";

function lerpAngle(a: number, b: number, t: number): number {
  let diff = b - a;
  diff = Math.atan2(Math.sin(diff), Math.cos(diff)); // wrap to [-pi, pi]
  return a + diff * t;
}

interface RemoteEntry {
  model: CharacterModel | null; // null while the glTF is still loading
  lastJailed: boolean;
  facingAngle: number;
}

// Ports GameScene.syncRemotePlayers: spawns/despawns a CharacterModel per
// remote player, lerps position at REMOTE_LERP (hard-snapping on the
// false->true isJailed transition, exactly as the 2D build did), lerps
// facing angle (its own constant - naive lerp on raw angles would spin the
// long way around at the +/-pi wraparound), and blends the Idle/Walk
// animation from the reported vx/vy speed.
export class RemoteCharacterSync {
  private remotes = new Map<string, RemoteEntry>();

  constructor(private scene: THREE.Scene) {}

  sync(dt: number, room: Room, localId: string) {
    const seen = new Set<string>();

    room.state.players.forEach((p: any, id: string) => {
      if (id === localId) return;
      seen.add(id);

      let entry = this.remotes.get(id);
      if (!entry) {
        // Reserve the slot synchronously so a second sync() call before the
        // glTF resolves doesn't kick off a duplicate load.
        entry = { model: null, lastJailed: p.isJailed, facingAngle: 0 };
        this.remotes.set(id, entry);
        CharacterModel.load(p.team as Team).then((model) => {
          const stillWanted = this.remotes.get(id);
          if (!stillWanted) {
            return; // player left while the model was loading
          }
          this.scene.add(model.root);
          stillWanted.model = model;
        });
        return;
      }
      if (!entry.model) return; // still loading

      const model = entry.model;
      const target = new THREE.Vector3(p.x, 0, p.y);
      const wasJailed = entry.lastJailed;
      if (p.isJailed && !wasJailed) {
        model.root.position.copy(target);
      } else {
        model.root.position.lerp(target, REMOTE_LERP);
      }
      entry.lastJailed = p.isJailed;

      const speed = Math.hypot(p.vx, p.vy);
      if (!p.isJailed && speed > 1) {
        const targetAngle = Math.atan2(p.vx, -p.vy);
        entry.facingAngle = lerpAngle(entry.facingAngle, targetAngle, ROTATION_LERP);
        model.root.rotation.y = entry.facingAngle;
      }

      model.setCarrying(p.isCarryingCash);
      model.setJailed(p.isJailed);
      // Binary walk/idle switch, matching CharacterController's local logic
      // exactly (speedFraction there is 1 whenever any input is held, 0
      // otherwise - not a continuous ratio of actual speed).
      model.update(dt, !p.isJailed && speed > 1 ? 1 : 0);
    });

    for (const [id, entry] of this.remotes) {
      if (!seen.has(id)) {
        if (entry.model) this.scene.remove(entry.model.root);
        this.remotes.delete(id);
      }
    }
  }
}
