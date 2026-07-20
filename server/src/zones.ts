// Shared world geometry + zone lookup used by GameRoom for all server-authoritative
// validation. Top-down floor plan: two mirrored houses (bedroom/living/basement
// stacked per team), each with a private BACKYARD strip along its outer edge,
// flanking a shared neutral garden in the middle. The backyard is part of the
// property: it has second doors into the bedroom and basement (plus one from the
// living room), and owners can jail intruders caught there. See
// client/src/objects/Zone.ts for the matching wall/door geometry (kept in sync by
// hand).

// Widens the whole floor plan relative to the original 2D layout (1600x900).
// All tables in this file stay written in original coordinates and are scaled
// at module load. The client applies the same factor (client/src/constants.ts
// WORLD_SCALE) - keep both in sync. Speeds and action ranges in GameRoom.ts
// scale with it too, so travel times and balance match the 2D-tuned values.
export const WORLD_SCALE = 2.5; // MUST match client/src/constants.ts WORLD_SCALE
const S = WORLD_SCALE;

export const WORLD_WIDTH = 1600 * S;
export const WORLD_HEIGHT = 900 * S;

// Column boundaries, left to right: backyard B | house B | garden | house A | backyard A
const YARD_B_MAX = 140 * S;
const HOUSE_B_MAX = 540 * S;
const HOUSE_A_MIN = 1060 * S;
const YARD_A_MIN = 1460 * S;
// Row boundaries within a house column: bedroom | living | basement
const BEDROOM_MAX_Y = 200 * S;
const BASEMENT_MIN_Y = 620 * S;

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
const scalePoint = (p: { x: number; y: number }) => ({ x: p.x * S, y: p.y * S });

