import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";

export class UIScene extends Phaser.Scene {
  private timerText!: Phaser.GameObjects.Text;
  private roundText!: Phaser.GameObjects.Text;
  private jailText!: Phaser.GameObjects.Text;
  private overlayText!: Phaser.GameObjects.Text;
  private overlaySubText!: Phaser.GameObjects.Text;

  constructor() {
    super("UIScene");
  }

  create() {
    const { width, height } = this.scale;

    this.timerText = this.add
      .text(20, 16, "05:00", { fontSize: "36px", color: "#ffffff", stroke: "#000000", strokeThickness: 4 })
      .setScrollFactor(0);

    this.roundText = this.add
      .text(20, 58, "Round 1 of 3", { fontSize: "16px", color: "#ffffff", stroke: "#000000", strokeThickness: 3 })
      .setScrollFactor(0);

    this.add
      .text(width / 2, height - 16, "WASD: Move | SPACE: Action", {
        fontSize: "14px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 3,
      })
      .setOrigin(0.5, 1)
      .setScrollFactor(0);

    this.jailText = this.add
      .text(width / 2, height / 2, "", {
        fontSize: "20px",
        color: "#ffdd55",
        stroke: "#000000",
        strokeThickness: 4,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);

    this.overlayText = this.add
      .text(width / 2, height / 2 - 30, "", {
        fontSize: "32px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 5,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);

    this.overlaySubText = this.add
      .text(width / 2, height / 2 + 24, "", {
        fontSize: "18px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 4,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);
  }

  update() {
    const room = colyseusClient.room;
    if (!room) return;
    const state = room.state as any;

    const t = Math.max(0, Math.floor(state.roundTimer));
    const mins = Math.floor(t / 60)
      .toString()
      .padStart(2, "0");
    const secs = (t % 60).toString().padStart(2, "0");
    this.timerText.setText(`${mins}:${secs}`);
    this.roundText.setText(`Round ${state.roundNumber} of 3`);

    const self = room.state.players.get(room.sessionId);
    if (self?.isJailed) {
      const secsLeft = Math.ceil(self.jailTimer);
      this.jailText.setVisible(true);
      this.jailText.setText(`JAILED — ${secsLeft}s\nTeammate can rescue you\nAuto-release in ${secsLeft}s`);
    } else {
      this.jailText.setVisible(false);
    }

    if (state.phase === "roundEnd") {
      this.overlayText.setVisible(true);
      this.overlaySubText.setVisible(true);
      this.overlayText.setText(
        state.roundWinner ? `ROUND ${state.roundNumber} WINNER: TEAM ${state.roundWinner}!` : `ROUND ${state.roundNumber} TIED!`
      );
      this.overlaySubText.setText(`Next round in ${Math.max(0, Math.floor(state.countdown))}...`);
    } else if (state.phase === "matchEnd") {
      this.overlayText.setVisible(true);
      this.overlaySubText.setVisible(true);
      this.overlayText.setText(`TEAM ${state.matchWinner} WINS THE MATCH!`);
      this.overlaySubText.setText("");
    } else if (state.phase === "countdown") {
      this.overlayText.setVisible(true);
      this.overlaySubText.setVisible(false);
      this.overlayText.setText(`${Math.max(0, Math.floor(state.countdown))}`);
    } else {
      this.overlayText.setVisible(false);
      this.overlaySubText.setVisible(false);
    }
  }
}
