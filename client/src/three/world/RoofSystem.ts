import * as THREE from "three";
import { ZONE_RECTS, type ZoneId } from "../../geometry/floorplan";
import { COLORS, ROOF_THICKNESS, WORLD_SCALE } from "../../constants";
import { ceilingY } from "./HeightField";

// The interior (enclosed) rooms - used by GameController to decide when the
// chase camera should be clamped inside a room vs. left free in the open-air
// garden/backyards. Every floor of a house is enclosed; the garden and
// backyards (floor 0 only) are not.
export const ROOFED_ZONES: ZoneId[] = ["bedroomB", "livingB", "basementB", "bedroomA", "livingA", "basementA"];

// In the stacked town-house the ceiling of each lower floor IS the floor slab
// of the one above it (built in EnvironmentBuilder), so the only actual ROOF is
// the lid over the top floor (the bedrooms) of each house. One chunky slab per
// house at the top-floor ceiling, tinted the house's team colour and overhung a
// little past the footprint so it reads as an eave from the garden.
const ROOF_OVERHANG = 14 * WORLD_SCALE;
const ROOF_SLAB_THICKNESS = ROOF_THICKNESS * 3;
const ROOF_EMISSIVE = 0.22;

export class RoofSystem {
  build(scene: THREE.Scene) {
    for (const zoneId of ["bedroomB", "bedroomA"] as ZoneId[]) {
      const zone = ZONE_RECTS.find((z) => z.id === zoneId);
      if (!zone) continue;

      const x1 = zone.xMin - ROOF_OVERHANG;
      const x2 = zone.xMax + ROOF_OVERHANG;
      const z1 = zone.yMin - ROOF_OVERHANG;
      const z2 = zone.yMax + ROOF_OVERHANG;
      const top = ceilingY(zone.floor); // top-floor ceiling plane

      const color = zoneId.endsWith("B") ? COLORS.roofB : COLORS.roofA;
      const material = new THREE.MeshStandardMaterial({
        color,
        roughness: 0.85,
        emissive: new THREE.Color(color).multiplyScalar(ROOF_EMISSIVE),
      });
      const slab = new THREE.Mesh(new THREE.BoxGeometry(x2 - x1, ROOF_SLAB_THICKNESS, z2 - z1), material);
      slab.position.set((x1 + x2) / 2, top + ROOF_SLAB_THICKNESS / 2, (z1 + z2) / 2);
      slab.castShadow = false;
      scene.add(slab);
    }
  }
}
