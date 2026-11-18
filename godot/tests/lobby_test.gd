extends SceneTree
## The lobby: joining, dropping, returning, and bots.
##
##   godot --headless --path godot --script res://tests/lobby_test.gd
##
## The cases that matter are the ones about PEOPLE rather than about state:
##
##   a hiccup must not cost anyone their seat
##   a returning player gets THEIR seat, not a new one
##   a seat held for someone is not filled over
##   bots are opt-in and decline rather than tilt the sides
##   the host leaving ends the match, and does so as a decision
##
## Joining is also checked for the thing that actually costs players: a code
## must survive being read aloud, and an invite must need no steps at all.

const EXPECTED_CHECKS: int = 99
const GRACE: int = 30

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Lobby ===")
	_test_codes_survive_being_read_aloud()
	_test_seating_stays_even()
	_test_a_hiccup_costs_nothing()
	_test_takeover_and_reclaim()
	_test_bots_are_opt_in()
	_test_host_loss()
	_test_lobby_state()
	_test_member_choice()

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

# ---- fixture ----

## Four seats, two a side, with actor ids standing in for a world's roster.
func _lobby(allow_bots: bool = false) -> Lobby:
	var lobby: Lobby = Lobby.create(GRACE, allow_bots)
	lobby.seats = [
		LobbySeat.make(&"team_a", 0, 1),
		LobbySeat.make(&"team_a", 1, 2),
		LobbySeat.make(&"team_b", 0, 3),
		LobbySeat.make(&"team_b", 1, 4),
	]
	return lobby

# ---- 1. getting in ----

func _test_codes_survive_being_read_aloud() -> void:
	var address: SessionHandle = SessionHandle.new(&"enet", "192.168.1.40:24545")
	var code: String = LobbyCode.encode(address)
	_check("code/an address becomes a short code", code.length() <= 14, true)
	_check("code/that decodes back", LobbyCode.decode(code).token, address.token)
	_check("code/to the same backend", LobbyCode.decode(code).backend, address.backend)

	# Read back over a call: wrong case, dashes in odd places, a stray space.
	var mangled: String = code.to_lower().replace("-", " ")
	_check("code/read back sloppily still works", LobbyCode.decode(mangled).token, address.token)

	# A Steam lobby id is a bare 64-bit number and must stay short too.
	var lobby_id: SessionHandle = SessionHandle.new(&"steam", "109775241012345678")
	var steam_code: String = LobbyCode.encode(lobby_id)
	_check("code/a steam lobby fits as well", steam_code.length() <= 20, true)
	_check("code/and round-trips", LobbyCode.decode(steam_code).token, lobby_id.token)

	# Nonsense is refused rather than decoded into a plausible session.
	_check("code/nonsense is not a session", LobbyCode.decode("NOT A CODE!!").is_valid(), false)

	# The invite path takes no steps at all: a handle IS the invite payload, so
	# there is nothing between the click and the lobby.
	var invited: SessionHandle = SessionHandle.parse(address.to_text())
	_check("code/an invite needs no code at all", invited.token, address.token)

# ---- 2. seating ----

func _test_seating_stays_even() -> void:
	var lobby: Lobby = _lobby()
	var first: LobbySeat = lobby.admit("p1", 11, "Ana", 0).seat
	var second: LobbySeat = lobby.admit("p2", 12, "Ben", 0).seat
	_check("seat/the first player sits down", first.team, &"team_a")
	_check("seat/the second goes to the other side", second.team, &"team_b")
	_check("seat/so the lobby stays even", lobby.is_balanced(), true)

	lobby.admit("p3", 13, "Cal", 0)
	lobby.admit("p4", 14, "Dee", 0)
	_check("seat/a full lobby is still even", lobby.is_balanced(), true)
	_check("seat/and holds everyone", lobby.humans_present(), 4)

	# A fifth is refused rather than squeezed in.
	_check("seat/a full lobby turns the next away",
		lobby.admit("p5", 15, "Eve", 0).kind, LobbyEvent.Kind.SEAT_FREED)

