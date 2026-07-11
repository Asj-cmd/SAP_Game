// Client-side mirror of server/src/zones.ts — used only to decide when to
// show the SPACE action prompt and which message to send. The server is the
// authority; these functions are duplicated deliberately (see server file).

export type Team = "A" | "B";
export type ZoneId =
  | "bedroomB"
  | "livingB"
  | "garden"
  | "livingA"
  | "bedroomA"
  | "basementB"
  | "dirtZone"
  | "basementA";

const GROUND_Y_MAX = 720;

export function getZoneAt(x: number, y: number): ZoneId {
  if (y < GROUND_Y_MAX) {
    if (x < 500) return "bedroomB";
    if (x < 980) return "livingB";
    if (x < 2220) return "garden";
    if (x < 2700) return "livingA";
    return "bedroomA";
  }
  if (x < 980) return "basementB";
  if (x < 2220) return "dirtZone";
  return "basementA";
}

export function isEnemyBedroom(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  return (team === "B" && zone === "bedroomA") || (team === "A" && zone === "bedroomB");
}

export function isOwnHome(team: Team, x: number, y: number): boolean {
  const zone = getZoneAt(x, y);
  if (team === "B") return zone === "bedroomB" || zone === "livingB";
  return zone === "bedroomA" || zone === "livingA";
}

export function jailBasementForTeam(team: Team): ZoneId {
  return team === "A" ? "basementB" : "basementA";
}

export function isInZone(zone: ZoneId, x: number, y: number): boolean {
  return getZoneAt(x, y) === zone;
}

export function otherTeam(team: Team): Team {
  return team === "A" ? "B" : "A";
}
