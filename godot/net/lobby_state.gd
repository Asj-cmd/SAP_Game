class_name LobbyState
extends RefCounted
## What the lobby tells everyone that is not the match: the family names the
## players typed (PT3-3) and who plays which family member (PT4-3). The body of
## a `MatchChannel.TAG_LOBBY` frame.
##
## Host to guest: the host's copy, which is the truth (sent on join, on
## reconnect and on every change), with `notice` set only on the copy sent back
## to a player whose request was refused. Guest to host: either the guest's own
## family's name as it typed it (`wanted` = NO_REQUEST; the host takes ONLY the
## entry for the sender's family), or a request to play a member (`wanted` = a
## slot or `Lobby.RANDOM`; the names are then ignored). No seats either way.
##
## Layout, version 2: one version byte; for team_a and team_b in that order one
## length byte and that many bytes of UTF-8; `wanted` as one byte (255 = no
## request, 254 = Random, else the slot); `notice` as a length byte and UTF-8;
## a seat count byte, then per seat: team index (0 = team_a, 1 = team_b), slot,
## occupant (`Occupant`), chosen (0 or 1), and the player's name as a length
## byte and UTF-8. Everything off the wire is untrusted: a body that is short,
## long, of another version, out of range or not UTF-8 decodes to null and is
## ignored, and every text that does decode is cleaned before anyone sees it.

const VERSION: int = 2
const TEAMS: Array[StringName] = [&"team_a", &"team_b"]
## Longest typed name, in characters.
const MAX_TYPED: int = 16
## A cleaned name is at most 16 characters, each at most 4 bytes of UTF-8.
const MAX_NAME_BYTES: int = 64
## A player's shown name ("Player 3", a Steam name) and a refusal notice.
const MAX_PLAYER: int = 24
const MAX_NOTICE: int = 60
## Bytes, as above: 4 bytes a character at most.
const MAX_PLAYER_BYTES: int = MAX_PLAYER * 4
const MAX_NOTICE_BYTES: int = MAX_NOTICE * 4
## 4v4 is the largest match.
const MAX_SEATS: int = 8
const MAX_SLOT: int = 7

## `wanted` when the frame asks for nothing (a name update, or the host's copy).
const NO_REQUEST: int = -2
const _WIRE_NO_REQUEST: int = 255
const _WIRE_RANDOM: int = 254

enum Occupant { EMPTY, HUMAN, BOT }

## One family member's place as the lobby shows it.
class Seat:
	extends RefCounted
	var team: StringName = &""
	var slot: int = 0
	var occupant: Occupant = Occupant.EMPTY
	## The occupant picked this member (false = they are on Random).
	var chosen: bool = false
	## Who plays it: a player's shown name; "" for a bot or nobody.
	var name: String = ""

	static func make(seat_team: StringName, seat_slot: int, who: Occupant,
			picked: bool, shown: String) -> Seat:
		var seat: Seat = Seat.new()
		seat.team = seat_team
		seat.slot = seat_slot
		seat.occupant = who
		seat.chosen = picked
		seat.name = shown
		return seat

var names: Dictionary[StringName, String] = {}
var wanted: int = NO_REQUEST
var notice: String = ""
var seats: Array[Seat] = []

static func of_names(typed: Dictionary[StringName, String]) -> LobbyState:
	var state: LobbyState = LobbyState.new()
	state.names = typed.duplicate()
	return state

## A guest asking to play member `slot` (or `Lobby.RANDOM`).
static func request(slot: int) -> LobbyState:
	var state: LobbyState = LobbyState.new()
	state.wanted = slot
	return state

## The lobby as everyone sees it: the names and every seat, from the host's copy.
static func of_lobby(lobby: Lobby, typed: Dictionary[StringName, String]) -> LobbyState:
	var state: LobbyState = of_names(typed)
	if lobby == null:
		return state
	for seat: LobbySeat in lobby.seats:
		var who: Occupant = Occupant.EMPTY
		if seat.is_persons():
			who = Occupant.HUMAN
		elif seat.occupancy == LobbySeat.Occupancy.BOT:
			who = Occupant.BOT
		state.seats.append(Seat.make(seat.team, seat.slot, who, seat.chosen and who == Occupant.HUMAN,
			seat.display_name if who == Occupant.HUMAN else ""))
	return state

## The seat of member `slot` in `team_id`, or null.
func seat_at(team_id: StringName, slot: int) -> Seat:
	for seat: Seat in seats:
		if seat.team == team_id and seat.slot == slot:
			return seat
	return null