# ---- 3. a hiccup is not a departure ----

func _test_a_hiccup_costs_nothing() -> void:
	var lobby: Lobby = _lobby()
	var seat: LobbySeat = lobby.admit("p1", 11, "Ana", 0).seat

	lobby.note_absence(11, 100)
	_check("hiccup/the seat goes quiet", seat.presence, LobbySeat.Presence.HICCUP)
	_check("hiccup/but is still theirs", seat.occupancy, LobbySeat.Occupancy.HUMAN)

	# Most of the way through the grace window, still nothing has happened.
	_check("hiccup/nothing happens while the window lasts",
		lobby.advance(100 + GRACE - 1).size(), 0)

	# Back before it expires: no takeover ever happened, so nothing to undo.
	var back: LobbyEvent = lobby.admit("p1", 99, "Ana", 100 + GRACE - 1)
	_check("hiccup/returning in time is not a reclaim", back.kind, LobbyEvent.Kind.SEAT_TAKEN)
	_check("hiccup/and they have their seat", back.seat, seat)
	_check("hiccup/under their new connection", seat.peer, 99)

# ---- 4. past the window ----

func _test_takeover_and_reclaim() -> void:
	var lobby: Lobby = _lobby()
	var seat: LobbySeat = lobby.admit("p1", 11, "Ana", 0).seat
	lobby.admit("p2", 12, "Ben", 0)

	lobby.note_absence(11, 100)
	var due: Array[LobbyEvent] = lobby.advance(100 + GRACE)
	_check("takeover/grace expiring hands the seat to a bot", due.size(), 1)
	_check("takeover/which is what the caller is told", due[0].kind, LobbyEvent.Kind.TAKEOVER_DUE)
	_check("takeover/the seat is now a bot's", seat.occupancy, LobbySeat.Occupancy.BOT)
	_check("takeover/held for the player who left", seat.is_being_held(), true)
	# It is only reported ONCE. A caller told twice would take the seat over
	# twice, and the second one would be a bot replacing a bot.
	_check("takeover/and only announced once", lobby.advance(100 + GRACE * 3).size(), 0)

	# A held seat still counts as its owner's, so a bot fill will not take it.
	_check("takeover/a held seat is not free to be filled",
		lobby.human_actor_ids().has(seat.actor_id), true)

	# And they come back.
	var reclaimed: LobbyEvent = lobby.admit("p1", 77, "Ana", 500)
	_check("reclaim/returning is recognised", reclaimed.kind, LobbyEvent.Kind.RECLAIMED)
	_check("reclaim/they get their own seat back", reclaimed.seat, seat)
	_check("reclaim/the actor never changed", seat.actor_id, 1)
	_check("reclaim/and the bot lets go", seat.is_being_held(), false)
	_check("reclaim/they are playing again", seat.is_played(), true)

# ---- 5. bots ----

func _test_bots_are_opt_in() -> void:
	var off: Lobby = _lobby()
	_check("bots/off by default", off.bots_enabled, false)

	var on: Lobby = _lobby(true)
	on.admit("p1", 11, "Ana", 0)
	# Reporting a fill that placed nothing, because it could not stay even.
	var declined: Array[LobbyEvent] = on.note_fill([] as Array[int], "one team would be larger")
	_check("bots/declining is reported", declined.size(), 1)
	_check("bots/as a decline, not a silence", declined[0].kind, LobbyEvent.Kind.BOTS_DECLINED)
	_check("bots/with a reason", on.bots_declined.is_empty(), false)

	var filled: Array[LobbyEvent] = on.note_fill([2, 3, 4] as Array[int], "")
	_check("bots/a fill marks the seats", filled.size(), 3)
	_check("bots/and the lobby is even", on.is_balanced(), true)

# ---- 6. the host going ----

