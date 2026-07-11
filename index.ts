import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import { drawZones, createWallColliders } from "../objects/Zone";
import { Player, Team } from "../objects/Player";
import { CashBundle } from "../objects/CashBundle";
import {
  WORLD_WIDTH,
  WORLD_HEIGHT,
  WORLD_MIN_X,
  WORLD_MAX_X,
  PLAYER_SPEED,
  PLAYER_SPEED_CARRYING,
  JUMP_VELOCITY,
  ACTION_RANGE,
  BEDROOM_DOORS,
} from "../constants";
import { isEnemyBedroom, isOwnHome, isInZone, jailBasementForTeam, otherTeam } from "../zones";

interface PendingAction {
  type: "pickupCash" | "stealScored" | "lockPlayer" | "rescuePlayer";
  bundleId?: string;
  targetId?: string;
  label: string;
}

export class GameScene extends Phaser.Scene {
  private localBody!: Phaser.GameObjects.Rectangle;
  private localVisual!: Player;
  private remotePlayers = new Map<string, Player>();
  private cashBundleSprites = new Map<string, CashBundle>();

  private cursors!: Phaser.Types.Input.Keyboard.CursorKeys;
  private wasd!: Record<"W" | "A" | "S" | "D", Phaser.Input.Keyboard.Key>;
  private spaceKey!: Phaser.Input.Keyboard.Key;

  private moveSendAccum = 0;
  private wasJailed = false;
  private lastPhase = "";

  constructor() {
    super("GameScene");
  }

  create() {
    const room = colyseusClient.room;
    if (!room) {
      this.scene.start("LobbyScene");
      return;
    }

    this.physics.world.setBounds(WORLD_MIN_X, 0, WORLD_MAX_X - WORLD_MIN_X, WORLD_HEIGHT);
    this.cameras.main.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);

    drawZones(this);
    const walls = createWallColliders(this);

    const me = room.state.players.get(room.sessionId);
    const team = (me?.team ?? "B") as Team;
    const startX = me?.x ?? 0;
    const startY = me?.y ?? 0;

    this.localBody = this.add.rectangle(startX, startY, 24, 48, 0x000000, 0);
    this.physics.add.existing(this.localBody, false);
    const body = this.localBody.body as Phaser.Physics.Arcade.Body;
    body.setCollideWorldBounds(true);
    body.setMaxVelocity(400, 1000);
    this.physics.add.collider(this.localBody, walls);

    this.localVisual = new Player(this, startX, startY, team, me?.name ?? "Player");

    this.cameras.main.startFollow(this.localVisual, true, 0.1, 0.1);
    this.cameras.main.setDeadzone(200, 160);

