import Phaser from "phaser";

export class BootScene extends Phaser.Scene {
  constructor() {
    super("BootScene");
  }

  create() {
    // Phase 1 has no sprite art / audio to preload - players are drawn with
    // primitives and zones are colored rectangles - so there's nothing to load.
    this.scene.start("LobbyScene");
  }
}
