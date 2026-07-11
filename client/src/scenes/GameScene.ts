import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import {
  drawZones,
  createWallColliders,
  getZoneAt,
  isEnemyBedroom,
  isOwnHome,
  jailBasementForTeam,
  Team,
} from "../objects/Zone";
import { Player } from "../objects/Player";
import { CashBundle } from "../objects/CashBundle";
import {
  WORLD_WIDTH,
  WORLD_HEIGHT,
  PLAYER_SPEED,
  CARRY_SPEED,
  JUMP_VELOCITY,
  MOVE_SEND_INTERVAL_MS,
  REMOTE_LERP,
  ACTION_RANGE,
} from "../constants";

type Action =
  | { kind: "pickupCash"; bundleId: string; prompt: string }
  | { kind: "lockPlayer"; targetId: string; prompt: string }
  | { kind: "rescuePlayer"; targetId: string; prompt: string }
  | { kind: "stealScored"; bundleId: string; prompt: string }
  | null;

function dist(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Phaser.Math.Distance.Between(a.x, a.y, b.x, b.y);
}

export class GameScene extends Phaser.Scene {
  private localPlayer!: Player;
  private localId = "";
  private localTeam: Team = "B";
  private wallGroup!: Phaser.Physics.Arcade.StaticGroup;

  private cursors!: Phaser.Types.Input.Keyboard.CursorKeys;
  private keyA!: Phaser.Input.Keyboard.Key;
  private keyD!: Phaser.Input.Keyboard.Key;
  private keyW!: Phaser.Input.Keyboard.Key;
  private spaceKey!: Phaser.Input.Keyboard.Key;

  private remoteSprites = new Map<string, Player>();
  private lastJailed = new Map<string, boolean>();
  private bundleSprites = new Map<string, CashBundle>();

  private moveAccumulator = 0;
  private depositSent = false;
  private currentAction: Action = null;

  constructor() {
    super("GameScene");
  }

  create() {
    const room = colyseusClient.room;
    if (!room) {
      this.scene.start("LobbyScene");
      return;
    }
    this.localId = room.sessionId;
    const selfState = room.state.players.get(this.localId);
    this.localTeam = (selfState?.team as Team) || "B";

    this.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    this.cameras.main.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);

    drawZones(this);
    this.wallGroup = createWallColliders(this, this.localTeam);

    this.localPlayer = new Player(
      this,
      selfState?.x ?? 0,
      selfState?.y ?? 0,
      this.localTeam,
      selfState?.name ?? "You",
      this.localId
    );
    this.physics.add.existing(this.localPlayer);
    const body = this.localPlayer.body as Phaser.Physics.Arcade.Body;
    body.setSize(28, 66);
    body.setOffset(-14, -26);
    body.setCollideWorldBounds(true);
    this.physics.add.collider(this.localPlayer, this.wallGroup);

    this.cameras.main.startFollow(this.localPlayer);
    this.cameras.main.setDeadzone(100, 80);