// ---- collision geometry (bots) ----
//
// Hand-synced with client/src/geometry/floorplan.ts WALLS + DOORS (same
// pre-scale numbers, scaled here at load) - keep both in sync. Humans collide
// against these CLIENT-side in CharacterController; bots have no client, so
// GameRoom.botTick resolves bot movement against the same rects server-side.
// Only the SEALED doors are colliders (and only for the team they're sealed
// for - the enemy walks through them); every open door gap is simply absent
// from WALLS, exactly like the client.
export interface Rect {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
const scaleRect = (r: Rect): Rect => ({ x1: r.x1 * S, y1: r.y1 * S, x2: r.x2 * S, y2: r.y2 * S });

export const WALLS: Rect[] = (
  [
    // world boundary
    { x1: 0, y1: 0, x2: 1600, y2: 10 },
    { x1: 0, y1: 890, x2: 1600, y2: 900 },
    { x1: 0, y1: 0, x2: 10, y2: 900 },
    { x1: 1590, y1: 0, x2: 1600, y2: 900 },
    // backyard B | house B (x=140)
    { x1: 135, y1: 0, x2: 145, y2: 60 },
    { x1: 135, y1: 140, x2: 145, y2: 370 },
    { x1: 135, y1: 450, x2: 145, y2: 700 },
    { x1: 135, y1: 780, x2: 145, y2: 900 },
    // house B | garden (x=540)
    { x1: 535, y1: 0, x2: 545, y2: 230 },
    { x1: 535, y1: 290, x2: 545, y2: 380 },
    { x1: 535, y1: 440, x2: 545, y2: 530 },
    { x1: 535, y1: 590, x2: 545, y2: 900 },
    // bedroom B | living B (y=200)
    { x1: 140, y1: 195, x2: 300, y2: 205 },
    { x1: 380, y1: 195, x2: 540, y2: 205 },
    // living B | basement B (y=620)
    { x1: 140, y1: 615, x2: 300, y2: 625 },
    { x1: 380, y1: 615, x2: 540, y2: 625 },
    // garden | house A (x=1060)
    { x1: 1055, y1: 0, x2: 1065, y2: 230 },
    { x1: 1055, y1: 290, x2: 1065, y2: 380 },
    { x1: 1055, y1: 440, x2: 1065, y2: 530 },
    { x1: 1055, y1: 590, x2: 1065, y2: 900 },
    // house A | backyard A (x=1460)
    { x1: 1455, y1: 0, x2: 1465, y2: 60 },
    { x1: 1455, y1: 140, x2: 1465, y2: 370 },
    { x1: 1455, y1: 450, x2: 1465, y2: 700 },
    { x1: 1455, y1: 780, x2: 1465, y2: 900 },
    // bedroom A | living A (y=200)
    { x1: 1060, y1: 195, x2: 1220, y2: 205 },
    { x1: 1300, y1: 195, x2: 1460, y2: 205 },
    // living A | basement A (y=620)
    { x1: 1060, y1: 615, x2: 1220, y2: 625 },
    { x1: 1300, y1: 615, x2: 1460, y2: 625 },
  ] as Rect[]
).map(scaleRect);

// The 8 sealed doors (4 per house), tagged with the team that CANNOT pass
// them - so a bot collides only with its OWN sealed doors, mirroring the
// client's colliderRects = WALLS + sealedDoors(localTeam).
export const SEALED_DOORS: (Rect & { team: Team })[] = (
  [
    { x1: 133, y1: 60, x2: 147, y2: 140, team: "B" }, // bedroom <-> backyard
    { x1: 300, y1: 193, x2: 380, y2: 207, team: "B" }, // bedroom <-> living
    { x1: 300, y1: 613, x2: 380, y2: 627, team: "B" }, // basement <-> living
    { x1: 133, y1: 700, x2: 147, y2: 780, team: "B" }, // basement <-> backyard
    { x1: 1453, y1: 60, x2: 1467, y2: 140, team: "A" },
    { x1: 1220, y1: 193, x2: 1300, y2: 207, team: "A" },
    { x1: 1220, y1: 613, x2: 1300, y2: 627, team: "A" },
    { x1: 1453, y1: 700, x2: 1467, y2: 780, team: "A" },
  ] as (Rect & { team: Team })[]
).map((d) => ({ ...scaleRect(d), team: d.team }));

export const SPAWN_POINTS: Record<Team, { x: number; y: number }[]> = {
  B: [
    { x: 280, y: 330 },
    { x: 400, y: 330 },
    { x: 280, y: 450 },
    { x: 400, y: 450 },
  ].map(scalePoint),
  A: [
    { x: 1200, y: 330 },
    { x: 1320, y: 330 },
    { x: 1200, y: 450 },
    { x: 1320, y: 450 },
  ].map(scalePoint),
};

export const JAIL_POSITIONS: Record<"basementB" | "basementA", { x: number; y: number }> = {
  basementB: scalePoint({ x: 340, y: 760 }),
  basementA: scalePoint({ x: 1260, y: 760 }),
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
  return bedroom === "bedroomB"
    ? grid(180 * S, 500 * S, 40 * S, 100 * S, count)
    : grid(1100 * S, 1420 * S, 40 * S, 100 * S, count);
}

// Where scored (deposited) bundles stack inside the scoring team's own bedroom
// (offset to a lower band so they never overlap the original-bundle grid above).
export function scoreSlotPositions(team: Team, count: number): { x: number; y: number }[] {
  return team === "B"
    ? grid(180 * S, 500 * S, 125 * S, 165 * S, count)
    : grid(1100 * S, 1420 * S, 125 * S, 165 * S, count);
}

// ---- Bot pathing graph ----
// A minimal waypoint graph AI bots use to route between rooms without
// clipping through walls. Team B can never re-enter its own bedroomB/basementB
// (those doors are sealedFor "B" - see the client's DOORS list) and never
// needs to: it defends from livingB/backyardB and only ever *targets* the
// enemy's bedroomA/basementA. So the graph only needs the door gates a bot's
// own team can actually use - not every physical door in the house.
export type BotNodeId =
  | "livingB"
  | "bedroomB"
  | "basementB"
  | "livingA"
  | "bedroomA"
  | "basementA"
  | "garden"
  | "gateB_bedroom"
  | "gateB_basement"
  | "gateB_garden"
  | "gateA_bedroom"
  | "gateA_basement"
  | "gateA_garden"
  // Backyard spur (per house). The yard is an open vertical STRIP, so it gets
  // one node per door latitude (bedroom / living / basement) linked vertically,
  // plus the three door gates - living<->yard (open to all), yard<->bedroom and
  // yard<->basement (sealed for the OWNING team, like the interior stairs).
  // Every edge is axis-aligned so a bot threads each door head-on instead of
  // beelining diagonally into a jamb and wedging. Gives bots the alternative
  // raid/rescue route humans always had, and lets a defender chase into its
  // own yard. `backyardB`/`backyardA` are the living-latitude strip nodes (the
  // hub the raid/rescue "via" and defence routing target).
  | "backyardB"
  | "yardB_bedroom"
  | "yardB_basement"
  | "gateB_yard"
  | "gateB_yardBedroom"
  | "gateB_yardBasement"
  | "backyardA"
  | "yardA_bedroom"
  | "yardA_basement"
  | "gateA_yard"
  | "gateA_yardBedroom"
  | "gateA_yardBasement";

export const BOT_WAYPOINTS: Record<BotNodeId, { x: number; y: number }> = {
  livingB: scalePoint({ x: 340, y: 410 }),
  bedroomB: scalePoint({ x: 340, y: 100 }),
  basementB: scalePoint({ x: 340, y: 760 }),
  livingA: scalePoint({ x: 1260, y: 410 }),
  bedroomA: scalePoint({ x: 1260, y: 100 }),
  basementA: scalePoint({ x: 1260, y: 760 }),
  garden: scalePoint({ x: 800, y: 450 }),
  gateB_bedroom: scalePoint({ x: 340, y: 200 }), // sealedFor B - only usable by team A
  gateB_basement: scalePoint({ x: 340, y: 620 }), // sealedFor B - only usable by team A
  gateB_garden: scalePoint({ x: 540, y: 410 }),
  gateA_bedroom: scalePoint({ x: 1260, y: 200 }), // sealedFor A - only usable by team B
  gateA_basement: scalePoint({ x: 1260, y: 620 }), // sealedFor A - only usable by team B
  gateA_garden: scalePoint({ x: 1060, y: 410 }),
  // Yard strip nodes: mid-strip (x=70 / x=1530), one per door latitude, so
  // travel in the open yard is vertical and each door is entered straight-on.
  backyardB: scalePoint({ x: 70, y: 410 }), // living latitude (the hub)
  yardB_bedroom: scalePoint({ x: 70, y: 100 }),
  yardB_basement: scalePoint({ x: 70, y: 740 }),
  gateB_yard: scalePoint({ x: 140, y: 410 }), // living<->backyard door, open to all
  gateB_yardBedroom: scalePoint({ x: 140, y: 100 }), // sealedFor B - only usable by team A
  gateB_yardBasement: scalePoint({ x: 140, y: 740 }), // sealedFor B - only usable by team A
  backyardA: scalePoint({ x: 1530, y: 410 }),
  yardA_bedroom: scalePoint({ x: 1530, y: 100 }),
  yardA_basement: scalePoint({ x: 1530, y: 740 }),
  gateA_yard: scalePoint({ x: 1460, y: 410 }),
  gateA_yardBedroom: scalePoint({ x: 1460, y: 100 }), // sealedFor A - only usable by team B
  gateA_yardBasement: scalePoint({ x: 1460, y: 740 }), // sealedFor A - only usable by team B
};

interface BotEdge {
  a: BotNodeId;
  b: BotNodeId;
  blockedFor?: Team; // the door here is sealed for this team
}

const BOT_EDGES: BotEdge[] = [
  { a: "livingB", b: "gateB_garden" },
  { a: "gateB_garden", b: "garden" },
  { a: "garden", b: "gateA_garden" },
  { a: "gateA_garden", b: "livingA" },
  { a: "livingB", b: "gateB_bedroom", blockedFor: "B" },
  { a: "gateB_bedroom", b: "bedroomB", blockedFor: "B" },
  { a: "livingB", b: "gateB_basement", blockedFor: "B" },
  { a: "gateB_basement", b: "basementB", blockedFor: "B" },
  { a: "livingA", b: "gateA_bedroom", blockedFor: "A" },
  { a: "gateA_bedroom", b: "bedroomA", blockedFor: "A" },
  { a: "livingA", b: "gateA_basement", blockedFor: "A" },
  { a: "gateA_basement", b: "basementA", blockedFor: "A" },
  // Backyard spurs. Living<->yard is open to everyone (owners chase intruders
  // into their own yard); the yard<->bedroom/basement legs mirror the interior
  // stair doors' seals. Every edge is axis-aligned: the strip nodes link
  // vertically (open yard), each door gate links straight across to its strip
  // node and straight in to the room, so a bot never beelines diagonally into
  // a door jamb.
  { a: "livingB", b: "gateB_yard" }, // straight W
  { a: "gateB_yard", b: "backyardB" }, // straight W through the living door
  { a: "backyardB", b: "yardB_bedroom" }, // straight N up the strip
  { a: "backyardB", b: "yardB_basement" }, // straight S down the strip
  { a: "yardB_bedroom", b: "gateB_yardBedroom", blockedFor: "B" }, // straight E to the door
  { a: "gateB_yardBedroom", b: "bedroomB", blockedFor: "B" }, // straight E into the bedroom
  { a: "yardB_basement", b: "gateB_yardBasement", blockedFor: "B" },
  { a: "gateB_yardBasement", b: "basementB", blockedFor: "B" },
  { a: "livingA", b: "gateA_yard" },
  { a: "gateA_yard", b: "backyardA" },
  { a: "backyardA", b: "yardA_bedroom" },
  { a: "backyardA", b: "yardA_basement" },
  { a: "yardA_bedroom", b: "gateA_yardBedroom", blockedFor: "A" },
  { a: "gateA_yardBedroom", b: "bedroomA", blockedFor: "A" },
  { a: "yardA_basement", b: "gateA_yardBasement", blockedFor: "A" },
  { a: "gateA_yardBasement", b: "basementA", blockedFor: "A" },
];

export function nearestBotNode(x: number, y: number): BotNodeId {
  let best: BotNodeId = "garden";
  let bestDist = Infinity;
  (Object.keys(BOT_WAYPOINTS) as BotNodeId[]).forEach((id) => {
    const p = BOT_WAYPOINTS[id];
    const d = Math.hypot(p.x - x, p.y - y);
    if (d < bestDist) {
      bestDist = d;
      best = id;
    }
  });
  return best;
}

// BFS shortest path (by hop count - the graph is small and roughly uniform in
// edge length, so hop count is a fine stand-in for distance) between two
// nodes, respecting which gates `team` is allowed to use. Falls back to
// staying put if the destination is unreachable (should not happen given the
// graph's fixed shape, but a bot standing still beats a crash).
export function findBotPath(team: Team, from: BotNodeId, to: BotNodeId): BotNodeId[] {
  if (from === to) return [from];

  const adjacency = new Map<BotNodeId, BotNodeId[]>();
  for (const edge of BOT_EDGES) {
    if (edge.blockedFor === team) continue;
    if (!adjacency.has(edge.a)) adjacency.set(edge.a, []);
    if (!adjacency.has(edge.b)) adjacency.set(edge.b, []);
    adjacency.get(edge.a)!.push(edge.b);
    adjacency.get(edge.b)!.push(edge.a);
  }

  const queue: BotNodeId[] = [from];
  const cameFrom = new Map<BotNodeId, BotNodeId>();
  const visited = new Set<BotNodeId>([from]);
  while (queue.length > 0) {
    const current = queue.shift()!;
    if (current === to) break;
    for (const next of adjacency.get(current) ?? []) {
      if (visited.has(next)) continue;
      visited.add(next);
      cameFrom.set(next, current);
      queue.push(next);
    }
  }

  if (!visited.has(to)) return [from];
  const path: BotNodeId[] = [to];
  while (path[0] !== from) path.unshift(cameFrom.get(path[0])!);
  return path;
}
