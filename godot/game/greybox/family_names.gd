class_name FamilyNames
extends RefCounted
## The two families' display names, read once from one plain text file.
##
## The user edits `content/family_names.cfg` by hand (HOW_TO_PLAY.md): two lines,
## `team_a_name=` and `team_b_name=`, plain text after the `=`. Presentation
## only: nothing in the sim, a snapshot or a network message reads it, so each
## machine shows what its own file says. Internal ids stay `team_a` / `team_b`.
##
## Hand-parsed rather than through ConfigFile, which wants a [section] and
## quoted strings; the user was told no quotes are needed.

const PATH: String = "res://content/family_names.cfg"
const FALLBACK: Dictionary[StringName, String] = {
	&"team_a": "Family A",
	&"team_b": "Family B",
}
const _KEYS: Dictionary[String, StringName] = {
	"team_a_name": &"team_a",
	"team_b_name": &"team_b",
}

static var _cache: Dictionary[StringName, String] = {}
static var _loaded: bool = false

## The name players see for a team id. Reads the file on the first call only.
static func name_of(team_id: StringName) -> String:
	if not _loaded:
		_cache = load_from(PATH)
		_loaded = true
	return _cache.get(team_id, "Family")

## The names in `text`, without fallbacks: an empty or missing value is left out.
static func parse(text: String) -> Dictionary[StringName, String]:
	var found: Dictionary[StringName, String] = {}
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var at: int = line.find("=")
		if at < 0:
			continue
		var key: String = line.substr(0, at).strip_edges()
		if not _KEYS.has(key):
			continue
		var value: String = _unquote(line.substr(at + 1).strip_edges()).strip_edges()
		if value != "":
			found[_KEYS[key]] = value
	return found

## The names in the file at `path`, with "Family A" / "Family B" for any that
## are missing or empty (both when the file itself is missing).
static func load_from(path: String) -> Dictionary[StringName, String]:
	var names: Dictionary[StringName, String] = {}
	if FileAccess.file_exists(path):
		names = parse(FileAccess.get_file_as_string(path))
	for team_id: StringName in FALLBACK:
		if not names.has(team_id):
			names[team_id] = FALLBACK[team_id]
	return names

## One pair of matching quotes round the whole value, if there is one.
static func _unquote(value: String) -> String:
	if value.length() >= 2:
		var first: String = value[0]
		if (first == "\"" or first == "'") and value.ends_with(first):
			return value.substr(1, value.length() - 2)
	return value
