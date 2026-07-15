import * as THREE from "three";
import { WALL_HEIGHT } from "../../constants";
import type { Rect } from "../../geometry/floorplan";
import { wallSegments } from "./HeightField";
import { rectToBox } from "../EnvironmentBuilder";

// Height-aware replacement for "one box per wall rect": every wall rect gets
// split (via HeightField.wallSegments) into runs of uniform adjacent ground
// height, and each run is extruded from its lowest adjacent ground up to its
// highest adjacent ground + WALL_HEIGHT. On the flat (pre-verticality) parts
// of the map this degenerates to exactly one box per rect at 0..WALL_HEIGHT,
// identical to the old behavior.
export function buildWallBoxes(r: Rect, colorHex: number): THREE.BufferGeometry[] {
  return wallSegments(r).map((seg) => {
    const height = seg.high + WALL_HEIGHT - seg.low;
    return rectToBox(seg.rect, height, seg.low + height / 2, colorHex);
  });
}
