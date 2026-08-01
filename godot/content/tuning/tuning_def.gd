class_name TuningDef
extends Resource
## Speeds, ranges, timers and AI weights. See ARCHITECTURE.md §4.
##
## Durations are authored in SECONDS because that is what a designer reasons
## in. The simulation converts them to whole ticks against its fixed timestep
## (SimWorld.seconds_to_ticks) and counts ticks thereafter - no wall clock ever
## reaches a rule (§3).
##
## The AI weights are a table, not logic. A future difficulty tier is a
## different .tres swapped in here - never an edit to the scoring code.

@export_group("Movement")
@export var move_speed: float = 440.0
## Multiplier applied to move_speed while carrying.
##
## 1.0 for now: carrying does not slow you down. The field and the
## carry_speed() path stay live precisely so that this is a number a designer
## dials rather than a code change - set it below 1.0 and laden actors are
## slower with nothing recompiled.
@export var carry_speed_scale: float = 1.0
## Actor body radius, for collision against level geometry.
@export var actor_radius: float = 20.0

@export_group("Interaction ranges")
@export var pickup_range: float = 144.0
@export var capture_range: float = 164.0
@export var rescue_range: float = 164.0

@export_group("Timers (seconds)")
@export var respawn_seconds: float = 0.0
## How long a captured actor stays held when nobody frees them.
@export var capture_hold_seconds: float = 60.0

@export_group("AI cadence (seconds)")
## How often a bot re-scores every candidate action: its reaction speed.
@export var ai_decide_seconds: float = 1.0
## De-syncs teammates' decide ticks so a squad does not think in lockstep.
@export var ai_decide_jitter_seconds: float = 0.3

@export_group("AI weights")
@export var ai_value_deposit: float = 100000.0
@export var ai_value_rescue: float = 6000.0
@export var ai_value_defend: float = 4000.0
@export var ai_value_objective: float = 3000.0
@export var ai_value_patrol: float = 150.0
## Score lost per world-unit of navigation path distance.
@export var ai_cost_weight: float = 0.6
## Score lost per enemy sitting on a chokepoint or on the target itself.
@export var ai_risk_weight: float = 1400.0
## How far away an enemy registers as a threat.
@export var ai_vision_radius: float = 840.0
## Stickiness: the task a bot already holds wins ties and near-ties.
@export var ai_commit_bonus: float = 700.0
## A teammate already handles it - usually pick something else.
@export var ai_coord_penalty: float = 2600.0
## Imperfection: +/- jitter applied per candidate per re-score.
@export var ai_choice_noise: float = 250.0

func carry_speed() -> float:
	return move_speed * carry_speed_scale