func _test_host_loss() -> void:
	var lobby: Lobby = _lobby()
	lobby.authority = 11
	lobby.admit("p1", 11, "Ana", 0)
	lobby.admit("p2", 12, "Ben", 0)
	_check("authority/held by whoever holds the role", lobby.holds_authority(11), true)
	_check("authority/and not by anyone else", lobby.holds_authority(12), false)

	var ended: Array[LobbyEvent] = lobby.note_absence(11, 200)
	_check("authority/the host leaving ends it", lobby.is_ended(), true)
	_check("authority/and says so", ended[0].kind, LobbyEvent.Kind.ENDED)
	# A decision, not an inability: every guest holds an identical confirmed
	# world and could continue. Migration is unbuilt, not precluded.
	_check("authority/nothing else is admitted afterwards",
		lobby.admit("p3", 13, "Cal", 201).kind, LobbyEvent.Kind.ENDED)

# ---- 7. the lobby message (PT3-3 names, PT4-3 seats and requests) ----

## Round trips, the cleaning on the way in, and bodies that must be ignored: the
## state comes off the wire from other players, so a short, long, foreign or
## future body decodes to nothing rather than to half a state.
func _test_lobby_state() -> void:
	var names: Dictionary[StringName, String] = {&"team_a": "Smith", &"team_b": "O'Neil-Müller"}
	var body: PackedByteArray = LobbyState.of_names(names).encode()
	_check("lobby state/names round trip", LobbyState.decode(body).names, names)
	_check("lobby state/framed under its own tag",
		MatchChannel.tag_of(MatchChannel.frame_lobby(LobbyState.of_names(names))), MatchChannel.TAG_LOBBY)
	_check("lobby state/through the frame", MatchChannel.lobby_state_of(MatchChannel.body_of(
		MatchChannel.frame_lobby(LobbyState.of_names(names)))).names, names)
	var empty: Dictionary[StringName, String] = {&"team_a": "", &"team_b": ""}
	var none: Dictionary[StringName, String] = {}
	_check("lobby state/empty names (defaults) round trip",
		LobbyState.decode(LobbyState.of_names(none).encode()).names, empty)
	var typed: Dictionary[StringName, String] = {&"team_a": " Sm1th!! ", &"team_b": "Abcdefghijklmnopq"}
	_check("lobby state/encode cleans", LobbyState.decode(LobbyState.of_names(typed).encode()).names,
		{&"team_a": "Smth", &"team_b": "Abcdefghijklmnop"})

	# The seats (PT4-3): a picked player, a Random player, a bot, an empty seat.
	var lobby: Lobby = _lobby()
	lobby.admit("p1", 11, "Ana", 0, 1)
	lobby.admit("p2", 12, "Ben" + char(7), 0)
	lobby.note_fill([1] as Array[int], "")
	var sent: LobbyState = LobbyState.of_lobby(lobby, names)
	sent.notice = "taken by Ana"
	var got: LobbyState = LobbyState.decode(sent.encode())
	var seats_seen: Array[String] = []
	for seat: LobbyState.Seat in got.seats:
		seats_seen.append("%s/%d/%d/%s/%s" % [seat.team, seat.slot, seat.occupant, seat.chosen, seat.name])
	_check("lobby state/seats round trip (version 2)", seats_seen, [
		"team_a/0/2/false/", "team_a/1/1/true/Ana", "team_b/0/1/false/Ben", "team_b/1/0/false/"])
	_check("lobby state/notice round trip", got.notice, "taken by Ana")
	_check("lobby state/the host's copy asks for nothing", got.wanted, LobbyState.NO_REQUEST)
	for wanted: int in [0, 3, Lobby.RANDOM]:
		_check("lobby state/request %d round trip" % wanted,
			LobbyState.decode(LobbyState.request(wanted).encode()).wanted, wanted)

	# A hand-built body with dirty names: the decoder cleans what a peer sent.
	var dirty: PackedByteArray = PackedByteArray([LobbyState.VERSION])
	for text: String in ["Sm1th 2000", "   "]:
		var raw: PackedByteArray = text.to_utf8_buffer()
		dirty.append(raw.size())
		dirty.append_array(raw)
	dirty.append_array(PackedByteArray([255, 0, 0]))
	_check("lobby state/decode cleans", LobbyState.decode(dirty).names, {&"team_a": "Smth", &"team_b": ""})

	var v: int = LobbyState.VERSION
	var bad_utf8: PackedByteArray = PackedByteArray([v, 2, 0xC3, 0x28, 0, 255, 0, 0])
	var too_long: PackedByteArray = PackedByteArray([v, LobbyState.MAX_NAME_BYTES + 1])
	too_long.resize(2 + LobbyState.MAX_NAME_BYTES + 1 + 4)
	var malformed: Array[Array] = [
		["empty body", PackedByteArray()],
		["version only", PackedByteArray([v])],
		["version 1 (names only)", PackedByteArray([1, 0, 0])],
		["wrong version", PackedByteArray([v + 1, 0, 0, 255, 0, 0])],
		["version zero", PackedByteArray([0, 0, 0])],
		["length past the end", PackedByteArray([v, 5, 65, 66])],
		["second name missing", PackedByteArray([v, 1, 65])],
		["no request byte", PackedByteArray([v, 0, 0])],
		["request out of range", PackedByteArray([v, 0, 0, 9, 0, 0])],
		["no seat count", PackedByteArray([v, 0, 0, 255, 0])],
		["too many seats", PackedByteArray([v, 0, 0, 255, 0, 9])],
		["seat cut short", PackedByteArray([v, 0, 0, 255, 0, 1, 0, 0])],
		["seat of a third team", PackedByteArray([v, 0, 0, 255, 0, 1, 2, 0, 1, 0, 0])],
		["seat occupant unknown", PackedByteArray([v, 0, 0, 255, 0, 1, 0, 0, 3, 0, 0])],
		["trailing bytes", PackedByteArray([v, 0, 0, 255, 0, 0, 7])],
		["name longer than allowed", too_long],
		["not UTF-8", bad_utf8],
	]
	for case: Array in malformed:
		_check("lobby state/ignored: %s" % case[0], LobbyState.decode(case[1]) == null, true)

