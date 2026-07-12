// Shared world geometry + zone lookup used by GameRoom for all server-authoritative validation.

export const WORLD_WIDTH = 3200;
export const WORLD_HEIGHT = 1020;
export const GROUND_Y = 720;

export type Team = "A" | "B";
export type ZoneId =
  | "bedroomB"
  | "livingB"
  | "garden"
  | "livingA"
  | "bedroomA"
  | "basementB"
  | "gardenPit"
  | "basementA";

export function getZoneAt(x: number, y: number): ZoneId {
  if (y < GROUND_Y) {
    if (x < 500) return "bedroomB";
    if (x < 980) return "livingB";
    if (x < 2220) return "garden";
    if (x < 2700) return "livingA";
    return "bedroomA";
  }
  if (x < 980) return "basementB";
  if (x < 2220) return "gardenPit";
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

// Up to 3 spawn points per team (2v2 uses the first two, 3v3 uses all three).
// All sit on the living-room floor of the owning team, clear of the basement gap.
export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 560, y: 620 },
    { x: 660, y: 620 },
    { x: 760, y: 620 },
  ],
  A: [
    { x: 2450, y: 620 },
    { x: 2550, y: 620 },
    { x: 2650, y: 620 },
  ],
};

export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: { x: 400, y: 880 },
  basementA: { x: 2800, y: 880 },
};

// Evenly spread `count` points across [xMin, xMax] at height y.
function spread(xMin: number, xMax: number, count: number, y: number): { x: number; y: number }[] {
  const out: { x: number; y: number }[] = [];
  if (count <= 1) return [{ x: Math.round((xMin + xMax) / 2), y }];
  const step = (xMax - xMin) / (count - 1);
  for (let i = 0; i < count; i++) out.push({ x: Math.round(xMin + i * step), y });
  return out;
}

// Starting positions for the `count` original bundles in a master bedroom.
export function bundlePositions(bedroom: "bedroomB" | "bedroomA", count: number): { x: number; y: number }[] {
  return bedroom === "bedroomB" ? spread(120, 440, count, 660) : spread(2760, 3080, count, 660);
}

// Where scored (deposited) bundles stack inside the scoring team's own bedroom.
export function scoreSlotPositions(team: Team, count: number): { x: number; y: number }[] {
  return team === "B" ? spread(110, 460, count, 690) : spread(2740, 3090, count, 690);
}
