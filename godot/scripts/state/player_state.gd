class_name PlayerState
extends RefCounted
## Ported from server/src/schema/GameState.ts PlayerState (minus Colyseus
## networking - plain fields only, MatchState is the sole mutator).

var id: String = ""
var display_name: String = ""
var team: String = "" # "A" or "B"
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var is_carrying_cash: bool = false
var is_jailed: bool = false
var jail_timer: float = 0.0 # seconds remaining, counts down from 60
var is_bot: bool = false
