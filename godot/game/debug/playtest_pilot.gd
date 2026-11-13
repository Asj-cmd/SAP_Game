class_name PlaytestPilot
extends Node
## Plays the local seat through one whole session, unattended, by the same keys,
## mouse clicks and mouse motion a person would use - and photographs each step.
##
##   godot --path godot -- --pilot [--pilot-speed=2] [--team-size=N]
##   godot --path godot -- --pilot=host     (and in a second window:)
##   godot --path godot -- --pilot=guest
##
## host/guest exercise the menu's network path instead: the host clicks Host
## and leaves its join code in user://pilot_code.txt; the guest types that code
## into the Join box key by key, clicks Join, and both play briefly and press F10.
##
## Exists because "a playable local session" is a claim about the INPUT path, and
## nothing else in the repo exercises it: bot_match drives bodies with commands,
## the capture tool holds one key. This presses Play solo on the menu, walks,
## jumps, crouches, grabs, throws, deposits, seizes an intruder, frees a jailed
## team-mate, plays the match out, asks for a rematch and leaves with F10.
##
## Debug presentation, not a test and not a gate. It reads the confirmed world
## to know where things are and to report what happened; everything it DOES goes
## through Input.parse_input_event, so the game cannot tell it from a player.
## Routes come from the bots' own NavGraph, as directions to walk in: the
## pilot turns the camera with mouse motion and holds W, nothing more.
##
## Writes `user://pilot[_host|_guest]/NN_<step>.png` and `report.txt`, prints one
## `PILOT` line per step, and quits.

const CODE_FILE: String = "user://pilot_code.txt"
const GUEST_DONE_FILE: String = "user://pilot_guest_done.txt"
## How close a route waypoint must get before the next one is steered for.
const WAYPOINT_REACHED: float = 45.0
## Re-route when a moving goal has drifted this far from the routed one.
const GOAL_DRIFT: float = 120.0
const REROUTE_SECONDS: float = 2.0
## Real-time cap for the match played out after the scripted steps.
const MATCH_LIMIT_SECONDS: float = 1500.0

var _game: GreyBoxMain = null
## "solo", "host" or "guest".
var _role: String = "solo"
var _out_dir: String = "user://pilot"
var _speed: float = 1.0
var _shot_index: int = 0
var _report: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _turn_by_mouse: bool = true
var _clock: float = 0.0
## Bundles the pilot has dropped in its own cash rooms and seen count.
var _deposits: int = 0
## A mouse turn sent and not yet seen on the camera (see _face).
var _turn_frames_pending: int = 0
var _yaw_when_turned: float = 0.0

func _init(game: GreyBoxMain) -> void:
	_game = game
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pilot="):
			_role = arg.trim_prefix("--pilot=")
			_out_dir = "user://pilot_%s" % _role
		if arg.begins_with("--pilot-speed="):
			_speed = clampf(float(arg.trim_prefix("--pilot-speed=")), 0.25, 4.0)

