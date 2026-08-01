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
## A safe room: no actor may be captured inside it. Cash sitting in a room
## where you cannot be sent to lockup is simply role = CASH_ROOM, no_capture = true.
@export var no_capture: bool = false
## Connected zones, for navigation.
@export var links: Array[StringName] = []

func contains_point(point: Vector3) -> bool:
	return bounds.has_point(point)

func is_owned_by(team_id: StringName) -> bool:
	return owner_team != &"" and owner_team == team_id

## True when `team_id` does not own this zone. Neutral ground is hostile to
## nobody, so it reads as not-enemy for every team.
func is_enemy_of(team_id: StringName) -> bool:
	return owner_team != &"" and owner_team != team_id
