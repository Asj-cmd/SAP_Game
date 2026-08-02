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
## Actor body radius, for collision against level geometry. Also acts as the
## body's half-height, so a resting actor's centre sits this far above the
## floor it stands on.
@export var actor_radius: float = 20.0

@export_group("Gravity")
## Downward acceleration in units per second squared. Zero or less means no
## gravity is authored and actors do not fall - only ever right for a fixture
## that is testing horizontal rules. See WORLD_AUTHORING.md §5.
@export var gravity: float = 2000.0
## Fall speed is capped so a long drop cannot outrun the swept test.
@export var terminal_fall_speed: float = 3000.0
## How high a threshold an actor walks over without a jump. Stairs and door
## sills should not require a verb the game may never have.
@export var step_up_height: float = 30.0

@export_group("Interaction ranges")
@export var pickup_range: float = 144.0
@export var capture_range: float = 164.0
@export var rescue_range: float = 164.0

@export_group("Timers (seconds)")
@export var respawn_seconds: float = 0.0
## How long a captured actor stays held when nobody frees them.
@export var capture_hold_seconds: float = 60.0

## The AI weights that used to sit here now live in BotProfileDef.
##
## They were in the wrong place. This resource is what the WORLD is like, and
## every player in a match shares one; a bot profile is what one OPPONENT is
## like, and a lobby may reasonably mix tiers. Merging them made difficulty a
## property of the level.

func carry_speed() -> float:
	return move_speed * carry_speed_scale
