import * as THREE from "three";
import { ZONE_RECTS, type ZoneId } from "../../geometry/floorplan";
import { COLORS, ROOF_BASE, ROOF_THICKNESS, ROOF_FADE_SPEED, ROOF_REVEAL_OPACITY } from "../../constants";
import { zoneBaseHeight } from "./HeightField";

// One flat slab per interior room - backyards/garden are open-air, so they're
// deliberately excluded. Not added to CameraRig's obstacle list: the roof
// should never block the chase camera's raycast, only visually cap the room
// the player isn't currently standing in.
const ROOFED_ZONES: ZoneId[] = ["bedroomB", "livingB", "basementB", "bedroomA", "livingA", "basementA"];

interface RoofPanel {
  zone: ZoneId;
  mesh: THREE.Mesh;
  material: THREE.MeshStandardMaterial;
}

// Fades the roof over whichever room the local player is standing in toward
// a low-but-visible opacity (ROOF_REVEAL_OPACITY - a ghosted ceiling, never
// literal open sky), and every other roof back toward opaque, so the camera
// never loses the room the player's actually in while every room still reads
// as enclosed. Per-panel material (6 draw calls) instead of one merged mesh,
// since each panel fades independently.
export class RoofSystem {
  private panels: RoofPanel[] = [];

  build(scene: THREE.Scene) {
    for (const zoneId of ROOFED_ZONES) {
      const zone = ZONE_RECTS.find((z) => z.id === zoneId);
      if (!zone) continue;

      const width = zone.xMax - zone.xMin;
      const depth = zone.yMax - zone.yMin;
      const cx = (zone.xMin + zone.xMax) / 2;
      const cz = (zone.yMin + zone.yMax) / 2;

      const geometry = new THREE.BoxGeometry(width, ROOF_THICKNESS, depth);
      // Roof color is the loudest per-house identity cue: terracotta over
      // house B, slate blue over house A (ROOFED_ZONES ids end in their
      // house letter), readable across the whole map.
      const material = new THREE.MeshStandardMaterial({
        color: zoneId.endsWith("B") ? COLORS.roofB : COLORS.roofA,
        transparent: true,
        opacity: 1,
      });
      const mesh = new THREE.Mesh(geometry, material);
      // Each room's roof sits one story above its own zone base: bedroom roof
      // at +FLOOR_RISE+WALL_HEIGHT, living at WALL_HEIGHT, basement at grade
      // (0 + WALL_HEIGHT) - reading as a cellar hatch cap over the sunken pit.
      mesh.position.set(cx, zoneBaseHeight(zoneId) + ROOF_BASE + ROOF_THICKNESS / 2, cz);
      mesh.castShadow = true;
      scene.add(mesh);

      this.panels.push({ zone: zoneId, mesh, material });
    }
  }

  update(dt: number, localZone: ZoneId) {
    const step = ROOF_FADE_SPEED * dt;
    for (const panel of this.panels) {
      const target = panel.zone === localZone ? ROOF_REVEAL_OPACITY : 1;
      const opacity = panel.material.opacity;
      panel.material.opacity =
        opacity < target ? Math.min(target, opacity + step) : Math.max(target, opacity - step);

      // Panels never fade below ROOF_REVEAL_OPACITY anymore, so they stay
      // visible always; a ghosted ceiling shouldn't darken its own room.
      panel.mesh.castShadow = panel.material.opacity > 0.5;
    }
  }
}
