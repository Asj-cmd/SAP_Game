import Phaser from "phaser";
import { COLORS } from "../constants";

export class CashBundle extends Phaser.GameObjects.Rectangle {
  constructor(scene: Phaser.Scene, x: number, y: number) {
    super(scene, x, y, 24, 16, COLORS.cash);
    this.setStrokeStyle(2, 0x8a6d00);
    scene.add.existing(this);
  }
}
