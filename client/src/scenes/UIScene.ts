import Phaser from "phaser";
import { colyseusClient } from "../network/ColyseusClient";
import { COLORS, WORLD_WIDTH, WORLD_HEIGHT, GROUND_Y } from "../constants";
import { Team } from "../objects/Zone";

function toHex(color: number): string {
  return "#" + color.toString(16).padStart(6, "0");
}

// Minimap zone rectangles (world coords) - purposely does NOT show cash, so the
// "look at the bedrooms to read the score" mechanic is preserved.
const MINIMAP_ZONES = [
  { xMin: 60, xMax: 500, yMin: 0, yMax: GROUND_Y, color: COLORS.bedroom },
  { xMin: 500, xMax: 980, yMin: 0, yMax: GROUND_Y, color: COLORS.livingRoom },
  { xMin: 980, xMax: 2220, yMin: 0, yMax: GROUND_Y, color: COLORS.garden },
  { xMin: 2220, xMax: 2700, yMin: 0, yMax: GROUND_Y, color: COLORS.livingRoom },
  { xMin: 2700, xMax: 3140, yMin: 0, yMax: GROUND_Y, color: COLORS.bedroom },
  { xMin: 60, xMax: 980, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.basement },
  { xMin: 980, xMax: 2220, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.dirt },
  { xMin: 2220, xMax: 3140, yMin: GROUND_Y, yMax: WORLD_HEIGHT, color: COLORS.basement },
];

const MINIMAP_W = 300;

export class UIScene extends Phaser.Scene {
  private timerText!: Phaser.GameObjects.Text;
  private roundText!: Phaser.GameObjects.Text;
  private objectiveText!: Phaser.GameObjects.Text;
  private controlsText!: Phaser.GameObjects.Text;
  private jailText!: Phaser.GameObjects.Text;
  private overlayBg!: Phaser.GameObjects.Rectangle;
  private overlayText!: Phaser.GameObjects.Text;
  private overlaySubText!: Phaser.GameObjects.Text;
  private minimap!: Phaser.GameObjects.Graphics;

  private localTeam: Team = "B";
  private mmScale = 1;
  private mmX = 0;
  private mmY = 8;
  private mmH = 0;

  constructor() {
    super("UIScene");
  }

