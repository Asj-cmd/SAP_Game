extends SceneTree
## The family display names loader (P5-0).
##
##   godot --headless --path godot --script res://tests/family_names_test.gd
##
## The one test of `game/`: the task asks for it, because the user edits the file
## by hand. Every value here is made up; the real names live only in
## `content/family_names.cfg`, and the last case compares with what the loader
## reads from it rather than with a written-out name.

const EXPECTED_CHECKS: int = 26

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Family display names ===")
	_test_parse()
	_test_files()

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

# Each case: text, then what the two teams read after the fallbacks.
func _test_parse() -> void:
	var cases: Array[Array] = [
		["both lines", "team_a_name=Alpha Test\nteam_b_name=Beta Test\n",
			"Alpha Test", "Beta Test"],
		["spaces round key and value", "  team_a_name =   Alpha Test  \n\tteam_b_name\t=Beta Test\t\n",
			"Alpha Test", "Beta Test"],
		["double quotes", "team_a_name=\"Alpha Test\"\nteam_b_name= \" Beta Test \" \n",
			"Alpha Test", "Beta Test"],
		["single quotes", "team_a_name='Alpha Test'\nteam_b_name='Beta'\n",
			"Alpha Test", "Beta"],
		["unmatched quote kept", "team_a_name=\"Alpha\nteam_b_name=Beta'\n",
			"\"Alpha", "Beta'"],
		["empty value falls back", "team_a_name=\nteam_b_name=   \n",
			"Family A", "Family B"],
		["empty quotes fall back", "team_a_name=\"\"\nteam_b_name=Beta Test\n",
			"Family A", "Beta Test"],
		["one line missing", "team_b_name=Beta Test\n",
			"Family A", "Beta Test"],
		["comments and blank lines", "# team_a_name=Not This\n\n   # note\nteam_a_name=Alpha Test\n\n",
			"Alpha Test", "Family B"],
		["value containing =", "team_a_name=A=B Test\nteam_b_name==Beta\n",
			"A=B Test", "=Beta"],
		["windows line ends, unknown keys", "team_c_name=Gamma\r\nteam_a_name=Alpha Test\r\nnonsense\r\n",
			"Alpha Test", "Family B"],
	]
	for case: Array in cases:
		var names: Dictionary[StringName, String] = _with_fallbacks(FamilyNames.parse(case[1]))
		_check("%s: team_a" % case[0], names.get(&"team_a", ""), case[2])
		_check("%s: team_b" % case[0], names.get(&"team_b", ""), case[3])

func _test_files() -> void:
	var missing: Dictionary[StringName, String] = FamilyNames.load_from("res://tests/no_such_family_names.cfg")
	_check("missing file: team_a", missing.get(&"team_a", ""), "Family A")
	_check("missing file: team_b", missing.get(&"team_b", ""), "Family B")
	var real: Dictionary[StringName, String] = FamilyNames.load_from(FamilyNames.PATH)
	_check("name_of reads the shipped file", FamilyNames.name_of(&"team_a"), real[&"team_a"])
	_check("unknown id", FamilyNames.name_of(&"team_c"), "Family")

func _with_fallbacks(parsed: Dictionary[StringName, String]) -> Dictionary[StringName, String]:
	for team_id: StringName in FamilyNames.FALLBACK:
		if not parsed.has(team_id):
			parsed[team_id] = FamilyNames.FALLBACK[team_id]
	return parsed
