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
## How long a seized actor is held when nobody comes for them.
##
## A FALLBACK, not the main way out - rescue is. That is why it is far shorter
## than it looks like it should be: rounds run one to two minutes, so a minute
## in the pen is elimination wearing a timer's clothes, and the player spends
## most of their round watching.
@export var capture_seconds: float = 20.0

## Added to the sentence for each previous capture in the same round.
##
## Being caught twice should cost more than being caught once, or the safest
## play is to throw yourself at the vault repeatedly and treat the pen as a slow
## respawn. Zero turns it off; the count resets between rounds, so a bad round
## is never carried into the next one.
@export var capture_escalation_seconds: float = 0.0
@export var pre_round_seconds: float = 3.0
@export var round_end_seconds: float = 3.0

## Bundles a team must hold to win a round. Both sides start holding
## `cash_per_team`, so a target of 2N-1 means winning the exchange by two.
func score_to_win() -> int:
	return cash_per_team * 2 - 1
