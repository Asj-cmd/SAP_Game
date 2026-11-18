class_name LobbyState
extends RefCounted
## What the lobby tells everyone that is not the match: the family names the
## players typed (PT3-3). The body of a `MatchChannel.TAG_LOBBY` frame.
##
## Host to guest: the host's copy, which is the truth (sent on join, on
## reconnect and on every change). Guest to host: the guest's own family's name
## as it typed it; the host takes ONLY the entry for the sender's family.
##
## Layout: one version byte (1), then for team_a and team_b in that order one
## length byte and that many bytes of UTF-8. PT4-3 appends the seat list as
## version 2. Everything off the wire is untrusted: a body that is short, long,
## of another version or not UTF-8 decodes to {} and is ignored, and each name
## that does decode is cleaned (`clean_name`) before anyone sees it.

const VERSION: int = 1
const TEAMS: Array[StringName] = [&"team_a", &"team_b"]
## Longest typed name, in characters.
const MAX_TYPED: int = 16
## A cleaned name is at most 16 characters, each at most 4 bytes of UTF-8.
const MAX_NAME_BYTES: int = 64

## The body for `names` (team id -> typed text; a missing team is sent empty).
static func encode(names: Dictionary[StringName, String]) -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray([VERSION])
	for team_id: StringName in TEAMS:
		var bytes: PackedByteArray = clean_name(names.get(team_id, "")).to_utf8_buffer()
		body.append(bytes.size())
		body.append_array(bytes)
	return body

## Both names, cleaned, or {} when the body is not a version-1 lobby state.
static func decode(body: PackedByteArray) -> Dictionary[StringName, String]:
	var names: Dictionary[StringName, String] = {}
	if body.size() < 1 or body[0] != VERSION:
		return names
	var at: int = 1
	for team_id: StringName in TEAMS:
		if at >= body.size():
			return {} as Dictionary[StringName, String]
		var length: int = body[at]
		at += 1
		if length > MAX_NAME_BYTES or at + length > body.size():
			return {} as Dictionary[StringName, String]
		var raw: PackedByteArray = body.slice(at, at + length)
		at += length
		var text: String = raw.get_string_from_utf8()
		# Bytes that are not UTF-8 come back as an empty or shorter string;
		# re-encoding tells the two apart.
		if text.to_utf8_buffer() != raw:
			return {} as Dictionary[StringName, String]
		names[team_id] = clean_name(text)
	if at != body.size():
		return {} as Dictionary[StringName, String]
	return names

## The one rule for a typed family name (`FamilyNames.clean` is this), applied
## where text is typed AND where it arrives off the wire: letters (any alphabet
## with upper and lower case, accents kept), spaces, hyphens and apostrophes;
## anything else is removed, runs of spaces become one, the ends are trimmed,
## and it is cut to MAX_TYPED characters (trimmed again after the cut).
## Lives here, not in game/, because the network layer must not reach upward.
static func clean_name(text: String) -> String:
	var kept: String = ""
	for i: int in text.length():
		var c: String = text[i]
		if c == " " or c == "-" or c == "'" or _is_letter(c):
			if c == " " and (kept == "" or kept.ends_with(" ")):
				continue
			kept += c
	return kept.strip_edges().left(MAX_TYPED).strip_edges()

## A letter is a character whose upper and lower case forms differ. Uncased
## scripts (CJK), emoji, digits and symbols are not letters here: the display
## font has no glyphs for most of them anyway.
static func _is_letter(c: String) -> bool:
	return c.to_upper() != c.to_lower()
