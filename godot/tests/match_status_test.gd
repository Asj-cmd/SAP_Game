extends SceneTree
## The top bar's split (P5-2): a pure function of the two banked cash counts.
##
##   godot --headless --path godot --script res://tests/match_status_test.gd

const EXPECTED_CHECKS: int = 9

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Cash bar split ===")
	# first, second, expected share of the first family
	var cases: Array[Array] = [
		[0, 0, 0.5], [1, 0, 1.0], [0, 4, 0.0], [3, 1, 0.75], [2, 2, 0.5],
		[1, 3, 0.25], [7, 0, 1.0], [0, 1, 0.0], [5, 3, 0.625],
	]
	for case: Array in cases:
		var got: float = MatchStatus.cash_split(case[0], case[1])
		if is_equal_approx(got, case[2]):
			_passed += 1
		else:
			_failed += 1
			_failures.append("%d/%d: expected %s, got %s" % [case[0], case[1], case[2], got])
	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d" % [ran, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)
