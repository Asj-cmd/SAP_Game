class_name LevelDef
extends Resource
## Everything a level is, in one file: its rooms, its rosters, and its walls.
##
## Baked from a blockout scene rather than hand-written (WORLD_AUTHORING.md §6
## and §8 step 4). One resource rather than a directory of them because the
## pieces are meaningless apart - a ZoneDef without the collision it sits in
## describes nothing - and because loading a level should be one load().
##
## Nothing here is edited by hand. Edit the blockout, run the baker.

@export var id: StringName = &""
@export var display_name: String = ""
@export var zones: Array[ZoneDef] = []
@export var teams: Array[TeamDef] = []
@export var collision: WorldCollisionDef = null
## Which blockout scene produced this, so a stale bake can be traced back.
@export var source_scene: String = ""

## Deep copy, for a caller that needs to vary something without editing the
## shared asset every other caller is reading.
func duplicated() -> LevelDef:
	var copy: LevelDef = LevelDef.new()
	copy.id = id
	copy.display_name = display_name
	copy.source_scene = source_scene
	copy.collision = collision
	var zone_copies: Array[ZoneDef] = []
	for zone: ZoneDef in zones:
		zone_copies.append(zone.duplicate())
	copy.zones = zone_copies
	var team_copies: Array[TeamDef] = []
	for team: TeamDef in teams:
		team_copies.append(team.duplicate())
	copy.teams = team_copies
	return copy

func zone(zone_id: StringName) -> ZoneDef:
	for candidate: ZoneDef in zones:
		if candidate.id == zone_id:
			return candidate
	return null

## Rooms that shelter, which is what a safe-room variant is a question about.
func sheltered_zones() -> Array[ZoneDef]:
	var found: Array[ZoneDef] = []
	for candidate: ZoneDef in zones:
		if candidate.role == ZoneDef.Role.CASH_ROOM:
			found.append(candidate)
	return found
