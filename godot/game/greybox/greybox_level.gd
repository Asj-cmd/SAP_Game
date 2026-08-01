class_name GreyBoxLevel
extends RefCounted
## The arena the grey-box slice plays in.
##
## Built in code rather than authored as .tres, deliberately and temporarily.
## WORLD_AUTHORING.md §6 puts level content behind a Blender export convention
## (§8 step 4), and hand-writing a dozen .tres files now only to regenerate
## them from Blender later is work with a negative return. Everything here is
## the shape that exporter will emit, so swapping it out is a change of source,
## not of structure.
##
## Plain boxes. No art. The point of the slice is feel, and anything that looks
## finished invites arguing about how it looks.

## Safe-room configurations under test. The whole reason the slice exists is
## to settle which of these is the better game, by playing them (§9).
enum SafeVariant {
	A, ## Sheltered indefinitely, until you grab something.
	B, ## Sheltered for a fixed few seconds, whatever you are carrying.
}

const SHELL: AABB = AABB(Vector3(0, 0, 0), Vector3(600, 200, 600))
const FLOOR_TOP: float = 20.0
const ACTOR_RADIUS: float = 20.0
## Where a body's centre sits when standing on the floor.
const STAND_Y: float = FLOOR_TOP + ACTOR_RADIUS

const CASH_PER_TEAM: int = 3

var variant: SafeVariant = SafeVariant.B
var zones: Array[ZoneDef] = []
var teams: Array[TeamDef] = []
var collision: WorldCollisionDef = null
var tuning: TuningDef = null
var mode: GameModeDef = null

func _init(safe_variant: SafeVariant = SafeVariant.B) -> void:
	variant = safe_variant
	_build()

func _build() -> void:
	collision = WorldCollisionDef.new()
	collision.bounds = SHELL
	collision.blockers = [
		# The floor is an ordinary blocker - nothing in sim/ knows what a floor
		# is, only that something solid stopped the fall.
		AABB(Vector3(0, 0, 0), Vector3(600, FLOOR_TOP, 600)),
		# One central pillar, purely so there is something to run into and
		# slide along while judging how movement feels.
		AABB(Vector3(280, FLOOR_TOP, 260), Vector3(40, 120, 80)),
	]

	zones = [
		_zone(&"vault_a", ZoneDef.Role.CASH_ROOM, &"team_a", AABB(Vector3(0, 0, 0), Vector3(200, 200, 300)), true),
		_zone(&"jail_a", ZoneDef.Role.JAIL, &"team_a", AABB(Vector3(0, 0, 300), Vector3(200, 200, 300)), false),
		_zone(&"yard", ZoneDef.Role.NEUTRAL, &"", AABB(Vector3(200, 0, 0), Vector3(200, 200, 600)), false),
		_zone(&"vault_b", ZoneDef.Role.CASH_ROOM, &"team_b", AABB(Vector3(400, 0, 0), Vector3(200, 200, 300)), true),
		_zone(&"jail_b", ZoneDef.Role.JAIL, &"team_b", AABB(Vector3(400, 0, 300), Vector3(200, 200, 300)), false),
	]

	teams = [
		_team(&"team_a", "Reds", &"vault_a", &"jail_b", Vector3(100, STAND_Y, 150), 60.0),
		_team(&"team_b", "Blues", &"vault_b", &"jail_a", Vector3(500, STAND_Y, 150), 460.0),
	]

	tuning = TuningDef.new()
	tuning.actor_radius = ACTOR_RADIUS
	tuning.move_speed = 440.0
	tuning.carry_speed_scale = 1.0
	tuning.pickup_range = 70.0
	tuning.capture_range = 80.0
	tuning.rescue_range = 80.0
	tuning.gravity = 2000.0
	tuning.step_up_height = 30.0

	mode = GameModeDef.new()
	mode.id = &"greybox"
	mode.display_name = "Grey box"
	mode.team_size = 1
	mode.cash_per_team = CASH_PER_TEAM
	mode.rounds_to_win = 2
	mode.round_seconds = 90.0
	mode.pre_round_seconds = 2.0
	mode.round_end_seconds = 3.0
	mode.capture_seconds = 8.0

func _zone(
	id: StringName,
	role: ZoneDef.Role,
	owner: StringName,
	bounds: AABB,
	sheltered: bool
) -> ZoneDef:
	var zone: ZoneDef = ZoneDef.new()
	zone.id = id
	zone.role = role
	zone.owner_team = owner
	zone.bounds = bounds
	if sheltered:
		# The A/B question, expressed entirely as content values. Nothing
		# outside this block - and nothing in the HUD - restates them (§9).
		if variant == SafeVariant.A:
			zone.safe_duration_seconds = -1.0
			zone.safe_ends_on_pickup = true
		else:
			zone.safe_duration_seconds = 5.0
			zone.safe_ends_on_pickup = false
	return zone

func _team(
	id: StringName,
	display: String,
	home: StringName,
	jail: StringName,
	spawn: Vector3,
	cash_base_x: float
) -> TeamDef:
	var team: TeamDef = TeamDef.new()
	team.id = id
	team.display_name = display
	team.home_zone = home
	team.jail_zone = jail
	var points: Array[Vector3] = [spawn]
	team.spawn_points = points
	var cash: Array[Vector3] = []
	for i: int in CASH_PER_TEAM:
		cash.append(Vector3(cash_base_x + i * 40.0, STAND_Y, 80.0))
	team.cash_points = cash
	return team

## The sheltered zone a variant question is actually about, for the HUD to
## read its numbers from rather than restate them.
func sheltered_zone() -> ZoneDef:
	for zone: ZoneDef in zones:
		if zone.grants_safety():
			return zone
	return null
