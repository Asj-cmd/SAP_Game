import type { Room } from "colyseus.js";
import { colyseusClient } from "../network/ColyseusClient";
import { SceneManager } from "./SceneManager";
import { buildEnvironment } from "./EnvironmentBuilder";
import { CharacterModel, pickFamilyVariant } from "./CharacterModel";
import { CharacterController, type BodyCollider } from "./CharacterController";
import { CameraRig } from "./CameraRig";
import { RemoteCharacterSync } from "./RemoteCharacterSync";
import { CashBundleView } from "./CashBundleView";
import { dressHouses } from "./world/HouseDresser";
import { RoofSystem, ROOFED_ZONES } from "./world/RoofSystem";
import { HudOverlay } from "../ui/HudOverlay";
import { AudioSystem } from "../audio/AudioSystem";
import { ParticleBurst } from "./juice/ParticleBurst";
import { GamepadInput, type GamepadFrame } from "./input/GamepadInput";
import {
  ZONE_RECTS,
  getZoneAt,
  isEnemyBedroom,
  isOwnHome,
  jailBasementForTeam,
  type Team,
  type ZoneRect,
} from "../geometry/floorplan";
import { MOVE_SEND_INTERVAL_MS, ACTION_RANGE, MOUSE_SENSITIVITY, COLORS, STORY_HEIGHT, GRAVITY } from "../constants";

type Action =
  | { kind: "pickupCash"; bundleId: string; prompt: string }
  | { kind: "lockPlayer"; targetId: string; prompt: string }
  | { kind: "rescuePlayer"; targetId: string; prompt: string }
  | { kind: "stealScored"; bundleId: string; prompt: string }
  | null;

interface InputState {
  left: boolean;
  right: boolean;
  up: boolean;
  down: boolean;
}

function dist(ax: number, ay: number, bx: number, by: number): number {
  return Math.hypot(ax - bx, ay - by);
}

// The per-match orchestrator: owns the 3D scene, local character/camera,
// remote sync, cash bundle view, and HUD, and drives the same per-frame logic
// GameScene.ts + UIScene.ts did together in the 2D build (client-side action
// availability detection, SPACE handling, auto-deposit-on-threshold) - now
// consolidated into one class since there's one render loop, not two Phaser
// scenes running in parallel.
export class GameController {
  private sceneManager: SceneManager;
  private room: Room;
  private localId: string;
  private localTeam: Team;

  private controller!: CharacterController;
  private cameraRig!: CameraRig;
  private remoteSync: RemoteCharacterSync;
  private cashView!: CashBundleView;
  private roofSystem!: RoofSystem;
  private hud: HudOverlay;
  // ---- juice layer: reads server state + local motion and produces feedback.
  // Strictly one-way (state -> feedback); nothing here can affect simulation.
  private audio = new AudioSystem();
  private particles!: ParticleBurst;
  private gamepad = new GamepadInput();
  private padFrame: GamepadFrame | null = null;
  private wasCarrying = false;
  private jailedLast = new Set<string>();
  private prevPhase2 = "";
  // Where every player was on the PREVIOUS frame. A jail/rescue teleports the
  // player before the client sees the transition, so the burst has to be drawn
  // at the spot it happened, not at the cell it ended in.
  private lastPos = new Map<string, { x: number; y: number; floor: number }>();
  // The last player this client acted ON. Jail/rescue feedback is for the two
  // people involved only - previously every jailing anywhere in the map threw
  // sparks in front of whoever was watching.
  private actedOnId = "";
  // Reused each frame so treating other characters as solid allocates nothing.
  private bodies: BodyCollider[] = [];

  private input: InputState = { left: false, right: false, up: false, down: false };
  private spaceJustPressed = false;
  private moveAccumulatorMs = 0;
  private depositSent = false;
  private currentAction: Action = null;
  // Tracked so we can detect the ONE frame the phase transitions into
  // "matchEnd" and free the cursor then, rather than fighting pointer lock
  // every frame while the result screen is up.
  private prevPhase = "";

  private canvasContainer: HTMLElement;
  // Cheap invert-Y read once at construction; no settings UI yet, so this is
  // the only way to flip it today (a real options menu comes later).
  private readonly invertY = localStorage.getItem("cashgrab.invertY") === "1";

