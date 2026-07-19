import * as THREE from "three";
import { WALL_HEIGHT } from "../../constants";
import type { Rect } from "../../geometry/floorplan";
import { wallSegments } from "./HeightField";
import { rectToBox } from "../EnvironmentBuilder";

// Height-aware replacement for "one box per wall rect": every wall rect gets
// split (via HeightField.wallSegments) into runs of uniform adjacent ground
// height, and each run is extruded from its lowest adjacent ground up to the
// CEILING plane above it. On the flat (pre-verticality) parts of the map this
// degenerates to exactly one box per rect at 0..WALL_HEIGHT, identical to the
// old behavior.
//
// The top is max(high, 0) + WALL_HEIGHT, NOT high + WALL_HEIGHT: this matches
// HeightField.ceilingHeight (roofs of sunken rooms sit at grade+WALL_HEIGHT,
// flush with the exterior walls, not down in the pit). A wall bordering ONLY
// sunken ground (both faces basement, e.g. the basement's world-boundary
// walls) would otherwise stop at grade and leave an open sky band between its
// top and the raised roof - the "back wall half open / sky instead of roof"
// bug. Clamping `high` up to 0 first carries those walls to the roof plane.
export function buildWallBoxes(r: Rect, colorHex: number): THREE.BufferGeometry[] {
  return wallSegments(r).map((seg) => {
    const top = Math.max(seg.high, 0) + WALL_HEIGHT;
    const height = top - seg.low;
    return rectToBox(seg.rect, height, seg.low + height / 2, colorHex);
  });
}
