@tool
class_name BlockoutZone
extends MeshInstance3D
## A room, placed and sized in the 3D editor.
##
## The box you see IS the zone: drag it, use the mesh's own resize handles, and
## the baker reads the result. That is the point of blocking out visually
## rather than typing coordinates - the geometry is judged by looking at it.
##
## Zone semantics live here as exported properties rather than in the node name
## (WORLD_AUTHORING.md §6 uses names because Blender objects have nothing else;
## a Godot node has an inspector, so it gets to be typed and validated).

@export var zone_id: StringName = &""
@export var role: ZoneDef.Role = ZoneDef.Role.NEUTRAL
## Open ground rather than a room. See ZoneDef.outdoor.
@export var outdoor: bool = false
## Empty for neutral ground.
@export var owner_team: StringName = &""
## Resolution order where zones overlap - higher wins.
@export var priority: int = 0

@export_group("Shelter")
## 0 none, -1 no timer, >0 seconds. See ZoneDef.
@export var safe_duration_seconds: float = 0.0
@export var safe_ends_on_pickup: bool = false

## Bounds are passed in rather than read off global_transform: the baker
## resolves placement by composing transforms, so it works on a scene that is
## merely loaded rather than one that is running.
func to_zone_def(bounds: AABB) -> ZoneDef:
	var zone: ZoneDef = ZoneDef.new()
	zone.id = zone_id
	zone.role = role
	zone.outdoor = outdoor
	zone.owner_team = owner_team
	zone.priority = priority
	zone.bounds = bounds
	zone.safe_duration_seconds = safe_duration_seconds
	zone.safe_ends_on_pickup = safe_ends_on_pickup
	return zone
