// The renderer's view of the world geometry.
//
// The geometry itself - walls, connectors, zone bounds, doorways, balconies,
// spawns, the bot graph and every helper - is defined ONCE in
// shared/worldGeometry.ts and re-exported here, so the client and the
// authoritative server can never disagree about where a wall is. Only
// PRESENTATION lives in this file: the colours and labels used to draw zones,
// which the simulation has no opinion about.
export * from "../../../shared/worldGeometry";

import { COLORS } from "../constants";
import { ZONE_BOUNDS, type ZoneId } from "../../../shared/worldGeometry";

export interface ZoneRect {
  id: ZoneId;
  label: string;
  labelColor?: string;
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
  floor: number;
  color: number;
}

// Per-zone presentation, keyed by the shared zone ids. Bounds always come from
// ZONE_BOUNDS, so a geometry change can never leave the drawn zones behind.
const ZONE_STYLE: Record<string, { label: string; color: number; labelColor?: string }> = {
  backyardB: { label: "BACKYARD B", color: COLORS.backyard },
  livingB: { label: "LIVING ROOM B", color: COLORS.livingB, labelColor: "#8c3f10" },
  garden: { label: "GARDEN", color: COLORS.garden },
  livingA: { label: "LIVING ROOM A", color: COLORS.livingA, labelColor: "#12467c" },
  backyardA: { label: "BACKYARD A", color: COLORS.backyard },
  bedroomB: { label: "BEDROOMS B", color: COLORS.bedroom },
  bedroomA: { label: "BEDROOMS A", color: COLORS.bedroom },
  basementB: { label: "BASEMENT B (jail: Team A)", color: COLORS.basement },
  basementA: { label: "BASEMENT A (jail: Team B)", color: COLORS.basement },
};

export const ZONE_RECTS: ZoneRect[] = ZONE_BOUNDS.map((z) => ({
  ...z,
  ...(ZONE_STYLE[z.id] ?? { label: z.id, color: COLORS.wall }),
}));

// The renderer draws a floor mat in every passable opening; the openings
// themselves are shared geometry.
export { DOORWAYS as DOORS } from "../../../shared/worldGeometry";