    this.cursors = this.input.keyboard!.createCursorKeys();
    this.keyA = this.input.keyboard!.addKey("A");
    this.keyD = this.input.keyboard!.addKey("D");
    this.keyW = this.input.keyboard!.addKey("W");
    this.spaceKey = this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.SPACE);
  }

  update(_time: number, delta: number) {
    const room = colyseusClient.room;
    if (!room) return;

    this.updateLocalMovement(delta);
    this.syncRemotePlayers(room);
    this.syncCashBundles(room);
    this.updateAction(room);
    this.handleSpaceInput();
    this.maybeAutoDeposit(room);
  }

  private updateLocalMovement(delta: number) {
    const room = colyseusClient.room!;
    const selfState = room.state.players.get(this.localId);
    if (!selfState) return;

    const body = this.localPlayer.body as Phaser.Physics.Arcade.Body;

    if (selfState.isJailed) {
      body.setVelocity(0, 0);
      this.localPlayer.setPosition(selfState.x, selfState.y);
      this.localPlayer.setJailed(true);
      this.localPlayer.setCarrying(false);
      return;
    }
    this.localPlayer.setJailed(false);

    const carrying = selfState.isCarryingCash;
    this.localPlayer.setCarrying(carrying);
    const speed = carrying ? CARRY_SPEED : PLAYER_SPEED;

    const left = this.cursors.left.isDown || this.keyA.isDown;
    const right = this.cursors.right.isDown || this.keyD.isDown;
    const up = this.cursors.up.isDown || this.keyW.isDown;

    if (left) body.setVelocityX(-speed);
    else if (right) body.setVelocityX(speed);
    else body.setVelocityX(0);

    if (up && body.blocked.down) body.setVelocityY(JUMP_VELOCITY);

    this.moveAccumulator += delta;
    if (this.moveAccumulator >= MOVE_SEND_INTERVAL_MS) {
      this.moveAccumulator = 0;
      colyseusClient.send("move", {
        x: this.localPlayer.x,
        y: this.localPlayer.y,
        vx: body.velocity.x,
        vy: body.velocity.y,
      });
    }
  }

  private syncRemotePlayers(room: NonNullable<typeof colyseusClient.room>) {
    const seen = new Set<string>();

    room.state.players.forEach((p: any, id: string) => {
      if (id === this.localId) return;
      seen.add(id);

      let sprite = this.remoteSprites.get(id);
      if (!sprite) {
        sprite = new Player(this, p.x, p.y, p.team as Team, p.name, id);
        this.remoteSprites.set(id, sprite);
        this.lastJailed.set(id, p.isJailed);
      }

      const wasJailed = this.lastJailed.get(id) ?? false;
      if (p.isJailed && !wasJailed) {
        sprite.setPosition(p.x, p.y);
      } else {
        sprite.x = Phaser.Math.Linear(sprite.x, p.x, REMOTE_LERP);
        sprite.y = Phaser.Math.Linear(sprite.y, p.y, REMOTE_LERP);
      }
      this.lastJailed.set(id, p.isJailed);

      sprite.setCarrying(p.isCarryingCash);
      sprite.setJailed(p.isJailed);
      sprite.setDisplayName(p.name);
    });

    for (const [id, sprite] of this.remoteSprites) {
      if (!seen.has(id)) {
        sprite.destroy();
        this.remoteSprites.delete(id);
        this.lastJailed.delete(id);
      }
    }
  }

  private syncCashBundles(room: NonNullable<typeof colyseusClient.room>) {
    const seen = new Set<string>();

    room.state.cashBundles.forEach((b: any, id: string) => {
      seen.add(id);
      let sprite = this.bundleSprites.get(id);
      if (!sprite) {
        sprite = new CashBundle(this, b.x, b.y, id);
        this.bundleSprites.set(id, sprite);
      }
      const carried = typeof b.location === "string" && b.location.startsWith("carried:");
      if (carried) {
        sprite.setVisible(false);
      } else {
        sprite.setVisible(true);
        sprite.setPosition(b.x, b.y);
      }
    });

    for (const [id, sprite] of this.bundleSprites) {
      if (!seen.has(id)) {
        sprite.destroy();
        this.bundleSprites.delete(id);
      }
    }
  }

  private updateAction(room: NonNullable<typeof colyseusClient.room>) {
    const selfState = room.state.players.get(this.localId);
    if (!selfState || selfState.isJailed) {
      this.currentAction = null;
      this.localPlayer.setPrompt("");
      return;
    }

    const x = this.localPlayer.x;
    const y = this.localPlayer.y;
    const team = this.localTeam;
    const enemyBedroom = team === "B" ? "bedroomA" : "bedroomB";
    const enemyTeam: Team = team === "B" ? "A" : "B";

    let action: Action = null;

    // 1. pick up an unscored bundle in the enemy bedroom
    if (!selfState.isCarryingCash && isEnemyBedroom(team, x, y)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === enemyBedroom && dist(this.localPlayer, b) <= ACTION_RANGE) {
          action = { kind: "pickupCash", bundleId: b.id, prompt: "SPACE: Pick up cash" };
        }
      });
    }

    // 3. lock a nearby enemy while in own home
    if (!action && isOwnHome(team, x, y)) {
      let nearest: { id: string; name: string; d: number } | null = null;
      room.state.players.forEach((p: any, id: string) => {
        if (id === this.localId || p.team === team || p.isJailed) return;
        const d = dist(this.localPlayer, p);
        if (d <= ACTION_RANGE && (!nearest || d < nearest.d)) {
          nearest = { id, name: p.name, d };
        }
      });
      if (nearest) {
        const n = nearest as { id: string; name: string; d: number };
        action = { kind: "lockPlayer", targetId: n.id, prompt: `SPACE: Lock ${n.name}` };
      }
    }

    // 4. rescue a jailed teammate in the correct basement
    if (!action && getZoneAt(x, y) === jailBasementForTeam(team)) {
      let nearest: { id: string; name: string; d: number } | null = null;
      room.state.players.forEach((p: any, id: string) => {
        if (id === this.localId || p.team !== team || !p.isJailed) return;
        const d = dist(this.localPlayer, p);
        if (d <= ACTION_RANGE && (!nearest || d < nearest.d)) {
          nearest = { id, name: p.name, d };
        }
      });
      if (nearest) {
        const n = nearest as { id: string; name: string; d: number };
        action = { kind: "rescuePlayer", targetId: n.id, prompt: `SPACE: Rescue ${n.name}` };
      }
    }

    // 5. steal an already-scored bundle from the enemy bedroom
    if (!action && !selfState.isCarryingCash && isEnemyBedroom(team, x, y)) {
      room.state.cashBundles.forEach((b: any) => {
        if (action) return;
        if (b.location === `scored:${enemyTeam}` && dist(this.localPlayer, b) <= ACTION_RANGE) {
          action = { kind: "stealScored", bundleId: b.id, prompt: "SPACE: Steal scored cash" };
        }
      });
    }

    this.currentAction = action;
    this.localPlayer.setPrompt(action ? action.prompt : "");
  }

  private handleSpaceInput() {
    if (!Phaser.Input.Keyboard.JustDown(this.spaceKey)) return;
    if (!this.currentAction) return;

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

  private maybeAutoDeposit(room: NonNullable<typeof colyseusClient.room>) {
    const selfState = room.state.players.get(this.localId);
    if (!selfState || !selfState.isCarryingCash) {
      this.depositSent = false;
      return;
    }
    if (this.depositSent) return;
    if (!isOwnHome(this.localTeam, this.localPlayer.x, this.localPlayer.y)) return;

    let carriedId: string | null = null;
    room.state.cashBundles.forEach((b: any, id: string) => {
      if (b.location === `carried:${this.localId}`) carriedId = id;
    });
    if (!carriedId) return;

    this.depositSent = true;
    colyseusClient.send("depositCash", { bundleId: carriedId });
  }
}
