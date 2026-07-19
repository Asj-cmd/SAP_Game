import * as THREE from "three";
import { ZONE_RECTS, type ZoneId } from "../../geometry/floorplan";
import { COLORS, ROOF_THICKNESS, WORLD_SCALE } from "../../constants";
import { ceilingHeight } from "./HeightField";

// One flat slab per interior room - backyards/garden are open-air, so they're
// deliberately excluded. Not added to CameraRig's obstacle list: the camera
// never needs to raycast against a ceiling it can't rise above (CameraRig's
// indoor Y clamp keeps it under ceilingHeight). Exported as THE definition of
// "enclosed interior room" - that clamp keys off the same list, so a zone
// can't be roofed but unclamped (or vice versa) by accident.
export const ROOFED_ZONES: ZoneId[] = ["bedroomB", "livingB", "basementB", "bedroomA", "livingA", "basementA"];

// Roof panels overhang the room's footprint by this much, so the slab tucks
// OVER the top of every surrounding wall (walls are centred on the zone edge
// and ~10 units thick) instead of meeting it at a hairline seam that leaks
// sky when viewed edge-on - and it reads as a proper eave.
const ROOF_OVERHANG = 14 * WORLD_SCALE;
// The eave slab is deliberately chunky (vs the old thin sheet) so from ground
// level the overhanging edge casts a readable lip, not a paper-thin line.
const ROOF_SLAB_THICKNESS = ROOF_THICKNESS * 3;

// Solid, always-opaque ceilings. The old fade-the-local-room's-roof reveal
// (and its ROOF_REVEAL_OPACITY translucency compromise) existed only because
// the chase camera could climb above roof height; now that CameraRig clamps
// indoor camera Y under the ceiling, a roof never stands between the camera
// and the character, so every room keeps a plain solid lid - and no sky or
// sun can ever bleed through it. ceilingHeight() puts a sunken basement's lid
// at grade+WALL_HEIGHT (level with the exterior walls) rather than deep in
// the pit, so the garden camera can't peer over the wall into the interior.
export class RoofSystem {
  build(scene: THREE.Scene) {
    for (const zoneId of ROOFED_ZONES) {
      const zone = ZONE_RECTS.find((z) => z.id === zoneId);
      if (!zone) continue;

      const width = zone.xMax - zone.xMin + ROOF_OVERHANG * 2;
      const depth = zone.yMax - zone.yMin + ROOF_OVERHANG * 2;
      const cx = (zone.xMin + zone.xMax) / 2;
      const cz = (zone.yMin + zone.yMax) / 2;
      const top = ceilingHeight(zoneId);

      // Roof color is the loudest per-house identity cue: terracotta over
      // house B, slate blue over house A (ROOFED_ZONES ids end in their
      // house letter), readable across the whole map.
      const color = zoneId.endsWith("B") ? COLORS.roofB : COLORS.roofA;
      const material = new THREE.MeshStandardMaterial({ color, roughness: 0.85 });

      // The slab's UNDERSIDE sits at `top` (the ceiling plane) and its bulk
      // rises above - so it never eats interior headroom, and the chunky
      // overhang reads as an eave from the garden.
      const slab = new THREE.Mesh(new THREE.BoxGeometry(width, ROOF_SLAB_THICKNESS, depth), material);
      slab.position.set(cx, top + ROOF_SLAB_THICKNESS / 2, cz);
      // Deliberately NOT a shadow caster: an opaque lid that also blocked the
      // sun would plunge every interior into flat shadow, and the standing
      // art direction is bright sunlit rooms.
      slab.castShadow = false;
      scene.add(slab);
    }
  }
}