  private keydownHandler = (e: KeyboardEvent) => this.onKey(e.key.toLowerCase(), true);
  private keyupHandler = (e: KeyboardEvent) => this.onKey(e.key.toLowerCase(), false);
  // Browsers only allow pointer lock from a user gesture, hence the click.
  private clickHandler = () => {
    // Browsers only allow audio to start from a user gesture.
    this.audio.unlock();
    if (document.pointerLockElement !== this.canvasContainer) {
      this.canvasContainer.requestPointerLock();
    }
  };
  private mouseMoveHandler = (e: MouseEvent) => {
    if (document.pointerLockElement !== this.canvasContainer) return;
    this.cameraRig?.addYaw(e.movementX * MOUSE_SENSITIVITY);
    // Mouse up (negative movementY) pitches the camera up by default -
    // toward CameraRig's PITCH_MIN, i.e. up the basement/bedroom staircases.
    this.cameraRig?.addPitch(e.movementY * MOUSE_SENSITIVITY * (this.invertY ? -1 : 1));
  };
  private pointerLockChangeHandler = () => {
    this.hud.setMouseHint(document.pointerLockElement !== this.canvasContainer);
  };

  private constructor(canvasContainer: HTMLElement, hudContainer: HTMLElement, room: Room) {
    this.room = room;
    this.localId = room.sessionId;
    const selfState = room.state.players.get(this.localId);
    this.localTeam = (selfState?.team as Team) || "B";

    this.canvasContainer = canvasContainer;
    this.sceneManager = new SceneManager(canvasContainer);
    this.remoteSync = new RemoteCharacterSync(this.sceneManager.scene);
    this.hud = new HudOverlay(hudContainer, this.localTeam, () => colyseusClient.send("rematch"));
    this.hud.setMouseHint(true);

    window.addEventListener("keydown", this.keydownHandler);
    window.addEventListener("keyup", this.keyupHandler);
    canvasContainer.addEventListener("click", this.clickHandler);
    window.addEventListener("mousemove", this.mouseMoveHandler);
    document.addEventListener("pointerlockchange", this.pointerLockChangeHandler);
  }

  static async start(canvasContainer: HTMLElement, hudContainer: HTMLElement, room: Room): Promise<GameController> {
    const gc = new GameController(canvasContainer, hudContainer, room);
    const selfState = room.state.players.get(gc.localId);

    const env = buildEnvironment(gc.localTeam);
    gc.sceneManager.scene.add(...env.meshes);

    const model = await CharacterModel.load(gc.localTeam, pickFamilyVariant(room.state.players, gc.localId));
    gc.sceneManager.scene.add(model.root);

    gc.controller = new CharacterController(
      model,
      gc.localTeam,
      selfState?.x ?? 0,
      selfState?.y ?? 0,
      selfState?.floor ?? 0
    );
    // Camera obstacles: walls + floor (slabs/foundation/lawn) so looking down
    // in the basement can't see through the slab into the void below it -
    // props/roofs never pull the chase camera in, and window glass is left
    // out since it's translucent and shouldn't block the view.
    gc.cameraRig = new CameraRig(gc.sceneManager.camera, env.occluders);

    gc.cashView = await CashBundleView.create(gc.sceneManager.scene);

    gc.particles = new ParticleBurst(gc.sceneManager.scene);

    gc.roofSystem = new RoofSystem();
    gc.roofSystem.build(gc.sceneManager.scene);

    // Decorative furniture/dressing (non-collidable) - fire and forget; props
    // stream in as their GLBs resolve without blocking the match start.
    void dressHouses(gc.sceneManager.scene);

    gc.sceneManager.start((dt) => gc.tick(dt));
    return gc;
  }

  private onKey(k: string, down: boolean) {
    if (k === "a" || k === "arrowleft") this.input.left = down;
    if (k === "d" || k === "arrowright") this.input.right = down;
    if (k === "w" || k === "arrowup") this.input.up = down;
    if (k === "s" || k === "arrowdown") this.input.down = down;
    if (k === " " && down) this.spaceJustPressed = true;
    if (k === "m" && down) this.audio.setMuted(!this.audio.isMuted());
  }

