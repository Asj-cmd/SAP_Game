import * as THREE from "three";
import type { Room } from "colyseus.js";
import { CharacterModel, pickFamilyVariant } from "./CharacterModel";
import { REMOTE_LERP, ROTATION_LERP } from "../constants";
import type { Team } from "../geometry/floorplan";
import { heightAt } from "./world/HeightField";

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
        CharacterModel.load(p.team as Team, pickFamilyVariant(room.state.players, id)).then((model) => {
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
      const wasJailed = entry.lastJailed;
      if (p.isJailed && !wasJailed) {
        model.root.position.set(p.x, heightAt(p.x, p.y), p.y);
      } else {
        // Lerp the ground-plane position exactly as before, then read the
        // height back off the lerped (x, z) - so the model's elevation is
        // always a pure function of its rendered ground position, never
        // lerped toward a stale target height on its own.
        model.root.position.x = THREE.MathUtils.lerp(model.root.position.x, p.x, REMOTE_LERP);
        model.root.position.z = THREE.MathUtils.lerp(model.root.position.z, p.y, REMOTE_LERP);
        model.root.position.y = heightAt(model.root.position.x, model.root.position.z);
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
