class_name TeamDef
extends Resource
## One family. See ARCHITECTURE.md §4.
##
## Deliberately holds no colours, meshes, or other presentation data: §3 bars
## those from leaking into rules, and sim/ reads this Resource. Presentation
## maps a team `id` to its look on its own side of the boundary.

@export var id: StringName = &""
@export var display_name: String = ""
## Zone this team defends and deposits into. Must name a ZoneDef with
## role = HOME and owner_team = this id.
@export var home_zone: StringName = &""
## Zone holding THIS team's captured members (i.e. the enemy's jail).
@export var jail_zone: StringName = &""
## Where members enter the world, in slot order. One entry per team member.
@export var spawn_points: Array[Vector3] = []

## Spawn point for the given roster slot, clamped so an oversized roster still
## resolves rather than failing out of range.
func spawn_point_for_slot(slot: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	return spawn_points[clampi(slot, 0, spawn_points.size() - 1)]
