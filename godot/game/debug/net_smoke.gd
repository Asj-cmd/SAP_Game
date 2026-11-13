class_name NetSmoke
extends Node
## Two real game processes, one host and one guest, checked against each other.
##
##   godot --headless --path godot -- --host --net-smoke=<dir> [--net-smoke-ticks=N]
##   godot --headless --path godot -- --join --net-smoke=<dir> [--net-smoke-ticks=N]
##
## `autobuild/net_smoke.mjs` starts the pair and compares what they wrote.
##
## The net tools (tools/net_loopback.gd, net_lobby.gd) put both ends in ONE
## process. This runs the whole game scene twice - menu skipped, lobby, ENet on
## localhost, bots filling the empty seats - and is the only check that two
## separate copies of the game agree. Each end records the hash of the world it
## treats as true (the host's authoritative world, the guest's confirmed one) on
## every tick it sees, and writes them to `<dir>/<role>.txt`. Every tick both
## saw must hash the same.
##
## The guest walks (injected WASD, a different key every 2 s) so its input has
## to cross the wire; the host reports how far that body moved in ITS world.
##
## Debug only, not part of a player's game. It reads the session and presses
## keys; it never writes to the simulation.

const TICKS_DEFAULT: int = 1800
## Ticks between the guest's key changes.
const WALK_TURN_TICKS: int = 60
const WALK_KEYS: Array[Key] = [KEY_W, KEY_D, KEY_S, KEY_A]
## Wall-clock limits, so a broken session ends the process instead of hanging it.
const SEAT_DEADLINE_MS: int = 20000
const RUN_DEADLINE_MS: int = 600000
## The host keeps running this many ticks past the guest's last one, so every
## tick the guest confirms has a host hash to be compared with.
const HOST_EXTRA_TICKS: int = 150

var _game: GreyBoxMain = null
var _out_dir: String = ""
var _ticks: int = TICKS_DEFAULT
var _role: String = ""
var _hashes: Dictionary[int, int] = {}
var _last_tick: int = -1
var _started_ms: int = 0
var _seated_ms: int = -1
var _joined_tick: int = -1
var _held_key: Key = KEY_NONE
## Host only: the guest's body, where the host first saw it, and how far it got.
var _guest_actor: int = SimEntity.NO_ENTITY
var _guest_start: Vector3 = Vector3.ZERO
var _guest_moved: float = 0.0
var _peak_humans: int = 0
var _peak_bots: int = 0
var _done: bool = false
## `--net-smoke-digests`: every tick's full digest too, to find WHAT differs.
var _digests: FileAccess = null

func _init(game: GreyBoxMain) -> void:
	_game = game
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--net-smoke="):
			_out_dir = arg.trim_prefix("--net-smoke=")
		elif arg.begins_with("--net-smoke-ticks="):
			_ticks = maxi(150, int(arg.trim_prefix("--net-smoke-ticks=")))
		elif arg.begins_with("--net-smoke-speed="):
			# Both ends run their clocks this much faster (a whole match in less
			# wall time). Ticks are still ticks; only the wait between them shrinks.
			Engine.time_scale = clampf(float(arg.trim_prefix("--net-smoke-speed=")), 1.0, 8.0)

