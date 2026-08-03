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

const EXPECTED_CHECKS: int = 42
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
