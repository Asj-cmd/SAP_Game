// Client-only elevation for the STACKED town-house. The server/network model
// carries a discrete `floor` (-1/0/+1); this module turns a (x, z, floor) into
// the three-y height a character/prop/camera should sit at. A floor's base is
// simply floor * STORY_HEIGHT; the only non-flat case is standing ON a
// staircase/ladder connector, where the height ramps smoothly between the two
// floors it joins so the climb reads as continuous (the discrete floor still
// flips at the connector's midline, server-side, via resolveFloor).
//
// Deliberately three.js-agnostic (like geometry/floorplan.ts) and a pure
// function of its inputs, so nothing here can create a rule/network/bot effect.
import { STORY_HEIGHT, WALL_HEIGHT } from "../../constants";
import { CONNECTORS, type Team, type Connector } from "../../geometry/floorplan";

// The flat floor elevation of a given floor.
export function floorY(floor: number): number {
  return floor * STORY_HEIGHT;
}

// The ceiling plane above a floor - CameraRig caps the indoor camera under it.
export function ceilingY(floor: number): number {
  return floorY(floor) + WALL_HEIGHT;
}

function smoothstep(t: number): number {
  const c = Math.max(0, Math.min(1, t));
  return c * c * (3 - 2 * c);
}

function inRect(x: number, y: number, c: Connector): boolean {
  return x >= c.rect.x1 && x <= c.rect.x2 && y >= c.rect.y1 && y <= c.rect.y2;
}

// The height a body at (x, z) on `floor` should render at. On a connector that
// serves this floor, ramp between the two floors it joins (floorLow at the
// low-coordinate end, floorHigh at the high end) so walking the stairs/ladder
// glides between levels instead of teleporting.
export function visualHeight(x: number, z: number, floor: number, team?: Team): number {
  for (const c of CONNECTORS) {
    if (c.sealedFor === team) continue;
    if (floor !== c.floorLow && floor !== c.floorHigh) continue;
    if (!inRect(x, z, c)) continue;
    const axisStart = c.axis === "x" ? c.rect.x1 : c.rect.y1;
    const axisEnd = c.axis === "x" ? c.rect.x2 : c.rect.y2;
    const coord = c.axis === "x" ? x : z;
    const t = smoothstep((coord - axisStart) / (axisEnd - axisStart));
    return (c.floorLow + (c.floorHigh - c.floorLow) * t) * STORY_HEIGHT;
  }
  return floorY(floor);
}