  create() {
    const room = colyseusClient.room;
    this.localTeam = (room?.state.players.get(room.sessionId)?.team as Team) || "B";

    this.timerText = this.add
      .text(20, 14, "05:00", { fontSize: "34px", color: "#ffffff", stroke: "#000000", strokeThickness: 5 })
      .setScrollFactor(0);

    this.roundText = this.add
      .text(20, 54, "Round 1 of 3", { fontSize: "15px", color: "#ffffff", stroke: "#000000", strokeThickness: 3 })
      .setScrollFactor(0);

    this.objectiveText = this.add
      .text(0, 12, "", {
        fontSize: "15px",
        color: toHex(this.localTeam === "B" ? COLORS.teamB : COLORS.teamA),
        stroke: "#000000",
        strokeThickness: 4,
        align: "right",
        fontStyle: "bold",
      })
      .setOrigin(1, 0)
      .setScrollFactor(0);

    this.controlsText = this.add
      .text(0, 0, "A/D or ←/→ : Move    W or ↑ : Jump    SPACE : Action    (cash deposits automatically at home)", {
        fontSize: "13px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 3,
      })
      .setOrigin(0.5, 1)
      .setScrollFactor(0);

    this.minimap = this.add.graphics().setScrollFactor(0);

    this.jailText = this.add
      .text(0, 0, "", {
        fontSize: "20px",
        color: "#ffdd55",
        stroke: "#000000",
        strokeThickness: 4,
        align: "center",
        backgroundColor: "#000000aa",
        padding: { x: 12, y: 8 },
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);

    this.overlayBg = this.add.rectangle(0, 0, 10, 10, 0x000000, 0.55).setScrollFactor(0).setVisible(false);
    this.overlayText = this.add
      .text(0, 0, "", {
        fontSize: "30px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 5,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);
    this.overlaySubText = this.add
      .text(0, 0, "", {
        fontSize: "18px",
        color: "#ffffff",
        stroke: "#000000",
        strokeThickness: 4,
        align: "center",
      })
      .setOrigin(0.5)
      .setScrollFactor(0)
      .setVisible(false);

    this.layout();
    this.scale.on("resize", this.layout, this);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => this.scale.off("resize", this.layout, this));
  }

  private layout() {
    const w = this.scale.width;
    const h = this.scale.height;

    this.mmScale = MINIMAP_W / WORLD_WIDTH;
    this.mmH = WORLD_HEIGHT * this.mmScale;
    this.mmX = (w - MINIMAP_W) / 2;
    this.mmY = 8;

    this.objectiveText.setPosition(w - 14, 12);
    this.controlsText.setPosition(w / 2, h - 10);
    this.jailText.setPosition(w / 2, h / 2 + 90);

    this.overlayBg.setPosition(w / 2, h / 2).setSize(w, h);
    this.overlayText.setPosition(w / 2, h / 2 - 26);
    this.overlaySubText.setPosition(w / 2, h / 2 + 26);
  }

  private drawMinimap(room: NonNullable<typeof colyseusClient.room>) {
    const g = this.minimap;
    g.clear();

    const s = this.mmScale;
    const ox = this.mmX;
    const oy = this.mmY;

    g.fillStyle(0x000000, 0.35);
    g.fillRect(ox - 3, oy - 3, MINIMAP_W + 6, this.mmH + 6);

    for (const z of MINIMAP_ZONES) {
      g.fillStyle(z.color, 0.9);
      g.fillRect(ox + z.xMin * s, oy + z.yMin * s, (z.xMax - z.xMin) * s, (z.yMax - z.yMin) * s);
    }
    g.lineStyle(1.5, 0x222222, 1);
    g.strokeRect(ox, oy, MINIMAP_W, this.mmH);

    room.state.players.forEach((p: any, id: string) => {
      const px = ox + p.x * s;
      const py = oy + p.y * s;
      const color = p.team === "B" ? COLORS.teamB : COLORS.teamA;
      if (id === room.sessionId) {
        g.fillStyle(0xffffff, 1);
        g.fillCircle(px, py, 5);
        g.fillStyle(color, 1);
        g.fillCircle(px, py, 3.2);
      } else {
        g.fillStyle(color, p.isJailed ? 0.4 : 1);
        g.fillCircle(px, py, 3.2);
      }
    });
  }

  private objectiveMessage(carrying: boolean): string {
    const teamLabel = `TEAM ${this.localTeam}`;
    if (this.localTeam === "B") {
      return carrying ? `${teamLabel}  ◀ Bring cash HOME` : `${teamLabel}  Steal enemy cash ▶`;
    }
    return carrying ? `${teamLabel}  Bring cash HOME ▶` : `${teamLabel}  ◀ Steal enemy cash`;
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
    this.roundText.setText(`Round ${state.roundNumber} of 3  •  Best of 3`);

    const self = room.state.players.get(room.sessionId);
    this.objectiveText.setText(this.objectiveMessage(!!self?.isCarryingCash));

    this.drawMinimap(room);

    if (self?.isJailed) {
      const secsLeft = Math.max(0, Math.ceil(self.jailTimer));
      this.jailText.setVisible(true);
      this.jailText.setText(`JAILED  •  A teammate can free you\nAuto-release in ${secsLeft}s`);
    } else {
      this.jailText.setVisible(false);
    }

    const showOverlay = (title: string, sub: string) => {
      this.overlayBg.setVisible(true);
      this.overlayText.setVisible(true).setText(title);
      this.overlaySubText.setVisible(sub.length > 0).setText(sub);
    };
    const hideOverlay = () => {
      this.overlayBg.setVisible(false);
      this.overlayText.setVisible(false);
      this.overlaySubText.setVisible(false);
    };

    if (state.phase === "countdown") {
      showOverlay(`ROUND ${state.roundNumber}`, `Get ready...  ${Math.max(0, Math.floor(state.countdown))}`);
    } else if (state.phase === "roundEnd") {
      const title = state.roundWinner
        ? `ROUND ${state.roundNumber}: TEAM ${state.roundWinner} WINS!`
        : `ROUND ${state.roundNumber}: TIE - REPLAY`;
      showOverlay(title, `Next round in ${Math.max(0, Math.floor(state.countdown))}...`);
    } else if (state.phase === "matchEnd") {
      showOverlay(`TEAM ${state.matchWinner} WINS THE MATCH!`, "Refresh the page to play again");
    } else {
      hideOverlay();
    }
  }
}
