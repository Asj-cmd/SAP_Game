import Phaser from "phaser";
import { COLORS } from "../constants";

export class CashBundle extends Phaser.GameObjects.Rectangle {
  bundleId: string;

  constructor(scene: Phaser.Scene, x: number, y: number, bundleId: string) {
    super(scene, x, y, 24, 16, COLORS.cash);
    this.bundleId = bundleId;
    this.setStrokeStyle(2, 0x8a6d00);
    scene.add.existing(this);
  }
}
