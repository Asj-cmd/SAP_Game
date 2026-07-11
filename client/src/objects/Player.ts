import Phaser from "phaser";
import { COLORS } from "../constants";

export type Team = "A" | "B";

export class Player extends Phaser.GameObjects.Container {
  team: Team;
  playerId: string;

  private head: Phaser.GameObjects.Arc;
  private torso: Phaser.GameObjects.Rectangle;
  private legLeft: Phaser.GameObjects.Line;
  private legRight: Phaser.GameObjects.Line;
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

    this.legLeft = scene.add.line(0, 0, -4, 20, -8, 40, color).setLineWidth(3);
    this.legRight = scene.add.line(0, 0, 4, 20, 8, 40, color).setLineWidth(3);
    this.torso = scene.add.rectangle(0, 9, 12, 22, color);
    this.head = scene.add.circle(0, -12, 14, color);

    this.cashIndicator = scene.add
      .rectangle(0, -36, 16, 10, COLORS.cash)
      .setStrokeStyle(1, 0x8a6d00)
      .setVisible(false);

    this.lockBody = scene.add.rectangle(0, -46, 10, 8, 0x222222).setVisible(false);
    this.lockShackle = scene.add
      .arc(0, -50, 5, 180, 360, false, 0x222222)
      .setStrokeStyle(2, 0x222222)
      .setVisible(false);

    this.nameText = scene.add
      .text(0, -62, name, { fontSize: "11px", color: "#ffffff", stroke: "#000000", strokeThickness: 3 })
      .setOrigin(0.5);

    this.promptText = scene.add
      .text(0, -80, "", {
        fontSize: "12px",
        color: "#ffff66",
        stroke: "#000000",
        strokeThickness: 3,
        align: "center",
      })
      .setOrigin(0.5)
      .setVisible(false);

    this.add([
      this.legLeft,
      this.legRight,
      this.torso,
      this.head,
      this.cashIndicator,
      this.lockBody,
      this.lockShackle,
      this.nameText,
      this.promptText,
    ]);

    scene.add.existing(this);
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
