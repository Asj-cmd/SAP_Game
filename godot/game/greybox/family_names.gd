class_name FamilyNames
extends RefCounted
## The two families' display names: what the players typed (PT3-3), or the
## defaults from one plain text file when a box was left empty.
##
## Typed names: the lobby has a name box per family (and the main menu two for
## a solo game). Every machine keeps the typed text here; on a networked game the
## host's copy is the truth and travels in the lobby message (`LobbyState`,
## `MatchChannel.TAG_LOBBY`). Presentation only: never in the sim, a snapshot,
## the input stream or the world hash. Not saved: empty at every launch.
##
## Defaults: `content/family_names.cfg`, two lines, `team_a_name=` and
## `team_b_name=`, plain text after the `=` (HOW_TO_PLAY.md). Internal ids stay
## `team_a` / `team_b`. Hand-parsed rather than through ConfigFile, which wants a
## [section] and quoted strings; the user was told no quotes are needed.

const PATH: String = "res://content/family_names.cfg"
## The defaults when the file is missing or a line is empty: named after the
## family colours (the first family is the green one, the second the rust orange).
const FALLBACK: Dictionary[StringName, String] = {
	&"team_a": "Green Family",
	&"team_b": "Orange Family",
}
## Longest typed name, in characters, before " Family" is added.
const MAX_TYPED: int = LobbyState.MAX_TYPED
## Added to a typed name that does not already end in the word.
const SUFFIX: String = "Family"
const _KEYS: Dictionary[String, StringName] = {
	"team_a_name": &"team_a",
	"team_b_name": &"team_b",
}

static var _cache: Dictionary[StringName, String] = {}
static var _loaded: bool = false
static var _typed: Dictionary[StringName, String] = {}
## Goes up on every change of a typed name, so a panel can tell it must redraw.
static var revision: int = 0

## The name players see for a team id: the typed name as "<Name> Family", or the
## default when nothing was typed. Reads the defaults file on the first call only.
static func name_of(team_id: StringName) -> String:
	var typed: String = _typed.get(team_id, "")
	if typed != "":
		return display(typed)
	return default_of(team_id)

## The default for a team id, from the file (or FALLBACK).
static func default_of(team_id: StringName) -> String:
	if not _loaded:
		_cache = load_from(PATH)
		_loaded = true
	return _cache.get(team_id, "Family")

## A cleaned typed name as shown: "Smith" -> "Smith Family"; "Smith family"
## and "Family" stay as they are (the word is not doubled).
static func display(typed: String) -> String:
	var words: PackedStringArray = typed.split(" ", false)
	if words.size() > 0 and words[words.size() - 1].to_lower() == SUFFIX.to_lower():
		return typed
	return "%s %s" % [typed, SUFFIX]

## What a name box may hold, enforced where text is typed AND where it arrives
## off the wire: letters (accents kept), spaces, hyphens and apostrophes, at most
## MAX_TYPED characters. The rule itself is `LobbyState.clean_name`, in net/,
## because the wire decoder applies it too and net/ may not reach into game/.
static func clean(text: String) -> String:
	return LobbyState.clean_name(text)

## Sets the typed name of a family on this machine (cleaned). "" = the default.
static func set_typed(team_id: StringName, text: String) -> void:
	if not FALLBACK.has(team_id):
		return
	var cleaned: String = clean(text)
	if _typed.get(team_id, "") == cleaned:
		return
	_typed[team_id] = cleaned
	revision += 1

## The typed (cleaned) name of a family, "" when none.
static func typed_of(team_id: StringName) -> String:
	return _typed.get(team_id, "")

## Both typed names, keyed by team id (empty strings for none).
static func typed_all() -> Dictionary[StringName, String]:
	var all: Dictionary[StringName, String] = {}
	for team_id: StringName in FALLBACK:
		all[team_id] = typed_of(team_id)
	return all

## Forgets both typed names (a new match setup).
static func clear_typed() -> void:
	if _typed.is_empty():
		return
	_typed.clear()
	revision += 1

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

## The names in the file at `path`, with FALLBACK for any that are missing or
## empty (both when the file itself is missing).
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