static func requested(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg == "--pilot" or arg.begins_with("--pilot="):
			return true
	return false

func _process(delta: float) -> void:
	_clock += delta

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	if _role == "solo":
		_run()
	else:
		_run_network()

# ---- the session ----

func _run() -> void:
	await _wait(1.5)
	await _shot("menu")
	await _menu_click("Play solo")
	if not await _until(_match_started, 10.0):
		_note("start", false, "no match after pressing Play solo")
		_finish()
		return
	await _wait(0.3)
	await _shot("countdown")
	await _until(func() -> bool: return _phase() == SimWorld.MatchPhase.PLAYING, 15.0)
	_turn_by_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_note("start", true, "playing round %d, %d bodies, mouse %s" % [
		_world().round_number, _world().actor_ids().size(),
		"captured (turning by mouse motion)" if _turn_by_mouse else "NOT captured (turning by pose)"])

	await _step_walk()
	await _step_jump()
	await _step_crouch()
	var cash: int = await _step_grab()
	if cash != SimEntity.NO_ENTITY:
		cash = await _step_throw(cash)
	if cash != SimEntity.NO_ENTITY:
		await _step_deposit(cash)
	await _step_seize()
	await _step_free()
	await _step_play_out()
	await _step_rematch()
	await _step_leave()
	_finish()

## The menu's Host / Join path, between two windows on this machine.
func _run_network() -> void:
	var host: bool = _role == "host"
	if host:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GUEST_DONE_FILE))
	await _wait(1.5)
	await _shot("menu")
	if host:
		await _menu_click("Host")
	else:
		await _menu_join()
	if not await _until(_in_network_match, 30.0):
		_note("in match", false, "no match (menu %s, banner: %s)" % [
			"shown" if _game.menu_screen().visible else "hidden", _game.banner_text()])
		_finish()
		return
	if host:
		var code: String = _game.link.session_code()
		var file: FileAccess = FileAccess.open(CODE_FILE, FileAccess.WRITE)
		file.store_string(code)
		file.close()
		_note("hosting", true, "code %s, %d bodies" % [code, _world().actor_ids().size()])
		var joined: bool = await _until(_guest_connected, 60.0)
		_note("guest joined", joined, "%d connected" % _game.link.transport.peers().size())
	else:
		_note("joined", true, "seated as actor %d (team %s), %d bodies" % [
			_game.link.actor_id, _me().team, _world().actor_ids().size()])
	await _shot("lobby")
	await _until(_phase_live, 15.0)
	_turn_by_mouse = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	await _step_walk()
	await _step_jump()
	await _wait(2.0)
	await _shot("in_match")
	if host:
		# The guest leaves first, so it sees its own F10 rather than "host left".
		await _until(_guest_left, 60.0)
	await _step_leave()
	if not host:
		FileAccess.open(GUEST_DONE_FILE, FileAccess.WRITE).close()
	_finish()

## Clicks the code box, types the host's code one key at a time, clicks Join.
func _menu_join() -> void:
	var waited: bool = await _until(_code_written, 60.0)
	if not waited:
		_note("code", false, "the host never wrote a code")
		return
	await _wait(0.5)
	var code: String = FileAccess.get_file_as_string(CODE_FILE).strip_edges()
	var box: LineEdit = null
	for node: Node in _game.menu_screen().find_children("*", "LineEdit", true, false):
		var candidate: LineEdit = node as LineEdit
		if candidate.placeholder_text.begins_with("code"):
			box = candidate
	if box == null:
		_note("code", false, "no code box on the menu")
		return
	await _click(MOUSE_BUTTON_LEFT, box.get_global_rect().get_center())
	for character: String in code:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = OS.find_keycode_from_string(character)
		event.unicode = character.unicode_at(0)
		event.pressed = true
		Input.parse_input_event(event)
		await _frames(1)
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await _frames(1)
	_note("code typed", box.text == code, "box reads '%s', code '%s'" % [box.text, code])
	await _shot("join_typed")
	await _menu_click("Join")

func _step_walk() -> void:
	var start: Vector3 = _me().position
	_key(KEY_W, true)
	await _wait(1.0)
	await _shot("walk")
	await _wait(0.4)
	_key(KEY_W, false)
	var moved: float = _flat(start).distance_to(_flat(_me().position))
	_note("move", moved > 150.0, "W for 1.4 s moved %.0f units" % moved)

func _step_jump() -> void:
	var ground: float = _me().position.y
	var peak: float = ground
	_key(KEY_SPACE, true)
	await _frames(2)
	_key(KEY_SPACE, false)
	var shot_taken: bool = false
	var clock: float = 0.0
	while clock < 1.2:
		peak = maxf(peak, _me().position.y)
		if not shot_taken and _me().position.y - ground > 60.0:
			shot_taken = true
			await _shot("jump")
		clock += await _frame_time()
	var landed: float = absf(_me().position.y - ground)
	_note("jump", peak - ground > 40.0 and landed < 5.0,
		"rose %.0f, back down within %.1f" % [peak - ground, landed])

