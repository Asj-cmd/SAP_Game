// Top-down world (Brawl Stars style): a single flat plane, no ground/underground
// split and no gravity - see server/src/zones.ts + client/src/objects/Zone.ts for
// the floor plan this size matches.
export const WORLD_WIDTH = 1400;
export const WORLD_HEIGHT = 900;

export const PLAYER_SPEED = 220;
export const CARRY_SPEED = 160;

export const MOVE_SEND_INTERVAL_MS = 50; // 20 times/sec
export const REMOTE_LERP = 0.2;

export const ACTION_RANGE = 60;
export const ROUND_TIME_DEFAULT = 300;

export const COLORS = {
  bedroom: 0xf0997b,
  livingRoom: 0xb5d4f4,
  garden: 0xeaf3de,
  gardenAlt: 0xdcefc9,
  basement: 0xb4b2a9,
  teamB: 0xe85d24,
  teamA: 0x185fa5,
  cash: 0xffd700,
  wall: 0x2b2b2b,
  void: 0x0d1926,
};
