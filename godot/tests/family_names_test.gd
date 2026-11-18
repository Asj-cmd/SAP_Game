extends SceneTree
## The family display names (P5-0, PT3-3).
##
##   godot --headless --path godot --script res://tests/family_names_test.gd
##
## One of the few tests of `game/`: the defaults file is edited by hand and the
## typed names arrive from other players, so the rules for both are pinned.
## Names in the parse cases are made up; the shipped defaults are compared with
## what the loader reads from the file rather than with written-out text.
##
## PT3-3: the one cleaning rule for a typed name (`FamilyNames.clean`), how a
## typed name is shown ("<Name> Family"), and that an empty box falls back to the
## default.

const EXPECTED_CHECKS: int = 52

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Family display names ===")
	_test_parse()
	_test_files()
	_test_clean()
	_test_shown()

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
			"Green Family", "Orange Family"],
		["empty quotes fall back", "team_a_name=\"\"\nteam_b_name=Beta Test\n",
			"Green Family", "Beta Test"],
		["one line missing", "team_b_name=Beta Test\n",
			"Green Family", "Beta Test"],
		["comments and blank lines", "# team_a_name=Not This\n\n   # note\nteam_a_name=Alpha Test\n\n",
			"Alpha Test", "Orange Family"],
		["value containing =", "team_a_name=A=B Test\nteam_b_name==Beta\n",
			"A=B Test", "=Beta"],
		["windows line ends, unknown keys", "team_c_name=Gamma\r\nteam_a_name=Alpha Test\r\nnonsense\r\n",
			"Alpha Test", "Orange Family"],
	]
	for case: Array in cases:
		var names: Dictionary[StringName, String] = _with_fallbacks(FamilyNames.parse(case[1]))
		_check("%s: team_a" % case[0], names.get(&"team_a", ""), case[2])
		_check("%s: team_b" % case[0], names.get(&"team_b", ""), case[3])

func _test_files() -> void:
	var missing: Dictionary[StringName, String] = FamilyNames.load_from("res://tests/no_such_family_names.cfg")
	_check("missing file: team_a", missing.get(&"team_a", ""), "Green Family")
	_check("missing file: team_b", missing.get(&"team_b", ""), "Orange Family")
	var real: Dictionary[StringName, String] = FamilyNames.load_from(FamilyNames.PATH)
	FamilyNames.clear_typed()
	_check("name_of reads the shipped file", FamilyNames.name_of(&"team_a"), real[&"team_a"])
	_check("unknown id", FamilyNames.name_of(&"team_c"), "Family")

# Each case: what was typed, what is kept.
func _test_clean() -> void:
	var cases: Array[Array] = [
		["empty", "", ""],
		["16 characters kept", "Abcdefghijklmnop", "Abcdefghijklmnop"],
		["17 characters cut to 16", "Abcdefghijklmnopq", "Abcdefghijklmnop"],
		["cut lands on a space, trimmed", "Abcdefghijklmno pq", "Abcdefghijklmno"],
		["digits removed", "Smith 2000", "Smith"],
		["digits inside removed", "Sm1th", "Smth"],
		["symbols removed", "Sm!th@#$%^&*()_+=.,;:/\\|<>?\"", "Smth"],
		["emoji removed", "Smith \U01F4B0", "Smith"],
		["tab and newline removed", "Van\tDer\nBerg", "VanDerBerg"],
		["accents kept", "Élodie Müller", "Élodie Müller"],
		["other alphabets kept", "Петров", "Петров"],
		["only spaces", "     ", ""],
		["ends trimmed", "  Smith  ", "Smith"],
		["space runs collapsed", "Van    der   Berg", "Van der Berg"],
		["hyphen and apostrophe kept", "O'Neil-Smith", "O'Neil-Smith"],
		["symbol between spaces leaves one space", "Smith & Jones", "Smith Jones"],
	]
	for case: Array in cases:
		_check("clean/%s" % case[0], FamilyNames.clean(case[1]), case[2])

func _test_shown() -> void:
	# Each case: typed for team_a, then what name_of shows.
	var cases: Array[Array] = [
		["typed name gets Family", "Smith", "Smith Family"],
		["already ends in family", "Smith family", "Smith family"],
		["the word alone", "FAMILY", "FAMILY"],
		["family inside a word is not the word", "Smithfamily", "Smithfamily Family"],
		["typed is cleaned when stored", "  Sm1th!! ", "Smth Family"],
	]
	for case: Array in cases:
		FamilyNames.set_typed(&"team_a", case[1])
		_check("shown/%s" % case[0], FamilyNames.name_of(&"team_a"), case[2])
	var defaults: Dictionary[StringName, String] = FamilyNames.load_from(FamilyNames.PATH)
	FamilyNames.set_typed(&"team_a", "!!!")
	_check("shown/nothing left after cleaning = the default", FamilyNames.name_of(&"team_a"), defaults[&"team_a"])
	FamilyNames.set_typed(&"team_a", "Smith")
	_check("shown/other family keeps its default", FamilyNames.name_of(&"team_b"), defaults[&"team_b"])
	FamilyNames.set_typed(&"team_c", "Nobody")
	_check("shown/unknown team is not stored", FamilyNames.typed_of(&"team_c"), "")
	FamilyNames.clear_typed()
	_check("shown/cleared = the default", FamilyNames.name_of(&"team_a"), defaults[&"team_a"])
	_check("shown/shipped defaults are the colour names", [defaults[&"team_a"], defaults[&"team_b"]],
		["Green Family", "Orange Family"])

func _with_fallbacks(parsed: Dictionary[StringName, String]) -> Dictionary[StringName, String]:
	for team_id: StringName in FamilyNames.FALLBACK:
		if not parsed.has(team_id):
			parsed[team_id] = FamilyNames.FALLBACK[team_id]
	return parsed
