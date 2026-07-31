class_name CashBundleState
extends RefCounted
## Ported from server/src/schema/GameState.ts CashBundleState.

var id: String = ""
var x: float = 0.0
var y: float = 0.0
var location: String = "" # "bedroomA" | "bedroomB" | "carried:{playerId}" | "scored:{team}"
var is_scored: bool = false
