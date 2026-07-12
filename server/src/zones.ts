// Shared world geometry + zone lookup used by GameRoom for all server-authoritative
// validation. Top-down floor plan: two mirrored houses (bedroom/living/basement
// stacked per team) flanking a shared neutral garden in the middle. See
// client/src/objects/Zone.ts for the matching wall/door geometry (kept in sync by
// hand).

export const WORLD_WIDTH = 1400;
export const WORLD_HEIGHT = 900;

const COL_B_MAX = 300;
const COL_A_MIN = 1100;
const BEDROOM_MAX_Y = 180;
const BASEMENT_MIN_Y = 620;

export type Team = "A" | "B";
export type ZoneId = "bedroomB" | "livingB" | "garden" | "livingA" | "bedroomA" | "basementB" | "basementA";

export function getZoneAt(x: number, y: number): ZoneId {
  if (x < COL_B_MAX) {
    if (y < BEDROOM_MAX_Y) return "bedroomB";
    if (y < BASEMENT_MIN_Y) return "livingB";
    return "basementB";
  }
  if (x < COL_A_MIN) return "garden";
  if (y < BEDROOM_MAX_Y) return "bedroomA";
  if (y < BASEMENT_MIN_Y) return "livingA";
  return "basementA";
}

export function isEnemyBedroom(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

// Own home = own living room OR own master bedroom (bedroom is normally unreachable
// by the owning team - blocked client-side - but the check is kept for spec fidelity).
export function isOwnHome(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  if (team === "B") return zone === "livingB" || zone === "bedroomB";
  return zone === "livingA" || zone === "bedroomA";
}

// The basement that holds a given team's jailed prisoners (i.e. the enemy's basement).
export function jailBasementForTeam(team: Team): "basementB" | "basementA" {
  return team === "A" ? "basementB" : "basementA";
}

// Up to 3 spawn points per team (2v2 uses the first two, 3v3 uses all three),
// clustered inside the living room interior, clear of every wall and door gap.
export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 110, y: 350 },
    { x: 190, y: 350 },
    { x: 150, y: 430 },
  ],
  A: [
    { x: 1210, y: 350 },
    { x: 1290, y: 350 },
    { x: 1250, y: 430 },
  ],
};

export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: { x: 150, y: 760 },
  basementA: { x: 1250, y: 760 },
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
  return bedroom === "bedroomB" ? grid(30, 270, 35, 95, count) : grid(1130, 1370, 35, 95, count);
}

// Where scored (deposited) bundles stack inside the scoring team's own bedroom
// (offset to a lower band so they never overlap the original-bundle grid above).
export function scoreSlotPositions(team: Team, count: number): { x: number; y: number }[] {
  return team === "B" ? grid(30, 270, 105, 160, count) : grid(1130, 1370, 105, 160, count);
}
