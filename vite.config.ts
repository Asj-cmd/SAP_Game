import Phaser from "phaser";
import {
  ZONES,
  BOUNDARY_WALLS,
  OPEN_DOOR_WALLS,
  BEDROOM_DIVIDER_WALLS,
  GROUND_FLOOR_SEGMENTS,
  UNDERGROUND_FLOOR,
  UNDERGROUND_DIVIDER_WALLS,
  STAIR_STEPS,
  WINDOW_PLATFORMS,
  ENTRY_MARKERS,
  COLORS,
  WORLD_WIDTH,
} from "../constants";

export function drawZones(scene: Phaser.Scene) {
  scene.add.rectangle(WORLD_WIDTH / 2, 360, WORLD_WIDTH, 720, COLORS.sky).setDepth(-10);
  scene.add.rectangle(WORLD_WIDTH / 2, 720 + 150, WORLD_WIDTH, 300, COLORS.dirt).setDepth(-10);

  ZONES.forEach((z) => {
    scene.add
      .rectangle(z.x + z.width / 2, z.y + z.height / 2, z.width, z.height, z.color)
      .setStrokeStyle(2, 0x333333)
      .setDepth(-5);
    if (z.label) {
      scene.add
        .text(z.x + z.width / 2, z.y + 20, z.label, { fontSize: "14px", color: "#333333" })
        .setOrigin(0.5)
        .setDepth(0);
    }
  });

  scene.add
    .rectangle(WORLD_WIDTH / 2, 720, WORLD_WIDTH, 4, COLORS.ground)
    .setDepth(-1);

  // Highlight every usable opening so players can find doors and stairs.
  ENTRY_MARKERS.forEach((m) => {
    scene.add
      .rectangle(m.x + m.width / 2, m.y + m.height / 2, m.width, m.height, 0x00cc44, 0.25)
      .setStrokeStyle(3, 0x00aa33)
      .setDepth(1);
    scene.add
      .text(m.x + m.width / 2, m.y - 12, m.label, {
        fontSize: "12px",
        color: "#007722",
        stroke: "#ffffff",
        strokeThickness: 3,
      })
      .setOrigin(0.5)
      .setDepth(1);
  });
}

export function createWallColliders(scene: Phaser.Scene): Phaser.Physics.Arcade.StaticGroup {
  const group = scene.physics.add.staticGroup();
  const allWalls = [
    ...BOUNDARY_WALLS,
    ...OPEN_DOOR_WALLS,
    ...BEDROOM_DIVIDER_WALLS,
    ...GROUND_FLOOR_SEGMENTS,
    UNDERGROUND_FLOOR,
    ...UNDERGROUND_DIVIDER_WALLS,
  ];
  allWalls.forEach((w) => {
    const rect = scene.add.rectangle(w.x + w.width / 2, w.y + w.height / 2, w.width, w.height, 0x000000, 0);
    scene.physics.add.existing(rect, true);
    group.add(rect);
  });
  // Stair steps and window platforms are visible, not invisible walls.
  [...STAIR_STEPS, ...WINDOW_PLATFORMS].forEach((w) => {
    const rect = scene.add
      .rectangle(w.x + w.width / 2, w.y + w.height / 2, w.width, w.height, COLORS.ground)
      .setStrokeStyle(1, 0x5a4409)
      .setDepth(1);
    scene.physics.add.existing(rect, true);
    group.add(rect);
  });
  return group;
}
