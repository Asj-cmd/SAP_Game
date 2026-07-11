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

export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 600, y: 620 },
    { x: 750, y: 620 },
  ],
  A: [
    { x: 2450, y: 620 },
    { x: 2600, y: 620 },
  ],
};

export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: { x: 400, y: 880 },
  basementA: { x: 2800, y: 880 },
};

export const BUNDLE_POSITIONS: Record<"bedroomB" | "bedroomA", { x: number; y: number }[]> = {
  bedroomB: [
    { x: 150, y: 660 },
    { x: 250, y: 660 },
    { x: 350, y: 660 },
  ],
  bedroomA: [
    { x: 2800, y: 660 },
    { x: 2900, y: 660 },
    { x: 3000, y: 660 },
  ],
};

// Where scored (deposited) bundles stack visually inside the scoring team's own bedroom,
// indexed by how many bundles that team already has scored (0-4).
export const SCORE_SLOT_POSITIONS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 130, y: 690 },
    { x: 200, y: 690 },
    { x: 270, y: 690 },
    { x: 340, y: 690 },
    { x: 410, y: 690 },
  ],
  A: [
    { x: 2790, y: 690 },
    { x: 2860, y: 690 },
    { x: 2930, y: 690 },
    { x: 3000, y: 690 },
    { x: 3070, y: 690 },
  ],
};