  private tick(dt: number) {
    const room = this.room;
    const selfState = room.state.players.get(this.localId);
    if (!selfState) return;

    // Free the mouse the instant the result screen appears - the player needs
    // a visible cursor to click the rematch button, and pointer lock has no
    // reason to hold on through a screen with no camera-look gameplay left.
    const phase = room.state.phase;
    if (phase === "matchEnd" && this.prevPhase !== "matchEnd" && document.pointerLockElement === this.canvasContainer) {
      document.exitPointerLock();
    }
    this.prevPhase = phase;

    // Gamepad is polled before movement so stick input joins the same frame as
    // the keyboard's, and the right stick feeds the camera like the mouse does.
    const pad = this.gamepad.poll(dt);
    if (pad.connected) {
      this.cameraRig.addYaw(pad.lookX);
      this.cameraRig.addPitch(pad.lookY * (this.invertY ? -1 : 1));
      if (pad.actionPressed) this.spaceJustPressed = true;
    }
    this.padFrame = pad;

    this.updateLocalMovement(dt, selfState);
    this.remoteSync.sync(dt, room, this.localId);
    this.cashView.sync(room);
    this.updateAction(selfState);
    this.handleSpaceInput();
    this.maybeAutoDeposit(selfState);
    this.updateFeedback(dt, room, selfState);
    this.particles.update(dt);

    this.hud.update(room, this.currentAction?.prompt ?? "");
    this.spaceJustPressed = false;
  }

  // The rect CameraRig clamps its position into: the character's current zone
  // if it's an enclosed interior room (RoofSystem's own ROOFED_ZONES list),
  // null in the open-air garden/backyards. Same getZoneAt lookup the roof
  // reveal already does each frame.
  private cameraBounds(): ZoneRect | null {
    const zone = getZoneAt(this.controller.x, this.controller.z, this.controller.floor);
    if (!ROOFED_ZONES.includes(zone)) return null;
    return ZONE_RECTS.find((z) => z.id === zone && z.floor === this.controller.floor) ?? null;
  }

  // Ports GameScene.updateLocalMovement: outside "playing" or while jailed,
  // the server is fully authoritative - snap to its position every frame
  // instead of processing input, exactly as the 2D build's body.reset() did.
  private updateLocalMovement(dt: number, selfState: any) {
    const model = this.controller.model;
    const playing = this.room.state.phase === "playing";

    if (!playing || selfState.isJailed) {
      this.controller.freeze(selfState.x, selfState.y, selfState.floor ?? 0);
      model.setJailed(selfState.isJailed);
      model.setCarrying(selfState.isCarryingCash);
      model.update(dt, 0);
      this.cameraRig.update(dt, this.controller.x, this.controller.z, model.root.position.y, this.cameraBounds());
      this.depositSent = false;
      return;
    }
    model.setJailed(false);
    // Your own overhead bundle: previously only set on the frozen path above,
    // so everyone BUT you could see you were carrying.
    model.setCarrying(selfState.isCarryingCash);

    // FPS-style controls: the mouse owns the camera heading (pointer lock ->
    // CameraRig.addYaw), and WASD/arrows move relative to it - W walks the
    // direction the camera faces, A/D strafe, S walks back toward the camera.
    let f = (this.input.up ? 1 : 0) - (this.input.down ? 1 : 0);
    let s = (this.input.right ? 1 : 0) - (this.input.left ? 1 : 0);
    // Stick adds to the keys, so either (or both) drives the same motion.
    if (this.padFrame?.connected) {
      f = Math.max(-1, Math.min(1, f + this.padFrame.moveZ));
      s = Math.max(-1, Math.min(1, s + this.padFrame.moveX));
    }
    const yaw = this.cameraRig.getYaw();
    const moveX = Math.sin(yaw) * f + Math.cos(yaw) * s;
    const moveZ = -Math.cos(yaw) * f + Math.sin(yaw) * s;
    // Other characters are solid: hand the motor everyone else's authoritative
    // position so it slides around them like any other obstacle.
    this.bodies.length = 0;
    this.room.state.players.forEach((p: any, id: string) => {
      if (id === this.localId || p.isJailed) return;
      this.bodies.push({ x: p.x, z: p.y, floor: p.floor ?? 0 });
    });
    this.controller.setBodies(this.bodies);
    this.controller.update(dt, moveX, moveZ);
    // Facing tracks the camera continuously, moving or not - true third-person
    // mouse-look. No smoothing: pointer-lock deltas arrive a few pixels per
    // frame, so the character turns exactly as fast as the view does.
    this.controller.model.setFacingAngle(yaw);
    this.cameraRig.update(dt, this.controller.x, this.controller.z, this.controller.model.root.position.y, this.cameraBounds());

    this.moveAccumulatorMs += dt * 1000;
    if (this.moveAccumulatorMs >= MOVE_SEND_INTERVAL_MS) {
      this.moveAccumulatorMs = 0;
      colyseusClient.send("move", {
        x: this.controller.x,
        y: this.controller.z,
        vx: this.controller.vx,
        vy: this.controller.vz,
      });
    }
  }