func _step_crouch() -> void:
	_key(KEY_SHIFT, true)
	await _wait(0.8)
	var ducked: bool = _me().stance == SimEntity.Stance.CROUCHED
	await _shot("crouch")
	_key(KEY_SHIFT, false)
	await _wait(0.6)
	_note("crouch", ducked and _me().stance == SimEntity.Stance.STANDING,
		"held SHIFT: %s; released: %s" % [
			SimEntity.Stance.keys()[SimEntity.Stance.CROUCHED if ducked else SimEntity.Stance.STANDING],
			SimEntity.Stance.keys()[_me().stance]])

## Walks into the enemy house and lifts a bundle. Returns its id, or none.
func _step_grab() -> int:
	var started: float = Time.get_ticks_msec() / 1000.0
	for attempt: int in 6:
		if not await _await_play():
			break
		var target: int = _enemy_cash()
		if target == SimEntity.NO_ENTITY:
			break
		var reach: float = _world().tuning.pickup_range * 0.6
		if not await _walk_to(func() -> Vector3: return _entity(target).position, reach, 90.0):
			continue
		await _click(MOUSE_BUTTON_LEFT)
		await _wait(0.4)
		if _me().is_carrying():
			await _shot("grab")
			_note("grab", true, "LMB lifted bundle %d in %s after %.0f s" % [
				target, _zone_name(_entity(target).position), _since(started)])
			return _me().carrying_id
	_note("grab", false, "never got a bundle into hand (me %s)" % _me_state())
	return SimEntity.NO_ENTITY

## Throws the bundle and picks it up again. Returns its id, or none.
func _step_throw(cash: int) -> int:
	# Face back toward home, so the throw goes somewhere useful.
	_face(_own_cash_room_point())
	await _wait(0.2)
	await _click(MOUSE_BUTTON_RIGHT)
	var flew: bool = false
	var shot_taken: bool = false
	var clock: float = 0.0
	var from: Vector3 = _me().position
	while clock < 2.0:
		if _entity(cash).in_flight:
			flew = true
			if not shot_taken and clock > 0.15:
				shot_taken = true
				await _shot("throw")
		clock += await _frame_time()
	var distance: float = _flat(from).distance_to(_flat(_entity(cash).position))
	_note("throw", flew and not _me().is_carrying(),
		"RMB: in flight %s, landed %.0f away" % [flew, distance])
	var reach: float = _world().tuning.pickup_range * 0.6
	for attempt: int in 3:
		if not await _walk_to(func() -> Vector3: return _entity(cash).position, reach, 40.0):
			continue
		await _click(MOUSE_BUTTON_LEFT)
		await _wait(0.4)
		if _me().carrying_id == cash:
			_note("pick up again", true, "LMB")
			return cash
		if _entity(cash).is_held():
			break
	_note("pick up again", false, "bundle %s (me %s)" % [
		"taken by someone else" if _entity(cash).is_held() else "not reached", _me_state()])
	return SimEntity.NO_ENTITY

func _step_deposit(cash: int) -> void:
	var team: StringName = _me().team
	var before: int = _world().score_for(team)
	if not await _walk_to(func() -> Vector3: return _own_cash_room_point(), 60.0, 90.0):
		_note("drop / score", false, "did not get home (me %s)" % _me_state())
		return
	await _click(MOUSE_BUTTON_LEFT)
	await _wait(0.6)
	var counted: bool = _entity(cash).scored_for_team == team
	await _shot("deposit")
	_note("drop / score", counted and not _me().is_carrying(),
		"LMB dropped in %s: counts for %s, team cash %d -> %d" % [
			_zone_name(_entity(cash).position), _entity(cash).scored_for_team,
			before, _world().score_for(team)])

