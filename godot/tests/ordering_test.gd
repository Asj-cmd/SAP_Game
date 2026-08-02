extends SceneTree
## Deterministic ordering, and the rule that keeps it that way.
##
##   godot --headless --path godot --script res://tests/ordering_test.gd
##
## `Array[StringName].sort()` compares interning identity rather than
## characters. It has now been found twice - once in zone resolution by someone
## who knew, once in team order by chasing a desync - so the assumption here is
## that luck found two and there may be more. NameOrder is the single place
## names get ordered, and the scan below fails if anything sorts them raw again.
##
## EVERY ordering fixture uses three or more elements. Two names sort correctly
## by coincidence roughly half the time, which is exactly why the team bug
## survived a suite full of two-team worlds.

const EXPECTED_CHECKS: int = 6

## Interned in an order that is neither alphabetical nor reverse-alphabetical,
## so a sort that compares interning identity cannot accidentally agree.
const NAMES: Array[StringName] = [&"zulu_house", &"alpha_house", &"mid_house"]
const IN_ORDER: Array[StringName] = [&"alpha_house", &"mid_house", &"zulu_house"]

## Where a raw name sort would actually hurt: the rules, the content they read,
## and the tool that writes that content.
const SCANNED: Array[String] = ["res://sim", "res://content", "res://game/blockout"]

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Deterministic ordering ===")
	_test_team_ordering()
	_test_zone_resolution_ordering()
	_test_no_raw_name_sorts()

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

# ---- teams ----

## Team order decides the sequence populate_roster creates bodies in, and so
## which entity id each actor gets. Two machines ordering teams differently hand
## the same player different ids and disagree about everything afterwards.
func _test_team_ordering() -> void:
	var teams: Array[TeamDef] = []
	for id: StringName in NAMES:
		var team: TeamDef = TeamDef.new()
		team.id = id
		team.spawn_points = [Vector3.ZERO] as Array[Vector3]
		teams.append(team)

	var mode: GameModeDef = GameModeDef.new()
	mode.team_size = 1
	var world: SimWorld = SimWorld.new(1)
	var zones: Array[ZoneDef] = []
	world.configure(mode, TuningDef.new(), zones, teams, null)

	_check("teams/sorted by name, not by interning", world.sorted_team_ids(), IN_ORDER)

	# The consequence that actually bites.
	world.populate_roster()
	_check("teams/and the roster is built in that order",
		world.get_entity(world.actor_ids()[0]).team, IN_ORDER[0])

# ---- zones ----

## Which room wins where bounds overlap. Priority decides it first; the name is
## the tie-break, and a tie-break that varies by machine is not a tie-break.
func _test_zone_resolution_ordering() -> void:
	var zones: Array[ZoneDef] = []
	for id: StringName in NAMES:
		var zone: ZoneDef = ZoneDef.new()
		zone.id = id
		zone.bounds = AABB(Vector3(zones.size() * 100, 0, 0), Vector3(100, 100, 100))
		zones.append(zone)

	var world: SimWorld = SimWorld.new(1)
	var teams: Array[TeamDef] = []
	world.configure(GameModeDef.new(), TuningDef.new(), zones, teams, null)
	_check("zones/equal priority breaks the tie by name",
		world.zone_ids_in_resolution_order(), IN_ORDER)

	# Priority still outranks the name, or the tie-break has quietly become the
	# rule and authored overlaps stop meaning anything.
	zones[0].priority = 5 # zulu_house, last alphabetically
	var ranked: SimWorld = SimWorld.new(1)
	ranked.configure(GameModeDef.new(), TuningDef.new(), zones, teams, null)
	_check("zones/but priority still wins", ranked.zone_ids_in_resolution_order()[0], NAMES[0])

# ---- the rule ----

func _test_no_raw_name_sorts() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	for directory: String in SCANNED:
		for path: String in _scripts_under(directory):
			offenders.append_array(
				_raw_sorts_in(FileAccess.get_file_as_string(path), path)
			)
	_check("scan/nothing sorts StringNames raw", offenders, PackedStringArray())

	# Teeth. A scanner that cannot see the bug it is looking for reports a clean
	# codebase forever, which is worse than not having one.
	var planted: String = "var ids: Array[StringName] = teams.keys()\n\tids.sort()\n"
	_check("scan/and the scanner can see one", _raw_sorts_in(planted, "planted").size(), 1)

## Flags `.sort()` called on anything declared as a StringName collection.
##
## Deliberately textual. A type-aware check would be better and there is no way
## to write one here; this catches the shape the bug actually took twice, which
## is a name array or a dictionary's keys sorted in place.
func _raw_sorts_in(text: String, label: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var declaration: RegEx = RegEx.create_from_string("(\\w+)\\s*:\\s*Array\\[StringName\\]")
	var plain_sort: RegEx = RegEx.create_from_string("(\\w+)\\.sort\\(\\)")
	var names: Dictionary[String, bool] = {}
	var line_number: int = 0

	for line: String in text.split("\n"):
		line_number += 1
		for hit: RegExMatch in declaration.search_all(line):
			names[hit.get_string(1)] = true
		# A dictionary's keys sorted where they stand, never having been given a
		# name to declare a type on.
		if line.contains(".keys().sort()"):
			found.append("%s:%d %s" % [label, line_number, line.strip_edges()])
			continue
		var sorted: RegExMatch = plain_sort.search(line)
		if sorted != null and names.has(sorted.get_string(1)):
			found.append("%s:%d %s" % [label, line_number, line.strip_edges()])
	return found

func _scripts_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for entry: String in DirAccess.get_files_at(directory):
		if entry.ends_with(".gd"):
			found.append("%s/%s" % [directory, entry])
	for entry: String in DirAccess.get_directories_at(directory):
		found.append_array(_scripts_under("%s/%s" % [directory, entry]))
	return found
