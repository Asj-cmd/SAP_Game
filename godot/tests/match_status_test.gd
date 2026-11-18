extends SceneTree
## The top bar's split (P5-2): a pure function of the two banked cash counts.
##
##   godot --headless --path godot --script res://tests/match_status_test.gd

const EXPECTED_CHECKS: int = 15

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
	_test_bar_layout()
	var ran: int = _passed + _failed
	if ran != EXPECTED_CHECKS:
		_failed += 1
		_failures.append("harness: ran %d checks, expected %d" % [ran, EXPECTED_CHECKS])
	print("\n%d passed, %d failed" % [_passed, _failed])
	for failure: String in _failures:
		print("  - %s" % failure)
	quit(1 if _failed > 0 else 0)

## PT4-4: the bar's layout. The first family fills from the left in its own
## colour, the second from the right in its own; both read from the theme.
func _test_bar_layout() -> void:
	print("=== Cash bar layout ===")
	var theme: ArtTheme = ArtTheme.current()
	var first: StringName = &"team_a"
	var second: StringName = &"team_b"
	# first, second, expected split
	var cases: Array[Array] = [[0, 0, 0.5], [0, 6, 0.0], [6, 0, 1.0], [3, 1, 0.75]]
	for case: Array in cases:
		var layout: Dictionary = MatchHud.bar_layout(case[0], case[1], first, second, theme)
		var ok: bool = is_equal_approx(layout[&"split"], case[2]) \
			and layout[&"left"] == theme.family_colour(first) \
			and layout[&"right"] == theme.family_colour(second)
		_count(ok, "layout %d/%d: expected split %s in %s|%s, got %s" % [case[0], case[1], case[2],
			theme.family_colour(first), theme.family_colour(second), layout])
	var plain: Dictionary = MatchHud.bar_layout(0, 0, first, second, theme)
	_count(plain[&"left"] != plain[&"right"], "the two families' colours are the same: %s" % plain[&"left"])
	# The sides follow the level's team order, not the ids: swapped ids swap colours.
	var swapped: Dictionary = MatchHud.bar_layout(0, 6, second, first, theme)
	_count(swapped[&"left"] == theme.family_colour(second) and swapped[&"right"] == theme.family_colour(first),
		"swapped ids did not swap the colours: %s" % swapped)

func _count(ok: bool, failure: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(failure)