## Chases an enemy standing on our ground and presses E on them.
func _step_seize() -> void:
	var started: float = _now()
	while _since(started) < 150.0 and _phase() != SimWorld.MatchPhase.MATCH_END:
		var intruder: int = _intruder()
		if not _phase_live():
			await _wait(0.5)
			continue
		if intruder == SimEntity.NO_ENTITY or _me().is_captured:
			await _walk_to(func() -> Vector3: return _own_cash_room_point(), 80.0, 3.0)
			continue
		var reach: float = _world().tuning.capture_range * 0.6
		var close: bool = await _walk_to(func() -> Vector3: return _entity(intruder).position,
			reach, 6.0, func() -> bool: return not _on_our_ground(intruder))
		if not close:
			continue
		# Where it happened: once seized, the body is moved to the jail.
		var seized_in: String = _zone_name(_entity(intruder).position)
		await _key_tap(KEY_E)
		await _wait(0.3)
		if _entity(intruder).is_captured:
			await _shot("seize")
			_note("seize", true, "E seized %s in %s after %.0f s" % [
				_entity(intruder).team, seized_in, _since(started)])
			return
	_note("seize", false, "no seizure in %.0f s" % _since(started))

## Waits for a team-mate to be jailed, goes to them, presses E.
func _step_free() -> void:
	var started: float = _now()
	while _since(started) < 200.0 and _phase() != SimWorld.MatchPhase.MATCH_END:
		var ally: int = _jailed_ally()
		if ally == SimEntity.NO_ENTITY or _me().is_captured or not _phase_live():
			await _wait(0.5)
			continue
		var reach: float = _world().tuning.rescue_range * 0.6
		var close: bool = await _walk_to(func() -> Vector3: return _entity(ally).position,
			reach, 30.0, func() -> bool: return not _entity(ally).is_captured)
		if not close:
			continue
		await _key_tap(KEY_E)
		await _wait(0.3)
		if not _entity(ally).is_captured:
			await _shot("free")
			_note("free", true, "E freed team-mate %d in %s after %.0f s" % [
				ally, _zone_name(_entity(ally).position), _since(started)])
			return
	_note("free", false, "no rescue in %.0f s (me %s)" % [_since(started), _me_state()])

## Keeps raiding until somebody wins the match, photographing each result.
func _step_play_out() -> void:
	Engine.time_scale = _speed
	var started: float = _now()
	var rounds_seen: int = 0
	while _phase() != SimWorld.MatchPhase.MATCH_END and _since(started) < MATCH_LIMIT_SECONDS:
		if _phase() == SimWorld.MatchPhase.ROUND_END:
			rounds_seen += 1
			await _shot("round_%d_end" % rounds_seen)
			_note("round %d" % rounds_seen, true, _game.headline_text().replace("\n", " "))
			await _until(func() -> bool: return _phase() != SimWorld.MatchPhase.ROUND_END, 30.0)
			continue
		if _phase() != SimWorld.MatchPhase.PLAYING or _me().is_captured:
			await _wait(0.5)
			continue
		await _raid_once()
	Engine.time_scale = 1.0
	var over: bool = _phase() == SimWorld.MatchPhase.MATCH_END
	if over:
		await _wait(0.5)
		await _shot("match_end")
	_note("match", over, "%s after %.0f s of play-out; the pilot banked %d bundle(s)" % [
		"winner %s, %s" % [_world().match_winner, _game.headline_text().replace("\n", " ")]
		if over else "no winner", _since(started), _deposits])

func _step_rematch() -> void:
	if _phase() != SimWorld.MatchPhase.MATCH_END:
		_note("rematch", false, "match never ended")
		return
	await _key_tap(KEY_ENTER)
	var restarted: bool = await _until(_restarted, 5.0)
	var wins: int = 0
	for team_id: StringName in _world().sorted_team_ids():
		wins += _world().round_wins_for(team_id)
	await _wait(0.3)
	await _shot("rematch")
	_note("rematch", restarted and wins == 0, "Enter: %s, round %d, rounds won %d" % [
		SimWorld.MatchPhase.keys()[_phase()], _world().round_number, wins])

