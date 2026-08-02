class_name GreyBoxLevel
extends RefCounted
## The arena the grey-box slice plays in, loaded from baked content.
##
## The geometry is authored visually in game/blockout/greybox_house.tscn and
## baked to a LevelDef by tools/bake_blockout.gd. Nothing here knows a
## coordinate: change the level by dragging boxes and re-baking, not by editing
## this file. That is the same separation WORLD_AUTHORING.md §6 asks for from
## the Blender pipeline, which is why the convention is worth having now - when
## the source moves to a .blend, only the baker changes.
##
## Still plain boxes. The point of the slice is feel, and anything that looks
## finished invites arguing about how it looks instead.

## Safe-room configurations under test. Settling which of these is the better
## game, by playing them, is the whole reason the slice exists.
enum SafeVariant {
	A, ## Sheltered indefinitely, until you grab something.
	B, ## Sheltered for a fixed few seconds, whatever you are carrying.
}

const LEVEL_PATH: String = "res://content/levels/greybox_house.tres"
## Difficulty is a file, not a build. Swapping this path - or editing the .tres
## it points at - is the whole of "make the bots harder".
const BOT_PROFILE_PATH: String = "res://content/ai/bot_profile_standard.tres"

var variant: SafeVariant = SafeVariant.B
var level: LevelDef = null
var zones: Array[ZoneDef] = []
var teams: Array[TeamDef] = []
var collision: WorldCollisionDef = null
var tuning: TuningDef = null
var mode: GameModeDef = null
var bot_profile: BotProfileDef = null

func _init(safe_variant: SafeVariant = SafeVariant.B) -> void:
	variant = safe_variant
	tuning = build_tuning()
	bot_profile = load(BOT_PROFILE_PATH) as BotProfileDef
	if bot_profile == null:
		push_error("grey box: no bot profile at %s - run tools/write_bot_profiles.gd" % BOT_PROFILE_PATH)

	var baked: LevelDef = load(LEVEL_PATH) as LevelDef
	if baked == null:
		push_error("grey box: no baked level at %s - run tools/bake_blockout.gd" % LEVEL_PATH)
		mode = build_mode(0)
		return

	# Worked on a copy. The variant switch must not edit the shared asset every
	# other caller is reading - and a runtime edit of content would be
	# presentation writing into the layer the rules read.
	level = baked.duplicated()
	_apply_variant()
	zones = level.zones
	teams = level.teams
	collision = level.collision
	mode = build_mode(_cash_per_team())

## Numbers a designer dials, kept apart from the geometry a designer drags.
static func build_tuning() -> TuningDef:
	var values: TuningDef = TuningDef.new()
	values.actor_radius = 20.0
	values.move_speed = 440.0
	values.carry_speed_scale = 1.0
	values.pickup_range = 70.0
	values.capture_range = 80.0
	values.rescue_range = 80.0
	values.gravity = 2000.0
	values.step_up_height = 30.0
	return values

static func build_mode(cash_per_team: int) -> GameModeDef:
	var rules: GameModeDef = GameModeDef.new()
	rules.id = &"greybox"
	rules.display_name = "Grey box"
	rules.team_size = 1
	rules.cash_per_team = cash_per_team
	rules.rounds_to_win = 2
	rules.round_seconds = 120.0
	rules.pre_round_seconds = 2.0
	rules.round_end_seconds = 3.0
	rules.capture_seconds = 8.0
	return rules

## The A/B question, expressed entirely as content values. Nothing outside this
## function - and nothing in the HUD - restates them (§9).
func _apply_variant() -> void:
	for zone: ZoneDef in level.sheltered_zones():
		if variant == SafeVariant.A:
			zone.safe_duration_seconds = -1.0
			zone.safe_ends_on_pickup = true
		else:
			zone.safe_duration_seconds = 5.0
			zone.safe_ends_on_pickup = false

## Taken from the level rather than declared, so moving cash markers in the
## blockout cannot leave the win target describing a different game.
func _cash_per_team() -> int:
	var most: int = 0
	for team: TeamDef in teams:
		most = maxi(most, team.cash_points.size())
	return most

## The sheltered room the variant question is about, for the HUD to read its
## numbers from rather than restate them.
func sheltered_zone() -> ZoneDef:
	if level == null:
		return null
	var sheltered: Array[ZoneDef] = level.sheltered_zones()
	return sheltered[0] if not sheltered.is_empty() else null

func is_loaded() -> bool:
	return level != null and collision != null