func encode() -> PackedByteArray:
	var body: PackedByteArray = PackedByteArray([VERSION])
	for team_id: StringName in TEAMS:
		_put_text(body, clean_name(names.get(team_id, "")))
	if wanted == NO_REQUEST:
		body.append(_WIRE_NO_REQUEST)
	elif wanted == Lobby.RANDOM:
		body.append(_WIRE_RANDOM)
	else:
		body.append(clampi(wanted, 0, MAX_SLOT))
	_put_text(body, clean_text(notice, MAX_NOTICE))
	var count: int = mini(seats.size(), MAX_SEATS)
	body.append(count)
	for i: int in count:
		var seat: Seat = seats[i]
		body.append(maxi(0, TEAMS.find(seat.team)))
		body.append(clampi(seat.slot, 0, MAX_SLOT))
		body.append(int(seat.occupant))
		body.append(1 if seat.chosen else 0)
		_put_text(body, clean_text(seat.name, MAX_PLAYER))
	return body

## The state in `body`, cleaned, or null when it is not a valid version-2 one.
static func decode(body: PackedByteArray) -> LobbyState:
	if body.size() < 1 or body[0] != VERSION:
		return null
	var state: LobbyState = LobbyState.new()
	var at: Array[int] = [1]
	for team_id: StringName in TEAMS:
		var text: Variant = _take_text(body, at, MAX_NAME_BYTES)
		if text == null:
			return null
		state.names[team_id] = clean_name(String(text))
	if at[0] >= body.size():
		return null
	var raw_wanted: int = body[at[0]]
	at[0] += 1
	if raw_wanted == _WIRE_NO_REQUEST:
		state.wanted = NO_REQUEST
	elif raw_wanted == _WIRE_RANDOM:
		state.wanted = Lobby.RANDOM
	elif raw_wanted <= MAX_SLOT:
		state.wanted = raw_wanted
	else:
		return null
	var said: Variant = _take_text(body, at, MAX_NOTICE_BYTES)
	if said == null:
		return null
	state.notice = clean_text(String(said), MAX_NOTICE)
	if at[0] >= body.size():
		return null
	var count: int = body[at[0]]
	at[0] += 1
	if count > MAX_SEATS:
		return null
	for i: int in count:
		if at[0] + 4 > body.size():
			return null
		var team_index: int = body[at[0]]
		var slot: int = body[at[0] + 1]
		var who: int = body[at[0] + 2]
		var picked: int = body[at[0] + 3]
		at[0] += 4
		if team_index >= TEAMS.size() or slot > MAX_SLOT or who > Occupant.BOT or picked > 1:
			return null
		var shown: Variant = _take_text(body, at, MAX_PLAYER_BYTES)
		if shown == null:
			return null
		state.seats.append(Seat.make(TEAMS[team_index], slot, who as Occupant, picked == 1,
			clean_text(String(shown), MAX_PLAYER)))
	if at[0] != body.size():
		return null
	return state

static func _put_text(body: PackedByteArray, text: String) -> void:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	body.append(bytes.size())
	body.append_array(bytes)

## A length byte and that much UTF-8 at `at[0]`, advancing it; null when short,
## too long or not UTF-8.
static func _take_text(body: PackedByteArray, at: Array[int], limit: int) -> Variant:
	if at[0] >= body.size():
		return null
	var length: int = body[at[0]]
	at[0] += 1
	if length > limit or at[0] + length > body.size():
		return null
	var raw: PackedByteArray = body.slice(at[0], at[0] + length)
	at[0] += length
	var text: String = raw.get_string_from_utf8()
	# Bytes that are not UTF-8 come back as an empty or shorter string;
	# re-encoding tells the two apart.
	if text.to_utf8_buffer() != raw:
		return null
	return text

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

## A player's name or a notice: anything printable (digits too: "Player 3"),
## control characters removed, ends trimmed, cut to `limit` characters.
static func clean_text(text: String, limit: int) -> String:
	var kept: String = ""
	for i: int in text.length():
		var c: String = text[i]
		if c.unicode_at(0) >= 32 and c.unicode_at(0) != 127:
			kept += c
	return kept.strip_edges().left(limit).strip_edges()

## A letter is a character whose upper and lower case forms differ. Uncased
## scripts (CJK), emoji, digits and symbols are not letters here: the display
## font has no glyphs for most of them anyway.
static func _is_letter(c: String) -> bool:
	return c.to_upper() != c.to_lower()