# ---- 8. choosing a family member (PT4-3) ----

## `size` seats a family, actor ids 1.. in seat order (team_a first).
func _sized(size: int, allow_bots: bool = false) -> Lobby:
	var lobby: Lobby = Lobby.create(GRACE, allow_bots)
	var actor: int = 1
	for team_id: StringName in [&"team_a", &"team_b"]:
		for slot: int in size:
			lobby.seats.append(LobbySeat.make(team_id, slot, actor))
			actor += 1
	return lobby

## Where a player sits: the slot, plus "!" when they picked it; "-" when unseated.
func _where(lobby: Lobby, identity: String) -> String:
	var seat: LobbySeat = lobby.seat_of(identity)
	if seat == null:
		return "-"
	return "%d%s" % [seat.slot, "!" if seat.chosen else ""]

## Players arrive in order (p1 team_a, p2 team_b, p3 team_a, ...), each asking
## for a member or Random on arrival; then the `choose` steps run in order. The
## last step's answer and where everyone ends up are checked.
func _test_member_choice() -> void:
	var r: int = Lobby.RANDOM
	var cases: Array[Dictionary] = [
		{"name": "a picked member is refused to the next, naming the taker", "size": 2,
			"admit": [["p1", r], ["p2", r], ["p3", r]], "choose": [["p1", 1], ["p3", 1]],
			"answer": "taken by P1", "where": {"p1": "1!", "p3": "0"}},
		{"name": "a pick displaces a Random player, who swaps", "size": 2,
			"admit": [["p1", r], ["p2", r], ["p3", r]], "choose": [["p1", 1]],
			"answer": "", "where": {"p1": "1!", "p3": "0"}},
		{"name": "an empty member is simply taken", "size": 3,
			"admit": [["p1", r]], "choose": [["p1", 2]],
			"answer": "", "where": {"p1": "2!"}},
		{"name": "a member the size does not have is refused", "size": 2,
			"admit": [["p1", r]], "choose": [["p1", 2]],
			"answer": "there is no such member at this team size", "where": {"p1": "0"}},
		{"name": "asked for on arrival", "size": 4,
			"admit": [["p1", 3]], "choose": [],
			"answer": "", "where": {"p1": "3!"}},
		{"name": "asked for on arrival but taken: seated on Random", "size": 2,
			"admit": [["p1", 1], ["p2", r], ["p3", 1]], "choose": [],
			"answer": "", "where": {"p1": "1!", "p3": "0"}},
		{"name": "back to Random keeps the seat, unpicked", "size": 3,
			"admit": [["p1", 2]], "choose": [["p1", r]],
			"answer": "", "where": {"p1": "2"}},
		{"name": "two players, two picks, no clash", "size": 4,
			"admit": [["p1", r], ["p2", r], ["p3", r]], "choose": [["p1", 3], ["p3", 2]],
			"answer": "", "where": {"p1": "3!", "p3": "2!"}},
	]
	for case: Dictionary in cases:
		var lobby: Lobby = _sized(case["size"])
		for arrival: Array in case["admit"]:
			lobby.admit(arrival[0], 0, String(arrival[0]).to_upper(), 0, arrival[1])
		var answer: String = ""
		for step: Array in case["choose"]:
			answer = lobby.choose(step[0], step[1])
		_check("member/%s: answer" % case["name"], answer, case["answer"])
		var where: Dictionary = {}
		for identity: String in case["where"]:
			where[identity] = _where(lobby, identity)
		_check("member/%s: seats" % case["name"], where, case["where"])

	# Every team size offers exactly its own members.
	for size: int in [1, 2, 3, 4]:
		var expected: Array[int] = []
		for slot: int in size:
			expected.append(slot)
		_check("member/%dv%d offers its own slots" % [size, size],
			_sized(size).offered_slots(&"team_a"), expected)

	# Random never draws a member somebody picked, and is a real draw (solo no
	# longer always plays Dad).
	var clashes: int = 0
	var drawn: Dictionary[int, bool] = {}
	for seed_value: int in 24:
		var lobby: Lobby = _sized(4)
		lobby.admit("p1", 0, "P1", 0)
		lobby.admit("p2", 0, "P2", 0)
		lobby.admit("p3", 0, "P3", 0, 2)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		lobby.resolve_random(rng)
		var p1: LobbySeat = lobby.seat_of("p1")
		var p3: LobbySeat = lobby.seat_of("p3")
		if p1 == null or p3 == null or p3.slot != 2 or p1.slot == 2 or p1.team != &"team_a":
			clashes += 1
		elif p1 != null:
			drawn[p1.slot] = true
	_check("member/Random never takes a picked member (24 draws)", clashes, 0)
	_check("member/Random is a draw, not always the first member", drawn.size() > 1, true)

	# Bots take only what is left: a pick takes a filler bot's seat, and after
	# the draw only the players' seats count as human for the bot fill.
	var bots: Lobby = _sized(3, true)
	bots.admit("p1", 0, "P1", 0)
	bots.note_fill([2, 3] as Array[int], "")
	_check("member/a pick takes a filler bot's member", bots.choose("p1", 2), "")
	_check("member/that seat is the player's now",
		bots.seat_at(&"team_a", 2).occupancy, LobbySeat.Occupancy.HUMAN)
	bots.resolve_random(RandomNumberGenerator.new())
	_check("member/after the draw the bots fill the rest", bots.human_actor_ids(), [3])

	# After the start nothing moves, and a returning player has their member.
	var started: Lobby = _sized(3)
	started.admit("p1", 11, "P1", 0, 1)
	started.begin()
	_check("member/refused once the match has started", started.choose("p1", 0), "the match has started")
	started.note_absence(11, 100)
	started.advance(100 + GRACE)
	var back: LobbyEvent = started.admit("p1", 21, "P1", 500, 0)
	_check("member/a rejoin keeps the member", back.seat.slot, 1)
	_check("member/and the pick", back.seat.chosen, true)
