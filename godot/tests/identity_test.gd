extends SceneTree
## Who a player is, across connections.
##
##   godot --headless --path godot --script res://tests/identity_test.gd
##
## The bug this exists to prevent is quiet rather than loud. Keyed on a peer id,
## a player who drops for longer than the grace window comes back as a stranger:
## they get a fresh seat, a bot keeps their old one, and from the inside it just
## looks like the game forgot them. Nothing errors, nothing logs, and it happens
## most often to whoever has the worst connection.

const EXPECTED_CHECKS: int = 15

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== Player identity ===")
	_test_token_is_stable()
	_test_shapes()
	_test_wire()
	_test_seats_follow_the_token()

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

# ---- the token itself ----

func _test_token_is_stable() -> void:
	var first: String = PlayerIdentity.local()
	_check("token/is minted", first.is_empty(), false)
	# The entire job: the same value next time. A token that changed per launch
	# would be no better than a peer id.
	_check("token/is the same on the next call", PlayerIdentity.local(), first)
	_check("token/was written down", FileAccess.file_exists(PlayerIdentity.PATH), true)

	# Two freshly minted tokens must differ, or two playtesters collide and each
	# keeps taking the other's seat.
	_check("token/a fresh one differs", PlayerIdentity.mint() != PlayerIdentity.mint(), true)

# ---- what we will accept off the wire ----

func _test_shapes() -> void:
	_check("shape/nothing is not an identity", PlayerIdentity.is_acceptable(""), false)
	_check("shape/nor is something absurdly long",
		PlayerIdentity.is_acceptable("x".repeat(PlayerIdentity.MAX_LENGTH + 1)), false)
	_check("shape/a real token is fine", PlayerIdentity.is_acceptable(PlayerIdentity.mint()), true)
	# A Steam id is a bare number and much shorter. The check has to admit what
	# replaces this, or the backend swap breaks on its first connection.
	_check("shape/and so is a steam id", PlayerIdentity.is_acceptable("76561197960287930"), true)

# ---- across the wire ----

func _test_wire() -> void:
	var token: String = PlayerIdentity.mint()
	var framed: PackedByteArray = MatchChannel.frame_hello(token)
	_check("wire/a hello is tagged as one", MatchChannel.tag_of(framed), MatchChannel.TAG_HELLO)
	_check("wire/and the token survives",
		MatchChannel.token_of(MatchChannel.body_of(framed)), token)

	# Untrusted, like everything else arriving.
	_check("wire/an empty body is not an identity",
		MatchChannel.token_of(PackedByteArray()), "")
	var oversized: PackedByteArray = ("x".repeat(PlayerIdentity.MAX_LENGTH + 10)).to_utf8_buffer()
	_check("wire/nor is an oversized one", MatchChannel.token_of(oversized), "")

# ---- and what it is all for ----

## The case that was broken: a returning player must get THEIR seat.
func _test_seats_follow_the_token() -> void:
	var lobby: Lobby = Lobby.create(30, false)
	lobby.seats = [
		LobbySeat.make(&"team_a", 0, 1),
		LobbySeat.make(&"team_b", 0, 2),
	]

	var token: String = PlayerIdentity.mint()
	var seat: LobbySeat = lobby.admit(token, 11, "Ana", 0).seat

	# Dropped, and gone long enough that a bot took over.
	lobby.note_absence(11, 100)
	lobby.advance(200)

	# Back on a DIFFERENT connection - which is what a reconnect always is - but
	# the same token. Keyed on the peer id this would be a new player, and the
	# only free seat is on the other team.
	var back: LobbyEvent = lobby.admit(token, 99, "Ana", 300)
	_check("seat/a reconnect is recognised", back.kind, LobbyEvent.Kind.RECLAIMED)
	_check("seat/and gets the same body", back.seat.actor_id, seat.actor_id)

	# A genuinely different player is still a different player.
	var other: LobbyEvent = lobby.admit(PlayerIdentity.mint(), 12, "Ben", 301)
	_check("seat/a different token is somebody else",
		other.seat.actor_id != seat.actor_id, true)
