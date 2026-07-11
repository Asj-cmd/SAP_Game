import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";

export class UIScene extends Phaser.Scene {
  private timerText!: Phaser.GameObjects.Text;
  private roundText!: Phaser.GameObjects.Text;
  private jailedText!: Phaser.GameObjects.Text;
  private endOverlayText!: Phaser.GameObjects.Text;

  constructor() {
    super("UIScene");
  }

  create() {
    this.timerText = this.add
      .text(20, 16, "05:00", { fontSize: "36px", color: "#ffffff", stroke: "#000000", strokeThickness: 4 })
      .setScrollFactor(0);
    this.roundText = this.add
      .text(20, 62, "Round 1 of 3", { fontSize: "16px", color: "#ffffff", stroke: "#000000", strokeThickness: 3 })
      .setScrollFactor(0);
    this.add
      .text(this.scale.width / 2, this.scale.height - 20, "WASD: Move | SPACE: Action", {
        fontSize: "14px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 3,
      })
      .setOrigin(0.5, 1)
      .setScrollFactor(0);
    this.jailedText = this.add
      .text(this.scale.width / 2, this.scale.height / 2, "", {
        fontSize: "20px",
        color: "#ffdd55",
        stroke: "#000000",
        strokeThickness: 4,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0);
    this.endOverlayText = this.add
      .text(this.scale.width / 2, this.scale.height / 2 - 90, "", {
        fontSize: "30px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 6,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0);
  }

  update() {
    const room = colyseusClient.room;
    if (!room) return;
    const state = room.state as any;

    const mins = Math.max(0, Math.floor(state.roundTimer / 60)).toString().padStart(2, "0");
    const secs = Math.max(0, Math.floor(state.roundTimer % 60)).toString().padStart(2, "0");
    this.timerText.setText(`${mins}:${secs}`);
    this.roundText.setText(`Round ${state.roundNumber} of 3`);

    const me = state.players.get(room.sessionId);
    if (me?.isJailed) {
      this.jailedText.setText(
        `JAILED — ${me.jailTimer}s\nTeammate can rescue you | Auto-release in ${me.jailTimer}s`
      );
    } else {
      this.jailedText.setText("");
    }

    if (state.phase === "roundEnd") {
      this.endOverlayText.setText(`ROUND ${state.roundNumber} WINNER: TEAM ${state.roundWinner || "-"}!\nNext round in 3...`);
    } else if (state.phase === "matchEnd") {
      this.endOverlayText.setText(`TEAM ${state.matchWinner} WINS THE MATCH!`);
    } else if (state.phase === "countdown") {
      this.endOverlayText.setText(`GET READY\n${Math.max(1, state.countdown)}`);
    } else {
      this.endOverlayText.setText("");
    }
  }
}
