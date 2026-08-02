extends SceneTree
## Rule regressions for CommandCodec. See godot/CLAUDE.md.
##
##   godot --headless --path godot --script res://tests/command_codec_test.gd
##
## A codec is not obviously "logic containing a decision", but this one decides
## two things that matter more than most rules: whether what arrives is exactly
## what was sent, and whether a malformed packet is refused. Clients predict by
## running the same step() on the same commands, so one rounded bit is a desync,
## and a desync is the hardest class of bug this project can produce.
##
## Fidelity is asserted on BIT PATTERNS, never approximately. An approximate
## comparison passes for exactly the drift it is supposed to catch.

const EXPECTED_CHECKS: int = 19

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	print("=== CommandCodec ===")
	_test_round_trip()
	_test_intent_is_exact()
	_test_malformed_input()

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

# ---- every kind survives the trip ----

## The digest string is the comparison, because it is the same canonical form
## the desync detector uses - if two commands digest alike they are alike in
## every way the simulation can observe.
func _test_round_trip() -> void:
	var sent: Array[SimCommand] = [
		MoveCommand.move(7, Vector3(0.30000001192092896, 0.0, -0.949999988079071), 41),
		MoveCommand.stop(7, 42),
		CarryCommand.pick_up(7, 19, 43),
		CarryCommand.drop(7, 44),
		CaptureCommand.capture(7, 12, 45),
		CaptureCommand.release(7, 12, 46),
		MatchCommand.start(47),
		MatchCommand.rematch(48),
	]

	for command: SimCommand in sent:
		var returned: SimCommand = CommandCodec.decode(CommandCodec.encode(command))
		if returned == null:
			_check("wire/%s survives" % command.kind, "decoded to null", command.to_digest_string())
			continue
		_check("wire/%s survives" % command.kind,
			returned.to_digest_string(), command.to_digest_string())

	# A whole tick at once, in order. Order is not incidental: commands are
	# applied in the order they arrive, so a batch that reorders them is a batch
	# that changes the match.
	var batch: Array[SimCommand] = CommandCodec.decode_batch(CommandCodec.encode_batch(sent))
	_check("wire/a batch keeps every command", batch.size(), sent.size())
	var ordered: bool = true
	for i: int in mini(batch.size(), sent.size()):
		if batch[i].to_digest_string() != sent[i].to_digest_string():
			ordered = false
	_check("wire/and keeps them in order", ordered, true)

# ---- exactness ----

## Direction survives to the bit, not to a tolerance.
##
## The values below are chosen to have awkward binary expansions. A codec that
## widened to double and back, or that normalised on the way through, passes an
## is_equal_approx check and desyncs a match twenty seconds later.
func _test_intent_is_exact() -> void:
	var awkward: Array[Vector3] = [
		Vector3(0.1, 0.2, 0.3),
		Vector3(-0.7071067811865476, 0.0, 0.7071067811865476),
		Vector3(1e-8, -1e-8, 0.9999999),
	]
	for intent: Vector3 in awkward:
		var sent: MoveCommand = MoveCommand.move(3, intent, 9)
		var got: MoveCommand = CommandCodec.decode(CommandCodec.encode(sent)) as MoveCommand
		var same: bool = (
			SimEntity.float_bits(got.intent.x) == SimEntity.float_bits(sent.intent.x)
			and SimEntity.float_bits(got.intent.y) == SimEntity.float_bits(sent.intent.y)
			and SimEntity.float_bits(got.intent.z) == SimEntity.float_bits(sent.intent.z)
		)
		_check("exact/%v arrives bit-identical" % intent, same, true)

# ---- nothing off the wire is trusted ----

## Everything arriving here was written by somebody else. A decoder that
## fabricates a command on malformed input hands the rules something nobody
## sent; one that crashes hands an attacker the server.
func _test_malformed_input() -> void:
	_check("hostile/empty input decodes to nothing", CommandCodec.decode(PackedByteArray()), null)
	_check("hostile/an unknown wire code is refused",
		CommandCodec.decode(PackedByteArray([200, 0, 0, 0, 0, 0, 0, 0, 0])), null)

	# A Move header with its direction missing. The header alone is plausible,
	# which is what makes truncation the interesting case rather than noise.
	var truncated: PackedByteArray = CommandCodec.encode(MoveCommand.move(1, Vector3.ONE, 2))
	truncated.resize(9)
	_check("hostile/a truncated payload is refused", CommandCodec.decode(truncated), null)

	# A batch whose length field is a lie.
	var lying: StreamPeerBuffer = StreamPeerBuffer.new()
	lying.big_endian = false
	lying.put_32(999999)
	_check("hostile/an impossible batch size is refused",
		CommandCodec.decode_batch(lying.data_array).size(), 0)

	# A batch that promises three commands and delivers one: keep what was
	# genuinely there, discard the promise.
	var short_batch: PackedByteArray = CommandCodec.encode_batch(
		[MoveCommand.stop(1, 1)] as Array[SimCommand]
	)
	short_batch.encode_s32(0, 3)
	_check("hostile/a batch that ends early keeps what arrived",
		CommandCodec.decode_batch(short_batch).size(), 1)

	# And the whole point of refusing: nothing above may produce a command the
	# rules would act on.
	_check("hostile/garbage never becomes a command",
		CommandCodec.decode_batch(PackedByteArray([1, 2, 3])).size(), 0)
