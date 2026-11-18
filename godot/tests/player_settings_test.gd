extends SceneTree
## Saved audio volumes (PT2-3): master, music, effects and footsteps.
##
##   godot --headless --path godot --script res://tests/player_settings_test.gd
##
## A test of `game/`, an exception the PLAN asks for (as family_names_test): the
## values live in a file the player's machine keeps between versions, so an old file
## without a key, a 0 that must stay 0 and out-of-range values are worth pinning.
## Uses its own file in user://, never the player's settings.cfg, and deletes it.

const EXPECTED_CHECKS: int = 35
const TEST_PATH: String = "user://settings_test.cfg"

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Player settings (audio) ===")
	_test_load()
	_test_round_trip()
	_remove()

	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d - a case was skipped"
			% [ran, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("\nFAILURES:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

func _check(case_name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s: expected %s, got %s" % [case_name, expected, actual])

# Each case: file text (null = no file), then read?, master, music, effects, footsteps.
func _test_load() -> void:
	var cases: Array[Array] = [
		["no file: defaults", null, false, 1.0, 0.6, 1.0, 0.4],
		["empty file: defaults", "", true, 1.0, 0.6, 1.0, 0.4],
		["old file without footsteps", "[audio]\nmaster=0.8\neffects=0.5\nmusic=0.3\n",
			true, 0.8, 0.3, 0.5, 0.4],
		["footsteps 0 stays off", "[audio]\nfootsteps=0.0\n", true, 1.0, 0.6, 1.0, 0.0],
		["out of range clamped", "[audio]\nmaster=1.7\neffects=-0.3\nmusic=2\nfootsteps=-1\n",
			true, 1.0, 1.0, 0.0, 0.0],
		["other sections only", "[team_tell]\nmarker=true\n", true, 1.0, 0.6, 1.0, 0.4],
	]
	for case: Array in cases:
		_remove()
		if case[1] != null:
			var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
			file.store_string(case[1])
			file.close()
		var settings: PlayerSettings = PlayerSettings.new()
		_check("%s: read" % case[0], settings.load_from(TEST_PATH), case[2])
		_check("%s: master" % case[0], settings.volume_of(&"Master"), case[3])
		_check("%s: music" % case[0], settings.volume_of(&"Music"), case[4])
		_check("%s: effects" % case[0], settings.volume_of(&"SFX"), case[5])
		_check("%s: footsteps" % case[0], settings.volume_of(&"Footsteps"), case[6])

# Saved values come back, and another section in the file (TeamTell's) survives.
func _test_round_trip() -> void:
	_remove()
	var other: ConfigFile = ConfigFile.new()
	other.set_value("team_tell", "marker", true)
	other.save(TEST_PATH)
	var written: PlayerSettings = PlayerSettings.new()
	written.master_volume = 0.5
	written.music_volume = 0.25
	written.effects_volume = 0.75
	written.footsteps_volume = 0.0
	written.save_to(TEST_PATH)
	var read: PlayerSettings = PlayerSettings.new()
	read.load_from(TEST_PATH)
	_check("round trip: master", read.master_volume, 0.5)
	_check("round trip: music", read.music_volume, 0.25)
	_check("round trip: effects", read.effects_volume, 0.75)
	_check("round trip: footsteps off", read.footsteps_volume, 0.0)
	var after: ConfigFile = ConfigFile.new()
	after.load(TEST_PATH)
	_check("round trip: other section kept", after.get_value("team_tell", "marker", false), true)

func _remove() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
