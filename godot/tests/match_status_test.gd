extends SceneTree
## The top bar's split (P5-2): a pure function of the two banked cash counts.
##
##   godot --headless --path godot --script res://tests/match_status_test.gd

const EXPECTED_CHECKS: int = 82

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
	_test_map_pointers()
	_test_player_labels()
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

## PT4-5: each member's minimap pointer. The map here shows world +z at the top
## (up = (0, 1)), so a body drawn facing +z (heading 0) points up the screen,
## and one facing +x (heading 90) points to screen LEFT (looking along +z, +x
## is on your left).
func _test_map_pointers() -> void:
	print("=== Minimap pointers ===")
	var up: Vector2 = Vector2(0.0, 1.0)
	# member, expected shape
	var members: Array[Array] = [
		[&"dad", &"square"], [&"mom", &"diamond"], [&"elder_girl", &"circle"],
		[&"elder_boy", &"triangle"], [&"younger_girl", &"circle"], [&"younger_boy", &"triangle"],
	]
	# heading, expected map direction
	var headings: Array[Array] = [[0.0, Vector2(0.0, -1.0)], [PI * 0.5, Vector2(-1.0, 0.0)]]
	for row: Array in members:
		for mine: bool in [false, true]:
			var label: String = "%s%s" % [row[0], " (mine)" if mine else ""]
			var got: Dictionary = TeamTellOverlay.pointer(row[0], mine, 0.0, up)
			_count(got[&"shape"] == row[1], "%s: shape %s, expected %s" % [label, got[&"shape"], row[1]])
			var radius: float = 6.5 if mine else 5.0
			_count(is_equal_approx(got[&"radius"], radius), "%s: radius %s, expected %s" % [label, got[&"radius"], radius])
			for heading: Array in headings:
				var turned: Dictionary = TeamTellOverlay.pointer(row[0], mine, heading[0], up)
				var tip: Vector2 = turned[&"tip"]
				var shown: bool = tip.length() > radius * 0.9 and tip.normalized().dot(heading[1]) > 0.99
				# The triangle points with its apex; the others with a notch.
				var how: bool = (turned[&"notch"] as PackedVector2Array).is_empty() == (row[1] == &"triangle")
				_count(shown and how, "%s at heading %s: tip %s, notch %s, expected toward %s"
					% [label, heading[0], tip, turned[&"notch"], heading[1]])

## PT5-1: how a body is named in the lineup, the lobby and the results, from the
## lobby state: "<Role> - <name>", " (you)" for the local player, "Bot" for bots.
func _test_player_labels() -> void:
	print("=== Player labels ===")
	var h: LobbyState.Occupant = LobbyState.Occupant.HUMAN
	var b: LobbyState.Occupant = LobbyState.Occupant.BOT
	var e: LobbyState.Occupant = LobbyState.Occupant.EMPTY
	# role, shown name, you?, bot?, expected
	var texts: Array[Array] = [
		["Dad", "Sam", true, false, "Dad - Sam (you)"],
		["Mom", "Alex", false, false, "Mom - Alex"],
		["Daughter", "", false, true, "Daughter - Bot"],
		["Son", "", false, false, "Son - Player"],
		["Son", "", true, false, "Son - Player (you)"],
	]
	for row: Array in texts:
		var got: String = FamilyLineup.player_text(row[0], row[1], row[2], row[3])
		_count(got == row[4], "player_text %s: expected '%s', got '%s'" % [row, row[4], got])
	# case, team_a seats [occupant, name] in slot order, my slot, own name, expected roster
	var rosters: Array[Array] = [
		["solo 3v3: you and two bots", [[h, "Sam"], [b, ""], [b, ""]], 0, "Sam",
			["Dad - Sam (you)", "Mom - Bot", "Daughter - Bot"]],
		["solo with no name typed", [[b, ""], [h, "Player"], [b, ""]], 1, "Player",
			["Dad - Bot", "Mom - Player (you)", "Daughter - Bot"]],
		["3v3 online: two named guests and a bot, seen by the second", [[h, "Sam"], [h, "Alex"], [b, ""]], 1, "Alex",
			["Dad - Sam", "Mom - Alex (you)", "Daughter - Bot"]],
		["3v3 online: a duplicate numbered by the host", [[h, "Sam"], [h, "Sam 2"], [b, ""]], 1, "Sam",
			["Dad - Sam", "Mom - Sam 2 (you)", "Daughter - Bot"]],
		["a guest before the host's copy names it", [[h, "Sam"], [h, ""], [e, ""]], 1, "Alex",
			["Dad - Sam", "Mom - Alex (you)", "Daughter - (empty)"]],
		["a rejoined guest, seen by the host", [[h, "Host"], [h, "Sam"], [b, ""], [e, ""]], 0, "Host",
			["Dad - Host (you)", "Mom - Sam", "Daughter - Bot", "Son - (empty)"]],
		["a guest away, a bot holding its seat", [[h, "Host"], [b, ""], [b, ""]], 0, "Host",
			["Dad - Host (you)", "Mom - Bot", "Daughter - Bot"]],
	]
	for row: Array in rosters:
		var view: LobbyState = LobbyState.new()
		var seats: Array = row[1]
		for slot: int in seats.size():
			view.seats.append(LobbyState.Seat.make(&"team_a", slot, seats[slot][0], false, seats[slot][1]))
			view.seats.append(LobbyState.Seat.make(&"team_b", slot, LobbyState.Occupant.BOT, false, ""))
		var got: Array[String] = FamilyLineup.roster(view, &"team_a", &"team_a", row[2], row[3])
		_count(str(got) == str(row[4]), "roster, %s: expected %s, got %s" % [row[0], row[4], got])
		var other: Array[String] = FamilyLineup.roster(view, &"team_b", &"team_a", row[2], row[3])
		_count(not " ".join(PackedStringArray(other)).contains("(you)"),
			"roster, %s: the other family has a (you): %s" % [row[0], other])

func _count(ok: bool, failure: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(failure)
