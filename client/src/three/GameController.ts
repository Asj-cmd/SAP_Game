import type { Room } from "colyseus.js";
import { colyseusClient } from "../network/ColyseusClient";
import { SceneManager } from "./SceneManager";
import { buildEnvironment } from "./EnvironmentBuilder";
import { CharacterModel, pickFamilyVariant } from "./CharacterModel";
import { CharacterController } from "./CharacterController";
import { CameraRig } from "./CameraRig";
import { RemoteCharacterSync } from "./RemoteCharacterSync";
import { CashBundleView } from "./CashBundleView";
import { dressHouses } from "./world/HouseDresser";
import { RoofSystem } from "./world/RoofSystem";
import { HudOverlay } from "../ui/HudOverlay";
import { getZoneAt, isEnemyBedroom, isOwnHome, jailBasementForTeam, type Team } from "../geometry/floorplan";
import { MOVE_SEND_INTERVAL_MS, ACTION_RANGE, MOUSE_SENSITIVITY } from "../constants";

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
    gc.sceneManager.scene.add(env.wallsMesh, env.floorMesh, env.windowGlassMesh);

    const model = await CharacterModel.load(gc.localTeam, pickFamilyVariant(room.state.players, gc.localId));
    gc.sceneManager.scene.add(model.root);

    const dresser = await dressHouses(gc.sceneManager.scene);
    gc.controller = new CharacterController(
      model,
      [...env.colliderRects, ...dresser.solidRects],
      selfState?.x ?? 0,
      selfState?.y ?? 0
    );
    // Camera obstacles: walls + floor (slabs/foundation/lawn) so looking down
    // in the basement can't see through the slab into the void below it -
    // props/roofs never pull the chase camera in, and window glass is left
    // out since it's translucent and shouldn't block the view.
    gc.cameraRig = new CameraRig(gc.sceneManager.camera, [env.wallsMesh, env.floorMesh]);

    gc.cashView = await CashBundleView.create(gc.sceneManager.scene);

    gc.roofSystem = new RoofSystem();
    gc.roofSystem.build(gc.sceneManager.scene);

    gc.sceneManager.start((dt) => gc.tick(dt));
    return gc;
  }

  private onKey(k: string, down: boolean) {
    if (k === "a" || k === "arrowleft") this.input.left = down;
    if (k === "d" || k === "arrowright") this.input.right = down;
    if (k === "w" || k === "arrowup") this.input.up = down;
    if (k === "s" || k === "arrowdown") this.input.down = down;
    if (k === " " && down) this.spaceJustPressed = true;
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

    this.updateLocalMovement(dt, selfState);
    this.remoteSync.sync(dt, room, this.localId);
    this.cashView.sync(room);
    this.updateAction(selfState);
    this.handleSpaceInput();
    this.maybeAutoDeposit(selfState);
    this.roofSystem.update(dt, getZoneAt(this.controller.x, this.controller.z));

    this.hud.update(room, this.currentAction?.prompt ?? "");
    this.spaceJustPressed = false;
  }

  // Ports GameScene.updateLocalMovement: outside "playing" or while jailed,
  // the server is fully authoritative - snap to its position every frame
  // instead of processing input, exactly as the 2D build's body.reset() did.
  private updateLocalMovement(dt: number, selfState: any) {
    const model = this.controller.model;
    const playing = this.room.state.phase === "playing";

    if (!playing || selfState.isJailed) {
      this.controller.freeze(selfState.x, selfState.y);
      model.setJailed(selfState.isJailed);
      model.setCarrying(selfState.isCarryingCash);
      model.update(dt, 0);
      this.cameraRig.update(dt, this.controller.x, this.controller.z);
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
    const f = (this.input.up ? 1 : 0) - (this.input.down ? 1 : 0);
    const s = (this.input.right ? 1 : 0) - (this.input.left ? 1 : 0);
    const yaw = this.cameraRig.getYaw();
    const moveX = Math.sin(yaw) * f + Math.cos(yaw) * s;
    const moveZ = -Math.cos(yaw) * f + Math.sin(yaw) * s;
    this.controller.update(dt, moveX, moveZ, selfState.isCarryingCash);
    this.cameraRig.update(dt, this.controller.x, this.controller.z);

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
    const team = this.localTeam;
    const enemyBedroom = team === "B" ? "bedroomA" : "bedroomB";
    const enemyTeam: Team = team === "B" ? "A" : "B";

    let action: Action = null;

    if (!selfState.isCarryingCash && isEnemyBedroom(team, x, y)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === enemyBedroom && dist(x, y, b.x, b.y) <= ACTION_RANGE) {
          action = { kind: "pickupCash", bundleId: b.id, prompt: "SPACE: Pick up cash" };
        }
      });
    }

    if (!action && isOwnHome(team, x, y)) {
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

    if (!action && getZoneAt(x, y) === jailBasementForTeam(team)) {
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

    if (!action && !selfState.isCarryingCash && isEnemyBedroom(team, x, y)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === `scored:${enemyTeam}` && dist(x, y, b.x, b.y) <= ACTION_RANGE) {
          action = { kind: "stealScored", bundleId: b.id, prompt: "SPACE: Steal scored cash" };
        }
      });
    }

    this.currentAction = action;
  }

  private handleSpaceInput() {
    if (!this.spaceJustPressed || !this.currentAction) return;

    switch (this.currentAction.kind) {
      case "pickupCash":
        colyseusClient.send("pickupCash", { bundleId: this.currentAction.bundleId });
        break;
      case "lockPlayer":
        colyseusClient.send("lockPlayer", { targetId: this.currentAction.targetId });
        break;
      case "rescuePlayer":
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
    if (!isOwnHome(this.localTeam, this.controller.x, this.controller.z)) {
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
