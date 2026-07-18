import * as THREE from "three";
import { ZONE_RECTS, type ZoneId } from "../../geometry/floorplan";
import { COLORS, ROOF_BASE, ROOF_THICKNESS } from "../../constants";
import { zoneBaseHeight } from "./HeightField";

// One flat slab per interior room - backyards/garden are open-air, so they're
// deliberately excluded. Not added to CameraRig's obstacle list: the camera
// never needs to raycast against a ceiling it can't rise above (CameraRig's
// indoor Y clamp keeps it under zoneBase + ROOF_BASE). Exported as THE
// definition of "enclosed interior room" - that clamp keys off the same
// list, so a zone can't be roofed but unclamped (or vice versa) by accident.
export const ROOFED_ZONES: ZoneId[] = ["bedroomB", "livingB", "basementB", "bedroomA", "livingA", "basementA"];

// Solid, always-opaque ceilings. The old fade-the-local-room's-roof reveal
// (and its ROOF_REVEAL_OPACITY translucency compromise) existed only because
// the chase camera could climb above roof height; now that CameraRig clamps
// indoor camera Y under the ceiling, a roof never stands between the camera
// and the character, so every room keeps a plain solid lid - and no sky or
// sun can ever bleed through it.
export class RoofSystem {
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
      });
      const mesh = new THREE.Mesh(geometry, material);
      // Each room's roof sits one story above its own zone base: bedroom roof
      // at +FLOOR_RISE+WALL_HEIGHT, living at WALL_HEIGHT, basement at grade
      // (0 + WALL_HEIGHT) - reading as a cellar hatch cap over the sunken pit.
      mesh.position.set(cx, zoneBaseHeight(zoneId) + ROOF_BASE + ROOF_THICKNESS / 2, cz);
      // Deliberately NOT a shadow caster: an opaque lid that also blocked the
      // sun would plunge every interior into flat shadow, and the standing
      // art direction is bright sunlit rooms (the old reveal achieved that by
      // disabling the faded roof's shadow - this keeps the same interior
      // light with the lid permanently solid).
      mesh.castShadow = false;
      scene.add(mesh);
    }
  }
}