func _step_leave() -> void:
	await _key_tap(KEY_F10)
	await _wait(0.8)
	var back: bool = _game.menu_screen().visible and _game.link == null
	await _shot("back_to_menu")
	_note("F10 to menu", back, "menu %s, session %s" % [
		"shown" if _game.menu_screen().visible else "hidden",
		"closed" if _game.link == null else "still open"])

func _finish() -> void:
	_report.append("PILOT %s: %d step(s) failed" % ["OK" if _failures == 0 else "DONE", _failures])
	print(_report[_report.size() - 1])
	var file: FileAccess = FileAccess.open(_out_dir.path_join("report.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_report) + "\n")
	Engine.time_scale = 1.0
	get_tree().quit()

# ---- one raid, for the play-out ----

func _raid_once() -> void:
	if not _me().is_carrying():
		var target: int = _enemy_cash()
		if target == SimEntity.NO_ENTITY:
			# Nothing left to steal: stand guard at home and seize what comes.
			var intruder: int = _intruder()
			if intruder != SimEntity.NO_ENTITY:
				var reach: float = _world().tuning.capture_range * 0.6
				if await _walk_to(func() -> Vector3: return _entity(intruder).position, reach, 4.0):
					await _key_tap(KEY_E)
			else:
				await _walk_to(func() -> Vector3: return _own_cash_room_point(), 80.0, 2.0)
			return
		var pickup: float = _world().tuning.pickup_range * 0.6
		if not await _walk_to(func() -> Vector3: return _entity(target).position, pickup, 25.0,
				func() -> bool: return _entity(target).is_held()):
			return
		await _click(MOUSE_BUTTON_LEFT)
		await _wait(0.3)
		return
	var cash: int = _me().carrying_id
	if await _walk_to(func() -> Vector3: return _own_cash_room_point(), 60.0, 40.0):
		var before: int = _world().score_for(_me().team)
		await _click(MOUSE_BUTTON_LEFT)
		await _wait(0.3)
		if _entity(cash).scored_for_team == _me().team:
			_deposits += 1
			if _deposits == 1:
				await _shot("deposit")
				_note("drop / score", true, "LMB dropped in %s during the play-out: team cash %d -> %d" % [
					_zone_name(_entity(cash).position), before, _world().score_for(_me().team)])

# ---- walking, by keys and mouse ----

## Steers toward a (possibly moving) goal along the bots' route: turns the
## camera toward the next waypoint and holds W. True when within `reach`.
## Gives up on timeout, on being seized, when play stops, or when `abandon` says so.
func _walk_to(goal_of: Callable, reach: float, timeout: float,
		abandon: Callable = Callable()) -> bool:
	var nav: NavGraph = _game.link.crew.nav
	var started: float = _now()
	var routed_goal: Vector3 = goal_of.call()
	var route: PackedVector3Array = nav.route(_me().position, routed_goal)
	var leg: int = 0
	var routed_at: float = _now()
	var reached: bool = false
	while _since(started) < timeout:
		if not _phase_live() or _me().is_captured:
			break
		if abandon.is_valid() and abandon.call():
			break
		var goal: Vector3 = goal_of.call()
		var here: Vector3 = _me().position
		if here.distance_to(goal) <= reach:
			reached = true
			break
		if goal.distance_to(routed_goal) > GOAL_DRIFT or _since(routed_at) > REROUTE_SECONDS:
			routed_goal = goal
			route = nav.route(here, goal)
			leg = 0
			routed_at = _now()
		while leg < route.size() - 1 and _flat(here).distance_to(_flat(route[leg])) < WAYPOINT_REACHED:
			leg += 1
		var aim: Vector3 = route[leg] if leg < route.size() else goal
		if _flat(here).distance_to(_flat(aim)) < 5.0:
			aim = goal
		_face(aim)
		_key(KEY_W, true)
		await _frame_time()
	_key(KEY_W, false)
	await _frames(2)
	return reached

## Turns the chase camera so it faces `point`, through mouse motion when the
## mouse is captured (the path a player's hand takes).
func _face(point: Vector3) -> void:
	var camera: ChaseCamera = _game.players[0].camera
	var want: float = FrameCapture.yaw_toward(_me().position, point)
	var turn: float = wrapf(camera.yaw_for_test() - want, -PI, PI)
	if _turn_by_mouse:
		# Injected motion reaches the camera a frame later. Sending the whole
		# error again before the last turn has landed doubles it, and the pilot
		# weaves off into a corner (seen on the first run).
		if _turn_frames_pending > 0 and is_equal_approx(camera.yaw_for_test(), _yaw_when_turned):
			_turn_frames_pending -= 1
			return
		_turn_frames_pending = 0
		if absf(turn) < 0.002:
			return
		_yaw_when_turned = camera.yaw_for_test()
		_turn_frames_pending = 3
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.relative = Vector2(turn / ChaseCamera.MOUSE_SENSITIVITY, 0.0)
		Input.parse_input_event(motion)
	else:
		camera.pose(want, deg_to_rad(FrameCapture.DEFAULT_CHASE_PITCH_DEG))

# ---- reading the world ----

func _world() -> SimWorld:
	return _game.link.outcome_world() if _game.link != null else null

func _phase() -> SimWorld.MatchPhase:
	return _world().match_phase if _world() != null else SimWorld.MatchPhase.WAITING

func _in_network_match() -> bool:
	return _game.link != null and _game.link.is_ready() and _match_started()

func _guest_connected() -> bool:
	return _game.link.transport.peers().size() > 0

func _guest_left() -> bool:
	return FileAccess.file_exists(GUEST_DONE_FILE)

func _code_written() -> bool:
	return FileAccess.file_exists(CODE_FILE)

func _match_started() -> bool:
	return _phase() == SimWorld.MatchPhase.COUNTDOWN or _phase() == SimWorld.MatchPhase.PLAYING

func _restarted() -> bool:
	return _phase() == SimWorld.MatchPhase.COUNTDOWN and _world().round_number == 1

## Waits out a countdown or a round result. False once the match is over.
func _await_play() -> bool:
	while not _phase_live():
		if _phase() == SimWorld.MatchPhase.MATCH_END or _world() == null:
			return false
		await get_tree().process_frame
	return true

func _phase_live() -> bool:
	return _phase() == SimWorld.MatchPhase.PLAYING

func _me() -> SimEntity:
	return _world().get_entity(_game.players[0].actor_id)

func _entity(entity_id: int) -> SimEntity:
	return _world().get_entity(entity_id)

## The nearest bundle at rest in an enemy cash room, not in anyone's hands.
func _enemy_cash() -> int:
	var team: StringName = _me().team
	var best: int = SimEntity.NO_ENTITY
	var best_distance: float = INF
	for entity_id: int in _world().sorted_entity_ids():
		var cash: SimEntity = _world().entities[entity_id]
		if not cash.is_carriable() or cash.is_held() or cash.in_flight:
			continue
		var zone: ZoneDef = _world().zone_at(cash.position)
		if zone == null or zone.role != ZoneDef.Role.CASH_ROOM or zone.owner_team == team:
			continue
		var distance: float = _me().position.distance_to(cash.position)
		if distance < best_distance:
			best_distance = distance
			best = entity_id
	return best

## Floor-level middle of our nearest cash room.
func _own_cash_room_point() -> Vector3:
	var team: StringName = _me().team
	var best: Vector3 = _me().position
	var best_distance: float = INF
	for zone: ZoneDef in _game.level.zones:
		if zone.role != ZoneDef.Role.CASH_ROOM or zone.owner_team != team:
			continue
		var middle: Vector3 = zone.bounds.get_center()
		middle.y = zone.bounds.position.y
		var distance: float = _me().position.distance_to(middle)
		if distance < best_distance:
			best_distance = distance
			best = middle
	return best

func _on_our_ground(entity_id: int) -> bool:
	var zone: ZoneDef = _world().zone_at(_entity(entity_id).position)
	return zone != null and zone.is_owned_by(_me().team) and zone.role != ZoneDef.Role.JAIL

## The nearest free enemy standing on ground we own.
func _intruder() -> int:
	var best: int = SimEntity.NO_ENTITY
	var best_distance: float = INF
	for entity_id: int in _world().actor_ids():
		var other: SimEntity = _entity(entity_id)
		if other.team == _me().team or other.is_captured or not _on_our_ground(entity_id):
			continue
		var distance: float = _me().position.distance_to(other.position)
		if distance < best_distance:
			best_distance = distance
			best = entity_id
	return best

func _jailed_ally() -> int:
	for entity_id: int in _world().actor_ids():
		var other: SimEntity = _entity(entity_id)
		if entity_id != _me().id and other.team == _me().team and other.is_captured:
			return entity_id
	return SimEntity.NO_ENTITY

func _zone_name(point: Vector3) -> String:
	var zone: ZoneDef = _world().zone_at(point)
	return String(zone.id) if zone != null else "nowhere"

func _me_state() -> String:
	return "at %s in %s%s" % [_me().position.round(), _zone_name(_me().position),
		", jailed" if _me().is_captured else ""]

# ---- input, injected ----

func _key(keycode: Key, down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = down
	Input.parse_input_event(event)

func _key_tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(3)
	_key(keycode, false)
	await _frames(1)

func _click(button: MouseButton, at: Vector2 = Vector2.ZERO) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = down
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await _frames(3)

## Clicks the menu button whose label starts with `label`, where it is drawn.
## Falls back to pressing it directly if the click did not land (and says so).
func _menu_click(label: String) -> void:
	var button: Button = null
	for node: Node in _game.menu_screen().find_children("*", "Button", true, false):
		var candidate: Button = node as Button
		if candidate.text.begins_with(label):
			button = candidate
	if button == null:
		_note("menu", false, "no %s button" % label)
		return
	await _click(MOUSE_BUTTON_LEFT, button.get_global_rect().get_center())
	await _wait(0.5)
	if not _game.menu_screen().visible:
		_note("menu", true, "clicked %s (team size %s)" % [label, _team_size_shown()])
		return
	button.pressed.emit()
	await _wait(0.5)
	_note("menu", not _game.menu_screen().visible,
		"click on %s did not land; pressed the button directly" % label)

func _team_size_shown() -> String:
	for node: Node in _game.menu_screen().find_children("*", "OptionButton", true, false):
		return (node as OptionButton).text
	return "?"

# ---- time ----

## Game time (scaled by Engine.time_scale), so timeouts hold at any pilot speed.
func _now() -> float:
	return _clock

func _since(started: float) -> float:
	return _now() - started

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame

## Waits one frame and returns how long it took, in game time.
func _frame_time() -> float:
	await get_tree().process_frame
	return get_process_delta_time()

func _until(condition: Callable, timeout: float) -> bool:
	var started: float = _now()
	while not condition.call():
		if _since(started) > timeout:
			return false
		await get_tree().process_frame
	return true

# ---- output ----

func _shot(step: String) -> void:
	_shot_index += 1
	await _game.save_frame(_out_dir.path_join("%02d_%s.png" % [_shot_index, step]))

func _note(step: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	var line: String = "PILOT %-14s %s  %s" % [step, "ok  " if ok else "FAIL", detail]
	_report.append(line)
	print(line)

static func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)