  // Ports GameScene.updateAction verbatim (same 5 checks, same priority order,
  // same ACTION_RANGE), just reading local position off the character
  // controller instead of a Phaser sprite.
  private updateAction(selfState: any) {
    const room = this.room;
    if (!selfState || selfState.isJailed || room.state.phase !== "playing") {
      this.currentAction = null;
      return;
    }

    const x = this.controller.x;
    const y = this.controller.z;
    const floor = this.controller.floor;
    const team = this.localTeam;
    const enemyBedroom = team === "B" ? "bedroomA" : "bedroomB";
    const enemyTeam: Team = team === "B" ? "A" : "B";

    let action: Action = null;

    if (!selfState.isCarryingCash && isEnemyBedroom(team, x, y, floor)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === enemyBedroom && dist(x, y, b.x, b.y) <= ACTION_RANGE) {
          action = { kind: "pickupCash", bundleId: b.id, prompt: "SPACE: Pick up cash" };
        }
      });
    }

    if (!action && isOwnHome(team, x, y, floor)) {
      let nearest: { id: string; name: string; d: number } | null = null;
      room.state.players.forEach((p: any, id: string) => {
        if (id === this.localId || p.team === team || p.isJailed) return;
        const d = dist(x, y, p.x, p.y);
        if (d <= ACTION_RANGE && (!nearest || d < nearest.d)) nearest = { id, name: p.name, d };
      });
      if (nearest) {
        const n = nearest as { id: string; name: string; d: number };
        action = { kind: "lockPlayer", targetId: n.id, prompt: `SPACE: Lock ${n.name}` };
      }
    }

    if (!action && getZoneAt(x, y, floor) === jailBasementForTeam(team)) {
      let nearest: { id: string; name: string; d: number } | null = null;
      room.state.players.forEach((p: any, id: string) => {
        if (id === this.localId || p.team !== team || !p.isJailed) return;
        const d = dist(x, y, p.x, p.y);
        if (d <= ACTION_RANGE && (!nearest || d < nearest.d)) nearest = { id, name: p.name, d };
      });
      if (nearest) {
        const n = nearest as { id: string; name: string; d: number };
        action = { kind: "rescuePlayer", targetId: n.id, prompt: `SPACE: Rescue ${n.name}` };
      }
    }

    if (!action && !selfState.isCarryingCash && isEnemyBedroom(team, x, y, floor)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === `scored:${enemyTeam}` && dist(x, y, b.x, b.y) <= ACTION_RANGE) {
          action = { kind: "stealScored", bundleId: b.id, prompt: "SPACE: Steal scored cash" };
        }
      });
    }

    this.currentAction = action;
  }

  // Turns state changes + local motion into feedback. One-way: it only reads.
  // Events are detected by diffing the previous frame's server state, so it
  // works identically for things the local player did and things that happened
  // to them (getting jailed, a teammate being freed).
  private updateFeedback(dt: number, room: Room, selfState: any) {
    const model = this.controller.model;
    const pos = model.root.position;

    // Landings come from the motor, which knows what actually happened (impact
    // speed) rather than what was requested. Walking itself is silent by
    // design - a tick per stride was the most-repeated sound in the game and
    // read as grating rather than as feedback.
    const impact = this.controller.consumeLandingImpact();
    if (impact > 0) {
      // Normalised against the speed reached falling one full storey.
      const hardness = Math.min(1, impact / Math.sqrt(2 * GRAVITY * STORY_HEIGHT));
      this.audio.play("land", 0.6 + hardness);
      this.cameraRig.addTrauma(0.12 + hardness * 0.22);
    }

    // Local player picked up / banked cash.
    const carrying = !!selfState.isCarryingCash;
    if (carrying && !this.wasCarrying) {
      this.audio.play("pickup");
      this.particles.burst(pos.x, pos.y + 60, pos.z, COLORS.cash, 18, 210);
    } else if (!carrying && this.wasCarrying && !selfState.isJailed) {
      this.audio.play("deposit");
      this.particles.burst(pos.x, pos.y + 50, pos.z, COLORS.cash, 34, 300);
      this.cameraRig.addTrauma(0.3);
    }
    this.wasCarrying = carrying;

    // Jail / rescue. The sound is a match-wide cue (you want to know a teammate
    // went down), but the BURST is drawn only for the two people involved -
    // whoever it happened to, and whoever did it. Everyone else used to get a
    // shower of sparks in their face, drawn at the victim's post-teleport
    // position, i.e. inside a basement they might not even be standing in.
    room.state.players.forEach((p: any, id: string) => {
      const wasJailed = this.jailedLast.has(id);
      const involved = id === this.localId || id === this.actedOnId;
      // Where it actually happened, before the server moved them to the cell.
      const at = this.lastPos.get(id) ?? { x: p.x, y: p.y, floor: p.floor ?? 0 };
      if (p.isJailed && !wasJailed) {
        this.jailedLast.add(id);
        this.audio.play("jail");
        if (involved) {
          this.particles.burst(at.x, at.floor * STORY_HEIGHT + 60, at.y, COLORS.teamA, 26, 260);
          // Being jailed yourself hits much harder than doing the jailing.
          this.cameraRig.addTrauma(id === this.localId ? 0.6 : 0.18);
        }
      } else if (!p.isJailed && wasJailed) {
        this.jailedLast.delete(id);
        this.audio.play("rescue");
        if (involved) this.particles.burst(at.x, at.floor * STORY_HEIGHT + 60, at.y, COLORS.cash, 16, 200);
      }
      this.lastPos.set(id, { x: p.x, y: p.y, floor: p.floor ?? 0 });
    });

    // Round / match result stingers, from the LOCAL team's point of view - a
    // win and a loss must never sound the same.
    const phase = room.state.phase;
    if (phase !== this.prevPhase2) {
      if (phase === "roundEnd") {
        const winner = room.state.roundWinner;
        if (!winner) this.audio.play("roundEnd"); // drawn round
        else if (winner === this.localTeam) {
          this.audio.play("win");
          this.particles.burst(pos.x, pos.y + 70, pos.z, COLORS.cash, 40, 320);
        } else {
          this.audio.play("lose");
        }
      } else if (phase === "matchEnd") {
        const won = room.state.matchWinner === this.localTeam;
        this.audio.play(won ? "matchWin" : "matchLose");
        if (won) {
          this.particles.burst(pos.x, pos.y + 80, pos.z, COLORS.cash, 60, 380);
          this.cameraRig.addTrauma(0.35);
        }
      }
      this.prevPhase2 = phase;
    }
  }

  private handleSpaceInput() {
    if (!this.spaceJustPressed || !this.currentAction) return;

    switch (this.currentAction.kind) {
      case "pickupCash":
        colyseusClient.send("pickupCash", { bundleId: this.currentAction.bundleId });
        break;
      case "lockPlayer":
        // Remembered so the jail burst can be shown to the jailer as well as
        // the jailed, and to nobody else (see updateFeedback).
        this.actedOnId = this.currentAction.targetId;
        colyseusClient.send("lockPlayer", { targetId: this.currentAction.targetId });
        break;
      case "rescuePlayer":
        this.actedOnId = this.currentAction.targetId;
        colyseusClient.send("rescuePlayer", { targetId: this.currentAction.targetId });
        break;
      case "stealScored":
        colyseusClient.send("stealScored", { bundleId: this.currentAction.bundleId });
        break;
    }
  }

  // Ports GameScene.maybeAutoDeposit verbatim, including the "push a fresh
  // position before depositing" trick (move messages are throttled to 20/s
  // otherwise, so the server could validate against a stale position).
  private maybeAutoDeposit(selfState: any) {
    const room = this.room;
    if (!selfState || room.state.phase !== "playing" || !selfState.isCarryingCash) {
      this.depositSent = false;
      return;
    }
    if (!isOwnHome(this.localTeam, this.controller.x, this.controller.z, this.controller.floor)) {
      this.depositSent = false;
      return;
    }
    if (this.depositSent) return;

    let carriedId: string | null = null;
    room.state.cashBundles.forEach((b: any, id: string) => {
      if (b.location === `carried:${this.localId}`) carriedId = id;
    });
    if (!carriedId) return;

    colyseusClient.send("move", {
      x: this.controller.x,
      y: this.controller.z,
      vx: this.controller.vx,
      vy: this.controller.vz,
    });
    this.depositSent = true;
    colyseusClient.send("depositCash", { bundleId: carriedId });
  }

  dispose() {
    window.removeEventListener("keydown", this.keydownHandler);
    window.removeEventListener("keyup", this.keyupHandler);
    this.canvasContainer.removeEventListener("click", this.clickHandler);
    window.removeEventListener("mousemove", this.mouseMoveHandler);
    document.removeEventListener("pointerlockchange", this.pointerLockChangeHandler);
    if (document.pointerLockElement === this.canvasContainer) document.exitPointerLock();
    this.hud.dispose();
    this.sceneManager.dispose();
  }
}
