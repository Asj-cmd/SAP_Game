import { Schema, type, MapSchema } from "@colyseus/schema";

export class PlayerState extends Schema {
  @type("string") id: string = "";
  @type("string") name: string = "";
  @type("string") team: string = ""; // "A" or "B"
  @type("number") x: number = 0;
  @type("number") y: number = 0;
  @type("number") vx: number = 0;
  @type("number") vy: number = 0;
  @type("boolean") isCarryingCash: boolean = false;
  @type("boolean") isJailed: boolean = false;
  @type("number") jailTimer: number = 0; // seconds remaining, counts down from 60
  @type("boolean") connected: boolean = true;
  @type("boolean") isBot: boolean = false;
}

export class CashBundleState extends Schema {
  @type("string") id: string = "";
  @type("number") x: number = 0;
  @type("number") y: number = 0;
  @type("string") location: string = ""; // "bedroomA" | "bedroomB" | "carried:{playerId}" | "scored:{team}"
  @type("boolean") isScored: boolean = false;
}

export class GameState extends Schema {
  @type("string") hostId: string = ""; // sessionId of the player who can assign teams/bots and start the match
  @type("string") phase: string = "waiting"; // "waiting" | "countdown" | "playing" | "roundEnd" | "matchEnd"
  @type("number") teamSize: number = 2; // players per team (2 = 2v2, 3 = 3v3)
  @type("number") winScore: number = 5; // bundles a team must hold to win the round
  @type("number") roundTimer: number = 300;
  @type("number") countdown: number = 3;
  @type("number") scoreA: number = 0;
  @type("number") scoreB: number = 0;
  @type("number") roundNumber: number = 1;
  @type("number") winsA: number = 0;
  @type("number") winsB: number = 0;
  @type("string") roundWinner: string = ""; // "A" | "B" | ""
  @type("string") matchWinner: string = ""; // "A" | "B" | ""
  @type({ map: PlayerState }) players: MapSchema<PlayerState> = new MapSchema<PlayerState>();
  @type({ map: CashBundleState }) cashBundles: MapSchema<CashBundleState> = new MapSchema<CashBundleState>();
}
