// Shared world geometry + zone lookup used by GameRoom for all server-authoritative
// validation. Top-down floor plan: two mirrored houses (bedroom/living/basement
// stacked per team), each with a private BACKYARD strip along its outer edge,
// flanking a shared neutral garden in the middle. The backyard is part of the
// property: it has second doors into the bedroom and basement (plus one from the
// living room), and owners can jail intruders caught there. See
// client/src/objects/Zone.ts for the matching wall/door geometry (kept in sync by
// hand).

export const WORLD_WIDTH = 1600;
export const WORLD_HEIGHT = 900;

// Column boundaries, left to right: backyard B | house B | garden | house A | backyard A
const YARD_B_MAX = 140;
const HOUSE_B_MAX = 540;
const HOUSE_A_MIN = 1060;
const YARD_A_MIN = 1460;
// Row boundaries within a house column: bedroom | living | basement
const BEDROOM_MAX_Y = 200;
const BASEMENT_MIN_Y = 620;

export type Team = "A" | "B";
export type ZoneId =
  | "backyardB"
  | "bedroomB"
  | "livingB"
  | "basementB"
  | "garden"
  | "bedroomA"
  | "livingA"
  | "basementA"
  | "backyardA";

export function getZoneAt(x: number, y: number): ZoneId {
  if (x < YARD_B_MAX) return "backyardB";
  if (x < HOUSE_B_MAX) {
    if (y < BEDROOM_MAX_Y) return "bedroomB";
    if (y < BASEMENT_MIN_Y) return "livingB";
    return "basementB";
  }
  if (x < HOUSE_A_MIN) return "garden";
  if (x < YARD_A_MIN) {
    if (y < BEDROOM_MAX_Y) return "bedroomA";
    if (y < BASEMENT_MIN_Y) return "livingA";
    return "basementA";
  }
  return "backyardA";
}

export function isEnemyBedroom(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

// Own home = own living room, own master bedroom, or own BACKYARD - the yard is
// part of the property, so owners can lock intruders caught there too. (The bedroom
// is normally unreachable by the owning team - blocked client-side - but the check
// is kept for spec fidelity.)
export function isOwnHome(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  if (team === "B") return zone === "livingB" || zone === "bedroomB" || zone === "backyardB";
  return zone === "livingA" || zone === "bedroomA" || zone === "backyardA";
}

// The basement that holds a given team's jailed prisoners (i.e. the enemy's basement).
export function jailBasementForTeam(team: Team): "basementB" | "basementA" {
  return team === "A" ? "basementB" : "basementA";
}

// Up to 4 spawn points per team (2v2 uses the first two, 3v3 the first three, 4v4
// all four), arranged in a 2x2 grid inside the living room interior, clear of
// every wall and door gap.
export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 280, y: 330 },
    { x: 400, y: 330 },
    { x: 280, y: 450 },
    { x: 400, y: 450 },
  ],
  A: [
    { x: 1200, y: 330 },
    { x: 1320, y: 330 },
    { x: 1200, y: 450 },
    { x: 1320, y: 450 },
  ],
};

export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: { x: 340, y: 760 },
  basementA: { x: 1260, y: 760 },
};

// Arrange `count` points in a compact grid inside [xMin,xMax] x [yMin,yMax].
function grid(xMin: number, xMax: number, yMin: number, yMax: number, count: number): { x: number; y: number }[] {
  const rows = count <= 5 ? 1 : 2;
  const cols = Math.ceil(count / rows);
  const out: { x: number; y: number }[] = [];
  for (let i = 0; i < count; i++) {
    const row = Math.floor(i / cols);
    const col = i % cols;
    const x = cols === 1 ? (xMin + xMax) / 2 : xMin + (col * (xMax - xMin)) / (cols - 1);
    const y = rows === 1 ? (yMin + yMax) / 2 : yMin + (row * (yMax - yMin)) / (rows - 1);
    out.push({ x: Math.round(x), y: Math.round(y) });
  }
  return out;
}

// Starting positions for the `count` original bundles in a master bedroom.
export function bundlePositions(bedroom: "bedroomB" | "bedroomA", count: number): { x: number; y: number }[] {
  return bedroom === "bedroomB" ? grid(180, 500, 40, 100, count) : grid(1100, 1420, 40, 100, count);
}

// Where scored (deposited) bundles stack inside the scoring team's own bedroom
// (offset to a lower band so they never overlap the original-bundle grid above).
export function scoreSlotPositions(team: Team, count: number): { x: number; y: number }[] {
  return team === "B" ? grid(180, 500, 125, 165, count) : grid(1100, 1420, 125, 165, count);
}