static func requested(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg.begins_with("--net-smoke="):
			return true
	return false

func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(_out_dir)

func _process(_delta: float) -> void:
	if _done:
		return
	var link: MatchLink = _game.link
	if link == null:
		return
	if _role == "":
		_role = "host" if link.role == MatchLink.Role.HOST else "guest"
		if OS.get_cmdline_user_args().has("--net-smoke-digests"):
			_digests = FileAccess.open(_out_dir.path_join("%s_digest.txt" % _role), FileAccess.WRITE)
		if link.role == MatchLink.Role.HOST:
			# The guest waits for this line before it starts.
			print("NETSMOKE host listening code=%s" % link.session_code())
	if link.failure != "":
		_finish(false, "session failed: %s" % link.failure)
		return
	if not link.is_ready():
		if Time.get_ticks_msec() - _started_ms > SEAT_DEADLINE_MS:
			_finish(false, "no seat after %d ms" % SEAT_DEADLINE_MS)
		return
	if Time.get_ticks_msec() - _started_ms > RUN_DEADLINE_MS:
		_finish(false, "ran out of wall-clock time at tick %d" % _last_tick)
		return

	var truth: SimWorld = link.outcome_world()
	# A match that ends before the tick budget ends the run there.
	if truth.match_phase == SimWorld.MatchPhase.MATCH_END:
		_ticks = mini(_ticks, truth.tick)
	if truth.tick != _last_tick:
		_last_tick = truth.tick
		var digest: String = truth.state_digest()
		_hashes[truth.tick] = SimWorld.hash_string(digest)
		if _digests != null:
			_digests.store_line("%d %s" % [truth.tick, digest])
	if link.role == MatchLink.Role.HOST:
		_watch_host(link, truth)
	else:
		_walk_guest(link, truth)

func _watch_host(link: MatchLink, truth: SimWorld) -> void:
	var humans: Array[int] = link.lobby.human_actor_ids()
	_peak_humans = maxi(_peak_humans, humans.size())
	_peak_bots = maxi(_peak_bots, link.crew.count())
	if _guest_actor == SimEntity.NO_ENTITY:
		for actor_id: int in humans:
			if actor_id != link.actor_id:
				_guest_actor = actor_id
				_joined_tick = truth.tick
				_guest_start = truth.get_entity(actor_id).position
				print("NETSMOKE host guest seated actor=%d tick=%d" % [actor_id, truth.tick])
	elif truth.get_entity(_guest_actor) != null:
		var at: Vector3 = truth.get_entity(_guest_actor).position
		_guest_moved = maxf(_guest_moved, Vector2(at.x - _guest_start.x, at.z - _guest_start.z).length())
	if truth.tick >= _ticks + HOST_EXTRA_TICKS:
		_finish(_guest_actor != SimEntity.NO_ENTITY, "")

func _walk_guest(link: MatchLink, truth: SimWorld) -> void:
	if _seated_ms < 0:
		_seated_ms = Time.get_ticks_msec() - _started_ms
		_joined_tick = truth.tick
		print("NETSMOKE guest seated actor=%d tick=%d after %d ms" % [link.actor_id, truth.tick, _seated_ms])
	var want: Key = WALK_KEYS[(truth.tick / WALK_TURN_TICKS) % WALK_KEYS.size()]
	if want != _held_key:
		_key(_held_key, false)
		_key(want, true)
		_held_key = want
	if truth.tick >= _ticks:
		_key(_held_key, false)
		_finish(true, "")

func _finish(ok: bool, problem: String) -> void:
	_done = true
	var lines: PackedStringArray = PackedStringArray()
	for tick: int in _hashes.keys():
		lines.append("%d %d" % [tick, _hashes[tick]])
	var file: FileAccess = FileAccess.open(_out_dir.path_join("%s.txt" % _role), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines))
		file.close()
	if _digests != null:
		_digests.close()
	var summary: Dictionary = {
		"role": _role, "ok": ok, "problem": problem, "last_tick": _last_tick,
		"ticks_hashed": _hashes.size(), "joined_tick": _joined_tick,
	}
	if _role == "host":
		summary["guest_actor"] = _guest_actor
		summary["guest_moved"] = roundi(_guest_moved)
		summary["humans"] = _peak_humans
		summary["bots"] = _peak_bots
	else:
		summary["seated_ms"] = _seated_ms
	var truth: SimWorld = _game.link.outcome_world() if _game.link != null else null
	if truth != null:
		summary["phase"] = SimWorld.MatchPhase.keys()[truth.match_phase]
		summary["round"] = truth.round_number
	print("NETSMOKE end %s" % JSON.stringify(summary))
	# Closed before quitting, so the far end sees a departure, not a timeout.
	if _game.link != null:
		_game.link.close()
	get_tree().quit(0 if ok else 1)

func _key(keycode: Key, down: bool) -> void:
	if keycode == KEY_NONE:
		return
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = down
	Input.parse_input_event(event)