    this.cursors = this.input.keyboard!.createCursorKeys();
    this.wasd = this.input.keyboard!.addKeys("W,A,S,D") as any;
    this.spaceKey = this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.SPACE);
  }

  update(_time: number, delta: number) {
    const room = colyseusClient.room;
    if (!room) return;
    const me = room.state.players.get(room.sessionId);
    if (!me) return;

    const body = this.localBody.body as Phaser.Physics.Arcade.Body;

    // Server-forced teleports (jail, round reset) snap immediately — no lerp.
    const justJailed = me.isJailed && !this.wasJailed;
    const justReset = room.state.phase === "countdown" && this.lastPhase !== "countdown";
    if (justJailed || justReset) {
      this.localBody.setPosition(me.x, me.y);
      body.reset(me.x, me.y);
    }
    this.wasJailed = me.isJailed;
    this.lastPhase = room.state.phase;

    if (me.isJailed || room.state.phase !== "playing") {
      body.setVelocityX(0);
    } else {
      const left = this.cursors.left?.isDown || this.wasd.A.isDown;
      const right = this.cursors.right?.isDown || this.wasd.D.isDown;
      const up = this.cursors.up?.isDown || this.wasd.W.isDown;
      const speed = me.isCarryingCash ? PLAYER_SPEED_CARRYING : PLAYER_SPEED;

      if (left) body.setVelocityX(-speed);
      else if (right) body.setVelocityX(speed);
      else body.setVelocityX(0);

      if (up && body.blocked.down) body.setVelocityY(JUMP_VELOCITY);
    }

    this.enforceBedroomDoorBlock(me.team as Team);

    this.localVisual.setPosition(this.localBody.x, this.localBody.y);
    this.localVisual.setVisualState({ isCarryingCash: me.isCarryingCash, isJailed: me.isJailed });

    this.moveSendAccum += delta;
    if (this.moveSendAccum >= 50) {
      this.moveSendAccum = 0;
      colyseusClient.send("move", { x: this.localBody.x, y: this.localBody.y });
    }

    this.syncRemotePlayers(room);
    this.syncCashBundles(room);
    this.updateActionAndDeposit(me, room);
  }

  private syncRemotePlayers(room: NonNullable<typeof colyseusClient.room>) {
    const seen = new Set<string>();
    room.state.players.forEach((p: any, id: string) => {
      if (id === room.sessionId) return;
      seen.add(id);
      let visual = this.remotePlayers.get(id);
      if (!visual) {
        visual = new Player(this, p.x, p.y, p.team as Team, p.name);
        this.remotePlayers.set(id, visual);
      }
      visual.x = Phaser.Math.Linear(visual.x, p.x, 0.2);
      visual.y = Phaser.Math.Linear(visual.y, p.y, 0.2);
      visual.setVisualState({ isCarryingCash: p.isCarryingCash, isJailed: p.isJailed });
    });
    this.remotePlayers.forEach((visual, id) => {
      if (!seen.has(id)) {
        visual.destroy();
        this.remotePlayers.delete(id);
      }
    });
  }

  private syncCashBundles(room: NonNullable<typeof colyseusClient.room>) {
    const seen = new Set<string>();
    room.state.cashBundles.forEach((b: any, id: string) => {
      seen.add(id);
      let targetX = b.x;
      let targetY = b.y;
      if (typeof b.location === "string" && b.location.startsWith("carried:")) {
        const carrierId = b.location.split(":")[1];
        const carrier = carrierId === room.sessionId ? this.localVisual : this.remotePlayers.get(carrierId);
        if (carrier) {
          targetX = carrier.x;
          targetY = carrier.y - 34;
        }
      }
      let sprite = this.cashBundleSprites.get(id);
      if (!sprite) {
        sprite = new CashBundle(this, targetX, targetY);
        this.cashBundleSprites.set(id, sprite);
      }
      sprite.setPosition(targetX, targetY);
    });
    this.cashBundleSprites.forEach((sprite, id) => {
      if (!seen.has(id)) {
        sprite.destroy();
        this.cashBundleSprites.delete(id);
      }
    });
  }

  private updateActionAndDeposit(me: any, room: NonNullable<typeof colyseusClient.room>) {
    const team = me.team as Team;
    const x = this.localBody.x;
    const y = this.localBody.y;

    // Deposit auto-fires the instant carrying player is back in their own home.
    if (me.isCarryingCash && isOwnHome(team, x, y)) {
      const bundle = [...room.state.cashBundles.values()].find(
        (b: any) => b.location === `carried:${room.sessionId}`
      );
      if (bundle) colyseusClient.send("depositCash", { bundleId: (bundle as any).id });
    }

    let action: PendingAction | null = null;

    if (!action && !me.isCarryingCash && !me.isJailed && isEnemyBedroom(team, x, y)) {
      const bundle = [...room.state.cashBundles.values()].find(
        (b: any) => b.location === `bedroom${otherTeam(team)}`
      );
      if (bundle) action = { type: "pickupCash", bundleId: (bundle as any).id, label: "SPACE: Pick up cash" };
    }

    if (!action && !me.isCarryingCash && !me.isJailed && isEnemyBedroom(team, x, y)) {
      const scored = [...room.state.cashBundles.values()].find(
        (b: any) => b.location === `scored:${otherTeam(team)}`
      );
      if (scored) action = { type: "stealScored", bundleId: (scored as any).id, label: "SPACE: Steal cash" };
    }

    if (!action && !me.isJailed && isOwnHome(team, x, y)) {
      let nearestId: string | null = null;
      let nearestDist = Infinity;
      let nearestName = "";
      room.state.players.forEach((p: any, id: string) => {
        if (id === room.sessionId || p.team === team || p.isJailed) return;
        if (!isOwnHome(team, p.x, p.y)) return;
        const d = Phaser.Math.Distance.Between(x, y, p.x, p.y);
        if (d < ACTION_RANGE && d < nearestDist) {
          nearestDist = d;
          nearestId = id;
          nearestName = p.name;
        }
      });
      if (nearestId) action = { type: "lockPlayer", targetId: nearestId, label: `SPACE: Lock ${nearestName}` };
    }

    if (!action && !me.isJailed) {
      const jailZone = jailBasementForTeam(team);
      if (isInZone(jailZone, x, y)) {
        let nearestId: string | null = null;
        let nearestDist = Infinity;
        let nearestName = "";
        room.state.players.forEach((p: any, id: string) => {
          if (id === room.sessionId || p.team !== team || !p.isJailed) return;
          const d = Phaser.Math.Distance.Between(x, y, p.x, p.y);
          if (d < ACTION_RANGE && d < nearestDist) {
            nearestDist = d;
            nearestId = id;
            nearestName = p.name;
          }
        });
        if (nearestId) action = { type: "rescuePlayer", targetId: nearestId, label: `SPACE: Rescue ${nearestName}` };
      }
    }

    this.localVisual.setPrompt(action?.label ?? "");

    if (action && Phaser.Input.Keyboard.JustDown(this.spaceKey)) {
      if (action.type === "pickupCash" || action.type === "stealScored") {
        colyseusClient.send(action.type, { bundleId: action.bundleId });
      } else {
        colyseusClient.send(action.type, { targetId: action.targetId });
      }
    }
  }

  private enforceBedroomDoorBlock(team: Team) {
    const body = this.localBody.body as Phaser.Physics.Arcade.Body;
    const margin = 14;
    for (const door of BEDROOM_DOORS) {
      if (door.ownTeam !== team) continue;
      const withinY = this.localBody.y > door.yTop - 10 && this.localBody.y < door.yBottom + 10;
      if (!withinY) continue;

      if (door.ownTeam === "B") {
        if (this.localBody.x < door.x + margin) {
          this.localBody.x = door.x + margin;
          body.setVelocityX(Math.max(0, body.velocity.x));
        }
      } else {
        if (this.localBody.x > door.x - margin) {
          this.localBody.x = door.x - margin;
          body.setVelocityX(Math.min(0, body.velocity.x));
        }
      }
    }
  }
}
