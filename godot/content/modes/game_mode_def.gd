class_name GameModeDef
extends Resource
## A ruleset: 2v2, 3v3, custom. See ARCHITECTURE.md §4.
##
## A new mode is a new .tres. Not a new code path, and not a constant edited at
## the top of a file.

@export var id: StringName = &""
@export var display_name: String = ""
@export var team_size: int = 2
@export var rounds_to_win: int = 2
@export var round_seconds: float = 300.0
@export var cash_per_team: int = 3
## Lockup timeout: how long a captured actor is held before automatic release.
@export var capture_seconds: float = 60.0
@export var pre_round_seconds: float = 3.0
@export var round_end_seconds: float = 3.0

## Bundles a team must hold to win a round. Both sides start holding
## `cash_per_team`, so a target of 2N-1 means winning the exchange by two.
func score_to_win() -> int:
	return cash_per_team * 2 - 1
