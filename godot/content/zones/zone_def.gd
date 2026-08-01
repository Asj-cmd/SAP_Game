class_name ZoneDef
extends Resource
## One room. See ARCHITECTURE.md §4.
##
## Zones carry ROLES, not identities. No rule may ask "is this bedroomA" - it
## asks "is this a cash room belonging to a team that is not mine". That is
## what lets a third house, a shared central vault, or an upstairs jail be new
## .tres files rather than new code paths.

enum Role {
	NEUTRAL, ## Shared ground owned by nobody (the garden, a corridor).
	HOME, ## A team's own territory: it may capture intruders here.
	CASH_ROOM, ## Holds carriables worth scoring.
	JAIL, ## Where captured actors are held.
}

@export var id: StringName = &""
@export var role: Role = Role.NEUTRAL
## Empty for neutral ground.
@export var owner_team: StringName = &""
## 3D from the first commit (§6) - a multi-storey house must not need a retrofit.
@export var bounds: AABB = AABB()
## How long protection from capture lasts once an actor enters, in seconds.
##
##   < 0  this room offers no protection at all (the default, and what almost
##        every zone wants)
##   = 0  protection has no time limit
##   > 0  protection lapses this many seconds after entry
##
## The negative sentinel is what lets "unlimited" keep the natural value of 0
## while a plain unconfigured zone still defaults to offering nothing.
@export var safe_duration_seconds: float = -1.0
## When true, protection also ends the moment the actor picks something up -
## a grab-and-you-are-fair-game rule, independent of any timer.
##
## The two conditions compose. Whichever fires first ends protection:
##   duration 5, pickup false   protected for 5s regardless of carrying
##   duration 0, pickup true    protected indefinitely until the grab
##   duration 5, pickup true    5s, or until the grab, whichever comes first
@export var safe_ends_on_pickup: bool = false

## Does this room protect at all? Both conditions are inert without it.
func grants_safety() -> bool:
	return safe_duration_seconds >= 0.0

## True when protection here lapses on a timer rather than lasting until some
## other condition ends it.
func safety_is_timed() -> bool:
	return safe_duration_seconds > 0.0
## Connected zones, for navigation.
@export var links: Array[StringName] = []
## Resolution order where zone bounds overlap: HIGHER WINS.
##
## Overlap is a legitimate authoring tool, not a mistake - a vault volume
## inside a bedroom, a stairwell shared between two floors. This makes the
## containing zone a deliberate choice rather than a consequence of which id
## happened to sort first alphabetically.
@export var priority: int = 0

func contains_point(point: Vector3) -> bool:
	return bounds.has_point(point)

func is_owned_by(team_id: StringName) -> bool:
	return owner_team != &"" and owner_team == team_id

## True when `team_id` does not own this zone. Neutral ground is hostile to
## nobody, so it reads as not-enemy for every team.
func is_enemy_of(team_id: StringName) -> bool:
	return owner_team != &"" and owner_team != team_id
