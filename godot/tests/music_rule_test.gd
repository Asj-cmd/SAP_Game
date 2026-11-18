extends SceneTree
## When the menu music plays (PT3-1): menu, lobby and results yes; a match, the
## end sequence and any screen nobody added to the rule no.
##
##   godot --headless --path godot --script res://tests/music_rule_test.gd

const EXPECTED_CHECKS: int = 7

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Music rule ===")
	# screen, music wanted
	var cases: Array[Array] = [
		[&"menu", true], [&"lobby", true], [&"results", true],
		[&"match", false], [&"end_sequence", false], [&"pause", false], [&"", false],
	]
	for case: Array in cases:
		var got: bool = GameAudio.music_wanted(case[0])
		if got == case[1]:
			_passed += 1
		else:
			_failed += 1
			_failures.append("%s: expected %s, got %s" % [case[0], case[1], got])
	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d" % [ran, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)
