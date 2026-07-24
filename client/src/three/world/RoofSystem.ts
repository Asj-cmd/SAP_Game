import * as THREE from "three";
import { ZONE_RECTS, type ZoneId } from "../../geometry/floorplan";
import { COLORS, WORLD_SCALE } from "../../constants";
import { ceilingY } from "./HeightField";

// The interior (enclosed) rooms - used by GameController to decide when the
// chase camera should be clamped inside a room vs. left free in the open-air
// garden/backyards. Every floor of a house is enclosed; the garden and
// backyards (floor 0 only) are not.
export const ROOFED_ZONES: ZoneId[] = ["bedroomB", "livingB", "basementB", "bedroomA", "livingA", "basementA"];

// In the stacked town-house the ceiling of each lower floor IS the floor slab
// of the one above it (built in EnvironmentBuilder), so the only actual ROOF is
// over the top floor (the bedrooms). A flat slab read as a shoebox lid, so each
// house instead gets a real GABLED roof - two slopes meeting at a ridge, with
// gable triangles closing the ends - tinted the house's team colour and overhung
// a little past the footprint for an eave. The ridge runs along the house's
// depth (z). The camera's indoor Y clamp keeps it under the eave (ceilingY), so
// the pitched underside just reads as a vaulted ceiling from inside.
const ROOF_OVERHANG = 16 * WORLD_SCALE;
const ROOF_PITCH = 0.3; // ridge height as a fraction of the footprint WIDTH (x)
const ROOF_EMISSIVE = 0.18;

export class RoofSystem {
  build(scene: THREE.Scene) {
    for (const zoneId of ["bedroomB", "bedroomA"] as ZoneId[]) {
      const zone = ZONE_RECTS.find((z) => z.id === zoneId);
      if (!zone) continue;

      const x1 = zone.xMin - ROOF_OVERHANG;
      const x2 = zone.xMax + ROOF_OVERHANG;
      const z1 = zone.yMin - ROOF_OVERHANG;
      const z2 = zone.yMax + ROOF_OVERHANG;
      const xMid = (x1 + x2) / 2;
      const eaveY = ceilingY(zone.floor); // top-floor ceiling plane = the eaves
      const ridgeY = eaveY + (x2 - x1) * ROOF_PITCH;

      // 6 corners: 4 eave corners + 2 ridge ends (ridge runs along z).
      const A = [x1, eaveY, z1];
      const B = [x2, eaveY, z1];
      const C = [x1, eaveY, z2];
      const D = [x2, eaveY, z2];
      const R1 = [xMid, ridgeY, z1];
      const R2 = [xMid, ridgeY, z2];

      // Two slope quads (each two tris) + two gable-end triangles. Wound for
      // outward normals; DoubleSide anyway so the vaulted underside also shades.
      const tris = [
        // west slope (x1 side)
        A, C, R2, A, R2, R1,
        // east slope (x2 side)
        B, R1, R2, B, R2, D,
        // gable end at z1
        A, R1, B,
        // gable end at z2
        C, D, R2,
      ];
      const positions = new Float32Array(tris.flat());
      const geo = new THREE.BufferGeometry();
      geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
      geo.computeVertexNormals();

      const color = zoneId.endsWith("B") ? COLORS.roofB : COLORS.roofA;
      const material = new THREE.MeshStandardMaterial({
        color,
        roughness: 0.85,
        side: THREE.DoubleSide,
        emissive: new THREE.Color(color).multiplyScalar(ROOF_EMISSIVE),
      });
      const roof = new THREE.Mesh(geo, material);
      roof.castShadow = false;
      roof.receiveShadow = true;
      scene.add(roof);
    }
  }
}
