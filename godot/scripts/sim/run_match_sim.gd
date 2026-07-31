extends SceneTree
## Headless deliverable: simulates a full best-of-3 between four bots (2v2)
## using the ported MatchState/WorldGeometry autoloads and prints the result.
## No scenes required. Run with:
##   godot --headless --path godot --script res://scripts/sim/run_match_sim.gd
## Optional: -- --seed 12345   (reproducible run; omitted = random each time)
##
## Fetches MatchState via get_node("/root/MatchState") rather than the bare
## global identifier: a --script entry point is compiled BEFORE the engine
## sets up the SceneTree's autoloads (autoloads compile each other's bare
## identifiers fine, in project.godot order - but this file compiles even
## earlier, as the MainLoop candidate itself), so the static name isn't
## resolvable here yet.

const TEAM_SIZE := 2
const BUNDLES_PER_BEDROOM := TEAM_SIZE + 1 # matches the client's default (3 for 2v2)

# Drives MatchState's two independent real-time intervals (tick @ 1Hz,
# bot_tick @ 4Hz) on a virtual clock instead of actual wall-clock time.
const TICK_MS := 1000.0
const BOT_TICK_MS := 250.0
# Safety valve: a round always resolves within ROUND_TIME (300s) either by
# score or timeout, so a best-of-3 is bounded - this is just a generous
# backstop against an infinite loop if that invariant ever breaks.
const MAX_SIM_MS := 50.0 * 310.0 * 1000.0

var ms # MatchState autoload, fetched dynamically - see note above

func _initialize() -> void:
	ms = get_root().get_node("MatchState")

	var seed_value := _get_seed_from_args()
	if seed_value != -1:
		seed(seed_value)
		print("[seed: %d]" % seed_value)
	else:
		randomize()

	ms.setup_match(TEAM_SIZE, BUNDLES_PER_BEDROOM)
	ms.add_bot("B")
	ms.add_bot("B")
	ms.add_bot("A")
	ms.add_bot("A")
	ms.start_countdown()

	print("=== Cash Grab - headless bot-only best-of-3 ===")
	print("2v2, %d bundles/bedroom, win a round by holding %d bundles, first to 2 round wins takes the match.\n" % [BUNDLES_PER_BEDROOM, ms.win_score])

	_run_match()
	quit()

func _run_match() -> void:
	var elapsed_ms := 0.0
	var tick_accum := 0.0
	var last_status_at := 0.0
	var seen_round_number: int = ms.round_number

	while ms.phase != "matchEnd" and elapsed_ms < MAX_SIM_MS:
		ms.bot_tick(BOT_TICK_MS / 1000.0)
		ms.now_ms += BOT_TICK_MS
		elapsed_ms += BOT_TICK_MS
		tick_accum += BOT_TICK_MS

		if tick_accum >= TICK_MS:
			tick_accum -= TICK_MS
			var prev_phase: String = ms.phase
			ms.tick()

			if prev_phase == "playing" and ms.phase == "roundEnd":
				_print_round_result()
			if ms.phase == "playing" and ms.round_number != seen_round_number:
				seen_round_number = ms.round_number
				print("--- Round %d starts (match: A %d - %d B) ---" % [ms.round_number, ms.wins_a, ms.wins_b])

			if ms.phase == "playing" and elapsed_ms - last_status_at >= 60000.0:
				last_status_at = elapsed_ms
				print("    [t=%ds] score A:%d B:%d" % [int(_round_elapsed_seconds()), ms.score_a, ms.score_b])

	if ms.phase != "matchEnd":
		print("\n!! Simulation safety cap hit before a match winner was decided - aborting.")
		return

	print("\n=== MATCH OVER: Team %s wins the match %d-%d ===" % [
		ms.match_winner,
		maxi(ms.wins_a, ms.wins_b),
		mini(ms.wins_a, ms.wins_b),
	])

func _round_elapsed_seconds() -> float:
	return ms.ROUND_TIME - ms.round_timer

func _print_round_result() -> void:
	if ms.round_winner == "":
		print("Round %d: TIE at full time (A:%d B:%d) - replaying round %d" % [
			ms.round_number, ms.score_a, ms.score_b, ms.round_number,
		])
	else:
		print("Round %d: Team %s wins (final score A:%d B:%d) -> match now A %d - %d B" % [
			ms.round_number, ms.round_winner, ms.score_a, ms.score_b,
			ms.wins_a, ms.wins_b,
		])

func _get_seed_from_args() -> int:
	var cmd_args := OS.get_cmdline_user_args()
	for i in range(cmd_args.size()):
		if cmd_args[i] == "--seed" and i + 1 < cmd_args.size():
			return cmd_args[i + 1].to_int()
	return -1
