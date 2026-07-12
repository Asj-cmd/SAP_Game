import Phaser from "phaser";
import { COLORS } from "../constants";

export type Team = "A" | "B";

const RADIUS = 16;

export class Player extends Phaser.GameObjects.Container {
  team: Team;
  playerId: string;

  private shadow: Phaser.GameObjects.Ellipse;
  private body_: Phaser.GameObjects.Arc;
  private facing: Phaser.GameObjects.Graphics;
  private facingAngle = 0; // radians; 0 = facing "up" (north)
  private cashIndicator: Phaser.GameObjects.Rectangle;
  private lockBody: Phaser.GameObjects.Rectangle;
  private lockShackle: Phaser.GameObjects.Arc;
  private nameText: Phaser.GameObjects.Text;
  private promptText: Phaser.GameObjects.Text;

  constructor(scene: Phaser.Scene, x: number, y: number, team: Team, name: string, playerId: string) {
    super(scene, x, y);
    this.team = team;
    this.playerId = playerId;

    const color = team === "B" ? COLORS.teamB : COLORS.teamA;

    this.shadow = scene.add.ellipse(0, 4, RADIUS * 1.6, RADIUS * 0.9, 0x000000, 0.3);
    this.body_ = scene.add.circle(0, 0, RADIUS, color).setStrokeStyle(2, 0x1a1a1a);
    this.facing = scene.add.graphics();
    this.drawFacingWedge();

    this.cashIndicator = scene.add
      .rectangle(0, -RADIUS - 14, 16, 10, COLORS.cash)
      .setStrokeStyle(1, 0x8a6d00)
      .setVisible(false);

    this.lockBody = scene.add.rectangle(0, -RADIUS - 10, 10, 8, 0x222222).setVisible(false);
    this.lockShackle = scene.add
      .arc(0, -RADIUS - 14, 5, 180, 360, false, 0x222222)
      .setStrokeStyle(2, 0x222222)
      .setVisible(false);

    this.nameText = scene.add
      .text(0, -RADIUS - 24, name, { fontSize: "11px", color: "#ffffff", stroke: "#000000", strokeThickness: 3 })
      .setOrigin(0.5);

    this.promptText = scene.add
      .text(0, -RADIUS - 40, "", {
        fontSize: "12px",
        color: "#ffff66",
        stroke: "#000000",
        strokeThickness: 3,
        align: "center",
      })
      .setOrigin(0.5)
      .setVisible(false);

    this.add([
      this.shadow,
      this.body_,
      this.facing,
      this.cashIndicator,
      this.lockBody,
      this.lockShackle,
      this.nameText,
      this.promptText,
    ]);

    scene.add.existing(this);
  }

  private drawFacingWedge() {
    const cos = Math.cos(this.facingAngle);
    const sin = Math.sin(this.facingAngle);
    const rot = (x: number, y: number) => ({ x: x * cos - y * sin, y: x * sin + y * cos });
    const p1 = rot(0, -RADIUS - 8);
    const p2 = rot(-6, -RADIUS + 4);
    const p3 = rot(6, -RADIUS + 4);
    this.facing.clear();
    this.facing.fillStyle(0xffffff, 0.9);
    this.facing.fillTriangle(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
  }

  // Rotates the facing wedge to point in the direction of travel. Called with
  // the player's current velocity/heading; keeps the last heading while still.
  setFacing(dx: number, dy: number) {
    if (dx === 0 && dy === 0) return;
    this.facingAngle = Math.atan2(dx, -dy);
    this.drawFacingWedge();
  }

  setCarrying(carrying: boolean) {
    this.cashIndicator.setVisible(carrying);
  }

  setJailed(jailed: boolean) {
    this.setAlpha(jailed ? 0.5 : 1);
    this.lockBody.setVisible(jailed);
    this.lockShackle.setVisible(jailed);
  }

  setPrompt(text: string) {
    this.promptText.setText(text);
    this.promptText.setVisible(text.length > 0);
  }

  setDisplayName(name: string) {
    this.nameText.setText(name);
  }
}
